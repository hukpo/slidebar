import SwiftUI

/// The set-once options, inside the popover. Everyday options first, expert ones folded away,
/// and scrollable so it never runs off a small screen.
struct SettingsPage: View {
    @Binding var page: MenuPage
    @ObservedObject var prefs = Prefs.shared
    @State private var showAdvanced = false
    @State private var confirmRestore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PageHeader(title: "Settings") { page = .main }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    Card {
                        NavigationRow(icon: "rectangle.and.hand.point.up.left", title: "Edges and Corners",
                                      subtitle: GestureSummary.text(prefs)) {
                            page = .gestures(back: .settings)
                        }
                    }

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

                    SectionHeader(title: "Apps")
                    Card {
                        NavigationRow(icon: "app.dashed", title: "Apps Where Brim Is Off",
                                      subtitle: prefs.excludedApps.isEmpty
                                        ? "Brim works in every app"
                                        : "\(prefs.excludedApps.count) app\(prefs.excludedApps.count == 1 ? "" : "s")") {
                            page = .apps
                        }
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
                                      subtitle: "The top of the left and right edges is ignored", isOn: $prefs.bottomQuarterOnly)
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
                    .padding(.leading, 6)
                    .padding(.top, 4)
                }
                .padding(.bottom, 4)
            }
            .frame(height: 470)

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

// MARK: - Apps where Brim is off

/// Lists the apps where edge gestures are turned off.
struct AppsPage: View {
    @Binding var page: MenuPage
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var live = LiveState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: "Apps Where Brim Is Off") { page = .settings }

            Text("Edges and corners do nothing while one of these apps is in front. Handy for games, drawing apps and music software.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)

            Card {
                if prefs.excludedApps.isEmpty {
                    VStack(spacing: 10) {
                        Text("No apps yet")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        if let app = live.lastApp, let id = app.bundleIdentifier, let name = app.localizedName {
                            Button("Add \(name)") { prefs.excludedApps.append(id) }
                                .controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    ForEach(Array(prefs.excludedApps.enumerated()), id: \.element) { index, id in
                        if index > 0 { RowDivider(inset: 42) }
                        AppRow(bundleID: id) { prefs.excludedApps.removeAll { $0 == id } }
                    }
                }
            }

            HStack(spacing: 8) {
                if !prefs.excludedApps.isEmpty, let app = live.lastApp, let id = app.bundleIdentifier,
                   let name = app.localizedName, !prefs.excludedApps.contains(id) {
                    Button("Add \(name)") { prefs.excludedApps.append(id) }
                        .controlSize(.small)
                }
                Spacer()
                Button("Choose an App…") { chooseApp() }
                    .controlSize(.small)
            }
            .padding(.horizontal, 2)
        }
        .padding(14)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose Apps Where Brim Is Off"
        panel.prompt = "Turn Off Brim"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !prefs.excludedApps.contains(id) {
                prefs.excludedApps.append(id)
            }
        }
    }
}

private struct AppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        let name = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID
        HStack(spacing: 10) {
            Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!)
                .resizable()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            Text(name).font(.system(size: 13, weight: .medium))
            Spacer()
            Button("Remove", action: onRemove)
                .controlSize(.small)
                .help("Turn Brim back on in \(name)")
                .accessibilityLabel("Turn Brim back on in \(name)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}
