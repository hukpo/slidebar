import SwiftUI

/// The set-once options, inside the popover. Everyday options first, expert ones folded away,
/// and scrollable so it never runs off a small screen.
struct SettingsPage: View {
    @Binding var page: MenuPage
    @ObservedObject var prefs = Prefs.shared
    @State private var showAdvanced: Bool
    @State private var confirmRestore = false
    @Environment(\.snapshotMode) private var snapshotMode

    init(page: Binding<MenuPage>, showAdvanced: Bool = false) {
        _page = page
        _showAdvanced = State(initialValue: showAdvanced)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PageHeader(title: "Settings") { page = .main }

            ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
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
                        ToggleRow(icon: "cursorarrow", title: "Keep Pointer Still",
                                  subtitle: "The pointer stays put while you slide", isOn: $prefs.freezeCursor)
                        RowDivider()
                        ToggleRow(icon: "rectangle.righthalf.inset.filled", title: "Edge Glow",
                                  subtitle: "A level bar on the edge of your screen", isOn: $prefs.edgeGlow)
                    }

                    SectionHeader(title: "General")
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

                    DisclosureGroup(isExpanded: $showAdvanced) {
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
                            RowDivider()
                            HStack(spacing: 10) {
                                FeatureIcon(systemName: "arrow.counterclockwise")
                                RowLabel(title: "Restore Defaults",
                                         subtitle: confirmRestore ? "All gestures and options go back to how Brim starts." : "Your app list stays as it is")
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
                        .padding(.top, 8)
                    } label: {
                        Text("Advanced")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .disclosureGroupStyle(FlushDisclosureStyle())
                    .padding(.top, 4)
                    .id("advanced")
                }
                .padding(.bottom, 4)
            }
            // Screenshots of the expanded page show everything; the real popover scrolls.
            .frame(height: snapshotMode && showAdvanced ? 1060 : 470)
            // Bring the newly opened Advanced options into view.
            .onChange(of: showAdvanced) { expanded in
                guard expanded else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("advanced", anchor: .top) }
                }
            }
            }

            MenuFooter {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Brim \(AppActions.shared.version)")
                        .font(.system(size: 11, weight: .medium))
                    Text("Free and open source")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 6)
            }
        }
        .padding(14)
        .onAppear { prefs.refreshOpenAtLogin() }
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

struct FlushDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { configuration.isExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    configuration.label
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                }
                .padding(.leading, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows more options")
            if configuration.isExpanded {
                configuration.content
                    .transition(.opacity)
            }
        }
    }
}
