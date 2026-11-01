import SwiftUI

/// The "set once" options, shown inside the popover.
struct SettingsPage: View {
    @Binding var page: MenuPage
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                AppIconView()
                Text("Settings").font(.system(size: 15, weight: .semibold))
                Spacer()
            }

            SectionHeader(title: "Edge Gestures")
            ToggleRow(icon: "arrow.left.arrow.right", title: "Swap Sides",
                      subtitle: prefs.swapSides ? "Left: Volume · Right: Brightness" : "Left: Brightness · Right: Volume",
                      isOn: $prefs.swapSides)
            ToggleRow(icon: "rectangle.bottomthird.inset.filled", title: "Bottom Quarter Only",
                      subtitle: "Ignore touches above the lower 25%", isOn: $prefs.bottomQuarterOnly)
            ToggleRow(icon: "option", title: "Require Fn or ⌥",
                      subtitle: "Only slide while holding a modifier", isOn: $prefs.requireModifier)

            Divider()

            SectionHeader(title: "While Sliding")
            ToggleRow(icon: "cursorarrow", title: "Freeze Cursor",
                      subtitle: "Pointer stays put while sliding", isOn: $prefs.freezeCursor)
            ToggleRow(icon: "plusminus", title: "Fine Control",
                      subtitle: "Hold ⇧⌥ for quarter steps", isOn: $prefs.fineControl)

            Divider()

            SectionHeader(title: "General")
            HStack(spacing: 11) {
                IconBadge(systemName: "circle.lefthalf.filled")
                RowLabel(title: "Appearance")
                Spacer()
                Picker("", selection: $prefs.appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .fixedSize()
            }
            ToggleRow(icon: "power", title: "Open at Login", subtitle: nil,
                      isOn: Binding(get: { prefs.openAtLogin }, set: { prefs.setOpenAtLogin($0) }))

            Divider()

            HStack(spacing: 4) {
                Button {
                    page = .main
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                Text("Version \(AppActions.shared.version)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                Spacer()
                MoreMenu()
                FooterIconButton(systemName: "power", help: "Quit Brim") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .onAppear { prefs.refreshOpenAtLogin() }
    }
}
