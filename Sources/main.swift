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
    // v4 新增
    var appearance: String?   // "system" | "light" | "dark"
    var accentHex: String?    // 主题色
    var secondId: UUID?       // 双城并排的第二个时钟

    var barStyle: BarStyle { style ?? .native }
    var hidesSystemClock: Bool { hideSystemClock ?? true }

    var primary: ClockEntry? { clocks.first { $0.showInBar } ?? clocks.first }
    /// 双城并排的第二个时间：列表里主时钟之外的第一个
    var secondary: ClockEntry? {
        if let i = secondId, i != primary?.id, let c = clocks.first(where: { $0.id == i }) { return c }
        return clocks.first { $0.id != primary?.id }
    }
    var appearanceMode: String { appearance ?? "dark" }   // 默认深色
    var accent: String { accentHex ?? "FF9500" }
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

        applyAppearance()
        refresh()
        scheduleTimer()
        Updater.shared.startAutoCheck()
        if store.s.hidesSystemClock { SystemClock.shrink() }
    }

    func applicationWillTerminate(_ n: Notification) { SystemClock.restore() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings(); return true
    }

    func applyAppearance() {
        switch store.s.appearanceMode {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    @objc func settingsChanged() {
        applyAppearance()
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
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let p = panel ?? FloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.appearance = NSApp.appearance
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
            w.isOpaque = false
            w.backgroundColor = .clear
            w.isReleasedWhenClosed = false
            // 整个窗口（含标题栏区域）铺一层背后模糊的毛玻璃，SwiftUI 内容放在上面
            let fx = NSVisualEffectView()
            fx.material = .underWindowBackground
            fx.blendingMode = .behindWindow
            fx.state = .active
            let host = NSHostingView(rootView: SettingsRoot().environmentObject(store).environmentObject(nav))
            host.translatesAutoresizingMaskIntoConstraints = false
            fx.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
                host.topAnchor.constraint(equalTo: fx.topAnchor),
                host.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
            ])
            w.contentView = fx
            w.setContentSize(NSSize(width: 980, height: 660))
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
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

// MARK: - 截图（开发用：TimeChange --snapshot <目录>）

func snapshot(_ view: some View, _ size: NSSize, _ path: String, dark: Bool) {
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(origin: .zero, size: size)
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
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
    UI.snapshot = true
    let store = Store.shared
    for dark in [false, true] {
        let suffix = dark ? "-dark" : ""
        let panel = AnyView(ZStack {
            Rectangle().fill(dark ? Color(red: 0.23, green: 0.18, blue: 0.15) : Color(red: 0.85, green: 0.71, blue: 0.54))
            PanelView(store: store, onSettings: {}, onAdd: {}, onQuit: {}).padding(28)
        }.fixedSize())
        let fit = NSHostingView(rootView: panel).fittingSize
        snapshot(panel, fit, dir + "/panel\(suffix).png", dark: dark)
        for page in [SettingsNav.Page.bar, .clocks, .general] {
            let nav = SettingsNav(); nav.page = page
            snapshot(AnyView(SettingsRoot().environmentObject(store).environmentObject(nav)), NSSize(width: 980, height: 660),
                     dir + "/settings-\(page.rawValue)\(suffix).png", dark: dark)
        }
        snapshot(AnyView(ZonePicker(mode: .add, close: {}).environmentObject(store)), NSSize(width: 440, height: 600),
                 dir + "/picker\(suffix).png", dark: dark)
    }
    snapshot(AnyView(ShowcaseHero(dark: true)), NSSize(width: 1400, height: 860), dir + "/showcase-hero.png", dark: true)
    snapshot(AnyView(ShowcaseHero(dark: false)), NSSize(width: 1400, height: 860), dir + "/showcase-hero-light.png", dark: false)
    snapshot(AnyView(ShowcaseTrio()), NSSize(width: 1400, height: 640), dir + "/showcase-trio.png", dark: true)
    exit(0)
}

// 开发用：TimeChange --self-update，立即检查并安装更新（测试更新流程）
if CommandLine.arguments.contains("--self-update") {
    _ = NSApplication.shared
    let up = Updater.shared
    up.check()
    Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
        if up.available != nil, !up.busy { print("found v\(up.available!.version), installing"); up.install() }
        if !up.status.isEmpty { print(up.status) }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 60) { print("timeout"); exit(1) }
    NSApplication.shared.run()
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
