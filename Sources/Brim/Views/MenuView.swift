import BrimCore
import SwiftUI

/// The popover's two pages.
enum MenuPage: Hashable {
    case main, advanced
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
            case .advanced:
                AdvancedPage(page: $page)
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

/// The home page: an on/off switch, the trackpad map (what every edge and corner does, with live
/// levels), and the everyday settings under it.
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
                Text(stateText)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(live.status == .noTrackpad ? Color.orange : Color.secondary)
                    .help(stateHelp)
                Toggle(isOn: Binding(get: { !prefs.paused }, set: { prefs.paused = !$0 })) { EmptyView() }
                    .labelsHidden()
                    .accessibilityLabel("Brim Gestures")
                    .modifier(SwitchStyle())
                    .controlSize(.small)
                    .help(prefs.paused ? "Turn Brim on" : "Pause Brim. Your trackpad works as usual.")
            }
            .padding(.horizontal, 2)

            NoticeArea()

            TrackpadMap(selection: $selection)
                .frame(height: 216)
                .padding(.bottom, 4)

            SettingsSections()

            MenuFooter {
                PlainIconButton(systemName: "slider.horizontal.3", title: "Advanced", help: "Advanced options") { page = .advanced }
            }
        }
        .padding(14)
    }

    private var stateText: String {
        if prefs.paused { return "Paused" }
        if live.status == .noTrackpad { return "No trackpad" }
        if prefs.requireModifier { return "Hold Fn or ⌥" }
        return "On"
    }

    private var stateHelp: String {
        if prefs.paused { return "Your trackpad works as usual." }
        if prefs.requireModifier { return "Hold Fn or Option to use your edges and corners." }
        return "Slide edges, double-tap corners. Click one to change it."
    }
}

/// The notices above the map: the most useful one of the general notices, then Keep Awake and
/// update status when they apply.
struct NoticeArea: View {
    @ObservedObject var live = LiveState.shared
    @ObservedObject var prefs = Prefs.shared
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        if snapshotMode {
            // Screenshots show the menu itself, not whatever notice this Mac happens to have.
            EmptyView()
        } else if live.showWelcome {
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
        } else if !prefs.starNoticeDismissed, prefs.hasCompletedSetup, AppConfig.sourceURL != nil {
            StarBanner()
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

/// Update progress and results, following the updater's phase.
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

/// A gentle, closable ask for a GitHub star, shown once nothing more useful needs saying.
struct StarBanner: View {
    var body: some View {
        Banner(icon: "star", tint: .yellow,
               text: "Enjoying Brim? A star on GitHub helps other Mac users find it.",
               primary: ("Star on GitHub", {
                   AppActions.shared.openSource()
                   Prefs.shared.starNoticeDismissed = true
               }),
               onDismiss: { Prefs.shared.starNoticeDismissed = true })
    }
}

/// Shown while Accessibility is off. Brim works without it, so this informs rather than alarms.
struct AccessBanner: View {
    var body: some View {
        Banner(icon: "lock.open",
               text: "Volume and brightness already work. Allow Accessibility to also see the usual on-screen display and use gestures that press keys, like songs and tabs.",
               primary: ("Allow…", { Permissions.ask() }),
               onDismiss: { Prefs.shared.accessNoticeDismissed = true })
    }
}
