import BrimCore
import SwiftUI

enum MenuPage {
    case main, settings, apps
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
            case .settings:
                SettingsPage(page: $page)
                    .transition(transition(from: .trailing))
            case .apps:
                AppsPage(page: $page)
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

/// The everyday surface: live levels, an on/off switch, the current app, and haptics.
/// Set-once options live on the Settings page.
struct MainPage: View {
    @Binding var page: MenuPage
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var live = LiveState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                AppIconView(size: 22)
                Text("Brim").font(.system(size: 15, weight: .semibold))
                Spacer()
                StatusPill()
            }
            .padding(.horizontal, 2)

            EdgeMeters()

            if live.showWelcome {
                Banner(icon: "menubar.arrow.up.rectangle",
                       text: "Brim lives here in the menu bar. Click its icon any time to see your levels or change settings.",
                       onDismiss: { live.showWelcome = false })
            } else if live.status == .needsAccess {
                AccessBanner()
            }
            UpdateBanner()

            Card {
                ToggleRow(icon: "hand.draw", title: "Edge Sliders",
                          subtitle: prefs.paused ? "Paused. Your trackpad works as usual." : "Slide the edges of your trackpad",
                          isOn: Binding(get: { !prefs.paused }, set: { prefs.paused = !$0 }))

                if let app = live.lastApp, let id = app.bundleIdentifier, let name = app.localizedName {
                    RowDivider()
                    ToggleRow(icon: "app.dashed", title: "Off in \(name)",
                              subtitle: "Pause Brim only while \(name) is in front",
                              isOn: Binding(
                                get: { prefs.excludedApps.contains(id) },
                                set: { off in
                                    if off { if !prefs.excludedApps.contains(id) { prefs.excludedApps.append(id) } }
                                    else { prefs.excludedApps.removeAll { $0 == id } }
                                }))
                        .disabled(prefs.paused)
                }

                RowDivider()

                ChoiceRow(icon: "hand.tap", title: "Haptic Feedback",
                          subtitle: "A tick under your finger at each step",
                          options: HapticStrength.allCases.map { ($0, $0.title) },
                          selection: $prefs.haptics,
                          onChange: { Haptics.tick($0) })
            }

            MenuFooter {
                PlainIconButton(systemName: "gearshape", title: "Settings", help: "Settings (⌘,)") { page = .settings }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
        .padding(14)
    }
}

// MARK: - Edge meters

/// The brand card: a little trackpad showing live brightness and volume on the edges that control them.
struct EdgeMeters: View {
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var live = LiveState.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            NightBackground(cornerRadius: 16)

            HStack(spacing: 12) {
                if prefs.swapSides {
                    meter(.volume)
                    readout(.volume, leading: true)
                    Spacer(minLength: 0)
                    readout(.brightness, leading: false)
                    meter(.brightness)
                } else {
                    meter(.brightness)
                    readout(.brightness, leading: true)
                    Spacer(minLength: 0)
                    readout(.volume, leading: false)
                    meter(.volume)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .frame(maxHeight: .infinity)

            // The media strip, lit when it's on.
            Capsule()
                .fill(Color.white.opacity(prefs.mediaStrip ? 0.25 : 0.08))
                .frame(width: 44, height: 3)
                .padding(.bottom, 7)
                .accessibilityHidden(true)
        }
        .frame(height: 108)
        .environment(\.colorScheme, .dark)
        .opacity(prefs.paused ? 0.6 : 1)
        .animation(.easeOut(duration: 0.2), value: prefs.paused)
    }

    private func value(_ c: EdgeControl) -> Float? {
        c == .brightness ? live.brightness : live.volume
    }

    private func meter(_ c: EdgeControl) -> some View {
        LevelBar(control: c,
                 level: CGFloat(value(c) ?? 0),
                 active: live.activeControl == c,
                 dimmed: c == .volume && live.muted)
    }

    @ViewBuilder
    private func readout(_ c: EdgeControl, leading: Bool) -> some View {
        let isVolume = c == .volume
        let active = live.activeControl == c
        let icon = isVolume ? (live.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") : "sun.max.fill"
        let tint: Color = isVolume ? .brimCyan : .brimAmberTop

        VStack(alignment: leading ? .leading : .trailing, spacing: 3) {
            HStack(spacing: 5) {
                if leading { Image(systemName: icon).foregroundStyle(tint) }
                Text(isVolume ? "Volume" : "Brightness")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                if !leading { Image(systemName: icon).foregroundStyle(tint) }
            }
            .font(.system(size: 10, weight: .semibold))

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                if isVolume && live.muted {
                    Text("Muted")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                } else if let v = value(c) {
                    Text("\(Int((v * 100).rounded()))")
                        .font(.system(size: 34, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white)
                    Text("%")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                } else {
                    Text("—")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .opacity(live.activeControl == nil || active ? 1 : 0.5)
            .animation(.easeOut(duration: 0.15), value: live.activeControl)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isVolume ? "Volume" : "Brightness")
        .accessibilityValue(isVolume && live.muted ? "Muted" : value(c).map { "\(Int(($0 * 100).rounded())) percent" } ?? "Unavailable")
    }
}

/// A glowing vertical meter. Drag it to set the level; VoiceOver can adjust it too.
struct LevelBar: View {
    let control: EdgeControl
    let level: CGFloat
    let active: Bool
    let dimmed: Bool
    @State private var hovering = false

    var body: some View {
        let colors: [Color] = control == .brightness ? [.brimAmber, .brimAmberTop] : [.brimViolet, .brimCyan]
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top))
                    .frame(height: max(geo.size.width, geo.size.height * min(max(level, 0), 1)))
                    .opacity(dimmed ? 0.3 : 1)
                    .shadow(color: colors[1].opacity(dimmed ? 0 : 0.5), radius: active || hovering ? 5 : 2)
            }
            .contentShape(Rectangle().inset(by: -10))
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    set(Float(1 - g.location.y / geo.size.height))
                }
            )
        }
        .frame(width: active || hovering ? 8 : 6)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: level)
        .animation(.easeOut(duration: 0.15), value: active || hovering)
        .help("Drag to adjust")
        .accessibilityElement()
        .accessibilityLabel(control == .brightness ? "Brightness" : "Volume")
        .accessibilityValue("\(Int((level * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(Float(level) + 1 / 16)
            case .decrement: set(Float(level) - 1 / 16)
            @unknown default: break
            }
        }
    }

    private func set(_ value: Float) {
        let v = min(max(value, 0), 1)
        if control == .brightness {
            SystemControls.setBrightness(v)
        } else {
            SystemControls.setVolume(v)
        }
        LiveState.shared.refreshLevels()
    }
}

// MARK: - Banners

/// Update notices. Every notice can be dismissed.
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

/// Shown while Accessibility is off. Brim works without it, so this informs rather than alarms.
struct AccessBanner: View {
    var body: some View {
        Banner(icon: "lock.open",
               text: "Volume and brightness already work. Allow Accessibility to also see the usual on-screen display and use the media gestures.",
               primary: ("Allow…", { Permissions.ask() }))
    }
}
