// TimeChange 界面：iOS 风格毛玻璃（下拉面板 / 时区选择 / 设置窗口）
import AppKit
import SwiftUI
import ServiceManagement

// MARK: - 主题

enum UI {
    static var snapshot = false   // 截图模式：毛玻璃用纯色代替（离屏渲染拍不到背后模糊）
    static var accent: Color { Color(hex: Store.shared.s.accent) }
    static let accents: [(name: String, hex: String)] = [
        ("橙色", "FF9500"), ("蓝色", "0A84FF"), ("绿色", "30D158"), ("紫色", "BF5AF2"), ("粉色", "FF375F"), ("石墨", "8E8E93"),
    ]
}

extension Color {
    init(hex: String) {
        let v = UInt32(hex, radix: 16) ?? 0xFF9500
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// 随浅色 / 深色变化的颜色
struct Pal {
    let dark: Bool
    init(_ scheme: ColorScheme) { dark = scheme == .dark }
    var group: Color { dark ? .white.opacity(0.07) : .white.opacity(0.62) }
    var fill: Color { Color(white: 0.46).opacity(dark ? 0.24 : 0.12) }
    var sep: Color { dark ? .white.opacity(0.12) : Color(red: 0.24, green: 0.24, blue: 0.26).opacity(0.18) }
    var segOn: Color { dark ? .white.opacity(0.22) : .white }
    var off: Color { Color(white: 0.47).opacity(dark ? 0.36 : 0.2) }
    var navOn: Color { dark ? .white.opacity(0.12) : .black.opacity(0.07) }
    var edge: Color { dark ? .white.opacity(0.14) : .black.opacity(0.12) }
    var hover: Color { dark ? .white.opacity(0.08) : .black.opacity(0.05) }
}

/// 背后模糊的毛玻璃
struct Glass: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        v.material = material
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

struct GlassBackground: View {
    var material: NSVisualEffectView.Material = .popover
    @Environment(\.colorScheme) var scheme
    var body: some View {
        if UI.snapshot {
            Rectangle().fill(scheme == .dark ? Color(red: 0.16, green: 0.16, blue: 0.17).opacity(0.94) : Color(red: 0.97, green: 0.97, blue: 0.98).opacity(0.94))
        } else {
            Glass(material: material)
        }
    }
}

// MARK: - 表盘

struct Dial: View {
    let tz: TimeZone
    let now: Date
    var size: CGFloat = 28
    var ticks = false
    @Environment(\.colorScheme) var scheme

    var body: some View {
        let (h, m, _) = Fmt.hm(tz, now)
        let day = h >= 7 && h < 19
        let accent = UI.accent
        let edge = scheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.12)
        Canvas { ctx, sz in
            let r = min(sz.width, sz.height) / 2
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let face = day ? Color.white : Color(red: 0.11, green: 0.11, blue: 0.12)
            let hand = day ? Color(red: 0.11, green: 0.11, blue: 0.12) : Color.white
            let circle = Path(ellipseIn: CGRect(x: c.x - r + 0.5, y: c.y - r + 0.5, width: 2 * r - 1, height: 2 * r - 1))
            ctx.fill(circle, with: .color(face))
            ctx.stroke(circle, with: .color(edge), lineWidth: 1)
            func line(_ angle: Double, _ from: CGFloat, _ to: CGFloat, _ w: CGFloat, _ col: Color) {
                let a = angle * .pi / 180
                var p = Path()
                p.move(to: CGPoint(x: c.x + sin(a) * from, y: c.y - cos(a) * from))
                p.addLine(to: CGPoint(x: c.x + sin(a) * to, y: c.y - cos(a) * to))
                ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: w, lineCap: .round))
            }
            if ticks { for i in 0..<12 { line(Double(i) * 30, r * 0.78, r * 0.9, max(1, r * 0.06), Color.gray.opacity(0.6)) } }
            line((Double(h % 12) + Double(m) / 60) * 30, 0, r * 0.47, max(1.6, r * 0.15), hand)
            line(Double(m) * 6, 0, r * 0.7, max(1.2, r * 0.1), hand)
            let d = max(3, r * 0.24)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)), with: .color(accent))
        }
        .frame(width: size, height: size)
    }
}

func clockSub(_ c: ClockEntry, _ now: Date) -> String {
    if c.isLocal { return cityName(kLocal) }
    let city = cityName(c.tz)
    let base = "\(Fmt.diff(c.timeZone, at: now)) · \(Fmt.dayWord(c.timeZone, now))"
    return c.label == city ? base : "\(city) · \(base)"
}

// MARK: - 下拉面板

struct PanelView: View {
    @ObservedObject var store: Store
    @ObservedObject var updater = Updater.shared
    var onSettings: () -> Void
    var onAdd: () -> Void
    var onQuit: () -> Void
    @Environment(\.colorScheme) var scheme

    var body: some View {
        let pal = Pal(scheme)
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let now = tl.date
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    QuickChip(icon: "日", label: "日期", on: $store.s.showDate)
                    QuickChip(icon: "周", label: "星期", on: $store.s.showWeekday)
                    QuickChip(icon: ":ss", label: "秒", on: $store.s.showSeconds)
                    QuickChip(icon: "24", label: "24 小时", on: $store.s.use24h)
                }
                .padding(.horizontal, 8).padding(.top, 2).padding(.bottom, 8)

                Rectangle().fill(pal.sep).frame(height: 0.5)

                Text("世界时钟").font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.top, 7).padding(.bottom, 1)

                ForEach(store.s.clocks) { c in
                    ClockRow(c: c, now: now, selected: store.s.primary?.id == c.id) { store.select(c.id) }
                }

                Rectangle().fill(pal.sep).frame(height: 0.5).padding(.vertical, 4)

                if let r = updater.available {
                    ActionRow(icon: "arrow.down.circle.fill", title: updater.busy ? "正在更新…" : "更新到 v\(r.version)", accent: true) { updater.install() }
                }
                ActionRow(icon: "plus", title: "添加时区", action: onAdd)
                ActionRow(icon: "gearshape", title: "设置…", action: onSettings)
                ActionRow(icon: "power", title: "退出 TimeChange", action: onQuit)
            }
            .padding(.vertical, 6)
            .frame(width: 272)
            .background(GlassBackground(material: .popover))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(pal.edge, lineWidth: 0.5))
        }
        .focusEffectDisabled()
    }
}

struct QuickChip: View {
    let icon: String
    let label: String
    @Binding var on: Bool
    @Environment(\.colorScheme) var scheme
    var body: some View {
        let pal = Pal(scheme)
        Button { on.toggle() } label: {
            VStack(spacing: 1) {
                Text(icon).font(.system(size: 12, weight: .semibold))
                Text(label).font(.system(size: 9.5))
            }
            .frame(maxWidth: .infinity).frame(height: 36)
            .foregroundStyle(on ? UI.accent : Color.primary)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? UI.accent.opacity(pal.dark ? 0.22 : 0.16) : pal.fill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: on)
    }
}

struct ClockRow: View {
    let c: ClockEntry
    let now: Date
    let selected: Bool
    let action: () -> Void
    @State private var hover = false
    @Environment(\.colorScheme) var scheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Dial(tz: c.timeZone, now: now, size: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(c.label).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(clockSub(c, now)).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(Fmt.time(now, c.timeZone, Store.shared.s)).font(.system(size: 14, weight: .medium).monospacedDigit())
                Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(UI.accent).opacity(selected ? 1 : 0).frame(width: 14)
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hover ? Pal(scheme).hover : .clear).padding(.horizontal, 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct ActionRow: View {
    let icon: String
    let title: String
    var accent = false
    let action: () -> Void
    @State private var hover = false
    @Environment(\.colorScheme) var scheme
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 11)).frame(width: 15)
                Text(title).font(.system(size: 13, weight: accent ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(accent ? UI.accent : Color.primary)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hover ? Pal(scheme).hover : .clear).padding(.horizontal, 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - 通用控件（iOS 分组列表）

struct GroupSection<Content: View>: View {
    var title: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title { Text(title).font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 14) }
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Pal(scheme).group))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if let footer {
                Text(footer).font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 14)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct Cell<Content: View>: View {
    var divider = false
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) var scheme
    var body: some View {
        HStack(spacing: 12) { content }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .overlay(alignment: .top) {
                if divider { Rectangle().fill(Pal(scheme).sep).frame(height: 0.5).padding(.leading, 14) }
            }
    }
}

struct IOSSwitch: ToggleStyle {
    @Environment(\.colorScheme) var scheme
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack {
                configuration.label.font(.system(size: 14))
                Spacer()
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? UI.accent : Pal(scheme).off).frame(width: 42, height: 25)
                    Circle().fill(.white).frame(width: 21, height: 21).padding(2)
                        .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.85), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct Segmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    @Environment(\.colorScheme) var scheme
    var body: some View {
        let pal = Pal(scheme)
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let (v, label) = options[i]
                let on = v == selection
                Button { selection = v } label: {
                    Text(label).font(.system(size: 13, weight: on ? .semibold : .regular))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? pal.segOn : .clear)
                            .shadow(color: .black.opacity(on ? 0.12 : 0), radius: 2, y: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(pal.fill))
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

struct MiniSystemIcon: View {
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary, lineWidth: 1.1)
            Path { p in p.move(to: CGPoint(x: 7, y: 7)); p.addLine(to: CGPoint(x: 9.6, y: 8.6)) }
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        }
        .frame(width: 14, height: 14)
    }
}

// MARK: - 时区选择

struct ZoneInfo: Identifiable {
    let id: String
    let city: String
    let abbr: String
    let name: String
    let offset: Int

    init(_ id: String, now: Date = Date()) {
        self.id = id
        let tz = id == kLocal ? TimeZone.current : (TimeZone(identifier: id) ?? .current)
        city = id == kLocal ? "本机 · \(cityName(kLocal))" : cityName(id)
        abbr = tz.abbreviation(for: now) ?? Fmt.offset(tz, at: now)
        let full = tz.localizedName(for: tz.isDaylightSavingTime(for: now) ? .daylightSaving : .standard, locale: Locale(identifier: "zh_CN")) ?? ""
        let fullName = full.hasPrefix("GMT") && tz.secondsFromGMT(for: now) == 0 ? "格林尼治标准时间" : full
        name = id == kLocal ? "\(fullName) · 跟随系统" : "\(fullName) · \(id)"
        offset = tz.secondsFromGMT(for: now)
    }
}

enum Zones {
    static let common = ["Asia/Shanghai", "Asia/Tokyo", "Europe/London", "America/New_York", "Europe/Paris",
                         "Asia/Hong_Kong", "Asia/Singapore", "Asia/Seoul", "Australia/Sydney", "America/Los_Angeles",
                         "Europe/Berlin", "Asia/Dubai"]
    static let all: [ZoneInfo] = TimeZone.knownTimeZoneIdentifiers
        .filter { $0.contains("/") && !$0.hasPrefix("Etc/") }
        .map { ZoneInfo($0) }
        .sorted { $0.offset == $1.offset ? $0.city < $1.city : $0.offset < $1.offset }
}

struct ZonePicker: View {
    enum Mode { case add, replace(UUID) }
    let mode: Mode
    var close: () -> Void
    @EnvironmentObject var store: Store
    @State private var q = ""
    @Environment(\.colorScheme) var scheme

    var title: String { if case .add = mode { return "添加时区" } else { return "更换时区" } }

    func isChecked(_ id: String) -> Bool {
        switch mode {
        case .add: return store.s.clocks.contains { $0.tz == id }
        case .replace(let cid): return store.s.clocks.first { $0.id == cid }?.tz == id
        }
    }

    func tap(_ id: String) {
        switch mode {
        case .add:
            if let i = store.s.clocks.firstIndex(where: { $0.tz == id }) {
                if store.s.clocks.count > 1 { store.s.clocks.remove(at: i) }
            } else {
                store.s.clocks.append(ClockEntry(label: id == kLocal ? "本机" : cityName(id), tz: id, showInBar: false))
            }
        case .replace(let cid):
            if let i = store.s.clocks.firstIndex(where: { $0.id == cid }) {
                let old = store.s.clocks[i]
                if old.label == cityName(old.tz) || old.label == "本机" || old.label.isEmpty {
                    store.s.clocks[i].label = id == kLocal ? "本机" : cityName(id)
                }
                store.s.clocks[i].tz = id
            }
            close()
        }
    }

    var results: [ZoneInfo] {
        let k = q.trimmingCharacters(in: .whitespaces).lowercased()
        return Zones.all.filter {
            $0.id.lowercased().contains(k) || $0.city.lowercased().contains(k) || $0.name.lowercased().contains(k) || $0.abbr.lowercased() == k
        }
    }

    var body: some View {
        let pal = Pal(scheme)
        TimelineView(.periodic(from: .now, by: 30)) { tl in
            VStack(spacing: 0) {
                ZStack {
                    Text(title).font(.system(size: 17, weight: .semibold))
                    HStack {
                        Spacer()
                        Button(action: close) {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                                .frame(width: 28, height: 28).background(Circle().fill(pal.fill))
                        }
                        .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                    }
                }
                .padding(.bottom, 14)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索城市、国家或时区", text: $q).textFieldStyle(.plain).font(.system(size: 14))
                }
                .padding(.horizontal, 12).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(pal.fill))
                .padding(.bottom, 14)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if q.trimmingCharacters(in: .whitespaces).isEmpty {
                            zoneGroup("本机", [ZoneInfo(kLocal)], tl.date)
                            zoneGroup("常用", Zones.common.map { ZoneInfo($0) }, tl.date)
                            zoneGroup("全部时区", Zones.all, tl.date)
                        } else {
                            let r = results
                            if r.isEmpty {
                                Text("没有找到「\(q)」").font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 30)
                                    .frame(maxWidth: .infinity)
                            } else {
                                zoneGroup("搜索结果", r, tl.date)
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.never)
            }
            .padding(.horizontal, 16).padding(.top, 18)
        }
        .frame(width: 440, height: 600)
        .background(GlassBackground(material: .popover))
        .focusEffectDisabled()
    }

    func zoneGroup(_ title: String, _ zones: [ZoneInfo], _ now: Date) -> some View {
        GroupSection(title: title) {
            ForEach(Array(zones.enumerated()), id: \.element.id) { i, z in
                ZoneRow(z: z, now: now, checked: isChecked(z.id), divider: i > 0) { tap(z.id) }
            }
        }
    }
}

struct ZoneRow: View {
    let z: ZoneInfo
    let now: Date
    let checked: Bool
    let divider: Bool
    let action: () -> Void
    @State private var hover = false
    @Environment(\.colorScheme) var scheme

    var body: some View {
        let tz = z.id == kLocal ? TimeZone.current : (TimeZone(identifier: z.id) ?? .current)
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    (Text(z.city).font(.system(size: 15, weight: .medium))
                     + Text(" (\(z.abbr))").font(.system(size: 15)).foregroundColor(UI.accent))
                    Text(z.name).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    Text("现在 \(Fmt.time(now, tz, Store.shared.s)) · \(Fmt.dayWord(tz, now))")
                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                if checked { Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(UI.accent) }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(hover ? Pal(scheme).hover : .clear)
            .overlay(alignment: .top) { if divider { Rectangle().fill(Pal(scheme).sep).frame(height: 0.5).padding(.leading, 14) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - 设置窗口

final class SettingsNav: ObservableObject {
    enum Page: String { case bar, clocks, general, update }
    @Published var page: Page = .bar
    @Published var addRequested = false
}

struct SettingsRoot: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: SettingsNav
    @Environment(\.colorScheme) var scheme

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            ScrollView {
                Group {
                    switch nav.page {
                    case .bar: BarPage()
                    case .clocks: ClocksPage()
                    case .general: GeneralPage()
                    case .update: UpdatePage()
                    }
                }
                .padding(.horizontal, 34).padding(.top, 40).padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.never)
        }
        .frame(width: 980, height: 660)
        .background(UI.snapshot ? AnyView(GlassBackground(material: .underWindowBackground)) : AnyView(Color.clear))
        .ignoresSafeArea()          // 内容和毛玻璃一直铺到标题栏下面，红绿灯浮在上面
        .focusEffectDisabled()
    }
}

struct Sidebar: View {
    @EnvironmentObject var nav: SettingsNav
    @Environment(\.colorScheme) var scheme
    var body: some View {
        let pal = Pal(scheme)
        VStack(alignment: .leading, spacing: 2) {
            NavItem(icon: "menubar.rectangle", tint: Color(hex: "FF9500"), title: "菜单栏", page: .bar)
            NavItem(icon: "clock", tint: Color(hex: "0A84FF"), title: "时钟", page: .clocks)
            NavItem(icon: "gearshape", tint: Color(hex: "8E8E93"), title: "通用", page: .general)
            NavItem(icon: "arrow.down.circle", tint: Color(hex: "30D158"), title: "更新", page: .update)
            Spacer()
            Text("TimeChange v\(Updater.current)").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.horizontal, 8)
        }
        .padding(.horizontal, 10).padding(.top, 52).padding(.bottom, 14)
        .frame(width: 212)
        .frame(maxHeight: .infinity)
        .ignoresSafeArea()
        .background(pal.dark ? Color.white.opacity(0.04) : Color.white.opacity(0.28))
        .overlay(alignment: .trailing) { Rectangle().fill(pal.sep).frame(width: 0.5) }
    }
}

struct NavItem: View {
    @EnvironmentObject var nav: SettingsNav
    @Environment(\.colorScheme) var scheme
    let icon: String, tint: Color, title: String, page: SettingsNav.Page
    var body: some View {
        let on = nav.page == page
        Button { nav.page = page } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(tint))
                Text(title).font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? Pal(scheme).navOn : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PageTitle: View {
    let t: String
    var body: some View { Text(t).font(.system(size: 26, weight: .bold)).padding(.bottom, 2) }
}

/// 右侧显示当前值、点开是菜单的行（iOS 的 ⌃⌄ 选择）
struct MenuValue<Content: View>: View {
    let value: String
    @ViewBuilder var content: Content
    var body: some View {
        Menu { content } label: {
            (Text(value + "  ") + Text(Image(systemName: "chevron.up.chevron.down")).font(.system(size: 10, weight: .semibold)))
                .font(.system(size: 14)).foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct BarPage: View {
    @EnvironmentObject var store: Store
    @Environment(\.colorScheme) var scheme

    var body: some View {
        let pal = Pal(scheme)
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let now = tl.date
            let (dot, main, second) = Fmt.bar(now, store.s)
            VStack(alignment: .leading, spacing: 18) {
                PageTitle(t: "菜单栏")
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 18) {
                        GroupSection(title: "显示样式", footer: store.s.barStyle.desc) {
                            VStack(spacing: 14) {
                                HStack(spacing: 10) {
                                    Spacer()
                                    if dot { Circle().fill(Color(hex: "FF9F43")).frame(width: 6, height: 6) }
                                    Text(main).font(.system(size: 14).monospacedDigit())
                                    if let second { Text(second).font(.system(size: 14).monospacedDigit()).foregroundStyle(.secondary) }
                                    MiniSystemIcon()
                                }
                                .padding(.horizontal, 14).frame(height: 52)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(pal.fill))
                                Segmented(options: BarStyle.allCases.map { ($0, $0.title) },
                                          selection: Binding(get: { store.s.barStyle }, set: { store.s.style = $0 }))
                            }
                            .padding(14)
                        }

                        GroupSection(title: "菜单栏时钟", footer: "点击菜单栏上的时间也可以快速切换。") {
                            Cell {
                                Text("显示的时钟").font(.system(size: 14))
                                Spacer()
                                MenuValue(value: store.s.primary.map(menuName) ?? "") {
                                    ForEach(store.s.clocks) { c in Button(menuName(c)) { store.select(c.id) } }
                                }
                            }
                            Cell(divider: true) {
                                Text("双城并排的第二个时钟").font(.system(size: 14))
                                Spacer()
                                MenuValue(value: store.s.secondary.map(menuName) ?? "") {
                                    ForEach(store.s.clocks.filter { $0.id != store.s.primary?.id }) { c in
                                        Button(menuName(c)) { store.s.secondId = c.id }
                                    }
                                }
                            }
                            .opacity(store.s.barStyle == .dual ? 1 : 0.45)
                            .disabled(store.s.barStyle != .dual)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    GroupSection(title: "格式") {
                        Cell { Toggle("日期", isOn: $store.s.showDate).toggleStyle(IOSSwitch()) }
                        Cell(divider: true) { Toggle("星期", isOn: $store.s.showWeekday).toggleStyle(IOSSwitch()) }
                        Cell(divider: true) { Toggle("秒", isOn: $store.s.showSeconds).toggleStyle(IOSSwitch()) }
                        Cell(divider: true) { Toggle("24 小时制", isOn: $store.s.use24h).toggleStyle(IOSSwitch()) }
                    }
                    .frame(width: 300)
                }
            }
        }
    }

    func menuName(_ c: ClockEntry) -> String { c.isLocal ? "\(c.label) · \(cityName(kLocal))" : c.label }
}

struct ClocksPage: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var nav: SettingsNav
    @Environment(\.colorScheme) var scheme
    @State private var picker: PickerTarget?

    struct PickerTarget: Identifiable {
        let id = UUID()
        let mode: ZonePicker.Mode
    }

    var body: some View {
        let pal = Pal(scheme)
        TimelineView(.periodic(from: .now, by: 30)) { tl in
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    PageTitle(t: "时钟")
                    Spacer()
                    Button { picker = PickerTarget(mode: .add) } label: {
                        Label("添加时区", systemImage: "plus").font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Capsule().fill(UI.accent)).foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
                GroupSection(footer: "「本机」跟随系统时区，出去旅行时自动切到当地；其他时钟固定在你选的时区。只改显示，不会更改系统时区和系统时间。") {
                    ForEach(Array($store.s.clocks.enumerated()), id: \.element.id) { i, $c in
                        Cell(divider: i > 0) {
                            Dial(tz: c.timeZone, now: tl.date, size: 28)
                            TextField("名称", text: $c.label).textFieldStyle(.plain).font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(pal.fill))
                                .frame(width: 120)
                            Button { picker = PickerTarget(mode: .replace(c.id)) } label: {
                                HStack(spacing: 5) {
                                    Text(c.isLocal ? "本机（跟随系统）" : "\(cityName(c.tz)) · \(Fmt.offset(c.timeZone))").lineLimit(1)
                                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                                }
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            iconButton("chevron.up") { move(c.id, -1) }.disabled(i == 0)
                            iconButton("chevron.down") { move(c.id, 1) }.disabled(i == store.s.clocks.count - 1)
                            iconButton("trash") { store.s.clocks.removeAll { $0.id == c.id } }.disabled(store.s.clocks.count <= 1)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .sheet(item: $picker) { t in
            ZonePicker(mode: t.mode) { picker = nil }.environmentObject(store)
        }
        .onAppear { if nav.addRequested { nav.addRequested = false; picker = PickerTarget(mode: .add) } }
        .onChange(of: nav.addRequested) { _, v in if v { nav.addRequested = false; picker = PickerTarget(mode: .add) } }
    }

    func iconButton(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Pal(scheme).fill))
        }
        .buttonStyle(.plain)
    }

    func move(_ id: UUID, _ d: Int) {
        guard let i = store.s.clocks.firstIndex(where: { $0.id == id }) else { return }
        let j = i + d
        guard store.s.clocks.indices.contains(j) else { return }
        store.s.clocks.swapAt(i, j)
    }
}

struct GeneralPage: View {
    @EnvironmentObject var store: Store
    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(t: "通用")
            GroupSection(title: "外观", footer: "「跟随系统」会随 macOS 的浅色 / 深色模式自动切换。主题色用于开关、勾号和选中状态。") {
                VStack(spacing: 0) {
                    Segmented(options: [("system", "跟随系统"), ("light", "浅色"), ("dark", "深色")],
                              selection: Binding(get: { store.s.appearanceMode }, set: { store.s.appearance = $0 }))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                    Cell(divider: true) {
                        Text("主题色").font(.system(size: 14))
                        Spacer()
                        HStack(spacing: 10) {
                            ForEach(UI.accents, id: \.hex) { a in
                                let on = store.s.accent == a.hex
                                Button { store.s.accentHex = a.hex } label: {
                                    Circle().fill(Color(hex: a.hex)).frame(width: 20, height: 20)
                                        .padding(3)
                                        .overlay(Circle().strokeBorder(on ? Color(hex: a.hex) : .clear, lineWidth: 2))
                                }
                                .buttonStyle(.plain).help(a.name)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 560)

            GroupSection(title: "系统", footer: "运行时把系统自带的数字时钟缩成小表盘，退出 TimeChange 后自动恢复。只改显示，不改系统时区和时间。") {
                Cell { Toggle("隐藏系统数字时钟", isOn: Binding(get: { store.s.hidesSystemClock }, set: { store.s.hideSystemClock = $0 })).toggleStyle(IOSSwitch()) }
                Cell(divider: true) { LoginToggle() }
            }
            .frame(maxWidth: 560)

            Text("提示：按住 ⌘ 拖动菜单栏上的时间，可以调整它的位置。").font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 14)
        }
    }
}

struct LoginToggle: View {
    @State private var on = SMAppService.mainApp.status == .enabled
    @State private var err = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("登录时启动", isOn: $on).toggleStyle(IOSSwitch())
                .onChange(of: on) { _, v in
                    do { v ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister(); err = "" }
                    catch { err = "设置失败：\(error.localizedDescription)" }
                }
            if !err.isEmpty { Text(err).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
    }
}

struct UpdatePage: View {
    @ObservedObject var up = Updater.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(t: "更新")
            GroupSection(footer: "新版本发布在 GitHub。更新会自动下载、替换并重新打开 TimeChange。") {
                Cell {
                    Text("当前版本").font(.system(size: 14))
                    Spacer()
                    Text("v\(Updater.current)").font(.system(size: 14)).foregroundStyle(.secondary)
                }
                Cell(divider: true) {
                    Toggle("自动检查更新", isOn: Binding(get: { up.autoCheck }, set: { up.autoCheck = $0 })).toggleStyle(IOSSwitch())
                }
                Cell(divider: true) {
                    if let r = up.available {
                        Button { up.install() } label: {
                            Text(up.busy ? "更新中…" : "更新到 v\(r.version)").font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(Capsule().fill(UI.accent)).foregroundStyle(.white)
                        }
                        .buttonStyle(.plain).disabled(up.busy)
                        Button("更新说明") { NSWorkspace.shared.open(r.page) }.buttonStyle(.plain)
                            .font(.system(size: 13)).foregroundStyle(UI.accent)
                    } else {
                        Button { up.check() } label: {
                            Text("检查更新").font(.system(size: 13, weight: .medium)).foregroundStyle(UI.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Text(up.status).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 560)
        }
    }
}
