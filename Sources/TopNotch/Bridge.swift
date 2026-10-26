import AppKit
import SwiftUI

// MARK: - Claude Code bridge: hooks hand permission prompts and questions to the menu bar popover
//
// Claude Code runs `TopNotch --hook` for each hook event (installed into ~/.claude/settings.json from the
// Agents tab). The client forwards the event over a unix socket. For PermissionRequest and AskUserQuestion it
// waits for the reply and prints it as the hook's decision. If TopNotch isn't running, or you pick "terminal",
// it prints nothing and Claude Code's own prompt takes over.

/// Where a session runs: the app that owns its terminal, and the tty that finds the exact tab.
struct Host: Equatable, Codable {
    var bundle: String, tty: String?

    static let names = [
        "com.googlecode.iterm2": "iTerm", "com.apple.Terminal": "Terminal", "com.microsoft.VSCode": "VS Code",
        "com.microsoft.VSCodeInsiders": "VS Code", "com.todesktop.230313mzl4w4u92": "Cursor", "com.mitchellh.ghostty": "Ghostty",
        "dev.warp.Warp-Stable": "Warp", "dev.zed.Zed": "Zed", "net.kovidgoyal.kitty": "kitty", "com.github.wez.wezterm": "WezTerm",
        "com.exafunction.windsurf": "Windsurf", "com.anthropic.claudefordesktop": "Claude",
    ]
    /// TERM_PROGRAM → bundle, for when the environment has no bundle id
    static let terms = ["iTerm.app": "com.googlecode.iterm2", "Apple_Terminal": "com.apple.Terminal", "vscode": "com.microsoft.VSCode",
                        "ghostty": "com.mitchellh.ghostty", "WarpTerminal": "dev.warp.Warp-Stable", "zed": "dev.zed.Zed"]

    var name: String {
        if let n = Self.names[bundle] { return n }
        guard let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return bundle.isEmpty ? "terminal" : bundle }
        return u.deletingPathExtension().lastPathComponent
    }
}

/// One AskUserQuestion question.
struct Question {
    let text: String, header: String, options: [(label: String, info: String)], multi: Bool
}

/// A Claude Code session waiting on you: a permission prompt or a question.
struct Ask: Identifiable {
    enum Kind { case permission, question }
    let id = UUID()
    let fd: Int32, kind: Kind, session: String, cwd: String, tool: String
    let input: [String: Any], suggestions: [[String: Any]], questions: [Question], host: Host?, at = Date()

    var project: String { URL(fileURLWithPath: cwd).lastPathComponent }

    /// The one line that says what the tool will do.
    var summary: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let s = ["command", "file_path", "url", "pattern", "query", "description", "prompt", "plan"]
            .lazy.compactMap { input[$0] as? String }.first
            ?? (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? ""
        return s.replacingOccurrences(of: home, with: "~")
    }
}

@Observable final class Bridge {
    var asks: [Ask] = []
    /// transcript path → where that session runs (learned from any hook event; kept across launches)
    var hosts: [String: Host] = (UserDefaults.standard.data(forKey: "hosts")).flatMap { try? JSONDecoder().decode([String: Host].self, from: $0) } ?? [:] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(hosts), forKey: "hosts") }
    }
    /// guesses from scanning running `claude` processes, for sessions no hook has reported yet
    var found: [String: Host] = [:]
    var connected = HookSetup.installed()
    var setupError: String?
    @ObservationIgnored var onAsk: ((Ask) -> Void)?

    static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TopNotch")
    static let sock = dir.appendingPathComponent("hook.sock").path
    @ObservationIgnored private var sources: [Int32: DispatchSourceRead] = [:]  // main only
    @ObservationIgnored private let jumpQ = DispatchQueue(label: "topnotch.jump")

    init() { listen() }

    func host(for a: Agent) -> Host? {
        if let h = hosts[a.id] ?? found[a.id] { return h }
        switch a.entry {
        case "claude-vscode": return Host(bundle: "com.microsoft.VSCode", tty: nil)
        case "claude-desktop": return Host(bundle: "com.anthropic.claudefordesktop", tty: nil)
        default: return nil
        }
    }

    /// Match live sessions to running `claude` processes by working directory (only when that's unambiguous),
    /// then walk up from the process to its tty and terminal app.
    func discover(_ live: [Agent]) {
        let need = live.filter { hosts[$0.id] == nil && found[$0.id] == nil && $0.cwd != nil }
        guard !need.isEmpty else { return }
        jumpQ.async {
            let procs = Dictionary(grouping: Self.claudes(), by: \.cwd)
            var out: [String: Host] = [:]
            for (cwd, group) in Dictionary(grouping: need, by: { $0.cwd! }) where group.count == 1 {
                guard let ps = procs[cwd], ps.count == 1 else { continue }
                let o = Hook.origin(from: ps[0].pid)
                if let b = o.bundle { out[group[0].id] = Host(bundle: b, tty: o.tty) }
            }
            guard !out.isEmpty else { return }
            DispatchQueue.main.async { self.found.merge(out) { $1 } }
        }
    }

    static func claudes() -> [(pid: pid_t, cwd: String)] {
        var pids = [pid_t](repeating: 0, count: Int(proc_listallpids(nil, 0)) + 64)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var out: [(pid: pid_t, cwd: String)] = []
        for pid in pids.prefix(Int(max(0, n))) where pid > 0 {
            var name = [CChar](repeating: 0, count: 256)
            guard proc_name(pid, &name, 256) > 0, String(cString: name) == "claude" else { continue }
            var vi = proc_vnodepathinfo()
            guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vi, Int32(MemoryLayout<proc_vnodepathinfo>.size)) > 0 else { continue }
            let cwd = withUnsafeBytes(of: vi.pvi_cdir.vip_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            out.append((pid, cwd))
        }
        return out
    }

    func connect(_ on: Bool) {
        do { try HookSetup.set(on); setupError = nil } catch { setupError = "\(error.localizedDescription)" }
        connected = HookSetup.installed()
    }

    // MARK: server

    private func listen() {
        try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        unlink(Self.sock)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, Hook.withAddress(Self.sock, { bind(fd, $0, $1) }) == 0, Darwin.listen(fd, 16) == 0 else { return }
        chmod(Self.sock, 0o600)
        Thread { [weak self] in
            while true {
                let c = accept(fd, nil, nil)
                guard c >= 0 else { continue }
                var on: Int32 = 1
                setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
                DispatchQueue.global().async { self?.handle(c) }
            }
        }.start()
    }

    private func handle(_ c: Int32) {
        guard let line = Hook.readLine(c),
              let ev = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let name = ev["hook_event_name"] as? String else { close(c); return }
        let session = ev["transcript_path"] as? String ?? ""
        let env = ev["topnotch"] as? [String: Any] ?? [:]
        var host: Host?
        if let b = env["bundle"] as? String, !b.isEmpty { host = Host(bundle: b, tty: env["tty"] as? String) }
        guard Hook.blocking.contains(name) else {
            close(c)
            DispatchQueue.main.async {
                if name == "SessionEnd" { self.hosts[session] = nil }
                else if let host, !session.isEmpty, self.hosts[session] != host { self.hosts[session] = host }
            }
            return
        }
        let tool = ev["tool_name"] as? String ?? "tool"
        let input = ev["tool_input"] as? [String: Any] ?? [:]
        let qs = (input["questions"] as? [[String: Any]] ?? []).map { q in
            Question(text: q["question"] as? String ?? "", header: q["header"] as? String ?? "",
                     options: (q["options"] as? [[String: Any]] ?? []).map { ($0["label"] as? String ?? "", $0["description"] as? String ?? "") },
                     multi: q["multiSelect"] as? Bool ?? false)
        }
        let kind: Ask.Kind = name == "PreToolUse" && tool == "AskUserQuestion" && !qs.isEmpty ? .question : .permission
        guard name == "PermissionRequest" || kind == .question else { close(c); return }  // nothing for us: let it through
        let ask = Ask(fd: c, kind: kind, session: session, cwd: ev["cwd"] as? String ?? "", tool: tool, input: input,
                      suggestions: ev["permission_suggestions"] as? [[String: Any]] ?? [], questions: qs, host: host)
        DispatchQueue.main.async { self.open(ask) }
    }

    private func open(_ a: Ask) {
        if let h = a.host, !a.session.isEmpty { hosts[a.session] = h }
        // the hook closing its end means Claude Code moved on without us (answered in the terminal, timed out, ctrl-c)
        let src = DispatchSource.makeReadSource(fileDescriptor: a.fd, queue: .main)
        src.setEventHandler { [weak self] in
            var b: UInt8 = 0
            if read(a.fd, &b, 1) <= 0 { self?.finish(a, nil) }
        }
        src.setCancelHandler { close(a.fd) }
        sources[a.fd] = src
        src.resume()
        withAnimation(spring) { asks.append(a) }
        onAsk?(a)
    }

    /// Send the decision (nil = hand back to Claude Code's own prompt) and drop the card.
    func finish(_ a: Ask, _ reply: [String: Any]?) {
        guard let src = sources.removeValue(forKey: a.fd) else { return }
        if let reply, var d = try? JSONSerialization.data(withJSONObject: reply) {
            d.append(10)
            _ = d.withUnsafeBytes { write(a.fd, $0.baseAddress, $0.count) }
        }
        src.cancel()
        withAnimation(spring) { asks.removeAll { $0.id == a.id } }
    }

    func allow(_ a: Ask, always: Bool = false) {
        var d: [String: Any] = ["behavior": "allow"]
        if always, !a.suggestions.isEmpty { d["updatedPermissions"] = a.suggestions }
        finish(a, Self.permission(d))
    }

    func deny(_ a: Ask, _ why: String? = nil) {
        let msg = why?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        finish(a, Self.permission(["behavior": "deny", "message": msg.isEmpty ? "The user denied this from TopNotch." : msg]))
    }

    func answer(_ a: Ask, _ answers: [String: String]) {
        var input = a.input
        input["answers"] = answers
        finish(a, ["hookSpecificOutput": ["hookEventName": "PreToolUse", "permissionDecision": "allow", "updatedInput": input]])
    }

    /// Hand the prompt back to the terminal and bring that terminal forward.
    func terminal(_ a: Ask) {
        finish(a, nil)
        jump(a.host ?? hosts[a.session], cwd: a.cwd)
    }

    static func permission(_ decision: [String: Any]) -> [String: Any] {
        ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
    }

    // MARK: jump

    /// Focus the exact iTerm / Terminal tab by tty; editors open the project's window; anything else just comes forward.
    func jump(_ h: Host?, cwd: String?) {
        guard let h else { return }
        jumpQ.async {
            if let tty = h.tty, let script = Self.focusScript(h.bundle, tty: tty) {
                var err: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&err)
                if err == nil { return }
            }
            DispatchQueue.main.async {
                guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: h.bundle) else { return }
                let editors: Set = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92",
                                    "dev.zed.Zed", "com.exafunction.windsurf"]
                let c = NSWorkspace.OpenConfiguration()
                c.activates = true
                if let cwd, !cwd.isEmpty, editors.contains(h.bundle) {
                    NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: app, configuration: c)
                } else {
                    NSWorkspace.shared.openApplication(at: app, configuration: c)
                }
            }
        }
    }

    static func focusScript(_ bundle: String, tty: String) -> String? {
        guard tty.hasPrefix("/dev/tty"), tty.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "/" }) else { return nil }
        switch bundle {
        case "com.googlecode.iterm2":
            return """
                tell application "iTerm2"
                  repeat with w in windows
                    repeat with t in tabs of w
                      repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                          tell w to select
                          tell t to select
                          tell s to select
                          activate
                          return
                        end if
                      end repeat
                    end repeat
                  end repeat
                end tell
                """
        case "com.apple.Terminal":
            return """
                tell application "Terminal"
                  repeat with w in windows
                    repeat with t in tabs of w
                      if tty of t is "\(tty)" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return
                      end if
                    end repeat
                  end repeat
                end tell
                """
        default: return nil
        }
    }
}

// MARK: - The hook client (`TopNotch --hook`), run by Claude Code

enum Hook {
    static let blocking: Set = ["PermissionRequest", "PreToolUse"]
    static let events: [(name: String, matcher: String?, timeout: Int)] = [
        ("PermissionRequest", nil, 600), ("PreToolUse", "AskUserQuestion", 600),
        ("SessionStart", nil, 5), ("UserPromptSubmit", nil, 5), ("Notification", nil, 5), ("SessionEnd", nil, 5),
    ]

    static func client() -> Never {
        let raw = FileHandle.standardInput.readDataToEndOfFile()
        guard var ev = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] else { exit(0) }
        let (bundle, tty) = origin()
        ev["topnotch"] = ["bundle": bundle ?? "", "tty": tty ?? ""]
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, withAddress(Bridge.sock, { connect(fd, $0, $1) }) == 0,
              var line = try? JSONSerialization.data(withJSONObject: ev) else { exit(0) }  // app not running
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        line.append(10)
        _ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard blocking.contains(ev["hook_event_name"] as? String ?? "") else { exit(0) }
        if let reply = readLine(fd) { FileHandle.standardOutput.write(reply + Data([10])) }
        exit(0)
    }

    /// The terminal app and tty this session lives in: walk up from the hook to the first process with a tty
    /// (Claude itself), then on up to the .app that launched it. Falls back to the inherited environment.
    static func origin(from start: pid_t = getppid()) -> (bundle: String?, tty: String?) {
        var pid = start, tty: String?, bundle: String?
        for _ in 0..<24 where pid > 1 {
            guard let (ppid, dev) = proc(pid) else { break }
            if tty == nil, dev != -1, let n = devname(dev_t(dev), S_IFCHR), String(cString: n).hasPrefix("tty") {
                tty = "/dev/" + String(cString: n)
            }
            if let app = NSRunningApplication(processIdentifier: pid), var b = app.bundleIdentifier {
                if let r = b.range(of: ".helper", options: .caseInsensitive) { b = String(b[..<r.lowerBound]) }  // editor terminals
                bundle = b
                break
            }
            pid = ppid
        }
        let env = ProcessInfo.processInfo.environment
        return (bundle ?? env["__CFBundleIdentifier"] ?? env["TERM_PROGRAM"].flatMap { Host.terms[$0] }, tty)
    }

    private static func proc(_ pid: pid_t) -> (pid_t, Int32)? {
        var kp = kinfo_proc(), size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &kp, &size, nil, 0) == 0, size > 0 else { return nil }
        return (kp.kp_eproc.e_ppid, kp.kp_eproc.e_tdev)
    }

    /// Reads up to the first newline (or EOF). nil if nothing arrived.
    static func readLine(_ fd: Int32) -> Data? {
        var out = Data(), buf = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            out.append(contentsOf: buf[0..<n])
            if let i = out.firstIndex(of: 10) { return out.prefix(upTo: i) }
            if out.count > 8 << 20 { break }
        }
        return out.isEmpty ? nil : out
    }

    static func withAddress(_ path: String, _ f: (UnsafePointer<sockaddr>, socklen_t) -> Int32) -> Int32 {
        var a = sockaddr_un()
        a.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8.prefix(MemoryLayout.size(ofValue: a.sun_path) - 1))
        withUnsafeMutableBytes(of: &a.sun_path) { $0.copyBytes(from: bytes) }
        return withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { f($0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
    }
}

// MARK: - Installing the hooks into ~/.claude/settings.json

enum HookSetup {
    static let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    static var command: String { "'\(Bundle.main.executablePath ?? "/Applications/TopNotch.app/Contents/MacOS/TopNotch")' --hook" }

    static func isOurs(_ h: Any) -> Bool {
        guard let c = (h as? [String: Any])?["command"] as? String else { return false }
        return c.contains("TopNotch") && c.hasSuffix("--hook")
    }

    static func installed() -> Bool {
        guard let root = read(), let hooks = root["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { ($0 as? [[String: Any]] ?? []).contains { ($0["hooks"] as? [Any] ?? []).contains(where: isOurs) } }
    }

    static func read() -> [String: Any]? {
        guard let d = try? Data(contentsOf: file) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    /// Our entries in or out; everything else in the file is left as it was.
    static func merge(_ root: [String: Any], on: Bool, command: String) -> [String: Any] {
        var root = root
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for (k, v) in hooks {
            guard let groups = v as? [[String: Any]] else { continue }
            let kept: [[String: Any]] = groups.compactMap { g in
                guard let hs = g["hooks"] as? [Any] else { return g }
                let rest = hs.filter { !isOurs($0) }
                if rest.isEmpty { return nil }
                var g = g
                g["hooks"] = rest
                return g
            }
            hooks[k] = kept.isEmpty ? nil : kept
        }
        if on {
            for e in Hook.events {
                var g: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": e.timeout]]]
                if let m = e.matcher { g["matcher"] = m }
                hooks[e.name] = (hooks[e.name] as? [[String: Any]] ?? []) + [g]
            }
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        return root
    }

    struct Unreadable: LocalizedError {
        var errorDescription: String? { "~/.claude/settings.json isn't plain JSON, so TopNotch left it alone" }
    }

    static func set(_ on: Bool) throws {
        let exists = FileManager.default.fileExists(atPath: file.path)
        guard let root = exists ? read() : [:] else { throw Unreadable() }  // never overwrite a file we can't parse
        if exists {
            let bak = file.appendingPathExtension("topnotch-backup")
            try? FileManager.default.removeItem(at: bak)
            try FileManager.default.copyItem(at: file, to: bak)
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let out = try JSONSerialization.data(withJSONObject: merge(root, on: on, command: command),
                                             options: [.prettyPrinted, .withoutEscapingSlashes])
        try out.write(to: file, options: .atomic)
    }
}

// MARK: - Model names

/// "claude-opus-5-5" → "Opus 5.5", "claude-sonnet-4-5-20250929" → "Sonnet 4.5"
func prettyModel(_ id: String) -> String {
    let parts = id.split(separator: "-").map(String.init).filter { !($0.count == 8 && Int($0) != nil) }
    guard let i = parts.firstIndex(where: { ["opus", "sonnet", "haiku", "fable"].contains($0) }) else { return id }
    let ver = parts[(i + 1)...].prefix { Int($0) != nil }.joined(separator: ".")
    return parts[i].capitalized + (ver.isEmpty ? "" : " " + ver)
}
