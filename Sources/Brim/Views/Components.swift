import AppKit
import SwiftUI

// MARK: - Colors

extension Color {
    static let brimAccent = Color(nsColor: Brand.accent)
    static let brimAmber = Color(nsColor: Brand.amberBottom)
    static let brimAmberTop = Color(nsColor: Brand.amberTop)
    static let brimCyan = Color(nsColor: Brand.cyanTop)
    static let brimViolet = Color(nsColor: Brand.violetBottom)
    static let brimNightTop = Color(nsColor: Brand.backgroundTop)
    static let brimNightBottom = Color(nsColor: Brand.backgroundBottom)
}

extension LinearGradient {
    static let brimAccent = LinearGradient(colors: [Color(red: 0.16, green: 0.74, blue: 0.92), .brimAccent],
                                           startPoint: .top, endPoint: .bottom)
    static let brimNight = LinearGradient(colors: [.brimNightTop, .brimNightBottom], startPoint: .top, endPoint: .bottom)
}

/// The dark, glowing surface used for brand moments (meters card, window headers).
struct NightBackground: View {
    var cornerRadius: CGFloat = 16

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(LinearGradient.brimNight)
            .overlay(
                ZStack {
                    RadialGradient(colors: [Color.brimAmber.opacity(0.32), .clear], center: .leading, startRadius: 0, endRadius: 190)
                    RadialGradient(colors: [Color.brimViolet.opacity(0.42), .clear], center: .trailing, startRadius: 0, endRadius: 190)
                }
                .clipShape(shape)
            )
            .overlay(
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom))
            )
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
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 1)
            .padding(.leading, 44)
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
            .padding(.bottom, -4)
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

/// Colored rounded-square icon on the left of each row. Dims when the feature is off.
struct FeatureIcon: View {
    let systemName: String
    let color: Color
    var on = true

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .top, endPoint: .bottom))
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.14)))
            .frame(width: 26, height: 26)
            .saturation(on ? 1 : 0.1)
            .opacity(on ? 1 : 0.55)
            .animation(.easeOut(duration: 0.15), value: on)
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

struct ToggleRow: View {
    let icon: String?
    var color: Color = .brimAccent
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                FeatureIcon(systemName: icon, color: color, on: isOn)
            } else {
                Color.clear.frame(width: 26, height: 1)
            }
            RowLabel(title: title, subtitle: subtitle)
            Spacer(minLength: 8)
            BrimSwitch(isOn: $isOn)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
        .hoverHighlight()
        .accessibilityElement(children: .combine)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Controls

/// A switch in Brim's accent color, drawn in SwiftUI so it looks the same in any window state.
struct BrimSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? AnyShapeStyle(LinearGradient.brimAccent) : AnyShapeStyle(Color.primary.opacity(0.14)))
            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                .padding(2)
        }
        .frame(width: 34, height: 20)
        .opacity(isEnabled ? 1 : 0.5)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isOn)
        .contentShape(Capsule())
        .onTapGesture { if isEnabled { isOn.toggle() } }
    }
}

/// A pill-shaped segmented control with a sliding selection.
struct PillPicker<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    var onChange: ((Value) -> Void)?
    @Namespace private var ns
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let selected = option.value == selection
                Text(option.title)
                    .font(.system(size: 11, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background {
                        if selected {
                            Capsule()
                                .fill(scheme == .dark ? Color.white.opacity(0.2) : Color.white)
                                .shadow(color: .black.opacity(0.16), radius: 1.5, y: 0.5)
                                .matchedGeometryEffect(id: "selection", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        guard option.value != selection else { return }
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { selection = option.value }
                        onChange?(option.value)
                    }
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }
}

/// A stepped slider with an accent fill, step dots and a soft knob.
struct BrimSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    private let knob: CGFloat = 16
    private var steps: Int { max(1, Int(((range.upperBound - range.lowerBound) / step).rounded())) }
    private var fraction: CGFloat {
        min(max(CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)), 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let usable = geo.size.width - knob
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(height: 6)
                Capsule()
                    .fill(LinearGradient.brimAccent)
                    .frame(width: knob / 2 + fraction * usable + 3, height: 6)
                HStack(spacing: 0) {
                    ForEach(0...steps, id: \.self) { i in
                        Circle()
                            .fill(CGFloat(i) / CGFloat(steps) <= fraction + 0.001 ? Color.white.opacity(0.75) : Color.primary.opacity(0.25))
                            .frame(width: 2.5, height: 2.5)
                        if i < steps { Spacer(minLength: 0) }
                    }
                }
                .padding(.horizontal, knob / 2 - 1.25)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.08)))
                    .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
                    .frame(width: knob, height: knob)
                    .offset(x: fraction * usable)
            }
            .frame(height: knob)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let f = min(max((g.location.x - knob / 2) / usable, 0), 1)
                    let raw = range.lowerBound + Double(f) * (range.upperBound - range.lowerBound)
                    let snapped = min(max((raw / step).rounded() * step, range.lowerBound), range.upperBound)
                    if abs(snapped - value) > step / 10 {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) { value = snapped }
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                }
            )
        }
        .frame(height: 16)
        .accessibilityRepresentation {
            Slider(value: $value, in: range, step: step)
        }
    }
}

struct SliderRow: View {
    let icon: String
    var color: Color = .brimAccent
    let title: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            FeatureIcon(systemName: icon, color: color)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(valueText)
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(LinearGradient.brimAccent))
                }
                BrimSlider(value: $value, range: range, step: step)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
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
                .font(.system(size: 13, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 28, height: 26)
        .hoverHighlight(cornerRadius: 7)
        .help("More")
    }
}

// MARK: - Status

struct StatusPill: View {
    @ObservedObject var live = LiveState.shared
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var licensing = Licensing.shared

    var body: some View {
        let status = live.status
        let color: Color = {
            switch status {
            case .ready: return .green
            case .needsAccess, .trialEnded: return .orange
            case .noTrackpad: return .red
            case .paused: return .gray
            }
        }()
        Button {
            switch status {
            case .needsAccess: AppActions.shared.showSetupGuide()
            case .paused: prefs.paused = false
            case .noTrackpad: EdgeEngine.shared.restart()
            case .trialEnded: AppActions.shared.showLicense()
            case .ready: break
            }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .shadow(color: color.opacity(0.9), radius: status == .ready ? 3 : 0)
                Text(status.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color == .gray ? Color.secondary : color)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.13)))
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
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: size / 12, y: size / 28)
    }
}

/// A tinted notice with optional buttons.
struct Banner: View {
    let icon: String
    let tint: Color
    let text: String
    var primary: (String, () -> Void)?
    var secondary: (String, () -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 7) {
                Text(text)
                    .font(.system(size: 11.5))
                    .fixedSize(horizontal: false, vertical: true)
                if primary != nil || secondary != nil {
                    HStack(spacing: 6) {
                        if let primary {
                            Button(primary.0, action: primary.1)
                                .buttonStyle(.borderedProminent)
                                .tint(tint)
                                .controlSize(.small)
                        }
                        if let secondary {
                            Button(secondary.0, action: secondary.1)
                                .controlSize(.small)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(tint.opacity(0.11)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(tint.opacity(0.2)))
    }
}
