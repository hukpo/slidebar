import BrimCore
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

    private let bar: CGFloat = 30
    private let gap: CGFloat = 6

    /// Clockwise from the top-left corner.
    static let ring: [MapSpot] = [.corner(.topLeft), .edge(.top), .corner(.topRight), .edge(.right),
                                  .corner(.bottomRight), .edge(.bottom), .corner(.bottomLeft), .edge(.left)]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let corner = bar
            ZStack(alignment: .topLeading) {
                NightBackground(cornerRadius: 18)

                CenterReadout(selection: selection)
                    .frame(width: w - 2 * (bar + 2 * gap) - 16, height: h - 2 * (bar + 2 * gap) - 8)
                    .offset(x: bar + 2 * gap + 8, y: bar + 2 * gap + 4)

                // Edges
                edgeButton(.top).frame(width: w - 2 * (corner + 2 * gap), height: bar)
                    .offset(x: corner + 2 * gap, y: gap)
                edgeButton(.bottom).frame(width: w - 2 * (corner + 2 * gap), height: bar)
                    .offset(x: corner + 2 * gap, y: h - bar - gap)
                edgeButton(.left).frame(width: bar, height: h - 2 * (corner + 2 * gap))
                    .offset(x: gap, y: corner + 2 * gap)
                edgeButton(.right).frame(width: bar, height: h - 2 * (corner + 2 * gap))
                    .offset(x: w - bar - gap, y: corner + 2 * gap)

                // Corners
                cornerButton(.topLeft).offset(x: gap, y: gap)
                cornerButton(.topRight).offset(x: w - corner - gap, y: gap)
                cornerButton(.bottomLeft).offset(x: gap, y: h - corner - gap)
                cornerButton(.bottomRight).offset(x: w - corner - gap, y: h - corner - gap)
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
        .environment(\.colorScheme, .dark)
        .opacity(prefs.paused ? 0.6 : 1)
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

    private func edgeButton(_ side: EdgeSide) -> some View {
        let function = prefs.edge(side)
        let spot = MapSpot.edge(side)
        let level = live.level(of: function).map { CGFloat($0) }
        let muted = function == .volume && live.muted
        let percent = muted ? "Muted" : level.map { "\(Int(($0 * 100).rounded()))%" }
        return SpotButton(selected: selection == spot, keyboardFocused: mapFocused && keyboardNav, off: function == .off,
                          shape: .capsule, levelValue: function.hasLevel ? level : nil, vertical: side.isVertical,
                          colors: function.levelColors, dimmed: muted, active: live.activeSide == side,
                          anchor: anchors.anchor(spot)) {
            open(spot)
        } label: {
            if function == .off {
                EmptySpotMark()
            } else {
                if side.isVertical {
                    VStack(spacing: 4) {
                        Image(systemName: muted ? "speaker.slash.fill" : function.icon)
                        Text(function.shortTitle)
                            .font(.system(size: 9, weight: .medium))
                            .fixedSize()
                            .rotationEffect(.degrees(side == .left ? -90 : 90))
                            .frame(width: 12, height: 60)
                        if let percent, !muted {
                            Text(percent.dropLast())
                                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: function.icon)
                        Text(function.shortTitle).font(.system(size: 11, weight: .medium))
                        if let percent {
                            Text(percent)
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
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
        return SpotButton(selected: selection == spot, keyboardFocused: mapFocused && keyboardNav, off: function == .off,
                          shape: .circle, anchor: anchors.anchor(spot)) {
            open(spot)
        } label: {
            if function == .openApp, let id = prefs.cornerApps[corner] {
                AppIcon(bundleID: id).frame(width: 18, height: 18)
            } else if function != .off {
                Image(systemName: function.icon)
            } else {
                EmptySpotMark()
            }
        }
        .frame(width: bar, height: bar)
        .help("\(corner.title): \(title(for: spot)). Click to change.")
        .accessibilityLabel("\(corner.title): \(title(for: spot))")
        .accessibilityHint("Opens a menu of actions")
        .accessibilitySortPriority(priority(spot))
    }
}

/// One spot on the map. The selected spot gets an accent ring; empty spots are dashed outlines.
private struct SpotButton<Label: View>: View {
    enum Shape { case capsule, circle }
    let selected: Bool
    /// The map has keyboard focus: the selected spot shows the system focus halo.
    let keyboardFocused: Bool
    let off: Bool
    let shape: Shape
    /// A live level (0…1) filling the edge from the bottom or the left.
    var levelValue: CGFloat? = nil
    var vertical = false
    var colors: [Color] = []
    var dimmed = false
    /// Being slid right now.
    var active = false
    /// Where the actions menu opens from.
    let anchor: MenuAnchor
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                background
                label()
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primary)
            }
            .contentShape(Rectangle())
            .background(AnchorView(anchor: anchor))
        }
        .buttonStyle(.plain)
        // The map is one Tab stop with arrow keys inside, like a native radio group.
        .focusable(false)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder private var background: some View {
        let fill = Color.primary.opacity(off ? (hovering ? 0.05 : 0) : (hovering || active ? 0.14 : 0.08))
        let dash = StrokeStyle(lineWidth: 1, dash: [3, 3])
        switch shape {
        case .capsule:
            Capsule().fill(fill)
                .overlay(levelFill)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(off && !selected ? 0.25 : 0), style: dash))
                .overlay(Capsule().strokeBorder(Color.brimAccent, lineWidth: selected ? 2 : 0))
                .overlay(Capsule().inset(by: -3).stroke(Color(nsColor: .keyboardFocusIndicatorColor),
                                                        lineWidth: selected && keyboardFocused ? 3 : 0))
        case .circle:
            Circle().fill(fill)
                .overlay(Circle().strokeBorder(Color.primary.opacity(off && !selected ? 0.3 : 0), style: dash))
                .overlay(Circle().strokeBorder(Color.brimAccent, lineWidth: selected ? 2 : 0))
                .overlay(Circle().inset(by: -3).stroke(Color(nsColor: .keyboardFocusIndicatorColor),
                                                       lineWidth: selected && keyboardFocused ? 3 : 0))
        }
    }
}

/// A faint plus in an empty spot: there's room for something here.
private struct EmptySpotMark: View {
    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

extension SpotButton {
    @ViewBuilder var levelFill: some View {
        if let level = levelValue, colors.count > 0 {
            GeometryReader { g in
                let v = min(max(level, 0), 1)
                LinearGradient(colors: colors, startPoint: vertical ? .bottom : .leading, endPoint: vertical ? .top : .trailing)
                    .frame(width: vertical ? g.size.width : max(g.size.height, g.size.width * v),
                           height: vertical ? max(g.size.width, g.size.height * v) : g.size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: vertical ? .bottom : .leading)
            }
            .clipShape(Capsule())
            .opacity(dimmed ? 0.12 : (active ? 0.6 : 0.38))
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: level)
            .animation(.easeOut(duration: 0.15), value: active)
        }
    }
}

/// The middle of the map: a hint when nothing is open, the live level while sliding.
private struct CenterReadout: View {
    let selection: MapSpot?
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var live = LiveState.shared

    var body: some View {
        Group {
            if let side = live.activeSide, prefs.edge(side).hasLevel, let v = live.level(of: prefs.edge(side)) {
                let function = prefs.edge(side)
                let muted = function == .volume && live.muted
                VStack(spacing: 2) {
                    Label(function.shortTitle, systemImage: muted ? "speaker.slash.fill" : function.icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(muted ? "Muted" : "\(Int((v * 100).rounded()))")
                            .font(.system(size: 34, weight: .medium).monospacedDigit())
                        if !muted {
                            Text("%").font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.65))
                        }
                    }
                    .foregroundStyle(.white)
                }
                .transition(.opacity)
            } else if prefs.paused {
                hint("Paused", "Your trackpad works as usual.")
            } else if selection == nil {
                hint(nil, "Click an edge or corner\nto choose what it does")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.15), value: live.activeSide)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func hint(_ title: String?, _ text: String) -> some View {
        VStack(spacing: 3) {
            if let title { Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.85)) }
            Text(text)
                .font(.system(size: 11.5))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.55))
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

enum AppNames {
    static func url(for id: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }

    static func name(for id: String) -> String {
        guard let url = url(for: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

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
