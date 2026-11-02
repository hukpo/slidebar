import SlidebarCore
import SwiftUI

/// Something on the trackpad map the user can pick.
enum MapSpot: Hashable {
    case edge(EdgeSide)
    case corner(Corner)

    var title: String {
        switch self {
        case .edge(let side): return side.title
        case .corner(let corner): return corner.title
        }
    }
}

// MARK: - Map

/// The home screen's trackpad: a button for every edge and corner showing what it does, with live
/// levels filling the edges. Click a spot to change it, click it again to close.
/// Arrow keys move in the direction pressed; VoiceOver reads the spots clockwise.
struct TrackpadMap: View {
    @Binding var selection: MapSpot?
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var live = LiveState.shared
    @FocusState private var mapFocused: Bool
    @State private var anchors = AnchorStore()
    /// Show the focus halo only when the user is navigating by keyboard, like native controls.
    @State private var keyboardNav = false
    @State private var clickingFocus = false

    /// Edges start this far from each corner, leaving the corners free.
    private let edgeInset: CGFloat = 42
    private let cornerPad: CGFloat = 6

    /// Clockwise from the top-left corner.
    static let ring: [MapSpot] = [.corner(.topLeft), .edge(.top), .corner(.topRight), .edge(.right),
                                  .corner(.bottomRight), .edge(.bottom), .corner(.bottomLeft), .edge(.left)]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                TrackpadSurface()

                ZStack {
                    edgeButton(.top, length: w - 2 * edgeInset).frame(maxHeight: .infinity, alignment: .top)
                    edgeButton(.bottom, length: w - 2 * edgeInset).frame(maxHeight: .infinity, alignment: .bottom)
                    edgeButton(.left, length: h - 2 * edgeInset).frame(maxWidth: .infinity, alignment: .leading)
                    edgeButton(.right, length: h - 2 * edgeInset).frame(maxWidth: .infinity, alignment: .trailing)

                    cornerButton(.topLeft).padding(cornerPad)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    cornerButton(.topRight).padding(cornerPad)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    cornerButton(.bottomLeft).padding(cornerPad)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    cornerButton(.bottomRight).padding(cornerPad)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
                .clipShape(TrackpadSurface.shape)
                .saturation(prefs.paused ? 0 : 1)
                .opacity(prefs.paused ? 0.55 : 1)

                if prefs.paused {
                    Text("Paused")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(.regularMaterial))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
        .focusable()
        .focused($mapFocused)
        .modifier(NoSystemFocusRing())
        .onChange(of: mapFocused) { focused in
            // Focus that arrives by Tab (not by a click) shows the halo.
            if focused && !clickingFocus { keyboardNav = true }
            if !focused { keyboardNav = false }
            clickingFocus = false
        }
        .onMoveCommand { direction in
            guard let current = selection else { select(.edge(.left), fromKeyboard: true); return }
            if let next = Self.neighbor(of: current, direction) { select(next, fromKeyboard: true) }
        }
        .onExitCommand { selection = nil }
        .modifier(OpenWithKeys { if let spot = selection { open(spot, fromKeyboard: true) } })
        .onAppear { UserShortcuts.preload() }
        .animation(.easeOut(duration: 0.2), value: prefs.paused)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Trackpad map. Arrow keys move between edges and corners.")
    }

    /// Where each spot sits on a 3×3 grid; the centre is empty.
    static func cell(_ spot: MapSpot) -> (x: Int, y: Int) {
        switch spot {
        case .corner(.topLeft): return (0, 0)
        case .edge(.top): return (1, 0)
        case .corner(.topRight): return (2, 0)
        case .edge(.left): return (0, 1)
        case .edge(.right): return (2, 1)
        case .corner(.bottomLeft): return (0, 2)
        case .edge(.bottom): return (1, 2)
        case .corner(.bottomRight): return (2, 2)
        }
    }

    /// Arrow keys move in the direction pressed, skipping the empty centre.
    static func neighbor(of spot: MapSpot, _ direction: MoveCommandDirection) -> MapSpot? {
        var (x, y) = cell(spot)
        let (dx, dy): (Int, Int)
        switch direction {
        case .left: (dx, dy) = (-1, 0)
        case .right: (dx, dy) = (1, 0)
        case .up: (dx, dy) = (0, -1)
        case .down: (dx, dy) = (0, 1)
        @unknown default: return nil
        }
        repeat {
            x += dx; y += dy
            guard (0...2).contains(x), (0...2).contains(y) else { return nil }
        } while x == 1 && y == 1
        return ring.first { cell($0) == (x, y) }
    }

    /// Opens a spot's actions menu right under it; the spot stays highlighted while it's open.
    private func open(_ spot: MapSpot, fromKeyboard: Bool = false) {
        select(spot, fromKeyboard: fromKeyboard)
        guard let view = anchors.anchor(spot).view else { return }
        SpotMenu.show(for: spot, under: view)
        if !keyboardNav { selection = nil }
    }

    private func select(_ spot: MapSpot, fromKeyboard: Bool = false) {
        selection = spot
        // Take focus so arrow keys work right after a click. Where the system focus ring can't be
        // hidden (macOS 13), only take it from the keyboard, like native controls.
        if fromKeyboard {
            keyboardNav = true
            mapFocused = true
        } else if #available(macOS 14, *) {
            keyboardNav = false
            clickingFocus = !mapFocused
            mapFocused = true
        }
        let text = "\(spot.title), \(title(for: spot))."
        if let window = NSApp.keyWindow {
            NSAccessibility.post(element: window, notification: .announcementRequested,
                                 userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    private func title(for spot: MapSpot) -> String {
        switch spot {
        case .edge(let side): return prefs.edge(side).title
        case .corner(let corner):
            let f = prefs.corner(corner)
            if f == .openApp, let id = prefs.cornerApps[corner] { return "Open \(AppNames.name(for: id))" }
            if f == .runShortcut, let name = prefs.cornerShortcuts[corner] { return "Run \u{201C}\(name)\u{201D}" }
            return f.title
        }
    }

    private func priority(_ spot: MapSpot) -> Double {
        Double(Self.ring.count - (Self.ring.firstIndex(of: spot) ?? 0))
    }

    private func edgeButton(_ side: EdgeSide, length: CGFloat) -> some View {
        let function = prefs.edge(side)
        let spot = MapSpot.edge(side)
        let level = live.level(of: function).map { CGFloat($0) }
        let muted = function == .volume && live.muted
        let percent = muted ? "Muted" : level.map { "\(Int(($0 * 100).rounded()))%" }
        return EdgeSpot(side: side, length: length, function: function,
                        level: function.hasLevel ? level : nil, value: function.hasLevel ? percent : nil,
                        muted: muted, active: live.activeSide == side,
                        selected: selection == spot, keyboardFocused: mapFocused && keyboardNav,
                        anchor: anchors.anchor(spot)) {
            open(spot)
        }
        .help("\(side.title): \(function.title). Click to change.")
        .accessibilityLabel("\(side.title): \(function.title)")
        .accessibilityValue(percent ?? "")
        .accessibilityHint("Opens a menu of actions")
        .accessibilitySortPriority(priority(spot))
    }

    private func cornerButton(_ corner: Corner) -> some View {
        let function = prefs.corner(corner)
        let spot = MapSpot.corner(corner)
        // Mute corners show when they're on: filled orange, so a muted mic is never a surprise.
        let isMuted = (function == .muteMicrophone && live.micMuted) || (function == .mute && live.muted)
        return CornerSpot(selected: selection == spot, keyboardFocused: mapFocused && keyboardNav,
                          off: function == .off, on: isMuted, anchor: anchors.anchor(spot)) {
            open(spot)
        } label: {
            if function == .openApp, let id = prefs.cornerApps[corner] {
                AppIcon(bundleID: id).frame(width: 18, height: 18)
            } else if isMuted {
                Image(systemName: function.icon + ".fill").foregroundStyle(.white)
            } else if function != .off {
                Image(systemName: function.icon)
            } else {
                Image(systemName: "plus").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
            }
        }
        .help("\(corner.title): \(title(for: spot))\(isMuted ? (function == .mute ? ". Sound is muted" : ". Microphone is muted") : ""). Click to change.")
        .accessibilityLabel("\(corner.title): \(title(for: spot))")
        .accessibilityValue(isMuted ? "Muted" : "")
        .accessibilityHint("Opens a menu of actions")
        .accessibilitySortPriority(priority(spot))
    }
}

// MARK: - Trackpad drawing

/// A Magic Trackpad seen from above: brushed silver in light mode, dark gray in dark mode,
/// with a lit top rim, a shaded bottom rim and a soft shadow underneath.
struct TrackpadSurface: View {
    static let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let shape = Self.shape
        shape
            .fill(LinearGradient(colors: dark ? [Color(white: 0.29), Color(white: 0.19)]
                                              : [Color(white: 0.96), Color(white: 0.80)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            // Glass sheen across the top.
            .overlay(shape.fill(LinearGradient(colors: [Color.white.opacity(dark ? 0.07 : 0.4), .clear],
                                               startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55))))
            // Bevel: light catches the top rim, the bottom rim falls into shade.
            .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(dark ? 0.24 : 1),
                                                                Color.white.opacity(dark ? 0.05 : 0.35),
                                                                Color.black.opacity(dark ? 0.45 : 0.14)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .overlay(shape.inset(by: -0.5).stroke(Color.black.opacity(dark ? 0.65 : 0.22), lineWidth: 0.5))
            .shadow(color: .black.opacity(dark ? 0.5 : 0.2), radius: 7, y: 4)
            .shadow(color: .black.opacity(dark ? 0.35 : 0.12), radius: 1, y: 1)
            .accessibilityHidden(true)
    }
}

/// One edge: a color strip along the trackpad's rim (filled to the live level) and a label chip
/// beside it. The whole band is one button.
private struct EdgeSpot: View {
    let side: EdgeSide
    let length: CGFloat
    let function: EdgeFunction
    let level: CGFloat?
    let value: String?
    let muted: Bool
    /// Being slid right now.
    let active: Bool
    let selected: Bool
    let keyboardFocused: Bool
    let anchor: MenuAnchor
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    private let thickness: CGFloat = 4
    private let spacing: CGFloat = 7

    var body: some View {
        Button(action: action) {
            layout.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The map is one Tab stop with arrow keys inside, like a native radio group.
        .focusable(false)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder private var layout: some View {
        switch side {
        case .left: HStack(spacing: spacing) { strip; chip }.frame(height: length)
        case .right: HStack(spacing: spacing) { chip; strip }.frame(height: length)
        case .top: VStack(spacing: spacing) { strip; chip }.frame(width: length)
        case .bottom: VStack(spacing: spacing) { chip; strip }.frame(width: length)
        }
    }

    /// The rim side of the strip, which keeps a small gap from the trackpad's edge.
    private var outward: Edge.Set {
        switch side {
        case .left: return .leading
        case .right: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        }
    }

    private var strip: some View {
        let vertical = side.isVertical
        let colors = function.mapColors
        return ZStack {
            if function == .off {
                Capsule().strokeBorder(Color.primary.opacity(hovering ? 0.4 : 0.22), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            } else {
                Capsule().fill(Color.primary.opacity(scheme == .dark ? 0.14 : 0.1))
                GeometryReader { g in
                    let v = min(max(level ?? 1, 0), 1)
                    LinearGradient(colors: colors, startPoint: vertical ? .bottom : .leading, endPoint: vertical ? .top : .trailing)
                        .frame(width: vertical ? g.size.width : g.size.width * v,
                               height: vertical ? g.size.height * v : g.size.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: vertical ? .bottom : .leading)
                }
                .clipShape(Capsule())
                .opacity(muted ? 0.3 : 1)
            }
        }
        .frame(width: vertical ? thickness : length, height: vertical ? length : thickness)
        .padding(outward, 4)
        .shadow(color: (colors.last ?? .clear).opacity(active ? 0.9 : (hovering ? 0.45 : 0)), radius: 5)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: level)
        .animation(.easeOut(duration: 0.15), value: active)
    }

    private var chip: some View {
        let dark = scheme == .dark
        let off = function == .off
        let fill: Color = off
            ? Color.white.opacity(dark ? (hovering ? 0.1 : 0.05) : (hovering ? 0.6 : 0.35))
            : (dark ? Color.black.opacity(hovering ? 0.5 : 0.34) : Color.white.opacity(hovering ? 0.98 : 0.8))
        return HStack(spacing: 4) {
            if off {
                Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                Text("Add")
            } else {
                Image(systemName: muted ? "speaker.slash.fill" : function.icon)
                    .foregroundStyle(function.mapColors[dark ? 1 : 0])
                Text(function.shortTitle)
                if let value {
                    Text(value).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(off ? Color.secondary : Color.primary)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(fill))
        .overlay(Capsule().strokeBorder(Color.white.opacity(dark ? 0.09 : 0.7), lineWidth: 0.5))
        .overlay(Capsule().strokeBorder(Color.brandAccent, lineWidth: selected ? 2 : 0))
        .overlay(Capsule().inset(by: -3).stroke(Color(nsColor: .keyboardFocusIndicatorColor),
                                                lineWidth: selected && keyboardFocused ? 3 : 0))
        .shadow(color: .black.opacity(off ? 0 : (dark ? 0.3 : 0.14)), radius: 1.5, y: 0.5)
        .fixedSize()
        .background(AnchorView(anchor: anchor))
        .scaleEffect(active ? 1.06 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: active)
    }
}

/// One corner: a small glyph that gets a soft disc on hover and turns solid orange while its
/// mute is on.
private struct CornerSpot<Label: View>: View {
    let selected: Bool
    let keyboardFocused: Bool
    let off: Bool
    /// A mute that's currently on.
    let on: Bool
    let anchor: MenuAnchor
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(on ? Color.orange : Color.primary.opacity(hovering ? 0.12 : 0))
                    .padding(on ? 3 : 0)
                Circle().strokeBorder(Color.primary.opacity(off && !selected ? 0.25 : 0), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .padding(3)
                Circle().strokeBorder(Color.brandAccent, lineWidth: selected ? 2 : 0)
                Circle().inset(by: -3).stroke(Color(nsColor: .keyboardFocusIndicatorColor),
                                              lineWidth: selected && keyboardFocused ? 3 : 0)
                label()
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.7))
            }
            .frame(width: 30, height: 30)
            .contentShape(Circle())
            .background(AnchorView(anchor: anchor))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

extension EdgeFunction {
    /// The strip's colors on the trackpad map: one hue per action, readable on silver and on gray.
    var mapColors: [Color] {
        switch self {
        case .brightness: return [.brandAmber, .brandAmberTop]
        case .volume: return [.brandViolet, .brandCyan]
        case .keyboardBrightness: return [Color(red: 0.24, green: 0.52, blue: 0.98), Color(red: 0.5, green: 0.74, blue: 1)]
        case .micVolume: return [Color(red: 0.16, green: 0.62, blue: 0.45), Color(red: 0.5, green: 0.95, blue: 0.72)]
        case .nightShift: return [Color(red: 0.95, green: 0.42, blue: 0.12), Color(red: 1.0, green: 0.72, blue: 0.38)]
        case .tabs: return [Color(red: 0.2, green: 0.6, blue: 0.9), Color(red: 0.45, green: 0.85, blue: 1)]
        case .undo: return [Color(red: 0.55, green: 0.38, blue: 0.95), Color(red: 0.75, green: 0.6, blue: 1)]
        case .songs: return [Color(red: 0.92, green: 0.3, blue: 0.48), Color(red: 1, green: 0.55, blue: 0.68)]
        case .windows: return [Color(red: 0.1, green: 0.66, blue: 0.66), Color(red: 0.4, green: 0.9, blue: 0.85)]
        case .off: return [Color.gray, Color.gray]
        }
    }
}

// MARK: - Actions menu

/// The native menu that opens under an edge or corner when you click it: every action it can
/// have, the current one checked, plus that action's own options.
enum SpotMenu {
    /// Shows the menu under `view` and returns when it closes.
    static func show(for spot: MapSpot, under view: NSView) {
        make(for: spot).popUp(positioning: nil, at: NSPoint(x: 0, y: -6), in: view)
    }

    static func make(for spot: MapSpot) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        switch spot {
        case .edge(let side): buildEdge(menu, side)
        case .corner(let corner): buildCorner(menu, corner)
        }
        return menu
    }

    // MARK: Edges

    private static func buildEdge(_ menu: NSMenu, _ side: EdgeSide) {
        let prefs = Prefs.shared
        let current = prefs.edge(side)
        menu.addItem(header(side.title))
        let choose: (EdgeFunction) -> Void = { f in
            prefs.edges[side] = f
            explainAccessIfNeeded(f.needsAccess, f.blockedName)
        }
        menu.addItem(item(EdgeFunction.off.title, nil, checked: current == .off) { choose(.off) })
        menu.addItem(.separator())
        menu.addItem(header("Slide"))
        for f in EdgeFunction.available where f.kind == .slider {
            menu.addItem(item(f.title, f.icon, checked: current == f, tip: f.detail(on: side)) { choose(f) })
        }
        menu.addItem(.separator())
        menu.addItem(header("Swipe"))
        for f in EdgeFunction.available where f.kind == .swipe {
            menu.addItem(item(f.title, f.icon, checked: current == f, tip: f.detail(on: side)) { choose(f) })
        }
        if current == .songs {
            menu.addItem(.separator())
            menu.addItem(item("Double-Tap the Edge to Play or Pause", nil, checked: prefs.tapToPlay) {
                prefs.tapToPlay.toggle()
            })
        }
    }

    // MARK: Corners

    private static func buildCorner(_ menu: NSMenu, _ corner: Corner) {
        let prefs = Prefs.shared
        let current = prefs.corner(corner)
        menu.addItem(header("\(corner.title): Double-Tap"))
        let choose: (CornerFunction) -> Void = { f in
            prefs.corners[corner] = f
            explainAccessIfNeeded(f.needsAccess, f.blockedName)
        }
        for (index, group) in CornerFunction.groups.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for f in group where isAvailable(f) {
                switch f {
                case .openApp:
                    let app = current == .openApp ? prefs.cornerApps[corner] : nil
                    let title = app.map { "Open \(AppNames.name(for: $0))" } ?? "Open an App…"
                    let open = item(title, f.icon, checked: app != nil) { chooseApp(for: corner) }
                    if let app, let url = AppNames.url(for: app) {
                        let icon = NSWorkspace.shared.icon(forFile: url.path)
                        icon.size = NSSize(width: 16, height: 16)
                        open.image = icon
                    }
                    menu.addItem(open)
                    if app != nil {
                        menu.addItem(item("Choose Another App…", nil, indent: 1) { chooseApp(for: corner) })
                    }
                case .runShortcut:
                    let run = item(f.title, f.icon, checked: current == .runShortcut)
                    run.submenu = shortcutsMenu(corner, chosen: current == .runShortcut ? prefs.cornerShortcuts[corner] : nil)
                    menu.addItem(run)
                default:
                    let tip = f.isDisruptive ? "Pick a corner your palm doesn't rest on, so it doesn't happen by accident." : nil
                    menu.addItem(item(f.title, f == .off ? nil : f.icon, checked: current == f, tip: tip) { choose(f) })
                }
            }
        }
    }

    private static func shortcutsMenu(_ corner: Corner, chosen: String?) -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false
        let names = UserShortcuts.cached
        if names.isEmpty {
            let none = item(UserShortcuts.loaded ? "You don't have any shortcuts yet" : "Loading your shortcuts…", nil)
            none.isEnabled = false
            sub.addItem(none)
        }
        for name in names {
            sub.addItem(item(name, nil, checked: name == chosen) {
                Prefs.shared.cornerShortcuts[corner] = name
                Prefs.shared.corners[corner] = .runShortcut
            })
        }
        sub.addItem(.separator())
        sub.addItem(item("Open Shortcuts", nil) { SystemControls.openSystemApp("/System/Applications/Shortcuts.app") })
        return sub
    }

    private static func chooseApp(for corner: Corner) {
        let prefs = Prefs.shared
        let panel = NSOpenPanel()
        panel.title = "Choose an App for the \(corner.title)"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier {
            prefs.cornerApps[corner] = id
            prefs.corners[corner] = .openApp
        }
    }

    private static func isAvailable(_ f: CornerFunction) -> Bool {
        f == .screenshot ? SystemControls.hasScreenshotApp : true
    }

    /// Keys-pressing actions need Accessibility: say so in the menu's notice area right away.
    private static func explainAccessIfNeeded(_ needsAccess: Bool, _ name: String) {
        if needsAccess && !LiveState.shared.trusted { LiveState.shared.blockedAction = name }
    }

    // MARK: Items

    private static func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14, *) { return NSMenuItem.sectionHeader(title: title) }
        let h = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        h.isEnabled = false
        return h
    }

    private static func item(_ title: String, _ icon: String?, checked: Bool = false, tip: String? = nil,
                             indent: Int = 0, _ handler: (() -> Void)? = nil) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: handler)
        if let icon { item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil) }
        item.state = checked ? .on : .off
        item.toolTip = tip
        item.indentationLevel = indent
        return item
    }
}

/// A menu item that runs a closure.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: (() -> Void)?

    init(title: String, handler: (() -> Void)?) {
        self.handler = handler
        super.init(title: title, action: handler == nil ? nil : #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler?() }
}

/// Holds the AppKit view under a spot, so its menu can open right below it.
final class MenuAnchor {
    weak var view: NSView?
}

/// One anchor per spot, kept for the life of the map.
final class AnchorStore {
    private var anchors: [MapSpot: MenuAnchor] = [:]
    func anchor(_ spot: MapSpot) -> MenuAnchor {
        if let a = anchors[spot] { return a }
        let a = MenuAnchor()
        anchors[spot] = a
        return a
    }
}

/// Return or Space opens the selected spot's menu (macOS 14 and later).
private struct OpenWithKeys: ViewModifier {
    let action: () -> Void
    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content.onKeyPress(keys: [.return, .space]) { _ in
                action()
                return .handled
            }
        } else {
            content
        }
    }
}

private struct AnchorView: NSViewRepresentable {
    let anchor: MenuAnchor
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { anchor.view = nsView }
}

// MARK: - App names and icons

/// Display names and locations of apps, by bundle ID.
enum AppNames {
    static func url(for id: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }

    static func name(for id: String) -> String {
        guard let url = url(for: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// An app's Finder icon, by bundle ID.
struct AppIcon: View {
    let bundleID: String
    var body: some View {
        Image(nsImage: AppNames.url(for: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
              ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!)
            .resizable()
            .accessibilityHidden(true)
    }
}

/// Hides the system's rectangle around the whole map; the selected spot shows focus instead.
private struct NoSystemFocusRing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content.focusEffectDisabled()
        } else {
            content
        }
    }
}
