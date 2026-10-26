import AppKit
import SwiftUI

@main @MainActor enum Main {
    static let delegate = AppDelegate()
    static func main() {
        if CommandLine.arguments.contains("--hook") { Hook.client() }
        if CommandLine.arguments.contains("--selftest") { selftest(); return }
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

enum Tab: String, CaseIterable { case agents = "ai", music, clip, notes, cal, msgs, sys }

/// A few seconds of news: the island drops into a card. Hovering it opens `tab`.
struct Flash: Equatable {
    let id = UUID(), icon: String, color: Color, app: String, title: String, body: String, tab: Tab, secs: Double
}

@Observable final class NotchState {
    var open = false
    var tab: Tab = .agents
    var notch = CGSize(width: 190, height: 32)
    var flash: Flash?
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The panels never activate the app, so the very first click has to land on a button, not just focus the window.
final class FirstClickHost<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    static let canvas = CGSize(width: 860, height: 340)  // transparent window; the shape animates inside it
    static let openSize = CGSize(width: 760, height: 280)
    static let toast = CGSize(width: 440, height: 40)  // the strip under the notch

    let state = NotchState()
    let music = Music()
    let clip = Clip()
    let agents = Agents()
    let notifs = Notifs()
    let coach = Coach()
    let stats = Stats()
    let bridge = Bridge()
    var claudeStatusItem: NSStatusItem!
    let claudePopover = NSPopover()
    var panel: NotchPanel!
    let side = Side()
    var sideWindow: NotchPanel!
    var sideClose: DispatchWorkItem?
    var inRemind = false  // pointer was already on the reminder card when it appeared
    var closeWork: DispatchWorkItem?
    var openWork: DispatchWorkItem?
    /// How long the pointer has to rest on the notch before it opens, so sweeping across the menu bar doesn't pop it.
    static let dwell = 0.12
    var inToast = false  // pointer was already over the toast; only a fresh touch dismisses it

    func applicationDidFinishLaunching(_ n: Notification) {
        panel = NotchPanel(contentRect: .init(origin: .zero, size: Self.canvas),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true  // only text fields grab the keyboard (and pin it open)
        panel.contentView = FirstClickHost(rootView: NotchView(s: state, music: music, clip: clip, agents: agents, notifs: notifs, stats: stats, bridge: bridge))

        // health reminders live in a liquid tab on the right screen edge, above the Dock
        sideWindow = NotchPanel(contentRect: .init(origin: .zero, size: Side.canvas),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        sideWindow.isOpaque = false
        sideWindow.backgroundColor = .clear
        sideWindow.hasShadow = false
        sideWindow.level = .statusBar
        sideWindow.collectionBehavior = panel.collectionBehavior
        sideWindow.ignoresMouseEvents = true
        sideWindow.becomesKeyOnlyIfNeeded = true
        sideWindow.contentView = FirstClickHost(rootView: SideView(side: side, coach: coach))
        coach.canInterrupt = { [weak self] in self?.side.mode == .idle }
        coach.onDue = { [weak self] r in self?.remind(r) }

        installClaudeStatusItem()

        place()
        panel.orderFrontRegardless()
        sideWindow.orderFrontRegardless()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
        // ponytail: global mouseMoved needs no Accessibility permission; key shortcuts would.
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.track() }
        }
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] e in
            MainActor.assumeIsolated { self?.track() }
            return e
        }
        // clicking outside closes a pinned (keyboard-focused) notch
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { if self?.state.open == true { self?.setOpen(false) } }
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard e.keyCode == 53, self?.state.open == true else { return e }  // esc
            MainActor.assumeIsolated { self?.setOpen(false) }
            return nil
        }
        // banners are read live through Accessibility; ask once (permission sticks thanks to the stable signature)
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        agents.onDone = { [weak self] name in
            NSSound(named: "Glass")?.play()
            self?.refreshClaudeStatusItem()
        }
        bridge.onAsk = { [weak self] _ in
            NSSound(named: "Ping")?.play()
            self?.refreshClaudeStatusItem()
        }
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if let self { self.bridge.discover(self.agents.live); self.refreshClaudeStatusItem() } }
        }
        stats.onEvent = { [weak self] f in self?.ping(f) }
        notifs.onNew = { [weak self] n in
            // who texted, never what: "Mani → arshyrzd" (Telegram multi-account) → "Mani"
            let who = n.title.components(separatedBy: " → ").first ?? n.title
            self?.ping(Flash(icon: n.icon, color: n.brand, app: n.appName, title: who.isEmpty ? n.appName : who,
                             body: n.appName, tab: .msgs, secs: 7))
        }

        let ev = NSAppleEventManager.shared().currentAppleEvent
        if ev?.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem)?.booleanValue != true { pin() }
    }

    private func installClaudeStatusItem() {
        claudeStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = claudeStatusItem.button {
            let image = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: "Claude Code")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(toggleClaudePopover)
            button.toolTip = "Claude Code sessions and approvals"
        }
        claudePopover.behavior = .transient
        claudePopover.animates = true
        claudePopover.contentSize = NSSize(width: 500, height: 680)
        claudePopover.contentViewController = NSHostingController(rootView: ClaudeStatusPopover(agents: agents, bridge: bridge))
        refreshClaudeStatusItem()
    }

    private func refreshClaudeStatusItem() {
        guard let button = claudeStatusItem?.button else { return }
        let waiting = bridge.asks.count
        let running = agents.live.count
        button.title = waiting > 0 ? " \(waiting)" : running > 0 ? " \(running)" : ""
        button.contentTintColor = waiting > 0 ? .systemOrange : nil
        button.toolTip = waiting > 0
            ? "\(waiting) Claude Code request\(waiting == 1 ? "" : "s") waiting for you"
            : "Claude Code · \(running) active session\(running == 1 ? "" : "s")"
    }

    @objc private func toggleClaudePopover() {
        guard let button = claudeStatusItem.button else { return }
        if claudePopover.isShown {
            claudePopover.performClose(nil)
        } else {
            claudePopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Opened from Finder/Launchpad/Spotlight, or clicked again while running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        pin()
        return false
    }

    /// Open and take keyboard focus; stays open until click-outside or esc.
    func pin() {
        setOpen(true)
        panel.makeKey()
    }

    func place() {
        guard let scr = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let f = scr.frame
        if let l = scr.auxiliaryTopLeftArea, let r = scr.auxiliaryTopRightArea, scr.safeAreaInsets.top > 0 {
            state.notch = CGSize(width: f.width - l.width - r.width, height: scr.safeAreaInsets.top)
        } else {
            state.notch = CGSize(width: 190, height: max(24, f.maxY - scr.visibleFrame.maxY))
        }
        let c = Self.canvas
        panel.setFrame(NSRect(x: f.midX - c.width / 2, y: f.maxY - c.height, width: c.width, height: c.height), display: true)
        let v = scr.visibleFrame, sc = Side.canvas  // visibleFrame stops above the Dock
        sideWindow.setFrame(NSRect(x: f.maxX - sc.width, y: v.minY + 6, width: sc.width, height: sc.height), display: true)
    }

    // MARK: edge tab

    /// The tab's current card, in screen coordinates (for hover / touch tests).
    var sideRect: NSRect {
        let f = sideWindow.frame, g = side.geo
        return NSRect(x: f.maxX - g.w - 8, y: f.minY + Side.base - 6, width: g.w + 8, height: g.h + 12)
    }

    func remind(_ r: Routine) {
        sideClose?.cancel()
        sideWindow.ignoresMouseEvents = true
        side.ends = Date().addingTimeInterval(Side.hold)
        side.mode = .remind(r)
        inRemind = sideRect.contains(NSEvent.mouseLocation)
        NSSound(named: "Tink")?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + Side.hold) { [weak self] in
            MainActor.assumeIsolated { if self?.side.mode == .remind(r) { self?.side.mode = .idle } }
        }
    }

    /// Magnet when the pointer approaches, pours open into the menu on touch, touch-and-go for reminders.
    func trackSide(_ p: NSPoint) {
        let f = sideWindow.frame
        switch side.mode {
        case .idle:
            let anchor = NSPoint(x: f.maxX, y: f.minY + Side.base + side.geo.h / 2)
            let m = max(0, 1 - hypot(p.x - anchor.x, p.y - anchor.y) / 170)
            if abs(m - side.magnet) > 0.02 || (m == 0) != (side.magnet == 0) {
                side.magnet = m
                side.pullY = min(f.height, max(0, f.maxY - p.y))
            }
            if p.x > f.maxX - 30, abs(p.y - anchor.y) < 44 {
                side.magnet = 0
                side.mode = .menu
                sideWindow.ignoresMouseEvents = false
            }
        case .menu:
            if NSEvent.pressedMouseButtons == 0 { sideWindow.ignoresMouseEvents = !sideRect.contains(p) }
            if sideRect.insetBy(dx: -14, dy: -14).contains(p) {
                sideClose?.cancel(); sideClose = nil
            } else if sideClose == nil {
                let w = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        self?.side.mode = .idle
                        self?.sideWindow.ignoresMouseEvents = true
                        self?.sideClose = nil
                    }
                }
                sideClose = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
            }
        case .remind:
            let inside = sideRect.contains(p)
            if inside && !inRemind { side.mode = .idle }   // touch to dismiss early
            inRemind = inside
        }
    }

    var toastRect: NSRect {
        let f = panel.frame, t = Self.toast
        return NSRect(x: f.midX - t.width / 2, y: f.maxY - state.notch.height - t.height, width: t.width, height: t.height)
    }

    func track() {
        let p = NSEvent.mouseLocation, f = panel.frame
        trackSide(p)
        if state.flash != nil, !state.open {  // touch-and-go: pointer entering the toast clears it
            let inside = toastRect.contains(p)
            if inside && !inToast { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { state.flash = nil } }
            inToast = inside
        }
        let size = state.open ? Self.openSize : CGSize(width: state.notch.width + 40, height: state.notch.height)
        let island = NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height, width: size.width, height: size.height)
        let hot = island.insetBy(dx: state.open ? -8 : -2, dy: state.open ? -8 : -2)
        // the window is bigger than the island: only the island itself may swallow clicks, the rest passes through
        if state.open, NSEvent.pressedMouseButtons == 0 { panel.ignoresMouseEvents = !island.contains(p) }
        if hot.contains(p) {
            closeWork?.cancel(); closeWork = nil
            if !state.open, openWork == nil {
                let w = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        self?.openWork = nil
                        guard let self, !self.state.open else { return }
                        let f = self.panel.frame, n = self.state.notch
                        let zone = NSRect(x: f.midX - n.width / 2 - 22, y: f.maxY - n.height - 2, width: n.width + 44, height: n.height + 4)
                        if zone.contains(NSEvent.mouseLocation) { self.setOpen(true) }
                    }
                }
                openWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.dwell, execute: w)
            }
        } else if !state.open {
            openWork?.cancel(); openWork = nil
        } else if state.open, closeWork == nil, !panel.isKeyWindow {
            let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.setOpen(false) } }
            closeWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: w)
        }
    }

    func setOpen(_ open: Bool) {
        closeWork = nil
        openWork?.cancel(); openWork = nil
        if open, let f = state.flash { state.tab = f.tab; state.flash = nil }  // hovering a toast takes you to it
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { state.open = open }
        panel.ignoresMouseEvents = !(open && panel.frame.contains(NSEvent.mouseLocation))
        if !open, panel.isKeyWindow {  // hand keyboard back to whatever app you were in
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    func ping(_ f: Flash) {
        inToast = toastRect.contains(NSEvent.mouseLocation)  // don't insta-dismiss if the pointer is already parked there
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { state.flash = f }
        DispatchQueue.main.asyncAfter(deadline: .now() + f.secs) { [weak self] in
            MainActor.assumeIsolated {
                guard self?.state.flash?.id == f.id else { return }  // a newer flash owns the wings now
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { self?.state.flash = nil }
            }
        }
    }
}

/// `TopNotch --selftest`: parser + 5h-window math, then a dry scan of your real logs.
func selftest() {
    let tool: [String: Any] = ["type": "assistant", "message": ["stop_reason": "tool_use",
        "content": [["type": "tool_use", "name": "Bash", "input": ["command": "ls"]]]]]
    precondition(Agents.status(tool)! == (.run, "Bash › ls"))
    let done: [String: Any] = ["type": "assistant", "message": ["stop_reason": "end_turn", "content": [["type": "text", "text": "ok"]]]]
    precondition(Agents.status(done)!.0 == .wait)
    let result: [String: Any] = ["type": "user", "message": ["content": [["type": "tool_result"]]]]
    precondition(Agents.status(result)!.0 == .think)
    precondition(Agents.status(["type": "attachment"]) == nil)

    let l = Music.lrc("[ti:x]\n[00:13.42] Yeah\n[00:14.81] \n[01:02.50] I've been tryna call")
    precondition(l.count == 3 && l[0].t == 13.42 && l[1].text.isEmpty && l[2].t == 62.5 && l[2].text == "I've been tryna call")
    // lyric matching: never pick a version far off the track's length (the "Savage Mode" remix bug)
    precondition(Music.clean("Savage Mode (feat. X) - Remastered [Explicit]") == "Savage Mode")
    let hits: [[String: Any]] = [
        ["trackName": "Purple Savage Mode II Intro (ChopNotSlop Remix)", "duration": 121.0, "syncedLyrics": "remix"],
        ["trackName": "Savage Mode", "duration": 250.0, "syncedLyrics": "real"],
        ["trackName": "Savage Mode - Live", "duration": 247.0, "syncedLyrics": "live"],
    ]
    precondition(Music.pick(hits, title: "Savage Mode", dur: 169) == nil)
    precondition(Music.pick(hits, title: "Savage Mode", dur: 249.4) == "real")
    precondition(Music.pick(hits, title: "Savage Mode", dur: 247.2) == "live")   // " - Live" cleans to the same title
    precondition(Music.pick(hits, title: "Savage Mode", dur: 121.4) == nil)      // different song, even if length fits

    let m = Music(); m.lyrics = l
    precondition(m.line(at: 5) == nil && m.line(at: 13.5)!.text == "Yeah" && m.line(at: 70)!.i == 2)

    let blob = try! PropertyListSerialization.data(fromPropertyList: ["date": 0.0, "req": ["titl": "Ali", "subt": "", "body": "yo"]],
                                                  format: .binary, options: 0)
    let n = Notifs.parse(id: 7, bundle: "ru.keepcoder.Telegram", data: blob)!
    precondition(n.tag == "TG" && n.title == "Ali" && n.body == "yo" && n.date == Date(timeIntervalSinceReferenceDate: 0))
    let sl = Notifs.parse(id: 8, bundle: "com.tinyspeck.slackmacgap", data: blob)!
    precondition(sl.tag == "SL" && sl.appName == "Slack" && Notifs.parse(id: 9, bundle: "net.whatsapp.WhatsApp", data: blob)!.tag == "WA")
    precondition(Notifs.parse(id: 1, bundle: "x", data: Data("junk".utf8)) == nil)

    // jalali: Nowruz boundaries, Saturday-first padding, fixed holidays and Fridays
    var greg = Calendar(identifier: .gregorian); greg.timeZone = Jalali.cal.timeZone
    let gd = { (y: Int, m: Int, d: Int) in greg.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }
    precondition(Jalali.ymd(gd(2026, 3, 21)) == (1405, 1, 1) && Jalali.ymd(gd(2026, 3, 20)) == (1404, 12, 29))
    precondition(Jalali.ymd(gd(2025, 3, 20)) == (1403, 12, 30) && Jalali.ymd(gd(2026, 10, 21)) == (1405, 7, 29))
    precondition(Jalali.holiday(gd(2026, 3, 21)) == "نوروز" && Jalali.holiday(gd(2026, 4, 2)) == "روز طبیعت")
    precondition(Jalali.off(gd(2026, 10, 23)) && !Jalali.off(gd(2026, 10, 21)))  // a Friday, then a Wednesday
    let mehr = Jalali.grid(Jalali.month(of: gd(2026, 10, 21)))
    precondition(mehr.count == 4 + 30 && mehr[4].map { Jalali.ymd($0) } ?? (0, 0, 0) == (1405, 7, 1))  // 1 Mehr 1405 is a Wednesday
    precondition(Jalali.num(1405) == "۱۴۰۵" && Jalali.year(gd(2026, 3, 20)).nowruz == 1)

    for name in symbols { precondition(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "missing SF Symbol \(name)") }

    // reminders: most overdue enabled one wins; nothing due early; disabled ones are skipped
    let now = Date(), rs = Coach.defaults
    var last = Dictionary(uniqueKeysWithValues: rs.map { ($0.id, now) })
    precondition(Coach.next(rs, last: last, now: now) == nil)
    last["water"] = now.addingTimeInterval(-61 * 60); last["blink"] = now.addingTimeInterval(-50 * 60)
    precondition(Coach.next(rs, last: last, now: now)?.id == "blink")  // 30m overdue beats 1m overdue
    var off = rs; off[0].on = false
    precondition(Coach.next(off, last: last, now: now)?.id == "water")

    precondition(Stats.parseProc("  412  23.5  81232 Google Chrome Helper") == Proc(id: 412, name: "Google Chrome Helper", cpu: 23.5, mem: 81232 * 1024))
    precondition(Stats.parseProc("PID %CPU") == nil)
    precondition(fmtBytes(512) == "512B" && fmtBytes(1536) == "1.5K" && fmtBytes(250 * 1024 * 1024) == "250M")
    precondition(mins(45) == "45m" && mins(192) == "3h12m")
    precondition(Stats.ticks() != nil && Stats.memUsed()! > 0)
    print("battery:", Stats.battery().map { "\($0)" } ?? "none", "| top:", Stats.topProcs().map(\.name))

    let h = Calendar.current.dateInterval(of: .hour, for: Date())!.start
    let b = Agents.blocks([(h.addingTimeInterval(-10 * 3600), 50), (h.addingTimeInterval(-9 * 3600), 50),
                           (h.addingTimeInterval(60), 10), (h.addingTimeInterval(120), 5)])
    precondition(b.peak == 100 && b.week == 115 && b.current!.1 == 15 && b.current!.0 == h.addingTimeInterval(5 * 3600))

    let recent = FileManager.default.enumerator(at: Agents.root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
    for u in recent where u.pathExtension == "jsonl" && !u.path.contains("/subagents/") {
        guard let m = try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              Date().timeIntervalSince(m) < 900, let t = Agents.tail(u) else { continue }
        print(t.0.rawValue, t.2.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "?", "|", t.1.prefix(60), "|", fmtTok(Agents.usage(u).reduce(0) { $0 + $1.2 }))
    }
    print("selftest ok")
}
