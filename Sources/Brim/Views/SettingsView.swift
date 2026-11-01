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
            }
            .frame(height: 24)

            SectionHeader(title: "Edge Gestures")
            Card {
                ToggleRow(icon: "arrow.left.arrow.right", title: "Swap Sides",
                          subtitle: prefs.swapSides ? "Left: Volume · Right: Brightness" : "Left: Brightness · Right: Volume",
                          isOn: $prefs.swapSides)
                RowDivider()
                ToggleRow(icon: "rectangle.bottomthird.inset.filled", title: "Bottom Quarter Only",
                          subtitle: "Only the lower 25% responds", isOn: $prefs.bottomQuarterOnly)
                RowDivider()
                ToggleRow(icon: "option", title: "Require Fn or ⌥",
                          subtitle: "Only slide while holding a modifier", isOn: $prefs.requireModifier)
                RowDivider()
                ToggleRow(icon: "hand.raised", title: "Palm Rejection",
                          subtitle: "Ignore a palm resting on an edge", isOn: $prefs.palmRejection)
            }

            SectionHeader(title: "While Sliding")
            Card {
                ToggleRow(icon: "cursorarrow", title: "Freeze Cursor",
                          subtitle: "Pointer stays put while sliding", isOn: $prefs.freezeCursor)
                RowDivider()
                ToggleRow(icon: "plusminus", title: "Fine Control",
                          subtitle: "Hold ⇧⌥ for quarter steps", isOn: $prefs.fineControl)
                RowDivider()
                ToggleRow(icon: "rectangle.righthalf.inset.filled", title: "Edge Glow",
                          subtitle: "A level bar on the screen edge", isOn: $prefs.edgeGlow)
            }

            SectionHeader(title: "Apps")
            Card {
                Button { page = .apps } label: {
                    HStack(spacing: 10) {
                        FeatureIcon(systemName: "app.badge.checkmark", on: !prefs.excludedApps.isEmpty)
                        RowLabel(title: "Turned Off In",
                                 subtitle: prefs.excludedApps.isEmpty ? "Works in every app" : "\(prefs.excludedApps.count) app\(prefs.excludedApps.count == 1 ? "" : "s")")
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight()
            }

            SectionHeader(title: "General")
            Card {
                HStack(spacing: 10) {
                    FeatureIcon(systemName: "circle.lefthalf.filled", on: false)
                    RowLabel(title: "Appearance")
                    Spacer(minLength: 8)
                    PillPicker(options: Appearance.allCases.map { ($0, $0.title) }, selection: $prefs.appearance)
                        .fixedSize()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                RowDivider()
                ToggleRow(icon: "power", title: "Open at Login",
                          isOn: Binding(get: { prefs.openAtLogin }, set: { prefs.setOpenAtLogin($0) }))
                RowDivider()
                ToggleRow(icon: "arrow.down.circle.fill", title: "Automatic Updates",
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

// MARK: - Apps where Brim is off

/// Lists the apps where edge gestures are turned off.
struct AppsPage: View {
    @Binding var page: MenuPage
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var live = LiveState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                PlainIconButton(systemName: "chevron.left", help: "Back") { page = .settings }
                Text("Turned Off In").font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .frame(height: 24)

            Text("Edge gestures do nothing while one of these apps is in front. Handy for games, design tools and music apps.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)

            Card {
                if prefs.excludedApps.isEmpty {
                    Text("No apps yet")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else {
                    ForEach(Array(prefs.excludedApps.enumerated()), id: \.element) { index, id in
                        if index > 0 { RowDivider() }
                        AppRow(bundleID: id) { prefs.excludedApps.removeAll { $0 == id } }
                    }
                }
            }

            HStack(spacing: 8) {
                if let app = live.lastApp, let id = app.bundleIdentifier, !prefs.excludedApps.contains(id) {
                    Button("Add \(app.localizedName ?? "Current App")") { prefs.excludedApps.append(id) }
                        .controlSize(.small)
                }
                Spacer()
                Button("Choose App…") { chooseApp() }
                    .controlSize(.small)
            }
            .padding(.horizontal, 2)
        }
        .padding(14)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "Turn Off Brim in an App"
        panel.prompt = "Turn Off"
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
            Text(name).font(.system(size: 13, weight: .medium))
            Spacer()
            PlainIconButton(systemName: "minus.circle", help: "Turn Brim back on in \(name)", action: onRemove)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}
