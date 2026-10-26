import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Theme

extension Color {
    static let neon = Color(red: 0.35, green: 1.0, blue: 0.55)
    static let hot = Color(red: 1.0, green: 0.32, blue: 0.56)
    static let amber = Color(red: 1.0, green: 0.73, blue: 0.30)
    static let ice = Color(red: 0.38, green: 0.84, blue: 1.0)
    static let violet = Color(red: 0.68, green: 0.58, blue: 1.0)
    static let jade = Color(red: 0.25, green: 0.88, blue: 0.80)  // firouzeh
    static let claude = Color(red: 0.92, green: 0.52, blue: 0.38)
    static let volt = Color(red: 0.86, green: 1.0, blue: 0.36)
    static let tg = Color(red: 0.18, green: 0.68, blue: 0.95)
    static let wa = Color(red: 0.16, green: 0.85, blue: 0.42)
    static let slack = Color(red: 0.88, green: 0.12, blue: 0.35)
    static let fg = Color.white.opacity(0.93)   // read this
    static let fg2 = Color.white.opacity(0.60)  // supporting
    static let fg3 = Color.white.opacity(0.36)  // labels, chrome
    static let panel = Color(red: 0.035, green: 0.045, blue: 0.06)
}

func mono(_ s: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: s, weight: w, design: .monospaced) }
func sans(_ s: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: s, weight: w) }

let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)

extension Tab {
    var icon: String {
        switch self {
        case .agents: "sparkles"
        case .music: "waveform"
        case .clip: "doc.on.clipboard.fill"
        case .notes: "square.and.pencil"
        case .cal: "calendar"
        case .msgs: "bubble.left.and.bubble.right.fill"
        case .sys: "cpu"
        }
    }
    var label: String { self == .agents ? "agents" : rawValue }
    var accent: Color {
        switch self { case .agents: .neon; case .music: .hot; case .clip: .ice; case .notes: .amber; case .cal: .jade; case .msgs: .violet; case .sys: .volt }
    }
}

extension Notif {
    var brand: Color { tag == "WA" ? .wa : tag == "SL" ? .slack : .tg }
    var icon: String { tag == "WA" ? "phone.bubble.fill" : tag == "SL" ? "number" : "paperplane.fill" }
    var appName: String { tag == "WA" ? "WhatsApp" : tag == "SL" ? "Slack" : "Telegram" }
}

/// Every SF Symbol the UI uses — the selftest checks they exist on this macOS.
let symbols = Tab.allCases.map(\.icon) + [
    "checkmark.seal.fill", "phone.bubble.fill", "paperplane.fill", "bolt.fill", "hand.raised.fill", "brain", "bell.fill",
    "terminal", "doc.text", "pencil", "magnifyingglass", "globe", "person.2", "checklist", "wrench.and.screwdriver",
    "text.bubble", "point.3.connected.trianglepath.dotted", "moon.zzz", "arrow.clockwise", "calendar", "power",
    "bolt.circle.fill", "bolt.circle", "backward.fill", "forward.fill", "play.fill", "pause.fill", "speaker.wave.2.fill",
    "captions.bubble.fill", "music.note", "link", "chevron.left.forwardslash.chevron.right", "number", "text.alignleft",
    "textformat", "checkmark", "doc.on.doc", "trash", "lock.shield.fill", "gearshape", "arrow.triangle.2.circlepath",
    "tray", "sparkle", "hand.wave.fill", "plus.circle.fill", "checkmark.circle.fill", "circle", "flag.fill", "flag",
    "xmark", "note.text", "textformat.size.smaller", "textformat.size.larger",
    "heart.fill", "flame.fill", "eye", "figure.mind.and.body", "hand.raised.fingers.spread", "figure.stand", "drop.fill",
    "wind", "minus", "plus", "pause.fill", "forward.end.fill", "circle.fill",
    "hand.raised.fill", "hand.raised.fingers.spread.fill",
    "questionmark.bubble.fill", "questionmark", "arrow.up.forward.app", "arrow.right", "link", "checkmark.seal.fill",
    "memorychip", "network", "arrow.down", "arrow.up", "internaldrive", "thermometer.medium", "clock",
    "music.note.list", "battery.100percent", "battery.75percent", "battery.50percent", "battery.25percent", "battery.0percent",
    "chevron.left", "chevron.right", "arrow.uturn.backward",
]

/// Small uppercase mono label — the "HUD" voice.
struct Caps: View {
    let text: String
    var color: Color = .fg3
    var body: some View {
        Text(text.uppercased()).font(mono(9, .semibold)).kerning(1.3).foregroundStyle(color).lineLimit(1)
    }
}

struct Pill: View {
    let icon: String, text: String, color: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            if !text.isEmpty { Text(text.uppercased()).font(mono(9, .bold)).kerning(1) }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8).frame(height: 20)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 0.5))
    }
}

struct Empty: View {
    let icon: String, title: String, sub: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 22, weight: .light)).foregroundStyle(Color.fg3)
            Text(title).font(sans(13, .medium)).foregroundStyle(Color.fg2)
            Caps(text: sub)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Card: ViewModifier {
    var tint: Color = .white
    var hover = false
    func body(content: Content) -> some View {
        content
            .background(Color.white.opacity(hover ? 0.07 : 0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(tint.opacity(hover ? 0.35 : 0.08), lineWidth: 0.5))
    }
}

extension View {
    func card(_ tint: Color = .white, hover: Bool = false) -> some View { modifier(Card(tint: tint, hover: hover)) }
}

// MARK: - Shape + background

/// The notch: flared top corners that melt into the menu bar, rounded bottom.
struct NotchShape: Shape {
    var top: CGFloat, bottom: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(top, bottom) }
        set { (top, bottom) = (newValue.first, newValue.second) }
    }
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + top, y: r.minY + top), control: CGPoint(x: r.minX + top, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + top, y: r.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: r.minX + top + bottom, y: r.maxY), control: CGPoint(x: r.minX + top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top - bottom, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - top, y: r.maxY - bottom), control: CGPoint(x: r.maxX - top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top, y: r.minY + top))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - top, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// Engineering-paper dots, fading in below the notch. Fixed size so it never re-lays out mid-animation.
struct DotGrid: View {
    var body: some View {
        Canvas { ctx, size in
            for x in stride(from: 7.0, to: size.width, by: 14) {
                for y in stride(from: 7.0, to: size.height, by: 14) {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2)), with: .color(.white.opacity(0.08)))
                }
            }
        }
        .frame(width: AppDelegate.openSize.width, height: AppDelegate.openSize.height)
        .mask(LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom))
        .drawingGroup()
    }
}

struct NotchView: View {
    let s: NotchState, music: Music, clip: Clip, agents: Agents, notifs: Notifs, stats: Stats, bridge: Bridge

    var flare: CGFloat { s.open ? 14 : 7 }
    var lyricIsland: Bool { !s.open && music.island && music.playing && !music.lyrics.isEmpty }
    var toast: Flash? { s.open ? nil : s.flash }
    var accent: Color { toast?.color ?? (s.open ? s.tab.accent : .hot) }
    var glow: Double { s.open ? 1 : toast != nil ? 1.8 : lyricIsland ? 0.55 : 0 }

    var size: CGSize {
        if s.open { return AppDelegate.openSize }
        let w = s.notch.width + 2 * (96 + flare)  // wings always out: the messages section lives there
        if toast != nil { return CGSize(width: max(w, AppDelegate.toast.width), height: s.notch.height + AppDelegate.toast.height) }
        return lyricIsland ? CGSize(width: max(w, 620), height: s.notch.height + 56) : CGSize(width: w, height: s.notch.height)
    }

    var body: some View {
        let shape = NotchShape(top: flare, bottom: s.open ? 28 : toast != nil ? 18 : lyricIsland ? 24 : 10)
        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                Color.black
                Group {
                    LinearGradient(colors: [.black, .panel], startPoint: .top, endPoint: .bottom)
                    if s.open, s.tab == .music, let art = music.art {  // album art as ambient light
                        Image(nsImage: art).resizable().aspectRatio(contentMode: .fill).blur(radius: 60).opacity(0.3)
                    }
                    RadialGradient(colors: [accent.opacity(0.26 * glow), .clear], center: UnitPoint(x: 0.5, y: 1.25),
                                   startRadius: 0, endRadius: 420)
                    DotGrid()
                }
                .opacity(glow > 0 ? 1 : 0)
            }
            .frame(width: size.width, height: size.height, alignment: .top)  // fixed-size grid must not grow the island
            .clipShape(shape)
            .overlay(shape.stroke(LinearGradient(colors: [.clear, accent.opacity(0.5)], startPoint: .top, endPoint: .bottom),
                                  lineWidth: 1).opacity(glow > 0 ? 1 : 0))
            .shadow(color: accent.opacity(0.22 * glow), radius: 24, y: 8)
            .shadow(color: .black.opacity(glow > 0 ? 0.55 : 0), radius: 14, y: 6)

            Group {
                if s.open {
                    Expanded(s: s, music: music, clip: clip, agents: agents, notifs: notifs, stats: stats, bridge: bridge)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top)).animation(spring.delay(0.06)),
                                                removal: .opacity.animation(.easeOut(duration: 0.12))))
                } else {
                    Collapsed(s: s, music: music, agents: agents, notifs: notifs, stats: stats, lyric: lyricIsland)
                        .transition(.opacity.animation(.easeInOut(duration: 0.18)))
                }
            }
            .padding(.horizontal, flare + (s.open ? 16 : 10))
        }
        .frame(width: size.width, height: size.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(spring, value: size)
        .animation(.easeInOut(duration: 0.35), value: s.tab)
    }
}

// MARK: - Collapsed

struct Collapsed: View {
    let s: NotchState, music: Music, agents: Agents, notifs: Notifs, stats: Stats, lyric: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                left.frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: s.notch.width + 8)
                right.frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: s.notch.height)
            if let f = s.flash {
                Toast(f: f).id(f.id)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -14)).animation(spring.delay(0.08)),
                                            removal: .opacity.animation(.easeOut(duration: 0.15))))
            } else if lyric {
                LyricsNow(m: music, size: 30).frame(height: 50).padding(.bottom, 6)
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .top)))
            }
        }
    }

    @ViewBuilder var left: some View {
        do {
            HStack(spacing: 10) {
                if music.playing {
                    HStack(spacing: 5) {
                        if let a = music.art {
                            Image(nsImage: a).resizable().frame(width: 15, height: 15).clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Bars(on: true)
                    }
                }
            }
        }
    }

    func count(_ icon: String, _ n: Int, _ c: Color, pulse: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold)).symbolEffect(.pulse, isActive: pulse)
            Text("\(n)").font(mono(11, .bold)).contentTransition(.numericText())
        }
        .foregroundStyle(c)
        .shadow(color: c.opacity(0.6), radius: 4)
    }

    @ViewBuilder var right: some View {
        do {
            HStack(spacing: 10) {
                // only when the Mac is struggling: a pegged CPU or thermal pressure
                if stats.thermal.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
                    Image(systemName: "flame.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.hot)
                        .symbolEffect(.pulse).shadow(color: Color.hot.opacity(0.6), radius: 4)
                } else if stats.cpu > 0.85 {
                    count("cpu", Int(stats.cpu * 100), .hot, pulse: true)
                }
                MsgBadge(icon: "paperplane.fill", color: .tg, count: notifs.badges["Telegram"])
                MsgBadge(icon: "phone.bubble.fill", color: .wa, count: notifs.badges["WhatsApp"])
                MsgBadge(icon: "number", color: .slack, count: notifs.badges["Slack"])
            }
        }
    }
}

/// Always-on unread indicator: app icon lit in brand color + Dock badge count, dim when nothing's waiting.
struct MsgBadge: View {
    let icon: String, color: Color, count: String?
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
                .symbolEffect(.bounce, value: count)
            if let count { Text(count).font(mono(11, .bold)).foregroundStyle(.white).contentTransition(.numericText()) }
        }
        .foregroundStyle(count == nil ? Color.fg3 : color)
        .shadow(color: count == nil ? .clear : color.opacity(0.7), radius: 4)
        .animation(spring, value: count)
    }
}

/// Slim heads-up under the notch: who + which app, never the message text. Touch it with the pointer to dismiss.
struct Toast: View {
    let f: Flash
    @State private var drain = false

    var body: some View {
        HStack(spacing: 9) {
            Spacer(minLength: 0)
            ZStack {
                Circle().stroke(f.color, lineWidth: 1.5)
                    .phaseAnimator([false, true]) { v, on in v.scaleEffect(on ? 1.8 : 1).opacity(on ? 0 : 0.8) }
                        animation: { on in on ? .easeOut(duration: 1.2) : .linear(duration: 0.01) }
                Circle().fill(LinearGradient(colors: [f.color, f.color.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                Image(systemName: f.icon).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 24, height: 24)
            .shadow(color: f.color.opacity(0.75), radius: 8)
            Text(f.title).font(sans(13, .semibold)).foregroundStyle(.white).lineLimit(1)
            Caps(text: f.body, color: f.color)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: 32)
        .overlay(alignment: .bottom) {
            Capsule().fill(f.color.opacity(0.7)).frame(height: 1.5)
                .scaleEffect(x: drain ? 0 : 1, anchor: .leading)
                .padding(.horizontal, 24)
        }
        .padding(.bottom, 8)
        .onAppear { withAnimation(.linear(duration: f.secs)) { drain = true } }
    }
}

/// Fake equalizer driven by the display link — free, and never stutters.
struct Bars: View {
    let on: Bool
    var color: Color = .hot
    var body: some View {
        TimelineView(.animation(paused: !on)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4) { i in
                    let h = on ? 3 + 9 * abs(sin(t * (3.1 + Double(i) * 1.7) + Double(i))) : 3
                    Capsule().fill(color).frame(width: 2.5, height: h)
                }
            }
            .frame(height: 12, alignment: .bottom)
        }
    }
}

// MARK: - Expanded

struct Expanded: View {
    let s: NotchState, music: Music, clip: Clip, agents: Agents, notifs: Notifs, stats: Stats, bridge: Bridge
    @State private var boot = SMAppService.mainApp.status == .enabled
    @Namespace private var ns

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // two equal halves around a hole exactly the notch's width, so nothing ever slides under it
            HStack(spacing: 0) {
                HStack(spacing: 2) {
                    ForEach(Tab.allCases, id: \.self) { tab($0) }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                Color.clear.frame(width: s.notch.width + 16)
                HStack(spacing: 12) {
                    Spacer(minLength: 0)
                    Button { toggleBoot() } label: {
                        Image(systemName: boot ? "bolt.circle.fill" : "bolt.circle")
                            .foregroundStyle(boot ? Color.neon : Color.fg3)
                    }
                    .help(boot ? "Launches at login — click to stop" : "Launch at login")
                    Button { NSApp.terminate(nil) } label: { Image(systemName: "power").foregroundStyle(Color.hot.opacity(0.85)) }
                        .help("Quit TopNotch")
                    TimelineView(.periodic(from: .now, by: 1)) { tl in
                        HStack(spacing: 0) {
                            Text(Jalali.short(tl.date)).font(sans(11, .medium)).foregroundStyle(Color.jade)
                                .padding(.trailing, 7)
                                .onTapGesture { withAnimation(spring) { s.tab = .cal } }
                                .help(Jalali.long(tl.date))
                            Text(tl.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute()).foregroundStyle(Color.fg)
                            Text(tl.date, format: .dateTime.second(.twoDigits)).foregroundStyle(Color.fg3)
                                .padding(.leading, 3)
                        }
                        .font(mono(11, .semibold)).monospacedDigit()
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
            }
            .lineLimit(1)
            .buttonStyle(Press())
            .frame(height: s.notch.height)

            Group {
                switch s.tab {
                case .agents: ClaudeMenuHint()
                case .music: MusicPane(m: music)
                case .clip: ClipPane(clip: clip)
                case .notes: NotesPane()
                case .cal: CalPane()
                case .msgs: MsgsPane(n: notifs)
                case .sys: SysPane(st: stats)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .id(s.tab)
            .transition(.opacity.combined(with: .offset(y: 6)))
        }
        .padding(.bottom, 16)
        .foregroundStyle(Color.fg)
    }

    func tab(_ t: Tab) -> some View {
        let on = s.tab == t
        return Button { withAnimation(spring) { s.tab = t } } label: {
            HStack(spacing: 5) {
                Image(systemName: t.icon).font(.system(size: 11, weight: .semibold))
                if on { Text(t.label).font(mono(10, .bold)).transition(.opacity.combined(with: .scale(scale: 0.7, anchor: .leading))) }
            }
            .foregroundStyle(on ? t.accent : Color.fg3)
            .padding(.horizontal, 8).frame(height: 22)
            .background {
                if on {
                    Capsule().fill(t.accent.opacity(0.16))
                        .overlay(Capsule().stroke(t.accent.opacity(0.4), lineWidth: 0.5))
                        .matchedGeometryEffect(id: "tab", in: ns)
                }
            }
            .overlay(alignment: .topTrailing) {
                if t == .msgs, notifs.unseen > 0, !on {
                    Text("\(min(notifs.unseen, 99))").font(mono(8, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 3).frame(minWidth: 13, minHeight: 13)
                        .background(Color.hot, in: Capsule())
                        .offset(x: 4, y: -3)
                }
            }
        }
        .help(t.label)
    }

    func toggleBoot() {
        try? boot ? SMAppService.mainApp.unregister() : SMAppService.mainApp.register()
        boot = SMAppService.mainApp.status == .enabled
    }
}

struct Press: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label.contentShape(Rectangle())
            .scaleEffect(c.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: c.isPressed)
    }
}

func hhmm(_ secs: Double) -> String {
    let s = max(0, Int(secs))
    return s >= 3600 ? "\(s / 3600)h\(String(format: "%02d", s / 60 % 60))m" : String(format: "%02d:%02d", s / 60, s % 60)
}

func ago(_ d: Date) -> String {
    let s = max(0, Int(Date().timeIntervalSince(d)))
    return s < 60 ? "\(s)s" : s < 3600 ? "\(s / 60)m" : "\(s / 3600)h"
}

// MARK: - Agents

struct AgentsPane: View {
    let agents: Agents, bridge: Bridge
    var displayAsks = true
    var displayUsage = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if displayAsks, !bridge.asks.isEmpty {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(bridge.asks) { a in
                            AskCard(a: a, bridge: bridge, agent: agents.live.first { $0.id == a.session })
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .scrollIndicators(.never)
            } else {
                list
            }
        }
    }

    @ViewBuilder var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            if displayUsage { limits }
            if !bridge.connected { connect }
            let live = agents.live.filter { $0.state != .wait }, yours = agents.live.filter { $0.state == .wait }
            if agents.live.isEmpty {
                Empty(icon: "moon.zzz", title: "No agents running", sub: "go touch grass")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        section("Live", live, .neon)
                        section("Your turn", yours, .amber)
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }

    @ViewBuilder func section(_ title: String, _ list: [Agent], _ c: Color) -> some View {
        if !list.isEmpty {
            HStack(spacing: 6) {
                Circle().fill(c).frame(width: 5, height: 5).shadow(color: c, radius: 3)
                Caps(text: "\(title) · \(list.count)", color: c)
                Spacer()
                Button { withAnimation(spring) { agents.dismiss(list.map(\.id)) } } label: { Caps(text: "clear") }
                    .buttonStyle(Press())
                    .help("hide these until they do something new")
            }
            .padding(.top, 4).padding(.horizontal, 2)
            ForEach(list) { a in
                let h = bridge.host(for: a)
                Row(a: a, tok: agents.tokens[a.id] ?? 0, host: h?.name,
                    jump: h.map { h in { bridge.jump(h, cwd: a.cwd) } }) { withAnimation(spring) { agents.dismiss([a.id]) } }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
    }

    var limits: some View {
        let frac = min(1, Double(agents.block) / Double(agents.peak))
        let color: Color = frac > 0.85 ? .hot : frac > 0.6 ? .amber : .neon
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Caps(text: "5h window")
                    Spacer()
                    Text("\(Int(frac * 100))% of peak").font(mono(10, .bold)).foregroundStyle(color)
                }
                Meter(frac: frac)
            }
            stat("bolt.fill", fmtTok(agents.block), "used", color)
            if let end = agents.blockEnd {
                TimelineView(.periodic(from: .now, by: 1)) { tl in
                    stat("arrow.clockwise", hhmm(end.timeIntervalSince(tl.date)), "resets", .ice)
                }
            }
            stat("calendar", fmtTok(agents.week), "7 days", .fg2)
            if bridge.connected {
                Button { bridge.connect(false) } label: {
                    Image(systemName: "link").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.neon)
                }
                .buttonStyle(Press())
                .help("disable menu bar approvals and return prompts to Claude Code")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .card()
        .help("tokens (in + cache writes + out) in the current 5h window, vs your busiest window this week")
    }

    var connect: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill").font(.system(size: 13)).foregroundStyle(Color.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text("Approve, deny and answer Claude from the menu bar").font(sans(12, .semibold))
                Caps(text: bridge.setupError ?? "adds TopNotch hooks to ~/.claude/settings.json", color: bridge.setupError == nil ? .fg3 : .hot)
            }
            Spacer()
            Button { bridge.connect(true) } label: { Pill(icon: "link", text: "connect", color: .neon) }
                .buttonStyle(Press())
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .card(.amber)
    }

    func stat(_ icon: String, _ value: String, _ label: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(c)
                Text(value).font(sans(15, .semibold)).monospacedDigit().foregroundStyle(Color.fg)
            }
            Caps(text: label)
        }
    }
}

struct ClaudeMenuHint: View {
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 22, weight: .medium)).foregroundStyle(Color.claude)
            Text("Claude Code is in the menu bar")
                .font(sans(14, .semibold)).foregroundStyle(Color.fg)
            Caps(text: "open the terminal icon beside Wi-Fi for sessions and approvals")
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Segmented usage meter: green → amber → red by position, lit segments glow.
struct Meter: View {
    let frac: Double
    var body: some View {
        let n = 36, on = Int((frac * Double(n)).rounded(.up))
        HStack(spacing: 2) {
            ForEach(0..<n, id: \.self) { i in
                let p = Double(i) / Double(n)
                let c: Color = p > 0.85 ? .hot : p > 0.6 ? .amber : .neon
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < on ? c : Color.white.opacity(0.08))
                    .shadow(color: i < on ? c.opacity(0.6) : .clear, radius: 3)
            }
        }
        .frame(height: 9)
    }
}

struct Row: View {
    let a: Agent, tok: Int
    var host: String?
    var jump: (() -> Void)?
    var dismiss: () -> Void = {}
    @State private var hover = false

    var color: Color {
        switch a.state { case .run: .neon; case .hold: .hot; case .think: .ice; case .wait: .amber }
    }
    var stateIcon: String {
        switch a.state { case .run: "bolt.fill"; case .hold: "hand.raised.fill"; case .think: "brain"; case .wait: "bell.fill" }
    }
    var stateLabel: String {
        switch a.state { case .run: "running"; case .hold: "hold"; case .think: "thinking"; case .wait: "your turn" }
    }
    /// "Bash › ls -la" → ("terminal", "ls -la")
    var tool: (icon: String, text: String) {
        let parts = a.detail.components(separatedBy: " › ")
        guard parts.count > 1 else { return ("text.bubble", a.detail) }
        let icon = switch parts[0] {
        case "Bash": "terminal"
        case "Read": "doc.text"
        case "Edit", "Write", "MultiEdit", "NotebookEdit": "pencil"
        case "Grep", "Glob": "magnifyingglass"
        case "WebFetch", "WebSearch": "globe"
        case "Task", "Agent": "person.2"
        case "TodoWrite": "checklist"
        default: "wrench.and.screwdriver"
        }
        return (icon, parts.dropFirst().joined(separator: " › "))
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: stateIcon).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
                .symbolEffect(.pulse, isActive: a.state == .run || a.state == .think)
                .frame(width: 20, height: 20)
                .background(color.opacity(0.15), in: Circle())
            Text(a.project).font(sans(12, .semibold)).foregroundStyle(Color.fg).lineLimit(1)
                .frame(maxWidth: 104, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            AgentTag(ai: a.ai, model: a.model, host: host)
            Image(systemName: tool.icon).font(.system(size: 9)).foregroundStyle(Color.fg3)
            Text(tool.text).font(mono(10)).foregroundStyle(Color.fg2).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 6)
            if a.subs > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 9))
                    Text("\(a.subs)").font(mono(9, .bold))
                }
                .foregroundStyle(Color.ice)
            }
            Text(fmtTok(tok)).font(mono(10, .semibold)).foregroundStyle(Color.fg2)
            if hover, let jump {
                Button(action: jump) {
                    Image(systemName: "arrow.up.forward.app").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.fg2)
                        .frame(width: 26, height: 18).background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(Press())
                .help("jump to this session\(host.map { " in " + $0 } ?? "")")
            }
            if hover {
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.fg2)
                        .frame(width: 26, height: 18).background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(Press())
                .help("remove from list (comes back if it does something new)")
            } else {
                Text(ago(a.updated)).font(mono(9)).foregroundStyle(Color.fg3).frame(width: 26, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .card(color, hover: hover)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .help("\(stateLabel): \(a.detail)\(a.branch.map { "\nbranch: " + $0 } ?? "")")
    }
}

/// "CLAUDE · OPUS 5.5 · ITERM": which AI, which model, which app it's running in.
struct AgentTag: View {
    let ai: String, model: String?, host: String?

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.claude).frame(width: 5, height: 5)
            Text(ai.uppercased()).foregroundStyle(Color.claude)
            if let model { Text(prettyModel(model).uppercased()).foregroundStyle(Color.fg2) }
            if let host { Text("· " + host.uppercased()).foregroundStyle(Color.fg3) }
        }
        .font(mono(8, .bold)).kerning(0.6).lineLimit(1)
        .padding(.horizontal, 6).frame(height: 16)
        .background(Color.claude.opacity(0.08), in: Capsule())
        .overlay(Capsule().stroke(Color.claude.opacity(0.3), lineWidth: 0.5))
        .fixedSize()
    }
}

/// A session blocked on you: allow / always / deny (or tell Claude what to do instead), or pick an answer.
struct AskCard: View {
    let a: Ask, bridge: Bridge, agent: Agent?
    @State private var note = ""
    @State private var step = 0
    @State private var picked: [String: [String]] = [:]  // question → chosen labels (or your own words)
    @State private var other = ""

    var tint: Color { a.kind == .question ? .ice : .amber }
    var host: Host? { a.host ?? bridge.hosts[a.session] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: a.kind == .question ? "questionmark.bubble.fill" : "hand.raised.fill")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(tint).symbolEffect(.pulse)
                Text(a.project).font(sans(12, .semibold)).lineLimit(1)
                AgentTag(ai: "Claude", model: agent?.model, host: host?.name)
                if let b = agent?.branch { Caps(text: b) }
                Spacer(minLength: 4)
                TimelineView(.periodic(from: .now, by: 1)) { _ in Caps(text: ago(a.at)) }
                Button { bridge.terminal(a) } label: { Pill(icon: "arrow.up.forward.app", text: "terminal", color: .fg2) }
                    .help("answer in \(host?.name ?? "the terminal") instead")
            }
            if a.kind == .permission { permission } else { question }
        }
        .padding(10)
        .card(tint, hover: true)
        .buttonStyle(Press())
    }

    var permission: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(a.tool).font(mono(10, .bold)).foregroundStyle(Color.amber)
                Text(a.summary).font(mono(11)).foregroundStyle(Color.fg).lineLimit(3).truncationMode(.middle)
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .help(a.summary)
            HStack(spacing: 6) {
                Button { bridge.allow(a) } label: { Pill(icon: "checkmark", text: "allow", color: .neon) }
                if !a.suggestions.isEmpty {
                    Button { bridge.allow(a, always: true) } label: { Pill(icon: "checkmark.seal.fill", text: "always", color: .ice) }
                        .help("allow, and don't ask again for this kind of call")
                }
                Button { bridge.deny(a) } label: { Pill(icon: "xmark", text: "deny", color: .hot) }
                field($note, "or tell Claude what to do instead ↩") { bridge.deny(a, note) }
            }
        }
    }

    var question: some View {
        let q = a.questions[min(step, a.questions.count - 1)]
        let sel = picked[q.text] ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if !q.header.isEmpty { Pill(icon: "questionmark", text: q.header, color: .ice) }
                if a.questions.count > 1 { Caps(text: "\(step + 1)/\(a.questions.count)") }
                Text(q.text).font(sans(12, .medium)).lineLimit(2)
            }
            HStack(spacing: 5) {
                ForEach(q.options, id: \.label) { o in
                    let on = sel.contains(o.label)
                    Button { choose(q, o.label) } label: {
                        Text(o.label).font(sans(11, .semibold)).lineLimit(1)
                            .foregroundStyle(on ? Color.black : Color.fg)
                            .padding(.horizontal, 10).frame(height: 24)
                            .background(on ? Color.ice : Color.white.opacity(0.07), in: Capsule())
                            .overlay(Capsule().stroke(Color.ice.opacity(0.35), lineWidth: 0.5))
                    }
                    .help(o.info)
                }
                if q.multi {
                    Button { advance() } label: { Pill(icon: "arrow.right", text: last ? "send" : "next", color: sel.isEmpty ? .fg3 : .neon) }
                        .disabled(sel.isEmpty)
                }
            }
            field($other, "or type your own answer ↩") {
                picked[q.text] = (q.multi ? sel : []) + [other]
                advance()
            }
        }
    }

    var last: Bool { step + 1 >= a.questions.count }

    func field(_ text: Binding<String>, _ hint: String, submit: @escaping () -> Void) -> some View {
        TextField("", text: text, prompt: Text(hint).foregroundStyle(Color.fg3))
            .textFieldStyle(.plain).font(sans(12))
            .onSubmit { if !text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty { submit() } }
            .padding(.horizontal, 9).frame(height: 22)
            .background(Color.white.opacity(0.05), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
    }

    func choose(_ q: Question, _ label: String) {
        var sel = picked[q.text] ?? []
        if q.multi {
            if let i = sel.firstIndex(of: label) { sel.remove(at: i) } else { sel.append(label) }
            picked[q.text] = sel
        } else {
            picked[q.text] = [label]
            advance()
        }
    }

    func advance() {
        if !last { withAnimation(spring) { step += 1; other = "" }; return }
        var answers: [String: String] = [:]
        for q in a.questions {
            let sel = picked[q.text] ?? []
            let ordered = q.options.map(\.label).filter(sel.contains) + sel.filter { s in !q.options.contains { $0.label == s } }
            answers[q.text] = ordered.joined(separator: ", ")
        }
        bridge.answer(a, answers)
    }
}

// MARK: - Music

struct MusicPane: View {
    let m: Music

    var body: some View {
        if m.app == nil {
            Empty(icon: "music.note", title: "Nothing playing", sub: "open Apple Music or Spotify")
        } else if !m.lyrics.isEmpty {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    art(48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.title).font(sans(14, .bold)).lineLimit(1)
                        Text(m.artist).font(sans(12)).foregroundStyle(Color.fg2).lineLimit(1)
                    }
                    Spacer()
                    controls
                }
                LyricsNow(m: m, size: 46).frame(maxHeight: .infinity)
                progress
            }
        } else {
            HStack(alignment: .top, spacing: 18) {
                art(150)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Pill(icon: "music.note", text: m.app!, color: .hot)
                        Bars(on: m.playing)
                    }
                    .padding(.bottom, 2)
                    Text(m.title).font(sans(19, .bold)).lineLimit(1)
                    Text(m.artist).font(sans(13, .medium)).foregroundStyle(Color.fg2).lineLimit(1)
                    Text(m.album).font(sans(11)).foregroundStyle(Color.fg3).lineLimit(1)
                    Spacer(minLength: 2)
                    progress
                    controls
                }
            }
        }
    }

    func art(_ side: CGFloat) -> some View {
        Group {
            if let a = m.art { Image(nsImage: a).resizable().aspectRatio(contentMode: .fill) }
            else { Color.white.opacity(0.06).overlay(Image(systemName: "music.note").font(.system(size: side / 3)).foregroundStyle(Color.hot)) }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side / 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: side / 12, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.5), radius: side / 10, y: side / 30)
        .scaleEffect(m.playing ? 1 : 0.94)
        .animation(spring, value: m.playing)
    }

    var progress: some View {
        TimelineView(.animation(paused: !m.playing)) { tl in
            let now = m.now(tl.date)
            VStack(spacing: 3) {
                Scrub(value: now / m.dur, color: .hot) { m.seek($0 * m.dur) }
                HStack { Text(hhmm(now)); Spacer(); Text("-" + hhmm(m.dur - now)) }
                    .font(mono(9, .medium)).monospacedDigit().foregroundStyle(Color.fg3)
            }
        }
    }

    var controls: some View {
        HStack(spacing: 16) {
            Button { m.send("previous track") } label: { Image(systemName: "backward.fill") }
            Button { m.toggle() } label: {
                Image(systemName: m.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 34, height: 34)
                    .background(Color.white, in: Circle())
                    .shadow(color: .hot.opacity(m.playing ? 0.5 : 0), radius: 10)
            }
            Button { m.send("next track") } label: { Image(systemName: "forward.fill") }
            Image(systemName: "speaker.wave.2.fill").font(.system(size: 10)).foregroundStyle(Color.fg3).padding(.leading, 4)
            Scrub(value: m.volume / 100, color: .fg2) { m.setVolume($0 * 100) }.frame(width: 80)
            Button { withAnimation(spring) { m.lyricsOn.toggle() } } label: {
                Pill(icon: "music.note.list", text: "lyrics", color: m.lyricsOn ? .neon : .fg3)
            }
            .help(m.lyricsOn ? "lyrics on — click to turn them off" : "lyrics off — click to turn them on")
            if m.lyricsOn {
                Button { m.island.toggle() } label: {
                    Pill(icon: "captions.bubble.fill", text: "island", color: m.island ? .neon : .fg3)
                }
                .help("show the live lyric line under the notch while music plays")
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Color.fg)
        .buttonStyle(Press())
    }
}

/// The line being sung right now — nothing else. Swaps with a blur-slide, fills karaoke-style as it's sung.
struct LyricsNow: View {
    let m: Music, size: CGFloat

    var body: some View {
        TimelineView(.animation(paused: !m.playing)) { tl in
            let cur = m.line(at: m.now(tl.date))
            ZStack {
                if let c = cur, !c.text.isEmpty {
                    LyricLine(text: c.text, p: c.p, size: size).id(c.i).transition(lyricSwap)
                } else {
                    Bars(on: m.playing).scaleEffect(size / 18).id(cur?.i ?? -1).transition(lyricSwap)  // instrumental
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: cur?.i)
        }
    }
}

struct LyricLine: View {
    let text: String, p: Double, size: CGFloat

    var body: some View {
        let f = Font.system(size: size, weight: .black).width(.condensed)
        Text(text).font(f).foregroundStyle(Color.white.opacity(0.32))
            .overlay {
                // sung part: polished white-chrome, a highlight sweeping across, soft white glow
                TimelineView(.animation) { tl in
                    let x = -0.25 + 1.5 * (tl.date.timeIntervalSinceReferenceDate / 2.4).truncatingRemainder(dividingBy: 1)
                    Text(text).font(f)
                        .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.9), Color(white: 0.68), Color(white: 0.95)],
                                                        startPoint: .top, endPoint: .bottom))
                        .overlay {
                            LinearGradient(stops: [.init(color: .clear, location: x - 0.1), .init(color: .white, location: x),
                                                   .init(color: .clear, location: x + 0.1)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                                .mask(Text(text).font(f))
                                .blendMode(.plusLighter)
                        }
                        .mask(alignment: .leading) { GeometryReader { g in Rectangle().frame(width: g.size.width * p) } }
                        .shadow(color: .white.opacity(0.5), radius: size / 7)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .padding(.horizontal, 8)
    }
}

struct Blur: ViewModifier {
    let r: CGFloat
    func body(content: Content) -> some View { content.blur(radius: r) }
}

let lyricSwap = AnyTransition.asymmetric(
    insertion: .opacity.combined(with: .offset(y: 16)).combined(with: .scale(scale: 0.92))
        .combined(with: .modifier(active: Blur(r: 10), identity: Blur(r: 0))),
    removal: .opacity.combined(with: .offset(y: -16)).combined(with: .modifier(active: Blur(r: 10), identity: Blur(r: 0))))

/// Drag/click-to-set bar. Shows the drag live, commits on release.
struct Scrub: View {
    let value: Double, color: Color, set: (Double) -> Void
    @State private var drag: Double?
    @State private var hover = false

    var body: some View {
        GeometryReader { g in
            let v = min(1, max(0, drag ?? value))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(color).frame(width: max(4, g.size.width * v)).shadow(color: color.opacity(0.6), radius: 4)
            }
            .frame(height: hover || drag != nil ? 7 : 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag = $0.location.x / g.size.width }
                .onEnded { set(min(1, max(0, $0.location.x / g.size.width))); drag = nil })
            .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        }
        .frame(height: 12)
    }
}

// MARK: - Pane header

struct Header<Trailing: View>: View {
    let icon: String, title: String, sub: String, color: Color
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
            Text(title).font(sans(13, .semibold)).foregroundStyle(Color.fg)
            Caps(text: sub)
            Spacer()
            trailing
        }
    }
}

// MARK: - Clipboard

struct ClipPane: View {
    let clip: Clip
    @State private var yanked: String?
    @State private var hover: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Header(icon: "doc.on.clipboard.fill", title: "Clipboard", sub: "\(clip.items.count) items", color: .ice) {
                Button { withAnimation(spring) { clip.items.removeAll() } } label: { Pill(icon: "trash", text: "clear", color: .hot) }
                    .buttonStyle(Press())
            }
            if clip.items.isEmpty {
                Empty(icon: "tray", title: "Clipboard history is empty", sub: "copy something")
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(clip.items, id: \.self) { s in row(s) }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }

    func kind(_ s: String) -> (icon: String, code: Bool) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return ("link", true) }
        if Double(t.replacingOccurrences(of: ",", with: "")) != nil { return ("number", true) }
        let cmds: Set = ["git", "cd", "ls", "sudo", "brew", "npm", "npx", "pnpm", "yarn", "swift", "python", "python3", "pip",
                         "curl", "ssh", "scp", "docker", "kubectl", "make", "cargo", "go", "open", "rm", "mv", "cp", "claude"]
        if t.hasPrefix("$ ") || t.split(separator: " ").first.map({ cmds.contains(String($0)) }) == true { return ("terminal", true) }
        if t.contains(where: { "{};<>=$".contains($0) }) { return ("chevron.left.forwardslash.chevron.right", true) }
        return (t.contains("\n") ? "text.alignleft" : "textformat", false)
    }

    func row(_ s: String) -> some View {
        let k = kind(s), done = yanked == s, on = hover == s
        return HStack(spacing: 10) {
            Image(systemName: done ? "checkmark" : k.icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(done ? Color.neon : Color.ice)
                .frame(width: 22, height: 22)
                .background((done ? Color.neon : Color.ice).opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            Text(done ? "Copied" : s.replacingOccurrences(of: "\n", with: " ⏎ "))
                .font(k.code ? mono(11) : sans(12))
                .foregroundStyle(done ? Color.neon : Color.fg).lineLimit(1)
            Spacer(minLength: 4)
            if on && !done { Image(systemName: "doc.on.doc").font(.system(size: 10)).foregroundStyle(Color.fg3) }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .card(.ice, hover: on)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.1)) { hover = h ? s : nil } }
        .onTapGesture {
            clip.copy(s)
            withAnimation(spring) { yanked = s }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { withAnimation { yanked = nil } }
        }
        .help(s)
    }
}

// MARK: - WhatsApp / Telegram / Slack

struct MsgsPane: View {
    let n: Notifs
    @State private var hover: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Header(icon: "bubble.left.and.bubble.right.fill", title: "Messages", sub: "\(n.items.count) recent", color: .violet) {
                Pill(icon: "paperplane.fill", text: "telegram", color: .tg)
                Pill(icon: "phone.bubble.fill", text: "whatsapp", color: .wa)
                Pill(icon: "number", text: "slack", color: .slack)
            }
            if n.denied {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill").font(.system(size: 16)).foregroundStyle(Color.hot)
                        Text("TopNotch needs Full Disk Access to read notifications.").font(sans(13, .medium))
                    }
                    HStack(spacing: 8) {
                        Button {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                        } label: { Pill(icon: "gearshape", text: "open settings", color: .neon) }
                        Button {
                            let p = Process()
                            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                            p.arguments = ["-n", Bundle.main.bundlePath]
                            try? p.run()
                            NSApp.terminate(nil)
                        } label: { Pill(icon: "arrow.triangle.2.circlepath", text: "relaunch", color: .ice) }
                    }
                    .buttonStyle(Press())
                }
                .padding(12).card(.hot)
            } else if n.items.isEmpty {
                Empty(icon: "bubble.left.and.bubble.right.fill", title: "No messages yet", sub: "enjoy the silence")
            }
            ScrollView {
                LazyVStack(spacing: 3) { ForEach(n.items) { row($0) } }
            }
            .scrollIndicators(.never)
        }
        .onAppear { n.unseen = 0 }
    }

    func row(_ x: Notif) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: x.icon).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(LinearGradient(colors: [x.brand, x.brand.opacity(0.65)], startPoint: .top, endPoint: .bottom), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(x.title.isEmpty ? x.appName : x.title).font(sans(12, .semibold)).foregroundStyle(x.brand).lineLimit(1)
                    Spacer()
                    Text(x.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                        .font(mono(9, .medium)).foregroundStyle(Color.fg3)
                }
                Text(x.body).font(sans(12)).foregroundStyle(Color.fg).lineLimit(2)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .card(x.brand, hover: hover == x.id)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.1)) { hover = h ? x.id : nil } }
        .onTapGesture { n.open(x) }
        .help(x.body)
    }
}

// MARK: - Scratchpad: todos + notes

struct Todo: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var done = false
    var flag = false
}

enum TodoFilter: String, CaseIterable { case all, active, done }

struct NotesPane: View {
    @AppStorage("notes") private var text = ""
    @AppStorage("todos") private var raw = "[]"
    @AppStorage("padMode") private var mode = "todo"
    @AppStorage("notesSize") private var fontSize = 12.0
    @State private var draft = ""
    @State private var filter = TodoFilter.all
    @State private var hover: UUID?

    var todos: [Todo] {
        get { (try? JSONDecoder().decode([Todo].self, from: Data(raw.utf8))) ?? [] }
        nonmutating set { raw = String(data: (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8), encoding: .utf8)! }
    }
    /// flagged first, then open, then done
    var shown: [Todo] {
        todos.filter { filter == .all || (filter == .done) == $0.done }
            .sorted { ($0.done ? 2 : $0.flag ? 0 : 1) < ($1.done ? 2 : $1.flag ? 0 : 1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.amber)
                Text("Scratchpad").font(sans(13, .semibold))
                Caps(text: mode == "todo" ? "\(todos.filter { !$0.done }.count) open · \(todos.filter(\.done).count) done"
                                          : "\(text.split(whereSeparator: \.isNewline).count) lines · \(text.count) chars")
                Spacer()
                HStack(spacing: 2) {
                    seg("todo", "checklist")
                    seg("notes", "note.text")
                }
                .padding(2)
                .background(Color.white.opacity(0.05), in: Capsule())
            }
            if mode == "todo" { todoView } else { notesView }
        }
        .buttonStyle(Press())
    }

    func seg(_ m: String, _ icon: String) -> some View {
        Button { withAnimation(spring) { mode = m } } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
                Text(m.uppercased()).font(mono(9, .bold)).kerning(1)
            }
            .foregroundStyle(mode == m ? Color.black : Color.fg3)
            .padding(.horizontal, 9).frame(height: 20)
            .background(mode == m ? Color.amber : .clear, in: Capsule())
        }
    }

    // MARK: todo

    var todoView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").foregroundStyle(Color.amber)
                TextField("", text: $draft, prompt: Text("add a task, hit return").foregroundStyle(Color.fg3))
                    .textFieldStyle(.plain).font(sans(13))
                    .onSubmit(add)
            }
            .padding(.horizontal, 10).frame(height: 30)
            .card(.amber)

            HStack(spacing: 4) {
                ForEach(TodoFilter.allCases, id: \.self) { f in
                    Button { withAnimation(spring) { filter = f } } label: {
                        Caps(text: f.rawValue, color: filter == f ? .amber : .fg3)
                            .padding(.horizontal, 7).frame(height: 18)
                            .background(filter == f ? Color.amber.opacity(0.14) : .clear, in: Capsule())
                    }
                }
                Spacer()
                if todos.contains(where: \.done) {
                    Button { withAnimation(spring) { todos.removeAll(where: \.done) } } label: {
                        Pill(icon: "trash", text: "clear done", color: .hot)
                    }
                }
            }

            if shown.isEmpty {
                Empty(icon: "checklist", title: filter == .done ? "Nothing finished yet" : "All clear", sub: "type above to add one")
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) { ForEach(shown) { row($0) } }
                }
                .scrollIndicators(.never)
            }
        }
    }

    func add() {
        let t = draft.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        withAnimation(spring) { todos.insert(Todo(text: t), at: 0) }
        draft = ""
    }

    func update(_ t: Todo, _ f: (inout Todo) -> Void) {
        var all = todos
        guard let i = all.firstIndex(where: { $0.id == t.id }) else { return }
        f(&all[i])
        withAnimation(spring) { todos = all }
    }

    func row(_ t: Todo) -> some View {
        let on = hover == t.id
        return HStack(spacing: 10) {
            Button { update(t) { $0.done.toggle() } } label: {
                Image(systemName: t.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(t.done ? Color.neon : Color.fg3)
                    .contentTransition(.symbolEffect(.replace))
            }
            Text(t.text).font(sans(13)).strikethrough(t.done, color: Color.fg3)
                .foregroundStyle(t.done ? Color.fg3 : Color.fg).lineLimit(2)
            Spacer(minLength: 4)
            if on || t.flag {
                Button { update(t) { $0.flag.toggle() } } label: {
                    Image(systemName: t.flag ? "flag.fill" : "flag").font(.system(size: 11)).foregroundStyle(t.flag ? Color.hot : Color.fg3)
                }
                .help("flag: keep on top")
            }
            if on {
                Button { withAnimation(spring) { todos.removeAll { $0.id == t.id } } } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.fg3)
                }
                .help("delete")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .card(t.flag ? .hot : .amber, hover: on)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.1)) { hover = h ? t.id : nil } }
    }

    // MARK: notes

    var notesView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button { fontSize = max(10, fontSize - 1) } label: { Pill(icon: "textformat.size.smaller", text: "", color: .fg2) }
                Button { fontSize = min(20, fontSize + 1) } label: { Pill(icon: "textformat.size.larger", text: "", color: .fg2) }
                Caps(text: "\(Int(fontSize))pt")
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: { Pill(icon: "doc.on.doc", text: "copy all", color: .ice) }
                Button { withAnimation(spring) { text = "" } } label: { Pill(icon: "trash", text: "clear", color: .hot) }
                    .help("erase the scratchpad")
            }
            TextEditor(text: $text)
                .font(mono(fontSize))
                .foregroundStyle(Color.fg)
                .scrollContentBackground(.hidden)
                .padding(8)
                .card(.amber)
                .tint(.amber)
        }
    }
}
