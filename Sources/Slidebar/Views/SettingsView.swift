import SwiftUI

/// The options under the trackpad on the home screen: how sliding feels, then the app itself.
struct SettingsSections: View {
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Feel")
            Card {
                SliderRow(icon: "speedometer", title: "Slide Speed",
                          lowLabel: "Slower", highLabel: "Faster",
                          value: $prefs.sensitivity, range: Prefs.sensitivityRange, step: Prefs.sensitivityStep,
                          valueDescription: String(format: "%g times", prefs.sensitivity))
                RowDivider()
                SliderRow(icon: "arrow.left.and.right", title: "Edge Width",
                          lowLabel: "Narrow", highLabel: "Wide",
                          value: $prefs.edgeWidth, range: Prefs.edgeWidthRange, step: Prefs.edgeWidthStep,
                          valueDescription: "\(Int((prefs.edgeWidth * 100).rounded())) percent of the trackpad")
                RowDivider()
                HapticsRow()
                RowDivider()
                ToggleRow(icon: "cursorarrow", title: "Keep Pointer Still",
                          subtitle: "The pointer stays put while you slide", isOn: $prefs.freezeCursor)
                RowDivider()
                ToggleRow(icon: "rectangle.righthalf.inset.filled", title: "Edge Glow",
                          subtitle: "A level bar on the edge of your screen", isOn: $prefs.edgeGlow)
            }

            SectionHeader(title: "General").padding(.top, 4)
            Card {
                HStack(spacing: 10) {
                    FeatureIcon(systemName: "circle.lefthalf.filled")
                    RowLabel(title: "Appearance")
                    Spacer(minLength: 8)
                    Picker("Appearance", selection: $prefs.appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                RowDivider()
                ToggleRow(icon: "arrow.up.forward.app", title: "Open at Login",
                          isOn: Binding(get: { prefs.openAtLogin }, set: { prefs.setOpenAtLogin($0) }))
                if Updater.shared.isConfigured {
                    RowDivider()
                    ToggleRow(icon: "arrow.triangle.2.circlepath", title: "Install Updates Automatically",
                              subtitle: "New versions install themselves", isOn: $prefs.autoUpdate)
                }
            }
        }
        .onAppear { prefs.refreshOpenAtLogin() }
    }
}

/// Haptic strength: a tick under your finger at each step.
struct HapticsRow: View {
    @ObservedObject var prefs = Prefs.shared

    var body: some View {
        HStack(spacing: 10) {
            FeatureIcon(systemName: "hand.tap")
            RowLabel(title: "Haptic Feedback")
            Spacer(minLength: 8)
            Menu {
                Picker("Haptic Feedback", selection: $prefs.haptics) {
                    ForEach(HapticStrength.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text(prefs.haptics.title)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Haptic Feedback")
            .accessibilityValue(prefs.haptics.title)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .help("A tick under your finger at each step")
        .onChange(of: prefs.haptics) { Haptics.tick($0) }
    }
}

/// The few options most people never touch.
struct AdvancedPage: View {
    @Binding var page: MenuPage
    @ObservedObject var prefs = Prefs.shared
    @State private var confirmRestore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: "Advanced") { page = .main }

            Card {
                ToggleRow(icon: "rectangle.bottomthird.inset.filled", title: "Ignore the Top of the Side Edges",
                          subtitle: "Only the lower part of the left and right edges responds", isOn: $prefs.bottomQuarterOnly)
                RowDivider()
                ToggleRow(icon: "hand.raised", title: "Palm Rejection",
                          subtitle: "Ignore a hand resting on an edge", isOn: $prefs.palmRejection)
                RowDivider()
                ToggleRow(icon: "option", title: "Only While Holding Fn or Option",
                          subtitle: "Edges respond only while a key is held", isOn: $prefs.requireModifier)
                RowDivider()
                ToggleRow(icon: "plusminus", title: "Smaller Steps with Shift-Option",
                          subtitle: "Hold Shift and Option for finer changes", isOn: $prefs.fineControl)
            }

            Card {
                HStack(spacing: 10) {
                    FeatureIcon(systemName: "arrow.counterclockwise")
                    RowLabel(title: "Restore Defaults",
                             subtitle: confirmRestore ? "Every edge, corner and option goes back to how Slidebar starts." : "Edges, corners and options")
                    Spacer(minLength: 8)
                    if confirmRestore {
                        Button("Cancel") { confirmRestore = false }.controlSize(.small)
                        Button("Restore") { prefs.restoreDefaults(); confirmRestore = false }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Restore…") { confirmRestore = true }.controlSize(.small)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
            }

            MenuFooter {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Slidebar \(AppActions.shared.version)")
                        .font(.system(size: 11, weight: .medium))
                    SourceLink()
                }
                .padding(.leading, 6)
            }
        }
        .padding(14)
    }
}

/// Back button and title. Escape also goes back.
struct PageHeader: View {
    let title: String
    let back: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            PlainIconButton(systemName: "chevron.left", help: "Back") { back() }
                .keyboardShortcut(.cancelAction)
            Text(title).font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
        .frame(height: 24)
    }
}

/// "Free and open source", linking to the code on GitHub.
struct SourceLink: View {
    @State private var hovering = false

    var body: some View {
        if let url = AppConfig.sourceURL {
            Link(destination: url) {
                HStack(spacing: 3) {
                    Text("Free and open source")
                        .underline(hovering)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .onHover { hovering = $0 }
            .help("View Slidebar on GitHub")
            .accessibilityLabel("Free and open source. View Slidebar on GitHub")
        } else {
            Text("Free and open source")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
