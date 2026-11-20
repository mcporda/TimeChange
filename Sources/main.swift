// TimeChange — 菜单栏多时区时钟
// 只改变"显示"，从不修改系统时区或系统时间。
import AppKit
import SwiftUI
import ServiceManagement

let kLocal = "__local__"   // 特殊值：跟随系统当前时区（旅行时自动切换）

// MARK: - 数据模型

struct ClockEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var label: String
    var tz: String          // IANA 时区 ID，或 kLocal
    var showInBar: Bool     // 当前在菜单栏显示的「主时钟」（只有一个为 true）

    var timeZone: TimeZone {
        tz == kLocal ? TimeZone.current : (TimeZone(identifier: tz) ?? .current)
    }
    var isLocal: Bool { tz == kLocal }
}

enum BarStyle: String, Codable, CaseIterable, Identifiable {
    case native, dual, dot
    var id: String { rawValue }
    var title: String { ["native": "原生一致", "dual": "双城并排", "dot": "一点提示"][rawValue]! }
    var desc: String { ["native": "和系统时钟一模一样", "dual": "同时看两个时区", "dot": "非当地时间前加橙点"][rawValue]! }
}

struct Settings: Codable, Equatable {
    var clocks: [ClockEntry]
    var showSeconds = false
    var use24h = true
    var showWeekday = true
    var showDate = true
    var showLabels = false
    var separator = "  |  "
    // v3 新增（可选，兼容旧数据）
    var style: BarStyle?
    var homeId: UUID?
    var hideSystemClock: Bool?

    var barStyle: BarStyle { style ?? .native }
    var hidesSystemClock: Bool { hideSystemClock ?? true }

    var primary: ClockEntry? { clocks.first { $0.showInBar } ?? clocks.first }
    /// 双城并排的第二个时间：列表里主时钟之外的第一个
    var secondary: ClockEntry? { clocks.first { $0.id != primary?.id } }
}

let zhCity: [String: String] = [
    "Shanghai": "上海", "Tokyo": "东京", "London": "伦敦", "Los_Angeles": "洛杉矶", "New_York": "纽约",
    "Paris": "巴黎", "Hong_Kong": "香港", "Taipei": "台北", "Singapore": "新加坡", "Seoul": "首尔",
    "Sydney": "悉尼", "Chicago": "芝加哥", "Denver": "丹佛", "Berlin": "柏林", "Dubai": "迪拜",
    "Bangkok": "曼谷", "Vancouver": "温哥华", "Toronto": "多伦多", "Macau": "澳门", "Honolulu": "檀香山",
    "Phoenix": "凤凰城", "Rome": "罗马", "Madrid": "马德里", "Amsterdam": "阿姆斯特丹", "Moscow": "莫斯科",
    "Kolkata": "加尔各答", "Jakarta": "雅加达", "Kuala_Lumpur": "吉隆坡", "Auckland": "奥克兰", "Zurich": "苏黎世",
]

func cityName(_ id: String) -> String {
    let real = id == kLocal ? TimeZone.current.identifier : id
    let last = real.split(separator: "/").last.map(String.init) ?? real
    return zhCity[last] ?? last.replacingOccurrences(of: "_", with: " ")
}

final class Store: ObservableObject {
    static let shared = Store()
    private let key = "settings.v1"

    @Published var s: Settings { didSet { if s != oldValue { save() } } }

    private init() {
        if let d = UserDefaults.standard.data(forKey: key),
           var v = try? JSONDecoder().decode(Settings.self, from: d) {
            if !UserDefaults.standard.bool(forKey: "migrated.v2") {
                v.showLabels = false; v.showDate = true; v.showWeekday = true; v.use24h = true
                UserDefaults.standard.set(true, forKey: "migrated.v2")
                if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: key) }
            }
            // v3：默认时钟改为 本机 / 上海 / 东京 / 伦敦，取消「家」
            if !UserDefaults.standard.bool(forKey: "migrated.v4") {
                v.clocks = Store.defaultClocks; v.homeId = nil
                UserDefaults.standard.set(true, forKey: "migrated.v4")
                if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: key) }
            }
            s = v
        } else {
            UserDefaults.standard.set(true, forKey: "migrated.v2")
            UserDefaults.standard.set(true, forKey: "migrated.v4")
            s = Settings(clocks: Store.defaultClocks)
        }
    }

    static var defaultClocks: [ClockEntry] {[
        ClockEntry(label: "本机", tz: kLocal, showInBar: true),
        ClockEntry(label: "上海", tz: "Asia/Shanghai", showInBar: false),
        ClockEntry(label: "东京", tz: "Asia/Tokyo", showInBar: false),
        ClockEntry(label: "伦敦", tz: "Europe/London", showInBar: false),
    ]}

    private func save() {
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: key) }
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }

    func select(_ id: UUID) {
        for i in s.clocks.indices { s.clocks[i].showInBar = (s.clocks[i].id == id) }
    }
}

extension Notification.Name { static let settingsChanged = Notification.Name("TimeChange.settingsChanged") }

// MARK: - 格式化

enum Fmt {
    static func fmt(_ date: Date, _ tz: TimeZone, date showDate: Bool, weekday: Bool, seconds: Bool, h24: Bool) -> String {
        let loc = Locale.autoupdatingCurrent
        var parts: [String] = []
        if showDate { parts.append(DateFormatter.dateFormat(fromTemplate: "MMMd", options: 0, locale: loc) ?? "M/d") }
        if weekday { parts.append("EEE") }
        var t = h24 ? "HH:mm" : "ah:mm"
        if seconds { t += ":ss" }
        parts.append(t)
        let f = DateFormatter()
        f.locale = loc
        f.timeZone = tz
        f.dateFormat = parts.joined(separator: " ")
        return f.string(from: date)
    }

    static func time(_ date: Date, _ tz: TimeZone, _ s: Settings, seconds: Bool = false) -> String {
        fmt(date, tz, date: false, weekday: false, seconds: seconds, h24: s.use24h)
    }

    /// 菜单栏上的文字（不同样式）
    static func bar(_ now: Date, _ s: Settings) -> (dot: Bool, main: String, second: String?) {
        guard let p = s.primary else { return (false, "--:--", nil) }
        let tz = p.timeZone
        switch s.barStyle {
        case .native:
            return (false, fmt(now, tz, date: s.showDate, weekday: s.showWeekday, seconds: s.showSeconds, h24: s.use24h), nil)
        case .dot:
            let foreign = tz.secondsFromGMT(for: now) != TimeZone.current.secondsFromGMT(for: now)
            return (foreign, fmt(now, tz, date: s.showDate, weekday: s.showWeekday, seconds: s.showSeconds, h24: s.use24h), nil)
        case .dual:
            let other = s.secondary
            let main = fmt(now, tz, date: false, weekday: s.showWeekday, seconds: s.showSeconds, h24: s.use24h)
            return (false, main, other.map { time(now, $0.timeZone, s, seconds: s.showSeconds) })
        }
    }

    static func offset(_ tz: TimeZone, at date: Date = Date()) -> String {
        let sec = tz.secondsFromGMT(for: date)
        let h = sec / 3600, m = abs(sec % 3600) / 60
        return m == 0 ? String(format: "GMT%+d", h) : String(format: "GMT%+d:%02d", h, m)
    }

    static func diff(_ tz: TimeZone, at date: Date = Date()) -> String {
        let d = tz.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        if d == 0 { return "与当地相同" }
        let h = Double(d) / 3600
        let s = h == h.rounded() ? String(format: "%+.0f", h) : String(format: "%+.1f", h)
        return "\(s) 小时"
    }

    /// 「今天 / 明天 / 昨天」相对系统当地日期
    static func dayWord(_ tz: TimeZone, _ now: Date) -> String {
        var a = Calendar(identifier: .gregorian); a.timeZone = TimeZone.current
        var b = Calendar(identifier: .gregorian); b.timeZone = tz
        let da = a.dateComponents([.year, .month, .day], from: now)
        let db = b.dateComponents([.year, .month, .day], from: now)
        guard let x = a.date(from: da), let y = a.date(from: db) else { return "" }
        let n = a.dateComponents([.day], from: x, to: y).day ?? 0
        return n == 0 ? "今天" : (n > 0 ? "明天" : "昨天")
    }

    static func hm(_ tz: TimeZone, _ now: Date) -> (Int, Int, Int) {
        var c = Calendar(identifier: .gregorian); c.timeZone = tz
        let k = c.dateComponents([.hour, .minute, .second], from: now)
        return (k.hour ?? 0, k.minute ?? 0, k.second ?? 0)
    }
}

// MARK: - 系统时钟：只改显示样式（数字 ↔ 模拟小图标），不碰时区和时间

enum SystemClock {
    static let domain = "com.apple.menuextra.clock"
    static let savedKey = "originalIsAnalog"

    static func isAnalog() -> Bool {
        CFPreferencesCopyAppValue("IsAnalog" as CFString, domain as CFString) as? Bool ?? false
    }

    static func set(analog: Bool) {
        guard isAnalog() != analog else { return }
        run("defaults write \(domain) IsAnalog -bool \(analog); killall ControlCenter 2>/dev/null; true")
    }

    static func shrink() {
        let d = UserDefaults.standard
        if d.object(forKey: savedKey) == nil { d.set(isAnalog(), forKey: savedKey) }
        set(analog: true)
    }

    static func restore() {
        let d = UserDefaults.standard
        guard let orig = d.object(forKey: savedKey) as? Bool else { return }
        d.removeObject(forKey: savedKey)
        set(analog: orig)
    }

    private static func run(_ cmd: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", cmd]
        try? p.run(); p.waitUntilExit()
    }
}

// MARK: - 视觉常量

enum UI {
    static let accent = Color(red: 0xE8 / 255, green: 0x83 / 255, blue: 0x3A / 255)
    static let bg = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1F / 255)
    static let sidebar = Color(red: 0x18 / 255, green: 0x18 / 255, blue: 0x1B / 255)
    static let card = Color(red: 0x23 / 255, green: 0x23 / 255, blue: 0x27 / 255)
    static let tile = Color(red: 0x2C / 255, green: 0x2C / 255, blue: 0x30 / 255)
    static let text = Color(red: 0xEC / 255, green: 0xEC / 255, blue: 0xEF / 255)
    static let sub = Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255)
    static let hair = Color.white.opacity(0.08)
}

/// 自绘表盘：白天白底、夜晚黑底，橙色中心点
struct Dial: View {
    let tz: TimeZone
    let now: Date
    var size: CGFloat = 64
    var ticks = true

    var body: some View {
        let (h, m, _) = Fmt.hm(tz, now)
        let day = h >= 7 && h < 19
        Canvas { ctx, sz in
            let r = min(sz.width, sz.height) / 2
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let face = day ? Color(white: 0.96) : Color(red: 0.07, green: 0.07, blue: 0.08)
            let hand = day ? Color(red: 0.11, green: 0.11, blue: 0.12) : Color(white: 0.96)
            let tick = day ? Color(white: 0.72) : Color(white: 0.3)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(face))
            func line(_ angle: Double, _ from: CGFloat, _ to: CGFloat, _ w: CGFloat, _ col: Color) {
                let a = angle * .pi / 180
                var p = Path()
                p.move(to: CGPoint(x: c.x + sin(a) * from, y: c.y - cos(a) * from))
                p.addLine(to: CGPoint(x: c.x + sin(a) * to, y: c.y - cos(a) * to))
                ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: w, lineCap: .round))
            }
            if ticks { for i in 0..<12 { line(Double(i) * 30, r * 0.78, r * 0.9, max(1, r * 0.06), tick) } }
            line((Double(h % 12) + Double(m) / 60) * 30, 0, r * 0.47, max(1.6, r * 0.1), hand)
            line(Double(m) * 6, 0, r * 0.73, max(1.2, r * 0.063), hand)
            let d = max(3, r * 0.17)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)), with: .color(UI.accent))
        }
        .frame(width: size, height: size)
    }
}

func clockTitle(_ c: ClockEntry) -> String {
    let city = cityName(c.tz)
    return c.label == city ? c.label : "\(c.label) · \(city)"
}

func clockSub(_ c: ClockEntry, _ now: Date) -> String {
    if c.isLocal { return cityName(kLocal) }
    let d = Fmt.diff(c.timeZone, at: now).replacingOccurrences(of: " 小时", with: "h").replacingOccurrences(of: "与当地相同", with: "同本机")
    let w = Fmt.dayWord(c.timeZone, now)
    return w == "今天" ? d : "\(w) \(d)"
}

// MARK: - 下拉面板（面板 C：表盘卡片）

struct PanelView: View {
    @ObservedObject var store: Store
    @ObservedObject var updater = Updater.shared
    var onSettings: () -> Void
    var onAdd: () -> Void
    var onQuit: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let now = tl.date
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("世界时钟").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("点选切换菜单栏").font(.system(size: 11)).foregroundStyle(UI.sub)
                }
                .padding(.horizontal, 4).padding(.top, 2)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(store.s.clocks) { c in
                        ClockCard(c: c, now: now, selected: store.s.primary?.id == c.id) { store.select(c.id) }
                    }
                }

                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1).padding(.horizontal, 4)
                VStack(spacing: 0) {
                    if let r = updater.available {
                        PanelRow(title: updater.busy ? "正在更新…" : "更新到 v\(r.version)", accent: true) { updater.install() }
                    }
                    PanelRow(title: "添加时区…", action: onAdd)
                    PanelRow(title: "设置…", action: onSettings)
                    PanelRow(title: "退出 TimeChange", action: onQuit)
                }
            }
            .padding(8)
            .frame(width: 320)
            .foregroundStyle(UI.text)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.97))
            )
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .environment(\.colorScheme, .dark)
        .focusEffectDisabled()
    }
}

struct ClockCard: View {
    let c: ClockEntry
    let now: Date
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Dial(tz: c.timeZone, now: now, size: 30, ticks: false)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(c.label).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(clockSub(c, now)).font(.system(size: 10)).foregroundStyle(UI.sub).lineLimit(1)
                    }
                    Text(Fmt.time(now, c.timeZone, Store.shared.s))
                        .font(.system(size: 17, weight: .medium).monospacedDigit())
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover ? Color(white: 0.21) : UI.tile))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(UI.accent, lineWidth: selected ? 1.5 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

struct PanelRow: View {
    let title: String
    var accent = false
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: accent ? .semibold : .regular))
                .foregroundStyle(accent ? UI.accent : UI.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Color.white.opacity(0.1) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// 无边框浮层，贴在菜单栏图标下方，点外面自动收起
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - 菜单栏控制器

final class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var timer: Timer?
    var panel: FloatingPanel?
    var monitor: Any?
    var settingsWindow: NSWindow?
    let store = Store.shared
    let nav = SettingsNav()

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "TimeChangeClock"
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: .settingsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .NSSystemTimeZoneDidChange, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)

        refresh()
        scheduleTimer()
        Updater.shared.startAutoCheck()
        if store.s.hidesSystemClock { SystemClock.shrink() }
    }

    func applicationWillTerminate(_ n: Notification) { SystemClock.restore() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings(); return true
    }

    @objc func settingsChanged() {
        refresh()
        if store.s.hidesSystemClock { SystemClock.shrink() } else { SystemClock.restore() }
    }

    func scheduleTimer() {
        timer?.invalidate()
        let fire = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) + 1.0)
        let t = Timer(fireAt: fire, interval: 1, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    static let barFont: NSFont = {
        let base = NSFont.menuBarFont(ofSize: 0)
        let d = base.fontDescriptor.addingAttributes([.featureSettings: [[
            NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
            NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]]])
        return NSFont(descriptor: d, size: base.pointSize) ?? base
    }()

    @objc func refresh() {
        NSTimeZone.resetSystemTimeZone()
        let (dot, main, second) = Fmt.bar(Date(), store.s)
        let f = Self.barFont
        let r = NSMutableAttributedString()
        if dot {
            r.append(NSAttributedString(string: "● ", attributes: [
                .font: NSFont.systemFont(ofSize: f.pointSize * 0.55),
                .foregroundColor: NSColor(red: 1, green: 0.62, blue: 0.26, alpha: 1),
                .baselineOffset: f.pointSize * 0.18]))
        }
        r.append(NSAttributedString(string: main, attributes: [.font: f]))
        if let s = second {
            r.append(NSAttributedString(string: "  " + s, attributes: [.font: f, .foregroundColor: NSColor.secondaryLabelColor]))
        }
        item.button?.attributedTitle = r
    }

    // MARK: 面板

    @objc func togglePanel() {
        if panel?.isVisible == true { closePanel() } else { showPanel() }
    }

    func showPanel() {
        guard let button = item.button, let bw = button.window else { return }
        let view = PanelView(store: store,
                             onSettings: { [weak self] in self?.closePanel(); self?.openSettings() },
                             onAdd: { [weak self] in self?.closePanel(); self?.nav.page = .clocks; self?.nav.addRequested = true; self?.openSettings() },
                             onQuit: { NSApp.terminate(nil) })
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let p = panel ?? FloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.contentView = host
        let bf = bw.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = bw.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        var x = bf.midX - size.width / 2
        x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
        p.setFrame(NSRect(x: x, y: bf.minY - size.height - 6, width: size.width, height: size.height), display: true)
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.14; p.animator().alphaValue = 1 }
        panel = p
        button.highlight(true)
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
    }

    func closePanel() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        panel?.orderOut(nil)
        item.button?.highlight(false)
    }

    // MARK: 设置窗口

    func openSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 660),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = NSColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1F / 255, alpha: 1)
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: SettingsRoot().environmentObject(store).environmentObject(nav))
            w.setContentSize(NSSize(width: 980, height: 660))
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - 设置界面

final class SettingsNav: ObservableObject {
    enum Page: String { case bar, clocks, general }
    @Published var page: Page = .bar
    @Published var addRequested = false
}

struct SettingsRoot: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: SettingsNav

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            ScrollView {
                Group {
                    switch nav.page {
                    case .bar: BarPage()
                    case .clocks: ClocksPage()
                    case .general: GeneralPage()
                    }
                }
                .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 980, height: 660)
        .background(UI.bg)
        .foregroundStyle(UI.text)
        .environment(\.colorScheme, .dark)
        .tint(UI.accent)
        .focusEffectDisabled()
    }
}

struct Sidebar: View {
    @EnvironmentObject var nav: SettingsNav

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tl in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Dial(tz: .current, now: tl.date, size: 34, ticks: false)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("TimeChange").font(.system(size: 14, weight: .semibold))
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0").font(.system(size: 11)).foregroundStyle(UI.sub)
                    }
                }
                .padding(.horizontal, 6).padding(.bottom, 16)
                NavItem(icon: "menubar.rectangle", title: "菜单栏", page: .bar)
                NavItem(icon: "clock", title: "时钟", page: .clocks)
                NavItem(icon: "gearshape", title: "通用", page: .general)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.top, 52)
            .frame(width: 208)
            .frame(maxHeight: .infinity)
            .background(UI.sidebar)
            .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1) }
        }
    }
}

struct NavItem: View {
    @EnvironmentObject var nav: SettingsNav
    let icon: String, title: String, page: SettingsNav.Page
    var body: some View {
        let on = nav.page == page
        Button { nav.page = page } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 18).foregroundStyle(on ? UI.accent : UI.sub)
                Text(title).font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(on ? UI.accent.opacity(0.18) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SectionTitle: View {
    let t: String
    var body: some View { Text(t).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(white: 0.63)).kerning(0.3) }
}

struct CardBox<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(UI.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(UI.hair, lineWidth: 0.5))
    }
}

struct Radio: View {
    let on: Bool
    var size: CGFloat = 16
    var body: some View {
        Circle().strokeBorder(on ? UI.accent : Color(white: 0.35), lineWidth: on ? size * 0.31 : 1.5)
            .frame(width: size, height: size)
    }
}

struct MiniSystemIcon: View {   // 菜单栏里系统小表盘的示意
    var body: some View {
        ZStack {
            Circle().stroke(Color.white, lineWidth: 1.1)
            Path { p in p.move(to: CGPoint(x: 7, y: 7)); p.addLine(to: CGPoint(x: 9.6, y: 8.6)) }
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        }
        .frame(width: 14, height: 14)
    }
}

struct BarPage: View {
    @EnvironmentObject var store: Store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let now = tl.date
            VStack(alignment: .leading, spacing: 22) {
                Text("菜单栏").font(.system(size: 20, weight: .semibold))

                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(t: "显示样式")
                    HStack(spacing: 12) {
                        ForEach(BarStyle.allCases) { st in StyleCard(style: st, now: now) }
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    CardBox {
                        HStack {
                            SectionTitle(t: "菜单栏显示哪个时钟")
                            Spacer()
                            Button("＋ 添加时区") { addClock() }
                                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(UI.accent)
                        }
                        VStack(spacing: 0) {
                            ForEach(store.s.clocks) { c in
                                Button { store.select(c.id) } label: {
                                    HStack(spacing: 12) {
                                        Dial(tz: c.timeZone, now: now, size: 30, ticks: false)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(c.label).font(.system(size: 13, weight: .semibold))
                                            Text(c.isLocal ? "跟随系统 · 现在是\(cityName(kLocal))" : (c.label == cityName(c.tz) ? "" : "\(cityName(c.tz)) · ") + Fmt.diff(c.timeZone, at: now))
                                                .font(.system(size: 11)).foregroundStyle(UI.sub)
                                        }
                                        Spacer()
                                        Text(Fmt.time(now, c.timeZone, store.s)).font(.system(size: 15).monospacedDigit())
                                        Radio(on: store.s.primary?.id == c.id, size: 18)
                                    }
                                    .padding(.vertical, 7)
                                    .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if store.s.barStyle == .dual {
                            Text("双城并排时，第二个时间显示「\(store.s.secondary?.label ?? "")」（列表中排在最前的另一个时钟，可在「时钟」里调整顺序）。")
                                .font(.system(size: 11)).foregroundStyle(UI.sub)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1.3)

                    CardBox {
                        SectionTitle(t: "格式")
                        Toggle("日期", isOn: $store.s.showDate).toggleStyle(OrangeSwitch())
                        Toggle("星期", isOn: $store.s.showWeekday).toggleStyle(OrangeSwitch())
                        Toggle("秒", isOn: $store.s.showSeconds).toggleStyle(OrangeSwitch())
                        Toggle("24 小时制", isOn: $store.s.use24h).toggleStyle(OrangeSwitch())
                        Rectangle().fill(UI.hair).frame(height: 1)
                        Toggle("隐藏系统数字时钟", isOn: hideBinding(store)).toggleStyle(OrangeSwitch())
                        LoginToggle()
                    }
                    .frame(width: 290)
                }
            }
        }
    }

    func addClock() {
        let e = ClockEntry(label: "新时钟", tz: "Europe/London", showInBar: false)
        store.s.clocks.append(e)
    }
}

func hideBinding(_ store: Store) -> Binding<Bool> {
    Binding(get: { store.s.hidesSystemClock }, set: { store.s.hideSystemClock = $0 })
}

struct OrangeSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack {
                configuration.label.font(.system(size: 13))
                Spacer()
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? UI.accent : Color(white: 0.23)).frame(width: 32, height: 19)
                    Circle().fill(.white).frame(width: 15, height: 15).padding(2)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.85), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct LoginToggle: View {
    @State private var on = SMAppService.mainApp.status == .enabled
    @State private var err = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("登录时启动", isOn: $on).toggleStyle(OrangeSwitch())
                .onChange(of: on) { _, v in
                    do { v ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister(); err = "" }
                    catch { err = "设置失败：\(error.localizedDescription)" }
                }
            if !err.isEmpty { Text(err).font(.system(size: 11)).foregroundStyle(UI.sub) }
        }
    }
}

struct StyleCard: View {
    @EnvironmentObject var store: Store
    let style: BarStyle
    let now: Date
    @State private var hover = false

    var body: some View {
        var s = store.s
        s.style = style
        let (dot, main, second) = Fmt.bar(now, s)
        let selected = store.s.barStyle == style
        return Button { store.s.style = style } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if dot || style == .dot {
                        Circle().fill(Color(red: 1, green: 0.62, blue: 0.26)).frame(width: 6, height: 6)
                            .opacity(dot ? 1 : 0.35)
                    }
                    Text(main).font(.system(size: 13).monospacedDigit()).lineLimit(1)
                    if let second { Text(second).font(.system(size: 13).monospacedDigit()).foregroundStyle(.white.opacity(0.62)) }
                    MiniSystemIcon()
                }
                .frame(height: 52)
                .overlay(alignment: .bottom) { Rectangle().fill(UI.hair).frame(height: 1) }
                HStack {
                    Text(style.title).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Radio(on: selected)
                }
                Text(style.desc).font(.system(size: 11)).foregroundStyle(UI.sub)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hover ? Color(white: 0.17) : Color(red: 0x26 / 255, green: 0x26 / 255, blue: 0x2A / 255)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? UI.accent : UI.hair, lineWidth: selected ? 2 : 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct ClocksPage: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: SettingsNav
    @State private var picking: UUID?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tl in
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("时钟").font(.system(size: 20, weight: .semibold))
                    Spacer()
                    Button { add() } label: {
                        Text("＋ 添加时区").font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(UI.accent)).foregroundStyle(.white)
                    }.buttonStyle(.plain)
                }
                CardBox {
                    ForEach($store.s.clocks) { $c in
                        HStack(spacing: 12) {
                            Dial(tz: c.timeZone, now: tl.date, size: 30, ticks: false)
                            TextField("名称", text: $c.label)
                                .textFieldStyle(.plain).font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                                .frame(width: 110)
                            Button { picking = c.id } label: {
                                HStack(spacing: 6) {
                                    Text(c.isLocal ? "本机（跟随系统）" : "\(cityName(c.tz)) · \(c.tz)").lineLimit(1)
                                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
                                }
                                .font(.system(size: 12))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                            }.buttonStyle(.plain)
                            Spacer()
                            iconButton("chevron.up") { move(c.id, -1) }
                            iconButton("chevron.down") { move(c.id, 1) }
                            iconButton("trash") { store.s.clocks.removeAll { $0.id == c.id } }
                                .disabled(store.s.clocks.count <= 1)
                        }
                        .padding(.vertical, 4)
                    }
                }
                Text("「本机」跟随系统时区，出去旅行时自动切到当地；其他时钟固定在你选的时区。只改显示，不会更改系统时区和系统时间。")
                    .font(.system(size: 11)).foregroundStyle(UI.sub)
            }
        }
        .sheet(item: Binding(get: { picking.map { IDBox(id: $0) } }, set: { picking = $0?.id })) { box in
            ZonePicker { tz in
                if let i = store.s.clocks.firstIndex(where: { $0.id == box.id }) {
                    store.s.clocks[i].tz = tz
                    if ["新时钟", ""].contains(store.s.clocks[i].label) { store.s.clocks[i].label = cityName(tz) }
                }
                picking = nil
            } cancel: { picking = nil }
            .environment(\.colorScheme, .dark)
        }
        .onAppear { if nav.addRequested { nav.addRequested = false; add() } }
        .onChange(of: nav.addRequested) { _, v in if v { nav.addRequested = false; add() } }
    }

    func iconButton(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 11)).foregroundStyle(UI.sub)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
        }.buttonStyle(.plain)
    }

    func add() {
        let e = ClockEntry(label: "新时钟", tz: "Europe/London", showInBar: false)
        store.s.clocks.append(e)
        picking = e.id
    }

    func move(_ id: UUID, _ d: Int) {
        guard let i = store.s.clocks.firstIndex(where: { $0.id == id }) else { return }
        let j = i + d
        guard store.s.clocks.indices.contains(j) else { return }
        store.s.clocks.swapAt(i, j)
    }
}

// MARK: - 自动更新（从 GitHub Releases 检查新版本，一键下载 DMG 并替换自身）

final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "mcporda/TimeChange"

    struct Release { let version: String; let dmg: URL?; let page: URL }

    @Published var available: Release?
    @Published var status = ""
    @Published var busy = false
    private var timer: Timer?

    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func newer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    var autoCheck: Bool {
        get { UserDefaults.standard.object(forKey: "autoCheckUpdates") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoCheckUpdates"); objectWillChange.send() }
    }

    func startAutoCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.autoCheck else { return }
            self.check(silent: true)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            guard let self, self.autoCheck else { return }
            self.check(silent: true)
        }
    }

    func check(silent: Bool = false) {
        guard !busy else { return }
        if !silent { status = "正在检查…" }
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.setValue("TimeChange-Updater", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, _, err in
            var rel: Release?
            if let data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = j["tag_name"] as? String, let page = (j["html_url"] as? String).flatMap(URL.init(string:)) {
                let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let assets = j["assets"] as? [[String: Any]] ?? []
                let dmg = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }?["browser_download_url"] as? String
                rel = Release(version: v, dmg: dmg.flatMap(URL.init(string:)), page: page)
            }
            DispatchQueue.main.async {
                if let r = rel, Self.newer(r.version, than: Self.current) {
                    self.available = r
                    self.status = "发现新版本 v\(r.version)"
                } else if rel != nil {
                    self.available = nil
                    if !silent { self.status = "已是最新版本（v\(Self.current)）" }
                } else if !silent {
                    self.status = "检查失败：\(err?.localizedDescription ?? "无法连接 GitHub")"
                }
            }
        }.resume()
    }

    /// 下载 DMG → 挂载 → 复制新 App → 退出后替换自身并重新打开
    func install() {
        guard let r = available, let dmgURL = r.dmg, !busy else { if let r = available { NSWorkspace.shared.open(r.page) }; return }
        busy = true
        status = "正在下载 v\(r.version)…"
        URLSession.shared.downloadTask(with: dmgURL) { tmp, _, err in
            guard let tmp else { return self.fail(err?.localizedDescription ?? "下载失败") }
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("TimeChange-update-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let dmg = work.appendingPathComponent("update.dmg")
            do { try FileManager.default.moveItem(at: tmp, to: dmg) } catch { return self.fail("保存失败") }
            DispatchQueue.main.async { self.status = "正在安装…" }
            let newApp = work.appendingPathComponent("TimeChange.app").path
            let prep = """
            set -e
            M=$(hdiutil attach -nobrowse -readonly '\(dmg.path)' | tail -1 | awk -F'\\t' '{print $NF}')
            ditto "$M/TimeChange.app" '\(newApp)'
            hdiutil detach -quiet "$M" || true
            xattr -dr com.apple.quarantine '\(newApp)' 2>/dev/null || true
            """
            guard Self.sh(prep) == 0, FileManager.default.fileExists(atPath: newApp) else { return self.fail("安装包解压失败") }
            let target = Bundle.main.bundlePath
            guard FileManager.default.isWritableFile(atPath: (target as NSString).deletingLastPathComponent) else {
                DispatchQueue.main.async { NSWorkspace.shared.open(r.page) }
                return self.fail("没有写入权限，已打开下载页面，请手动替换")
            }
            let pid = ProcessInfo.processInfo.processIdentifier
            let swap = """
            while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
            rm -rf '\(target)' && mv '\(newApp)' '\(target)' && open '\(target)'
            rm -rf '\(work.path)'
            """
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", swap]
            try? p.run()
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }.resume()
    }

    private func fail(_ msg: String) {
        DispatchQueue.main.async { self.busy = false; self.status = msg }
    }

    @discardableResult static func sh(_ cmd: String) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", cmd]
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus
    }
}

struct UpdateCard: View {
    @ObservedObject var up = Updater.shared
    var body: some View {
        CardBox {
            HStack {
                SectionTitle(t: "更新")
                Spacer()
                Text("当前版本 v\(Updater.current)").font(.system(size: 11)).foregroundStyle(UI.sub)
            }
            Toggle("自动检查更新", isOn: Binding(get: { up.autoCheck }, set: { up.autoCheck = $0 })).toggleStyle(OrangeSwitch())
            HStack(spacing: 10) {
                if let r = up.available {
                    Button { up.install() } label: {
                        Text(up.busy ? "更新中…" : "更新到 v\(r.version)").font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(UI.accent)).foregroundStyle(.white)
                    }.buttonStyle(.plain).disabled(up.busy)
                    Button("更新说明") { NSWorkspace.shared.open(r.page) }.buttonStyle(.plain)
                        .font(.system(size: 12)).foregroundStyle(UI.sub)
                } else {
                    Button { up.check() } label: {
                        Text("检查更新").font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }.buttonStyle(.plain)
                }
                Text(up.status).font(.system(size: 11)).foregroundStyle(UI.sub)
            }
        }
    }
}

struct GeneralPage: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("通用").font(.system(size: 20, weight: .semibold))
            CardBox {
                Toggle("隐藏系统数字时钟", isOn: hideBinding(store)).toggleStyle(OrangeSwitch())
                Text("运行时把系统自带的数字时钟缩成小表盘，退出 TimeChange 自动恢复。只改显示样式，不改时区和时间。")
                    .font(.system(size: 11)).foregroundStyle(UI.sub)
                Rectangle().fill(UI.hair).frame(height: 1)
                LoginToggle()
            }
            .frame(maxWidth: 520)
            UpdateCard().frame(maxWidth: 520)
            Text("提示：按住 ⌘ 拖动菜单栏上的时间，可以调整它的位置。")
                .font(.system(size: 11)).foregroundStyle(UI.sub)
        }
    }
}

struct IDBox: Identifiable { let id: UUID }

struct ZonePicker: View {
    var done: (String) -> Void
    var cancel: () -> Void
    @State private var q = ""
    static let all: [(id: String, name: String)] = TimeZone.knownTimeZoneIdentifiers.map { id in
        (id, TimeZone(identifier: id)?.localizedName(for: .generic, locale: Locale(identifier: "zh_CN")) ?? "")
    }

    var filtered: [(id: String, name: String)] {
        let k = q.trimmingCharacters(in: .whitespaces).lowercased()
        if k.isEmpty { return Self.all }
        return Self.all.filter {
            $0.id.lowercased().contains(k) || $0.name.lowercased().contains(k) || cityName($0.id).contains(k)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("搜索城市 / 国家 / 时区，例如 东京、上海、London", text: $q)
                .textFieldStyle(.plain).font(.system(size: 13))
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
            List {
                Button { done(kLocal) } label: {
                    Text("本机时间（跟随系统，旅行时自动切换）").bold().foregroundStyle(UI.accent)
                }.buttonStyle(.plain)
                ForEach(filtered, id: \.id) { z in
                    Button { done(z.id) } label: {
                        HStack {
                            Text(cityName(z.id))
                            Text(z.id).foregroundStyle(.secondary)
                            Spacer()
                            Text(Fmt.offset(TimeZone(identifier: z.id) ?? .current)).font(.caption).foregroundStyle(.secondary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            .scrollContentBackground(.hidden)
            HStack { Spacer(); Button("取消", action: cancel).keyboardShortcut(.cancelAction) }
        }
        .padding(16)
        .frame(width: 520, height: 480)
        .background(UI.bg)
    }
}

// MARK: - 截图（开发用：TimeChange --snapshot <目录>）

func snapshot(_ view: some View, _ size: NSSize, _ path: String) {
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(origin: .zero, size: size)
    host.appearance = NSAppearance(named: .darkAqua)
    let w = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    w.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    let dir = CommandLine.arguments[i + 1]
    _ = NSApplication.shared
    let store = Store.shared
    let panel = AnyView(PanelView(store: store, onSettings: {}, onAdd: {}, onQuit: {})
        .padding(20).background(Color(red: 0.24, green: 0.33, blue: 0.47)))
    let fit = NSHostingView(rootView: panel).fittingSize
    snapshot(panel, NSSize(width: fit.width, height: fit.height), dir + "/panel.png")
    for page in [SettingsNav.Page.bar, .clocks, .general] {
        let nav = SettingsNav(); nav.page = page
        snapshot(AnyView(SettingsRoot().environmentObject(store).environmentObject(nav)), NSSize(width: 980, height: 660), dir + "/settings-\(page.rawValue).png")
    }
    exit(0)
}

// 只允许运行一个 TimeChange：已在运行就让它打开设置，自己退出
if let me = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: me).contains(where: { $0 != NSRunningApplication.current }) {
    exit(0)
}

// MARK: - 启动

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
