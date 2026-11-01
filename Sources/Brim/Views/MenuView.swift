import BrimCore
import SwiftUI

indirect enum MenuPage: Hashable {
    case main, settings, apps
    case gestures(back: MenuPage)
}

/// Root view of the menu bar popover.
struct MenuView: View {
    @State private var page: MenuPage = .main
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            switch page {
            case .main:
                MainPage(page: $page)
                    .transition(transition(from: .leading))
            case .settings:
                SettingsPage(page: $page)
                    .transition(transition(from: .trailing))
            case .apps:
                AppsPage(page: $page)
                    .transition(transition(from: .trailing))
            case .gestures(let back):
                GesturesPage(page: $page, back: back)
                    .transition(transition(from: .trailing))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.9), value: page)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .clipped()
    }

    private func transition(from edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}

// MARK: - Main page

/// The everyday surface: live levels, an on/off switch, the current app, gestures and haptics.
struct MainPage: View {
    @Binding var page: MenuPage
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var live = LiveState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                AppIconView(size: 22)
                Text("Brim").font(.system(size: 15, weight: .semibold))
                Spacer()
                StatusPill()
            }
            .padding(.horizontal, 2)

            EdgeMeters()

            NoticeArea()

            Card {
                ToggleRow(icon: "hand.draw", title: "Brim Gestures",
                          subtitle: edgeSlidersSubtitle,
                          isOn: Binding(get: { !prefs.paused }, set: { prefs.paused = !$0 }))

                if let app = live.lastApp, let id = app.bundleIdentifier, let name = app.localizedName {
                    RowDivider()
                    ToggleRow(icon: "app.dashed", title: "Use in \(name)",
                              subtitle: "Turn off to pause Brim while \(name) is in front",
                              isOn: Binding(
                                get: { !prefs.excludedApps.contains(id) },
                                set: { on in
                                    if on { prefs.excludedApps.removeAll { $0 == id } }
                                    else if !prefs.excludedApps.contains(id) { prefs.excludedApps.append(id) }
                                }))
                        .disabled(prefs.paused)
                }

                RowDivider()

                NavigationRow(icon: "rectangle.and.hand.point.up.left", title: "Edges and Corners",
                              subtitle: GestureSummary.text(prefs)) {
                    page = .gestures(back: .main)
                }

                RowDivider()

                ChoiceRow(icon: "hand.tap", title: "Haptic Feedback",
                          subtitle: "A tick under your finger at each step",
                          options: HapticStrength.allCases.map { ($0, $0.title) },
                          selection: $prefs.haptics,
                          onChange: { Haptics.tick($0) })
            }

            MenuFooter {
                PlainIconButton(systemName: "gearshape", title: "Settings", help: "Settings (⌘,)") { page = .settings }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
        .padding(14)
    }

    private var edgeSlidersSubtitle: String {
        if prefs.paused { return "Paused. Your trackpad works as usual." }
        if prefs.requireModifier { return "Hold Fn or Option to use your edges and corners" }
        return "Your edges and corners"
    }
}

/// One short line describing the current edges and corners, in map order (left, right, top, bottom, corners).
enum GestureSummary {
    static func text(_ prefs: Prefs) -> String {
        var parts = [EdgeSide.left, .right, .top, .bottom].compactMap { side -> String? in
            let f = prefs.edge(side)
            return f == .off ? nil : f.shortTitle
        }
        let corners = Corner.allCases.filter { prefs.cornerIsActive($0) }
        if corners.count <= 2 {
            for c in corners {
                let f = prefs.corner(c)
                switch f {
            case .openApp: parts.append(prefs.cornerApps[c].map(AppNames.name(for:)) ?? f.title)
            case .runShortcut: parts.append(prefs.cornerShortcuts[c] ?? f.title)
            default: parts.append(f.title)
            }
            }
        } else {
            parts.append("\(corners.count) corners")
        }
        // A no-break space keeps each dot at the end of a line rather than the start of the next.
        return parts.isEmpty ? "Nothing assigned yet" : parts.joined(separator: "\u{00A0}· ")
    }
}

/// At most one notice at a time, most useful first. Every notice can be dismissed or acted on.
struct NoticeArea: View {
    @ObservedObject var live = LiveState.shared
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        if live.showWelcome {
            Banner(icon: "menubar.arrow.up.rectangle",
                   text: "Brim lives here in the menu bar. Click its icon any time to see your levels or change what the edges do.",
                   onDismiss: { live.showWelcome = false })
        } else if live.status == .noTrackpad {
            Banner(icon: "exclamationmark.triangle", tint: .orange,
                   text: "Brim can't find a trackpad. Turn on or connect your Magic Trackpad.",
                   primary: ("Look Again", { EdgeEngine.shared.restart() }))
        } else if let action = live.blockedAction, !live.trusted {
            Banner(icon: "lock", tint: .orange,
                   text: "\(action) needs Accessibility, so Brim can press keys for you.",
                   primary: ("Allow…", { Permissions.ask() }),
                   onDismiss: { live.blockedAction = nil })
        } else if live.showAccessNotice {
            AccessBanner()
        }
        if live.keepingAwake {
            Banner(icon: "cup.and.saucer.fill",
                   text: "Keeping your Mac awake. Its display won't turn off on its own.",
                   primary: ("Let It Sleep", { _ = KeepAwake.toggle() }))
        }
        if live.micMuted && prefs.corners.values.contains(.muteMicrophone) {
            Banner(icon: "mic.slash.fill", tint: .orange,
                   text: "Your microphone is muted.",
                   primary: ("Unmute", {
                       Microphone.setMuted(false)
                       live.micMuted = Microphone.isMuted()
                   }))
        }
        UpdateBanner()
    }
}

// MARK: - Edge meters

/// The brand card: a little trackpad showing what the left and right edges control, live.
struct EdgeMeters: View {
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var live = LiveState.shared

    var body: some View {
        ZStack {
            NightBackground(cornerRadius: 16)

            HStack(spacing: 12) {
                meter(.left)
                readout(.left, leading: true)
                Spacer(minLength: 0)
                readout(.right, leading: false)
                meter(.right)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)

            // The top and bottom edges, lit when they do something.
            VStack {
                strip(.top).padding(.top, 7)
                Spacer()
                strip(.bottom).padding(.bottom, 7)
            }
            .accessibilityHidden(true)
        }
        .frame(height: 108)
        .environment(\.colorScheme, .dark)
        .opacity(prefs.paused ? 0.6 : 1)
        .animation(.easeOut(duration: 0.2), value: prefs.paused)
    }

    private func strip(_ side: EdgeSide) -> some View {
        Capsule()
            .fill(Color.white.opacity(prefs.edge(side) != .off ? 0.25 : 0.06))
            .frame(width: 44, height: 3)
            .overlay(Capsule().fill(Color.white).opacity(live.activeSide == side ? 0.7 : 0))
    }

    private func meter(_ side: EdgeSide) -> some View {
        let function = prefs.edge(side)
        return LevelBar(function: function,
                        level: CGFloat(live.level(of: function) ?? 0),
                        active: live.activeSide == side,
                        dimmed: function == .volume && live.muted)
    }

    @ViewBuilder
    private func readout(_ side: EdgeSide, leading: Bool) -> some View {
        let function = prefs.edge(side)
        let active = live.activeSide == side
        let muted = function == .volume && live.muted
        let icon = muted ? "speaker.slash.fill" : function.icon
        let tint = function.levelColors[1]

        VStack(alignment: leading ? .leading : .trailing, spacing: 3) {
            HStack(spacing: 5) {
                if leading { iconView(icon, tint: tint, function: function) }
                Text(function.shortTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                if !leading { iconView(icon, tint: tint, function: function) }
            }

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                if muted {
                    Text("Muted")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                } else if let v = live.level(of: function) {
                    Text("\(Int((v * 100).rounded()))")
                        .font(.system(size: 34, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white)
                    Text("%")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                } else {
                    Text(function == .off ? "—" : (function.kind == .swipe ? "Swipe" : "Slide"))
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(height: 40, alignment: .bottom)
            .opacity(live.activeSide == nil || active ? 1 : 0.5)
            .animation(.easeOut(duration: 0.15), value: live.activeSide)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(side.title): \(function.title)")
        // For levels, the bar beside it speaks and adjusts the same value for VoiceOver.
        .accessibilityHidden(function.hasLevel)
    }

    private func iconView(_ name: String, tint: Color, function: EdgeFunction) -> some View {
        Image(systemName: name)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(function.hasLevel ? tint : .white.opacity(0.6))
    }
}

/// A glowing vertical meter. Drag it to set the level; VoiceOver can adjust it too.
struct LevelBar: View {
    let function: EdgeFunction
    let level: CGFloat
    let active: Bool
    let dimmed: Bool
    @State private var hovering = false

    var body: some View {
        let colors = function.levelColors
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.white.opacity(function == .off ? 0.06 : 0.14))
                if function.hasLevel {
                    Capsule()
                        .fill(LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top))
                        .frame(height: max(geo.size.width, geo.size.height * min(max(level, 0), 1)))
                        .opacity(dimmed ? 0.3 : 1)
                        .shadow(color: colors[1].opacity(dimmed ? 0 : 0.5), radius: active || hovering ? 5 : 2)
                } else if active {
                    Capsule().fill(Color.white.opacity(0.5))
                }
            }
            .contentShape(Rectangle().inset(by: -10))
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    guard function.hasLevel else { return }
                    set(Float(1 - g.location.y / geo.size.height))
                }
            )
        }
        .frame(width: active || hovering ? 8 : 6)
        .onHover { inside in
            guard function.hasLevel else { return }
            hovering = inside
            if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: level)
        .animation(.easeOut(duration: 0.15), value: active || hovering)
        .help(function.hasLevel ? "Drag to change the \(function.title.lowercased())" : "")
        .accessibilityElement()
        .accessibilityHidden(!function.hasLevel)
        .accessibilityLabel(function.title)
        .accessibilityValue(dimmed ? "Muted" : "\(Int((level * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(Float(level) + 1 / 16)
            case .decrement: set(Float(level) - 1 / 16)
            @unknown default: break
            }
        }
    }

    private func set(_ value: Float) {
        let v = min(max(value, 0), 1)
        switch function {
        case .brightness: SystemControls.setBrightness(v)
        case .volume: SystemControls.setVolume(v)
        case .keyboardBrightness: KeyboardBacklight.setLevel(v)
        default: return
        }
        LiveState.shared.refreshLevels()
    }
}

// MARK: - Banners

/// Update notices. Every notice can be dismissed.
struct UpdateBanner: View {
    @ObservedObject var updater = Updater.shared

    var body: some View {
        switch updater.phase {
        case .available(let info):
            Banner(icon: "arrow.down.circle",
                   text: "Brim \(info.version) is ready to install." + (info.notes?.first.map { " \($0)" } ?? ""),
                   primary: ("Install and Relaunch", { Task { await updater.install(info) } }),
                   onDismiss: { updater.dismiss() })
        case .downloading, .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(updater.phase == .downloading ? "Downloading the update…" : "Installing the update…")
                    .font(.system(size: 11.5))
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.brimAccent.opacity(0.1)))
        case .upToDate:
            Banner(icon: "checkmark.circle", tint: .green,
                   text: "You have the latest version of Brim (\(AppConfig.version)).",
                   onDismiss: { updater.dismiss() })
        case .failed(let message):
            Banner(icon: "exclamationmark.triangle", tint: .orange,
                   text: "Brim couldn't update. \(message) Your current version keeps working.",
                   primary: ("Try Again", { AppActions.shared.checkForUpdates() }),
                   onDismiss: { updater.dismiss() })
        default:
            EmptyView()
        }
    }
}

/// Shown while Accessibility is off. Brim works without it, so this informs rather than alarms.
struct AccessBanner: View {
    var body: some View {
        Banner(icon: "lock.open",
               text: "Volume and brightness already work. Allow Accessibility to also see the usual on-screen display and use gestures that press keys, like songs and desktops.",
               primary: ("Allow…", { Permissions.ask() }),
               onDismiss: { Prefs.shared.accessNoticeDismissed = true })
    }
}
