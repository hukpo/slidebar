import AppKit
import SwiftUI

// MARK: - Colors

extension Color {
    /// The user's own accent color from System Settings, like any native Mac app.
    static let brimAccent = Color.accentColor
    static let brimAmber = Color(nsColor: Brand.amberBottom)
    static let brimAmberTop = Color(nsColor: Brand.amberTop)
    static let brimCyan = Color(nsColor: Brand.cyanTop)
    static let brimViolet = Color(nsColor: Brand.violetBottom)
    static let brimNightTop = Color(nsColor: Brand.backgroundTop)
    static let brimNightBottom = Color(nsColor: Brand.backgroundBottom)
}

extension LinearGradient {
    static let brimNight = LinearGradient(colors: [.brimNightTop, .brimNightBottom], startPoint: .top, endPoint: .bottom)
}

/// The dark surface used for brand moments (meters card, setup header).
struct NightBackground: View {
    var cornerRadius: CGFloat = 16

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(LinearGradient.brimNight)
            .overlay(
                ZStack {
                    RadialGradient(colors: [Color.brimAmber.opacity(0.16), .clear], center: .leading, startRadius: 0, endRadius: 160)
                    RadialGradient(colors: [Color.brimViolet.opacity(0.24), .clear], center: .trailing, startRadius: 0, endRadius: 160)
                }
                .clipShape(shape)
            )
            .overlay(shape.strokeBorder(Color.white.opacity(0.08)))
    }
}

// MARK: - Grouped cards

/// A rounded group of rows, like System Settings.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
    }
}

struct RowDivider: View {
    var inset: CGFloat = 44
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 1)
            .padding(.leading, inset)
            .padding(.trailing, 8)
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
            .padding(.top, 4)
            .padding(.bottom, -4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Highlights its content softly while the pointer is over it.
struct HoverHighlight: ViewModifier {
    @State private var hovering = false
    var cornerRadius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.06 : 0))
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

extension View {
    func hoverHighlight(cornerRadius: CGFloat = 8) -> some View { modifier(HoverHighlight(cornerRadius: cornerRadius)) }
}

// MARK: - Row parts

/// Quiet monochrome icon on the left of each row. State lives in the control, not the icon.
struct FeatureIcon: View {
    let systemName: String

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            )
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
    }
}

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

/// A row with a native switch. The whole row is the switch's label, so VoiceOver and
/// Full Keyboard Access treat it as one labeled control.
struct ToggleRow: View {
    let icon: String?
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                if let icon {
                    FeatureIcon(systemName: icon)
                } else {
                    Color.clear.frame(width: 26, height: 1)
                }
                RowLabel(title: title, subtitle: subtitle)
                Spacer(minLength: 8)
            }
        }
        .modifier(SwitchStyle())
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }
}

/// True while rendering marketing screenshots offscreen.
private struct SnapshotModeKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var snapshotMode: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }
}

/// The native switch. Offscreen renders can't draw its active (accent) look, so screenshots
/// use a drawn stand-in that matches it.
struct SwitchStyle: ViewModifier {
    @Environment(\.snapshotMode) private var snapshotMode
    func body(content: Content) -> some View {
        if snapshotMode {
            content.toggleStyle(SnapshotSwitchStyle())
        } else {
            content.toggleStyle(.switch)
        }
    }
}

private struct SnapshotSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            configuration.label
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? Color.brimAccent : Color.primary.opacity(0.12))
                Circle().fill(.white).shadow(color: .black.opacity(0.25), radius: 1, y: 0.5).padding(1.5)
            }
            .frame(width: 32, height: 18)
        }
    }
}

/// A row with a native segmented control under its label.
struct ChoiceRow<Value: Hashable>: View {
    let icon: String
    let title: String
    var subtitle: String?
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    var onChange: ((Value) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                FeatureIcon(systemName: icon)
                RowLabel(title: title, subtitle: subtitle)
                Spacer(minLength: 0)
            }
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { i in
                    Text(options[i].title).tag(options[i].value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .padding(.leading, 36)
            .onChange(of: selection) { onChange?($0) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }
}

/// A row with a native slider and plain-language ends ("Narrow … Wide").
struct SliderRow: View {
    let icon: String
    let title: String
    let lowLabel: String
    let highLabel: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueDescription: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                FeatureIcon(systemName: icon)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Text(lowLabel)
                // Continuous slider (no tick marks) that still snaps to whole steps.
                Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range) { Text(title) }
                    .labelsHidden()
                    .controlSize(.small)
                    .accessibilityValue(valueDescription)
                    .onChange(of: value) { _ in
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                Text(highLabel)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.leading, 36)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }
}

/// A row that opens another page.
struct NavigationRow: View {
    let icon: String
    let title: String
    var subtitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                FeatureIcon(systemName: icon)
                RowLabel(title: title, subtitle: subtitle)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight()
    }
}

// MARK: - Buttons

/// Borderless footer / header button with a hover background.
struct PlainIconButton: View {
    let systemName: String
    var title: String?
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemName).font(.system(size: 13, weight: .medium))
                if let title { Text(title).font(.system(size: 12, weight: .medium)) }
            }
            .padding(.horizontal, title == nil ? 0 : 8)
            .frame(minWidth: 28, minHeight: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .hoverHighlight(cornerRadius: 7)
        .help(help)
        .accessibilityLabel(title ?? help)
    }
}

/// The "…" menu shared by every page.
struct MoreMenu: View {
    @ObservedObject var updater = Updater.shared

    var body: some View {
        Menu {
            Button("Setup Guide…") { AppActions.shared.showSetupGuide() }
            Button("Accessibility Settings…") { Permissions.openAccessibilitySettings() }
            Button("Find Trackpads Again") { EdgeEngine.shared.restart() }
            Divider()
            if let update = updater.available {
                Button("Install Brim \(update.version)…") { Task { await updater.install(update) } }
            } else if updater.isConfigured {
                Button("Check for Updates…") { AppActions.shared.checkForUpdates() }
            }
            if AppConfig.sourceURL != nil {
                Button("View Source Code…") { AppActions.shared.openSource() }
            }
            Button("About Brim") { AppActions.shared.showAbout() }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 28, height: 26)
        .hoverHighlight(cornerRadius: 7)
        .help("More")
        .accessibilityLabel("More")
    }
}

/// Footer shared by every page: a leading view, then More and Quit, kept apart.
struct MenuFooter<Leading: View>: View {
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: 6) {
            leading
            Spacer()
            MoreMenu()
            PlainIconButton(systemName: "power", title: "Quit", help: "Quit Brim (⌘Q)") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
    }
}

// MARK: - Status

/// Read-only status. Anything that needs action appears as a notice with a button instead.
struct StatusPill: View {
    @ObservedObject var live = LiveState.shared
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        let status = live.status
        HStack(spacing: 5) {
            Circle()
                .fill(dotColor(status))
                .frame(width: 6, height: 6)
            Text(status.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(status.title)")
    }

    private func dotColor(_ status: LiveState.Status) -> Color {
        switch status {
        case .ready: return .green
        case .noTrackpad: return .orange
        case .paused: return .gray
        }
    }
}

struct AppIconView: View {
    var size: CGFloat = 22
    var body: some View {
        Image(nsImage: AppActions.shared.badgeImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: size / 12, y: size / 28)
            .accessibilityHidden(true)
    }
}

/// A tinted notice with an optional button and an optional close button.
struct Banner: View {
    let icon: String
    var tint: Color = .brimAccent
    let text: String
    var primary: (String, () -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(text)
                    .font(.system(size: 11.5))
                    .fixedSize(horizontal: false, vertical: true)
                if let primary {
                    Button(primary.0, action: primary.1)
                        .controlSize(.small)
                }
            }
            Spacer(minLength: 0)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Dismiss")
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(tint.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(tint.opacity(0.12)))
        .accessibilityElement(children: .contain)
    }
}
