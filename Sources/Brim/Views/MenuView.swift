import BrimCore
import SwiftUI

enum MenuPage: Hashable {
    case main, settings, apps
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

/// The everyday surface: your trackpad with what every edge and corner does (and live levels),
/// options for the spot you click, an on/off switch, the current app and haptics.
struct MainPage: View {
    @Binding var page: MenuPage
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var live = LiveState.shared
    /// The spot whose menu is open (or that has keyboard focus).
    @State private var selection: MapSpot?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                AppIconView(size: 22)
                Text("Brim").font(.system(size: 15, weight: .semibold))
                Spacer()
                StatusPill()
            }
            .padding(.horizontal, 2)

            NoticeArea()

            TrackpadMap(selection: $selection)
                .frame(height: 212)

            Card {
                ToggleRow(icon: "hand.draw", title: "Brim Gestures",
                          subtitle: gesturesSubtitle,
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

    private var gesturesSubtitle: String {
        if prefs.paused { return "Paused. Your trackpad works as usual." }
        if prefs.requireModifier { return "Hold Fn or Option to use your edges and corners" }
        return "Slide edges, double-tap corners"
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
        UpdateBanner()
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
