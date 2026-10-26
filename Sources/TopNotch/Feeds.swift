import AppKit
import SQLite3
import ApplicationServices

// MARK: - Music (Spotify + Apple Music over AppleScript)

@Observable final class Music {
    var app: String?
    var playing = false
    var title = ""
    var artist = ""
    var album = ""
    var pos: Double = 0
    var dur: Double = 1
    var volume: Double = 50
    var stamp = Date()
    var art: NSImage?
    var lyrics: [(t: Double, text: String)] = []   // synced, from lrclib.net
    var island = UserDefaults.standard.object(forKey: "island") as? Bool ?? true {  // live lyric under the notch
        didSet { UserDefaults.standard.set(island, forKey: "island") }
    }
    /// Master switch for lyrics: off means no LRCLIB lookups and no lyrics anywhere.
    var lyricsOn = UserDefaults.standard.object(forKey: "lyricsOn") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(lyricsOn, forKey: "lyricsOn")
            if !lyricsOn { lyrics = []; lyricsKey = "" }
            q.async { self.artKey = "" }  // turning it back on: refetch for the current track on the next poll
        }
    }
    /// Seconds to show a line early — AppleScript's playhead lags a hair. Tune if lines feel late/early.
    static let lyricLead = 0.3

    @ObservationIgnored private let q = DispatchQueue(label: "topnotch.music")
    @ObservationIgnored private var artKey = ""          // touched only on q
    @ObservationIgnored private var scripts: [String: NSAppleScript] = [:]  // NSAppleScript is not thread-safe: q only
    private static let bundle = ["Spotify": "com.spotify.client", "Music": "com.apple.Music"]

    init() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    /// Smoothly interpolated playhead for the UI.
    func now(_ d: Date) -> Double { playing ? min(dur, pos + d.timeIntervalSince(stamp)) : pos }

    func poll() {
        let wantLyrics = lyricsOn
        q.async { [weak self] in
            guard let self else { return }
            var best: (String, [String])?
            for app in ["Spotify", "Music"]
            where !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundle[app]!).isEmpty {
                // checking running first so AppleScript never launches the player
                guard let r = run(Self.query(app)) else { continue }
                let f = r.components(separatedBy: "|||")
                guard f.count == 8 else { continue }
                if best == nil || f[0] == "playing" { best = (app, f) }
            }
            var newArt: NSImage??
            if let (app, f) = best, artKey != app + f[1] + f[3] {
                artKey = app + f[1] + f[3]
                if wantLyrics { fetchLyrics(title: f[1], artist: f[2], album: f[3], dur: Self.num(f[5]), key: artKey) }
                newArt = .some(app == "Spotify"
                    ? URL(string: f[6]).flatMap { try? Data(contentsOf: $0) }.flatMap(NSImage.init(data:))
                    : (try? runDescriptor("tell application \"Music\" to get raw data of artwork 1 of current track"))
                        .flatMap { NSImage(data: $0.data) })
            }
            DispatchQueue.main.async {
                if let a = newArt { self.art = a }
                guard let (app, f) = best else { self.app = nil; self.playing = false; return }
                self.app = app
                self.playing = f[0] == "playing"
                (self.title, self.artist, self.album) = (f[1], f[2], f[3])
                self.pos = Self.num(f[4]); self.dur = max(1, Self.num(f[5])); self.volume = Self.num(f[7])
                self.stamp = Date()
            }
        }
    }

    /// Current line index, its text and how far through it we are (0...1).
    func line(at t: Double) -> (i: Int, text: String, p: Double)? {
        let t = t + Self.lyricLead
        guard let i = lyrics.lastIndex(where: { $0.t <= t }) else { return nil }
        let end = i + 1 < lyrics.count ? lyrics[i + 1].t : lyrics[i].t + 5
        return (i, lyrics[i].text, min(1, max(0, (t - lyrics[i].t) / max(0.1, end - lyrics[i].t))))
    }

    @ObservationIgnored private var lyricsKey = ""
    /// Exact LRCLIB match first (title/artist/album/length ±2s), then a strict search. Wrong lyrics are worse than none.
    private func fetchLyrics(title: String, artist: String, album: String, dur: Double, key: String) {
        DispatchQueue.main.async { self.lyrics = []; self.lyricsKey = key }
        func call(_ path: String, _ q: [String: String], _ done: @escaping (Any?) -> Void) {
            var c = URLComponents(string: "https://lrclib.net/api/" + path)!
            c.queryItems = q.map { URLQueryItem(name: $0.key, value: $0.value) }
            var req = URLRequest(url: c.url!)
            req.setValue("TopNotch/1.0 (personal notch app)", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: req) { data, _, _ in done(data.flatMap { try? JSONSerialization.jsonObject(with: $0) }) }.resume()
        }
        func use(_ synced: String?) {
            let lines = Self.lrc(synced ?? "")
            DispatchQueue.main.async { if self.lyricsKey == key { self.lyrics = lines } }
        }
        call("get", ["track_name": title, "artist_name": artist, "album_name": album, "duration": "\(Int(dur.rounded()))"]) { got in
            if let synced = (got as? [String: Any])?["syncedLyrics"] as? String { return use(synced) }
            call("search", ["track_name": Self.clean(title), "artist_name": artist]) { hits in
                use(Self.pick(hits as? [[String: Any]] ?? [], title: title, dur: dur))
            }
        }
    }

    /// "Song (feat. X) - Remastered [Explicit]" → "Song"
    static func clean(_ t: String) -> String {
        t.replacingOccurrences(of: #"\s*[\(\[].*?[\)\]]"#, with: "", options: .regularExpression)
            .components(separatedBy: " - ").first!.trimmingCharacters(in: .whitespaces)
    }

    /// Synced lyrics for the same title (after `clean`) within 8s of the track's length; closest length wins.
    static func pick(_ hits: [[String: Any]], title: String, dur: Double) -> String? {
        let want = clean(title).lowercased()
        return hits.compactMap { h -> (Double, String)? in
            guard let s = h["syncedLyrics"] as? String, let d = h["duration"] as? Double, abs(d - dur) <= 8,
                  clean(h["trackName"] as? String ?? "").lowercased() == want else { return nil }
            return (abs(d - dur), s)
        }
        .min { $0.0 < $1.0 }?.1
    }

    /// "[01:23.45] text" → (83.45, "text")
    static func lrc(_ s: String) -> [(t: Double, text: String)] {
        s.split(separator: "\n").compactMap { l in
            guard l.hasPrefix("["), let close = l.firstIndex(of: "]") else { return nil }
            let ts = l[l.index(after: l.startIndex)..<close].split(separator: ":")
            guard ts.count == 2, let m = Double(ts[0]), let sec = Double(ts[1]) else { return nil }
            return (m * 60 + sec, l[l.index(after: close)...].trimmingCharacters(in: .whitespaces))
        }
    }

    func send(_ cmd: String) {
        guard let app else { return }
        q.async { [weak self] in
            _ = self?.run("tell application \"\(app)\" to \(cmd)")
            self?.poll()
        }
    }
    func toggle() { playing.toggle(); stamp = Date(); send("playpause") }
    func seek(_ t: Double) { pos = t; stamp = Date(); send("set player position to \(t)") }
    func setVolume(_ v: Double) { volume = v; send("set sound volume to \(Int(v))") }

    private func runDescriptor(_ src: String) throws -> NSAppleEventDescriptor {
        let s = scripts[src] ?? NSAppleScript(source: src)!
        scripts[src] = s
        var err: NSDictionary?
        let d = s.executeAndReturnError(&err)
        if let err { throw NSError(domain: "applescript", code: 1, userInfo: err as? [String: Any]) }
        return d
    }
    private func run(_ src: String) -> String? { (try? runDescriptor(src))?.stringValue }

    private static func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    private static func query(_ app: String) -> String {
        let dur = app == "Spotify" ? "((duration of t) / 1000)" : "(duration of t)"
        let art = app == "Spotify" ? "(artwork url of t)" : "\"\""
        return """
        tell application "\(app)"
            if player state is stopped then return "stopped"
            set t to current track
            return (player state as string) & "|||" & (name of t) & "|||" & (artist of t) & "|||" & (album of t) & "|||" & (player position as string) & "|||" & (\(dur) as string) & "|||" & \(art) & "|||" & (sound volume as string)
        end tell
        """
    }
}

// MARK: - Clipboard history (memory only, skips password-manager copies)

@Observable final class Clip {
    var items: [String] = []
    @ObservationIgnored private var count = NSPasteboard.general.changeCount
    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    init() {
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        let pb = NSPasteboard.general
        guard pb.changeCount != count else { return }
        count = pb.changeCount
        guard pb.types?.contains(Self.concealed) != true,
              let s = pb.string(forType: .string),
              !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        items.removeAll { $0 == s }
        items.insert(s, at: 0)
        if items.count > 50 { items.removeLast() }
    }

    func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

// MARK: - Claude Code agents + usage, read straight from ~/.claude/projects/*.jsonl

enum AState: String { case run = "RUN", hold = "HOLD", think = "THNK", wait = "YOU" }

struct Agent: Identifiable {
    let id: String, project: String, state: AState, detail: String, updated: Date, subs: Int
    var cwd: String?, model: String?, branch: String?
    /// "cli", "claude-vscode", "claude-desktop", "sdk-ts"…: where the session was started from
    var entry: String?
    var ai = "Claude"
}

struct ModelTokenUsage: Identifiable {
    let model: String
    let tokens: Int
    var id: String { model }
}

struct UsageWindow: Identifiable {
    let id: String
    let name: String
    let percent: Double
    let resetsAt: Date?
}

struct ExtraUsage {
    let enabled: Bool
    let used: Double?
    let limit: Double?
    let currency: String
}

@Observable final class Agents {
    var live: [Agent] = []
    var tokens: [String: Int] = [:]  // per session file
    var block = 0
    var peak = 1
    var week = 0
    var blockEnd: Date?
    /// Last seven local calendar days, one row per day and one column per hour.
    var activity = Array(repeating: Array(repeating: 0, count: 24), count: 7)
    var modelUsage: [ModelTokenUsage] = []
    var accountSession: UsageWindow?
    var accountWeek: UsageWindow?
    var accountModels: [UsageWindow] = []
    var extraUsage: ExtraUsage?
    var accountUsageLoaded = false

    @ObservationIgnored var onDone: ((String) -> Void)?
    @ObservationIgnored private var all: [Agent] = []
    /// session path → last-activity time when you dismissed it. It comes back only if it does something newer.
    @ObservationIgnored private var dismissed = (UserDefaults.standard.dictionary(forKey: "dismissed") as? [String: Double] ?? [:])
        .filter { Date().timeIntervalSince1970 - $0.value < 86400 }

    func dismiss(_ ids: [String]) {
        for a in live where ids.contains(a.id) { dismissed[a.id] = a.updated.timeIntervalSince1970 }
        UserDefaults.standard.set(dismissed, forKey: "dismissed")
        publish()
    }

    private func publish() {
        live = all.filter { a in dismissed[a.id].map { a.updated.timeIntervalSince1970 > $0 } ?? true }
    }
    @ObservationIgnored private var prev: [String: AState] = [:]
    @ObservationIgnored private var cache: [String: (Date, [(String, Date, Int, String?)])] = [:]  // q only
    @ObservationIgnored private let q = DispatchQueue(label: "topnotch.agents", qos: .utility)
    static let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")

    init() {
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.q.async { self?.scanLive() } }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.q.async { self?.scanUsage() } }
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.refreshAccountUsage() }
        q.async { self.scanLive(); self.scanUsage() }
        refreshAccountUsage()
    }

    private func files(within s: TimeInterval) -> [(URL, Date)] {
        let cut = Date().addingTimeInterval(-s)
        let en = FileManager.default.enumerator(at: Self.root, includingPropertiesForKeys: [.contentModificationDateKey])
        return (en?.allObjects as? [URL] ?? []).compactMap { u in
            guard u.pathExtension == "jsonl",
                  let m = try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  m > cut else { return nil }
            return (u, m)
        }
    }

    private func scanLive() {
        let recent = files(within: 30 * 60)
        var out: [Agent] = []
        for (u, m) in recent where !u.path.contains("/subagents/") {
            guard let t = Self.tail(u) else { continue }
            let (raw, detail, cwd) = (t.0, t.1, t.2)
            let age = Date().timeIntervalSince(m)
            let state: AState = raw == .run && age > 20 ? .hold : raw  // long tool, or waiting on your approval
            // only what's alive or waiting on you: a log that stopped mid-turn is a closed/crashed session
            if state == .think && age > 300 || (state == .run || state == .hold) && age > 15 * 60 { continue }
            let subDir = u.deletingPathExtension().path + "/subagents/"
            let subs = recent.filter { $0.0.path.hasPrefix(subDir) && Date().timeIntervalSince($0.1) < 60 }.count
            let name = cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? u.deletingLastPathComponent().lastPathComponent
            out.append(Agent(id: u.path, project: name, state: state, detail: detail, updated: m, subs: subs,
                             cwd: cwd, model: t.meta.model, branch: t.meta.branch, entry: t.meta.entry))
        }
        out.sort { $0.updated > $1.updated }
        DispatchQueue.main.async { [self] in
            for a in out where a.state == .wait && prev[a.id].map({ $0 != .wait }) == true { onDone?(a.project) }
            prev = Dictionary(uniqueKeysWithValues: out.map { ($0.id, $0.state) })
            all = out
            publish()
        }
    }

    /// Status from the last real message in the session log, plus which model, branch and front end it's on.
    static func tail(_ u: URL) -> (AState, String, String?, meta: (model: String?, branch: String?, entry: String?))? {
        guard let h = try? FileHandle(forReadingFrom: u) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 262_144 ? size - 262_144 : 0)
        guard let data = try? h.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
        var found: (AState, String, String?)?, model: String?, branch: String?, entry: String?
        for line in text.split(separator: "\n").reversed() {
            guard let d = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            branch = branch ?? (d["gitBranch"] as? String).flatMap { $0.isEmpty || $0 == "HEAD" ? nil : $0 }
            entry = entry ?? d["entrypoint"] as? String
            if model == nil, let m = (d["message"] as? [String: Any])?["model"] as? String, m.hasPrefix("claude") { model = m }
            if found == nil, let s = status(d) { found = (s.0, clean(s.1), d["cwd"] as? String) }
            if found != nil, model != nil, branch != nil, entry != nil { break }
        }
        return found.map { ($0.0, $0.1, $0.2, (model, branch, entry)) }
    }

    static func status(_ d: [String: Any]) -> (AState, String)? {
        guard let type = d["type"] as? String, type == "assistant" || type == "user",
              d["isSidechain"] as? Bool != true, d["isMeta"] as? Bool != true,
              let msg = d["message"] as? [String: Any] else { return nil }
        let blocks = msg["content"] as? [[String: Any]] ?? []
        if type == "user" {
            let text = msg["content"] as? String ?? blocks.last?["text"] as? String
            if blocks.last?["type"] as? String == "tool_result" { return (.think, "chewing on tool output") }
            if text?.hasPrefix("[Request interrupted") == true { return (.wait, "interrupted") }
            return (.think, text ?? "")
        }
        guard let last = blocks.last else { return nil }
        switch last["type"] as? String {
        case "tool_use":
            let inp = last["input"] as? [String: Any] ?? [:]
            let arg = ["description", "command", "file_path", "pattern", "url", "prompt", "query"]
                .lazy.compactMap { inp[$0] as? String }.first ?? ""
            return (.run, "\(last["name"] as? String ?? "tool") › \(arg)")
        case "text":
            return (msg["stop_reason"] as? String == "end_turn" ? .wait : .think, last["text"] as? String ?? "")
        default:
            return (.think, "thinking…")
        }
    }

    private static func clean(_ s: String) -> String {
        String(s.split(whereSeparator: \.isNewline).first ?? "").trimmingCharacters(in: .whitespaces).prefix(140).description
    }

    // ponytail: re-parses a whole changed log every 30s; tail-offset caching if logs get huge.
    private func scanUsage() {
        var all: [String: (Date, Int, String?)] = [:]
        var per: [String: Int] = [:]
        var models: [String: Int] = [:]
        let weekCutoff = Date().addingTimeInterval(-7 * 86400)
        for (u, m) in files(within: 7 * 86400) {
            let entries: [(String, Date, Int, String?)]
            if let c = cache[u.path], c.0 == m { entries = c.1 } else { entries = Self.usage(u); cache[u.path] = (m, entries) }
            let key = u.path.contains("/subagents/")
                ? u.deletingLastPathComponent().deletingLastPathComponent().path + ".jsonl" : u.path
            for (id, t, n, model) in entries {
                all[id] = (t, n, model)
                per[key, default: 0] += n
                if t > weekCutoff, let model { models[prettyModel(model), default: 0] += n }
            }
        }
        let now = Date()
        let entries = all.values.map { ($0.0, $0.1) }
        let recent = entries.filter { $0.0 > now.addingTimeInterval(-7 * 86400) }
        let b = Self.blocks(recent)
        let grid = Self.activityGrid(entries, now: now)
        DispatchQueue.main.async { [self] in
            tokens = per
            week = b.week; peak = max(b.peak, 1)
            (block, blockEnd) = b.current.map { ($0.1, $0.0) } ?? (0, nil)
            activity = grid
            modelUsage = models.map { ModelTokenUsage(model: $0.key, tokens: $0.value) }.sorted { $0.tokens > $1.tokens }
        }
    }

    private func refreshAccountUsage() {
        q.async { [weak self] in
            guard let token = Self.oauthToken() else {
                DispatchQueue.main.async { self?.accountUsageLoaded = true }
                return
            }
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 12)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            URLSession.shared.dataTask(with: request) { data, response, _ in
                guard let data, (response as? HTTPURLResponse)?.statusCode == 200,
                      let parsed = Self.parseAccountUsage(data) else {
                    DispatchQueue.main.async { self?.accountUsageLoaded = true }
                    return
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.accountSession = parsed.session
                    self.accountWeek = parsed.week
                    self.accountModels = parsed.models
                    self.extraUsage = parsed.extra
                    self.accountUsageLoaded = true
                }
            }.resume()
        }
    }

    /// Claude Code keeps its OAuth credential in Keychain, with a file fallback for older installs.
    private static func oauthToken() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        if (try? process.run()) != nil {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus == 0, let token = token(from: data) { return token }
        }
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        return (try? Data(contentsOf: file)).flatMap(token(from:))
    }

    private static func token(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let oauth = json["claudeAiOauth"] as? [String: Any] ?? json
        return (oauth["accessToken"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func parseAccountUsage(_ data: Data) -> (session: UsageWindow?, week: UsageWindow?, models: [UsageWindow], extra: ExtraUsage?)? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func window(_ value: Any?, id: String, name: String) -> UsageWindow? {
            guard let d = value as? [String: Any],
                  let raw = (d["utilization"] as? NSNumber)?.doubleValue ?? (d["percent"] as? NSNumber)?.doubleValue else { return nil }
            let percent = raw <= 1 ? raw * 100 : raw
            let reset = (d["resets_at"] as? String).flatMap(parseDate)
            return UsageWindow(id: id, name: name, percent: percent, resetsAt: reset)
        }
        let session = window(json["five_hour"], id: "session", name: "Current session")
        let week = window(json["seven_day"], id: "week", name: "All models")
        var models: [UsageWindow] = []
        if let limits = json["limits"] as? [[String: Any]] {
            for (index, item) in limits.enumerated() {
                guard let display = ((item["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String,
                      let model = window(item, id: "model-\(index)", name: display) else { continue }
                models.append(model)
            }
        }
        if models.isEmpty {
            for (key, name) in [("seven_day_opus", "Opus"), ("seven_day_sonnet", "Sonnet"), ("seven_day_haiku", "Haiku")] {
                if let model = window(json[key], id: key, name: name) { models.append(model) }
            }
        }
        let extra: ExtraUsage? = (json["extra_usage"] as? [String: Any]).map { d in
            ExtraUsage(enabled: d["is_enabled"] as? Bool ?? false,
                       used: (d["used_credits"] as? NSNumber)?.doubleValue,
                       limit: (d["monthly_limit"] as? NSNumber)?.doubleValue,
                       currency: d["currency"] as? String ?? "USD")
        }
        return (session, week, models, extra)
    }

    private static func parseDate(_ value: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let date = f.date(from: value) { return date }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: value)
    }

    /// Count Claude usage messages in each local hour for the last seven calendar days.
    static func activityGrid(_ entries: [(Date, Int)], now: Date = Date()) -> [[Int]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        guard let first = cal.date(byAdding: .day, value: -6, to: today) else {
            return Array(repeating: Array(repeating: 0, count: 24), count: 7)
        }
        var grid = Array(repeating: Array(repeating: 0, count: 24), count: 7)
        for (date, _) in entries {
            let day = cal.startOfDay(for: date)
            guard let offset = cal.dateComponents([.day], from: first, to: day).day, (0..<7).contains(offset) else { continue }
            grid[offset][cal.component(.hour, from: date)] += 1
        }
        return grid
    }

    /// Claude's 5h windows: a block starts at the hour of the first message after the previous block expired.
    static func blocks(_ es: [(Date, Int)]) -> (current: (Date, Int)?, peak: Int, week: Int) {
        var bs: [(Date, Int)] = []
        for (t, n) in es.sorted(by: { $0.0 < $1.0 }) {
            if let b = bs.last, t < b.0.addingTimeInterval(5 * 3600) { bs[bs.count - 1].1 += n }
            else { bs.append((Calendar.current.dateInterval(of: .hour, for: t)!.start, n)) }
        }
        let cur = bs.last.flatMap { Date() < $0.0.addingTimeInterval(5 * 3600) ? ($0.0.addingTimeInterval(5 * 3600), $0.1) : nil }
        return (cur, bs.map(\.1).max() ?? 0, bs.map(\.1).reduce(0, +))
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()

    /// (message id, time, tokens) — input + cache writes + output; cache reads are excluded (they're ~free).
    static func usage(_ u: URL) -> [(String, Date, Int, String?)] {
        guard let data = try? Data(contentsOf: u), let text = String(data: data, encoding: .utf8) else { return [] }
        var seen = Set<String>(), out: [(String, Date, Int, String?)] = []
        for line in text.split(separator: "\n") where line.contains("\"usage\"") {
            guard let d = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let msg = d["message"] as? [String: Any], let id = msg["id"] as? String,
                  let us = msg["usage"] as? [String: Any],
                  let t = (d["timestamp"] as? String).flatMap(iso.date(from:)),
                  seen.insert(id).inserted else { continue }
            let n = ["input_tokens", "cache_creation_input_tokens", "output_tokens"].reduce(0) { $0 + (us[$1] as? Int ?? 0) }
            let model = (msg["model"] as? String) ?? (d["model"] as? String)
            out.append((id, t, n, model))
        }
        return out
    }
}

// MARK: - WhatsApp / Telegram / Slack notifications, read from Notification Center's own DB (needs Full Disk Access)

struct Notif: Identifiable {
    let id = UUID()
    let rec: Int64, bundle: String, title: String, body: String, date: Date
    var tag: String {
        let b = bundle.lowercased()
        return b.contains("whatsapp") ? "WA" : b.contains("tinyspeck") || b.contains("slack") ? "SL" : "TG"
    }
}

@Observable final class Notifs {
    var items: [Notif] = []
    var denied = false
    var unseen = 0   // badge on the msgs tab
    @ObservationIgnored var onNew: ((Notif) -> Void)?
    // q only. Keyed by row id + blob, NOT "id > last": apps delete read notifications and sqlite reuses the max rowid.
    @ObservationIgnored private var seen: Set<String>?   // nil = first read, load history silently
    @ObservationIgnored private let q = DispatchQueue(label: "topnotch.notifs")
    static let bundles = ["net.whatsapp.whatsapp", "desktop.whatsapp", "ru.keepcoder.telegram", "org.telegram.desktop",
                          "com.tinyspeck.slackmacgap"]  // lowercase: matched against lower(identifier)
    static let db = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db").path

    @ObservationIgnored private var stream: FSEventStreamRef?

    init() {
        // fallback in case FSEvents stays quiet for the protected folder
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.q.async { self?.poll() } }
        q.async { self.poll() }
        watch()
        // live path: read the banner itself while it's on screen (DB only gets the row once it leaves)
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.q.async { self?.scanBanners() } }
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.q.async { self?.scanDock() } }
    }

    /// Real unread counts: the red badge on each app's Dock tile ("Telegram": "3"). Missing = no badge / not running.
    var badges: [String: String] = [:]

    private func scanDock() {
        guard AXIsProcessTrusted(),
              let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        else { return }
        func get(_ e: AXUIElement, _ k: String) -> AnyObject? {
            var v: AnyObject?
            return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil
        }
        var found: [String: String] = [:]
        for list in get(AXUIElementCreateApplication(pid), kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            for item in get(list, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                guard let t = get(item, kAXTitleAttribute) as? String, Self.bannerApps[t] != nil,
                      let b = get(item, "AXStatusLabel") as? String, !b.isEmpty else { continue }
                found[t] = b
            }
        }
        DispatchQueue.main.async { if self.badges != found { self.badges = found } }
    }

    @ObservationIgnored private var bannerSeen: Set<String>?  // q only; nil = first scan, silent
    static let bannerApps = ["Telegram": "ru.keepcoder.Telegram", "WhatsApp": "net.whatsapp.WhatsApp",
                             "Slack": "com.tinyspeck.slackmacgap"]

    /// NotificationCenter window → … → AXGroup[AXNotificationCenterBanner] desc="App, title, sub, body" with
    /// AXStaticText children id=title/subtitle/body. Needs Accessibility.
    private func scanBanners() {
        guard AXIsProcessTrusted(),
              let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first?.processIdentifier
        else { return }
        func get(_ e: AXUIElement, _ k: String) -> AnyObject? {
            var v: AnyObject?
            return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil
        }
        let wins = (get(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] ?? [])
            .filter { get($0, kAXTitleAttribute) as? String == "Notification Center" }
        var banners: [AXUIElement] = [], stack = wins, budget = 200
        while let e = stack.popLast(), budget > 0 {
            budget -= 1
            if get(e, kAXSubroleAttribute) as? String == "AXNotificationCenterBanner" { banners.append(e); continue }
            stack += get(e, kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        let silent = bannerSeen == nil || banners.count > 3  // >3 = you opened the NC panel, not new pings
        var seen = bannerSeen ?? []
        for b in banners {
            guard let id = get(b, "AXIdentifier") as? String, seen.insert(id).inserted, !silent,
                  let app = (get(b, kAXDescriptionAttribute) as? String)?.components(separatedBy: ", ").first,
                  let bundle = Self.bannerApps[app] else { continue }
            var f: [String: String] = [:]
            for t in get(b, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                if let k = get(t, "AXIdentifier") as? String { f[k] = get(t, kAXValueAttribute) as? String }
            }
            let title = [f["title"], f["subtitle"]].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            let n = Notif(rec: -1, bundle: bundle, title: title, body: f["body"] ?? "", date: Date())
            DispatchQueue.main.async { self.add([n], ping: true, count: true) }
        }
        bannerSeen = seen
    }

    /// Both paths land here; the DB copy of a banner we already showed is dropped.
    private func add(_ ns: [Notif], ping: Bool, count: Bool) {
        let fresh = ns.filter { n in
            n.rec < 0 || !items.contains {  // banner (rec -1) always wins; a DB row only duplicates a recent banner
                $0.rec < 0 && $0.title == n.title && $0.body == n.body && abs($0.date.timeIntervalSince(n.date)) < 120
            }
        }
        guard !fresh.isEmpty else { return }
        items = Array((fresh + items).prefix(60))
        if count { unseen += fresh.count }
        if ping, let n = fresh.first { onNew?(n) }
    }

    /// Re-read the instant usernoted writes db / db-wal, instead of waiting for the timer.
    private func watch() {
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let dir = (Self.db as NSString).deletingLastPathComponent
        guard let st = FSEventStreamCreate(nil, { _, info, _, _, _, _ in
            Unmanaged<Notifs>.fromOpaque(info!).takeUnretainedValue().poll()  // already on q
        }, &ctx, [dir] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.03,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)) else { return }
        FSEventStreamSetDispatchQueue(st, q)
        FSEventStreamStart(st)
        stream = st
    }

    private func poll() {
        var h: OpaquePointer?, st: OpaquePointer?
        defer { sqlite3_finalize(st); sqlite3_close(h) }
        let ids = Self.bundles.map { "'\($0)'" }.joined(separator: ",")
        let sql = """
            SELECT r.rec_id, a.identifier, r.data FROM record r JOIN app a ON a.app_id = r.app_id
            WHERE lower(a.identifier) IN (\(ids)) ORDER BY r.rec_id DESC LIMIT 25
            """
        guard sqlite3_open_v2(Self.db, &h, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              sqlite3_prepare_v2(h, sql, -1, &st, nil) == SQLITE_OK else {
            DispatchQueue.main.async { self.denied = true }
            return
        }
        let silent = seen == nil
        var seen = self.seen ?? [], new: [Notif] = []
        while sqlite3_step(st) == SQLITE_ROW {
            guard let b = sqlite3_column_text(st, 1), let blob = sqlite3_column_blob(st, 2) else { continue }
            let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(st, 2)))
            let id = sqlite3_column_int64(st, 0)
            guard seen.insert("\(id):\(data.hashValue)").inserted,
                  let n = Self.parse(id: id, bundle: String(cString: b), data: data) else { continue }
            new.append(n)
        }
        self.seen = seen
        new.sort { $0.date > $1.date }
        DispatchQueue.main.async {
            self.denied = false
            // With Accessibility, only an on-screen banner pops the card: macOS hides banners under
            // Do Not Disturb / Focus, so the notch stays quiet too. The DB still logs + counts them.
            self.add(new, ping: !silent && !AXIsProcessTrusted(), count: !silent)
        }
    }

    /// Record blob is a binary plist: { date: <abs time>, req: { titl, subt, body } }.
    static func parse(id: Int64, bundle: String, data: Data) -> Notif? {
        guard let pl = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let req = pl["req"] as? [String: Any] else { return nil }
        let title = [req["titl"], req["subt"]].compactMap { $0 as? String }.filter { !$0.isEmpty }.joined(separator: " · ")
        return Notif(rec: id, bundle: bundle, title: title, body: req["body"] as? String ?? "",
                     date: (pl["date"] as? Double).map(Date.init(timeIntervalSinceReferenceDate:)) ?? Date())
    }

    func open(_ n: Notif) {
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: n.bundle) { NSWorkspace.shared.open(u) }
    }
}

func fmtTok(_ n: Int) -> String {
    n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : n >= 1000 ? String(format: "%.0fk", Double(n) / 1e3) : "\(n)"
}
