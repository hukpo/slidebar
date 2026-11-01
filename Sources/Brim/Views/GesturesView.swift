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

/// "Edges and Corners": a trackpad map to choose what every edge and corner does.
struct GesturesPage: View {
    @Binding var page: MenuPage
    var back: MenuPage = .main
    @ObservedObject var prefs = Prefs.shared
    @State private var selection: MapSpot = .edge(.right)
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: "Edges and Corners") { page = back }

            Text("Click an edge or corner to choose what it does. Edges respond to a slide or swipe; corners to a double-tap.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)

            TrackpadMap(selection: $selection)
                .frame(height: 196)

            Card {
                SpotEditor(spot: selection)
            }

            VStack(alignment: .trailing, spacing: 6) {
                if confirmReset {
                    Text("Back to brightness, volume, songs and mute?")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Cancel") { confirmReset = false }.controlSize(.small)
                        Button("Restore") { prefs.resetGestures(); confirmReset = false }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    Button("Restore Defaults…") { confirmReset = true }
                        .controlSize(.small)
                        .disabled(prefs.gesturesAreDefault)
                        .help("Put edges and corners back the way Brim starts")
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
    }
}

// MARK: - Map

/// A small trackpad with a button for every edge and corner, showing what each does.
/// Arrow keys move in the direction pressed; VoiceOver reads the spots clockwise.
struct TrackpadMap: View {
    @Binding var selection: MapSpot
    @ObservedObject var prefs = Prefs.shared
    @FocusState private var mapFocused: Bool
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
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12))

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
            if let next = Self.neighbor(of: selection, direction) { select(next, fromKeyboard: true) }
        }
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
        let text = "\(spot.title), \(title(for: spot)). Options below."
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
            return f.title
        }
    }

    private func priority(_ spot: MapSpot) -> Double {
        Double(Self.ring.count - (Self.ring.firstIndex(of: spot) ?? 0))
    }

    private func edgeButton(_ side: EdgeSide) -> some View {
        let function = prefs.edge(side)
        let spot = MapSpot.edge(side)
        return SpotButton(selected: selection == spot, keyboardFocused: mapFocused && keyboardNav, off: function == .off, shape: .capsule) {
            select(spot)
        } label: {
            if function != .off {
                if side.isVertical {
                    VStack(spacing: 4) {
                        Image(systemName: function.icon)
                        Text(function.shortTitle)
                            .font(.system(size: 9, weight: .medium))
                            .fixedSize()
                            .rotationEffect(.degrees(side == .left ? -90 : 90))
                            .frame(width: 12, height: 60)
                    }
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: function.icon)
                        Text(function.shortTitle).font(.system(size: 11, weight: .medium))
                    }
                }
            }
        }
        .help("\(side.title): \(function.title)")
        .accessibilityLabel("\(side.title): \(function.title)")
        .accessibilityHint("Shows its options below")
        .accessibilitySortPriority(priority(spot))
    }

    private func cornerButton(_ corner: Corner) -> some View {
        let function = prefs.corner(corner)
        let spot = MapSpot.corner(corner)
        return SpotButton(selected: selection == spot, keyboardFocused: mapFocused && keyboardNav, off: function == .off, shape: .circle) {
            select(spot)
        } label: {
            if function == .openApp, let id = prefs.cornerApps[corner] {
                AppIcon(bundleID: id).frame(width: 18, height: 18)
            } else if function != .off {
                Image(systemName: function.icon)
            }
        }
        .frame(width: bar, height: bar)
        .help("\(corner.title): \(title(for: spot))")
        .accessibilityLabel("\(corner.title): \(title(for: spot))")
        .accessibilityHint("Shows its options below")
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
        }
        .buttonStyle(.plain)
        // The map is one Tab stop with arrow keys inside, like a native radio group.
        .focusable(false)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder private var background: some View {
        let fill = Color.primary.opacity(off ? (hovering ? 0.05 : 0) : (hovering ? 0.12 : 0.08))
        let dash = StrokeStyle(lineWidth: 1, dash: [3, 3])
        switch shape {
        case .capsule:
            Capsule().fill(fill)
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

// MARK: - Editor

/// Choose the action for the selected spot, with a plain description of the gesture.
private struct SpotEditor: View {
    let spot: MapSpot
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var live = LiveState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch spot {
            case .edge(let side): edgeEditor(side)
            case .corner(let corner): cornerEditor(corner)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func edgeEditor(_ side: EdgeSide) -> some View {
        let function = prefs.edge(side)
        HStack {
            Text(side.title).font(.system(size: 13, weight: .semibold))
            Spacer()
            Picker(side.title, selection: Binding(
                get: { prefs.edge(side) },
                set: { prefs.edges[side] = $0 }
            )) {
                ForEach(EdgeFunction.available.filter { $0.kind == .off }) { option($0.title, $0.icon).tag($0) }
                Divider()
                Section("Slide") {
                    ForEach(EdgeFunction.available.filter { $0.kind == .slider }) { option($0.title, $0.icon).tag($0) }
                }
                Section("Swipe") {
                    ForEach(EdgeFunction.available.filter { $0.kind == .swipe }) { option($0.title, $0.icon).tag($0) }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        Text(function.detail(on: side))
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if function == .songs {
            Toggle("Tap the edge to play or pause", isOn: $prefs.tapToPlay)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
        }
        if function.needsAccess && !live.trusted { NeedsAccessNote() }
    }

    @ViewBuilder
    private func cornerEditor(_ corner: Corner) -> some View {
        let function = prefs.corner(corner)
        HStack {
            Text(corner.title).font(.system(size: 13, weight: .semibold))
            Spacer()
            Picker(corner.title, selection: Binding(
                get: { prefs.corner(corner) },
                set: { newValue in
                    prefs.corners[corner] = newValue
                    if newValue == .openApp && prefs.cornerApps[corner] == nil { chooseApp(for: corner) }
                }
            )) {
                ForEach(Array(CornerFunction.groups.enumerated()), id: \.offset) { index, group in
                    if index > 0 { Divider() }
                    ForEach(group.filter(isAvailable)) { option($0.title, $0.icon).tag($0) }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        Text(function == .off ? "This corner works like the rest of the trackpad."
                              : "Double-tap the corner to \(cornerVerb(function, corner)).")
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if function.isDisruptive {
            Label {
                Text("Pick a corner your palm doesn't rest on, so it doesn't happen by accident.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            .font(.system(size: 11))
        }
        if function == .openApp {
            HStack(spacing: 8) {
                if let id = prefs.cornerApps[corner] {
                    AppIcon(bundleID: id).frame(width: 18, height: 18)
                    Text(AppNames.name(for: id)).font(.system(size: 12, weight: .medium))
                } else {
                    Text("No app chosen yet").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(prefs.cornerApps[corner] == nil ? "Choose App…" : "Change…") { chooseApp(for: corner) }
                    .controlSize(.small)
            }
        }
        if function.needsAccess && !live.trusted { NeedsAccessNote() }
    }

    private func isAvailable(_ f: CornerFunction) -> Bool {
        switch f {
        case .missionControl: return SystemControls.hasMissionControl
        case .screenshot: return SystemControls.hasScreenshotApp
        default: return true
        }
    }

    private func cornerVerb(_ f: CornerFunction, _ corner: Corner) -> String {
        switch f {
        case .off: return ""
        case .mute: return "mute or unmute"
        case .playPause: return "play or pause"
        case .nextSong: return "skip to the next song"
        case .previousSong: return "go back to the previous song"
        case .missionControl: return "open Mission Control"
        case .showDesktop: return "show the desktop"
        case .spotlight: return "open Spotlight"
        case .screenshot: return "take a screenshot"
        case .lockScreen: return "lock your Mac"
        case .sleepDisplay: return "turn off the display"
        case .openApp: return prefs.cornerApps[corner].map { "open \(AppNames.name(for: $0))" } ?? "open the app you choose"
        }
    }

    private func option(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon)
    }

    private func chooseApp(for corner: Corner) {
        let panel = NSOpenPanel()
        panel.title = "Choose an App for the \(corner.title)"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier {
            prefs.cornerApps[corner] = id
        } else if prefs.cornerApps[corner] == nil {
            prefs.corners[corner] = .off
        }
    }
}

/// Explains, in place, that an action needs Accessibility, with a way to allow it.
struct NeedsAccessNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("This needs Accessibility, so Brim can press keys for you.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Allow…") { Permissions.ask() }
                .controlSize(.small)
        }
    }
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
