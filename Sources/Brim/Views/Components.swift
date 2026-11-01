import SwiftUI

extension Color {
    static let brimAccent = Color(nsColor: Brand.accent)
    static let brimAmber = Color(nsColor: Brand.amberBottom)
    static let brimAmberTop = Color(nsColor: Brand.amberTop)
    static let brimCyan = Color(nsColor: Brand.cyanTop)
    static let brimViolet = Color(nsColor: Brand.violetBottom)
}

/// Round icon badge on the left of each row. Filled with the accent when the feature is on.
struct IconBadge: View {
    let systemName: String
    var active = false

    var body: some View {
        ZStack {
            Circle()
                .fill(active ? Color.brimAccent : Color.primary.opacity(0.08))
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Color.white : Color.primary.opacity(0.75))
        }
        .frame(width: 30, height: 30)
        .animation(.easeOut(duration: 0.15), value: active)
    }
}

/// A small switch in Brim's accent color (drawn in SwiftUI so it looks the same in any window state).
struct BrimSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color.brimAccent : Color.primary.opacity(0.14))
            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                .padding(2)
        }
        .frame(width: 34, height: 20)
        .opacity(isEnabled ? 1 : 0.5)
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isOn)
        .contentShape(Capsule())
        .onTapGesture { if isEnabled { isOn.toggle() } }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAction { isOn.toggle() }
    }
}

/// Title + subtitle label used in every row.
struct RowLabel: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ToggleRow: View {
    let icon: String?
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 11) {
            if let icon {
                IconBadge(systemName: icon, active: isOn)
            } else {
                Color.clear.frame(width: 30, height: 1)
            }
            RowLabel(title: title, subtitle: subtitle)
            Spacer(minLength: 8)
            BrimSwitch(isOn: $isOn)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct SliderRow: View {
    let icon: String
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            IconBadge(systemName: icon)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(valueText)
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $value, in: range, step: step)
                    .controlSize(.small)
                    .tint(.brimAccent)
                    .labelsHidden()
            }
        }
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}

/// Small borderless icon button for the footer.
struct FooterIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .regular))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

/// The "…" menu shared by both pages.
struct MoreMenu: View {
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var licensing = Licensing.shared
    @ObservedObject var updater = Updater.shared

    var body: some View {
        Menu {
            Button(prefs.paused ? "Resume Brim" : "Pause Brim") { prefs.paused.toggle() }
            Divider()
            Button("Setup Guide…") { AppActions.shared.showSetupGuide() }
            Button("Accessibility Settings…") { Permissions.openAccessibilitySettings() }
            Button("Rescan Trackpads") { EdgeEngine.shared.restart() }
            Divider()
            if let update = updater.available {
                Button("Install Brim \(update.version)…") { Task { await updater.install(update) } }
            } else {
                Button("Check for Updates…") { AppActions.shared.checkForUpdates() }
            }
            Button(licensing.isLicensed ? "License…" : "Enter License…") { AppActions.shared.showLicense() }
            if licensing.canBuy {
                Button("Buy Brim…") { licensing.openCheckout() }
            }
            Divider()
            Button("About Brim") { AppActions.shared.showAbout() }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }
}

struct StatusPill: View {
    @ObservedObject var live = LiveState.shared
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        let status = live.status
        let color: Color = {
            switch status {
            case .ready: return .green
            case .needsAccess: return .orange
            case .noTrackpad: return .red
            case .paused: return .gray
            case .trialEnded: return .orange
            }
        }()
        Button {
            if status == .needsAccess { AppActions.shared.showSetupGuide() }
            if status == .paused { prefs.paused = false }
            if status == .noTrackpad { EdgeEngine.shared.restart() }
            if status == .trialEnded { AppActions.shared.showLicense() }
        } label: {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(status.title)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help(status == .ready ? "Brim is listening to your trackpad" : "Click to fix")
    }
}

struct AppIconView: View {
    var size: CGFloat = 22
    var body: some View {
        Image(nsImage: AppActions.shared.badgeImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.18), radius: size / 14, y: size / 30)
    }
}
