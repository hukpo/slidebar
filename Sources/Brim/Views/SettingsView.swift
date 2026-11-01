import SwiftUI

/// The "set once" options, shown inside the popover.
struct SettingsPage: View {
    @Binding var page: MenuPage
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var licensing = Licensing.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                PlainIconButton(systemName: "chevron.left", help: "Back") { page = .main }
                Text("Settings").font(.system(size: 15, weight: .semibold))
                Spacer()
                AppIconView(size: 20)
            }
            .frame(height: 24)

            SectionHeader(title: "Edge Gestures")
            Card {
                ToggleRow(icon: "arrow.left.arrow.right", color: .indigo, title: "Swap Sides",
                          subtitle: prefs.swapSides ? "Left: Volume · Right: Brightness" : "Left: Brightness · Right: Volume",
                          isOn: $prefs.swapSides)
                RowDivider()
                ToggleRow(icon: "rectangle.bottomthird.inset.filled", color: .purple, title: "Bottom Quarter Only",
                          subtitle: "Only the lower 25% responds", isOn: $prefs.bottomQuarterOnly)
                RowDivider()
                ToggleRow(icon: "option", color: .brown, title: "Require Fn or ⌥",
                          subtitle: "Only slide while holding a modifier", isOn: $prefs.requireModifier)
            }

            SectionHeader(title: "While Sliding")
            Card {
                ToggleRow(icon: "cursorarrow", color: .blue, title: "Freeze Cursor",
                          subtitle: "Pointer stays put while sliding", isOn: $prefs.freezeCursor)
                RowDivider()
                ToggleRow(icon: "plusminus", color: .green, title: "Fine Control",
                          subtitle: "Hold ⇧⌥ for quarter steps", isOn: $prefs.fineControl)
            }

            SectionHeader(title: "General")
            Card {
                HStack(spacing: 10) {
                    FeatureIcon(systemName: "circle.lefthalf.filled", color: Color(white: 0.35))
                    RowLabel(title: "Appearance")
                    Spacer(minLength: 8)
                    PillPicker(options: Appearance.allCases.map { ($0, $0.title) }, selection: $prefs.appearance)
                        .fixedSize()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                RowDivider()
                ToggleRow(icon: "power", color: .mint, title: "Open at Login",
                          isOn: Binding(get: { prefs.openAtLogin }, set: { prefs.setOpenAtLogin($0) }))
                RowDivider()
                ToggleRow(icon: "arrow.down.circle.fill", color: .cyan, title: "Automatic Updates",
                          subtitle: "Download and install new versions", isOn: $prefs.autoUpdate)
            }

            HStack(spacing: 2) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Brim \(AppActions.shared.version)")
                        .font(.system(size: 11, weight: .medium))
                    Text(licenseLine)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 6)
                Spacer()
                MoreMenu()
                PlainIconButton(systemName: "power", help: "Quit Brim") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .onAppear { prefs.refreshOpenAtLogin() }
    }

    private var licenseLine: String {
        switch licensing.state {
        case .free: return "Free edition"
        case .trial(let days): return "Trial · \(days) day\(days == 1 ? "" : "s") left"
        case .licensed(let owner): return "Licensed to \(owner)"
        case .expired: return "Trial ended"
        }
    }
}
