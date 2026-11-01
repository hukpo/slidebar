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
    @ObservedObject var live = LiveState.shared
    @State private var selection: MapSpot = .edge(.right)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: "Edges and Corners") { page = back }

            Text("Choose what each edge and corner of your trackpad does. Click one to change it.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)

            TrackpadMap(selection: $selection)
                .frame(height: 196)

            Card {
                SpotEditor(spot: selection)
            }

            HStack {
                Text("Corners respond to a double-tap. Edges respond to a slide or swipe along them.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
        }
        .padding(14)
    }
}

// MARK: - Map

/// A small trackpad with a button for every edge and corner, labeled with what it does.
struct TrackpadMap: View {
    @Binding var selection: MapSpot
    @ObservedObject var prefs = Prefs.shared

    private let bar: CGFloat = 30
    private let gap: CGFloat = 6

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

                // What's selected, in the middle of the pad.
                VStack(spacing: 3) {
                    Text(selection.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(currentTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .multilineTextAlignment(.center)
                }
                .frame(width: w - 2 * (bar + 3 * gap) - 20)
                .position(x: w / 2, y: h / 2)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Trackpad map")
    }

    private var currentTitle: String {
        switch selection {
        case .edge(let side): return prefs.edge(side).title
        case .corner(let corner):
            let f = prefs.corner(corner)
            if f == .openApp, let id = prefs.cornerApps[corner] { return "Open \(AppNames.name(for: id))" }
            return f.title
        }
    }

    private func edgeButton(_ side: EdgeSide) -> some View {
        let function = prefs.edge(side)
        let selected = selection == .edge(side)
        return SpotButton(selected: selected, off: function == .off, shape: .capsule) {
            selection = .edge(side)
        } label: {
            Group {
                if side.isVertical {
                    VStack(spacing: 4) {
                        Image(systemName: function.icon)
                        if function != .off {
                            Text(function.shortTitle)
                                .font(.system(size: 9, weight: .medium))
                                .fixedSize()
                                .rotationEffect(.degrees(side == .left ? -90 : 90))
                                .frame(width: 12, height: 60)
                        }
                    }
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: function.icon)
                        if function != .off { Text(function.shortTitle).font(.system(size: 11, weight: .medium)) }
                    }
                }
            }
        }
        .accessibilityLabel("\(side.title): \(function.title)")
    }

    private func cornerButton(_ corner: Corner) -> some View {
        let function = prefs.corner(corner)
        return SpotButton(selected: selection == .corner(corner), off: function == .off, shape: .circle) {
            selection = .corner(corner)
        } label: {
            Image(systemName: function.icon)
        }
        .frame(width: bar, height: bar)
        .accessibilityLabel("\(corner.title): \(function.title)")
    }
}

/// One tappable spot on the map. Selected spots take the accent color; empty spots are dashed.
private struct SpotButton<Label: View>: View {
    enum Shape { case capsule, circle }
    let selected: Bool
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
                    .foregroundStyle(selected ? Color.white : (off ? Color.secondary : Color.primary))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder private var background: some View {
        let fill: Color = selected ? .brimAccent : Color.primary.opacity(hovering ? 0.12 : (off ? 0.03 : 0.08))
        switch shape {
        case .capsule:
            Capsule().fill(fill)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(off && !selected ? 0.2 : 0), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        case .circle:
            Circle().fill(fill)
                .overlay(Circle().strokeBorder(Color.primary.opacity(off && !selected ? 0.25 : 0), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
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
