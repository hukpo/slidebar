import BrimCore
import SwiftUI

enum MenuPage {
    case main, settings
}

/// Root view of the menu bar popover.
struct MenuView: View {
    @State private var page: MenuPage = .main

    var body: some View {
        ZStack(alignment: .top) {
            switch page {
            case .main:
                MainPage(page: $page)
                    .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)).combined(with: .opacity))
            case .settings:
                SettingsPage(page: $page)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: page)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .clipped()
    }
}

// MARK: - Main page

struct MainPage: View {
    @Binding var page: MenuPage
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var live = LiveState.shared
    @State private var showMediaOptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                AppIconView(size: 24)
                Text("Brim").font(.system(size: 15, weight: .semibold))
                Spacer()
                StatusPill()
            }
            .padding(.horizontal, 2)

            EdgeMeters()

            if live.status == .needsAccess {
                AccessBanner()
            }
            NoticeBanners()

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        FeatureIcon(systemName: "hand.tap.fill", on: prefs.haptics != .off)
                        RowLabel(title: "Haptic Feedback", subtitle: "A light tick as you slide")
                        Spacer(minLength: 0)
                    }
                    PillPicker(options: HapticStrength.allCases.map { ($0, $0.title) },
                               selection: $prefs.haptics,
                               onChange: { Haptics.tick($0) })
                        .padding(.leading, 36)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)

                RowDivider()

                ToggleRow(icon: "speaker.slash.fill", title: "Quick Mute",
                          subtitle: "Double-tap the top-right corner", isOn: $prefs.quickMute)

                RowDivider()

                HStack(spacing: 10) {
                    FeatureIcon(systemName: "forward.fill", on: prefs.mediaStrip)
                    VStack(alignment: .leading, spacing: 1) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showMediaOptions.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Media Strip").font(.system(size: 13, weight: .medium))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .rotationEffect(.degrees(showMediaOptions ? 180 : 0))
                            }
                        }
                        .buttonStyle(.plain)
                        .help("More media options")
                        Text("Swipe the bottom edge to skip")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    BrimSwitch(isOn: $prefs.mediaStrip)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)

                if showMediaOptions {
                    ToggleRow(icon: nil, title: "Tap to Play or Pause",
                              subtitle: "Clicks near the bottom edge can trigger it", isOn: $prefs.tapToPlay)
                        .disabled(!prefs.mediaStrip)
                        .opacity(prefs.mediaStrip ? 1 : 0.5)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Card {
                SliderRow(icon: "gauge.with.dots.needle.50percent", title: "Sensitivity",
                          valueText: String(format: "%g×", prefs.sensitivity),
                          value: $prefs.sensitivity, range: Prefs.sensitivityRange, step: Prefs.sensitivityStep)
                RowDivider()
                SliderRow(icon: "arrow.left.and.right", title: "Edge Width",
                          valueText: "\(Int((prefs.edgeWidth * 100).rounded()))%",
                          value: $prefs.edgeWidth, range: Prefs.edgeWidthRange, step: Prefs.edgeWidthStep)
            }

            HStack(spacing: 2) {
                PlainIconButton(systemName: "gearshape", title: "Settings", help: "Settings") { page = .settings }
                Spacer()
                MoreMenu()
                PlainIconButton(systemName: "power", help: "Quit Brim") { NSApp.terminate(nil) }
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
        }
        .frame(height: 108)
        .environment(\.colorScheme, .dark)
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
                    .foregroundStyle(.white.opacity(0.6))
                if !leading { Image(systemName: icon).foregroundStyle(tint) }
            }
            .font(.system(size: 10, weight: .semibold))

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                if isVolume && live.muted {
                    Text("Muted")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                } else if let v = value(c) {
                    Text("\(Int((v * 100).rounded()))")
                        .font(.system(size: 34, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white)
                    Text("%")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                } else {
                    Text("—")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .opacity(live.activeControl == nil || active ? 1 : 0.5)
            .animation(.easeOut(duration: 0.15), value: live.activeControl)
        }
    }
}

/// A glowing vertical meter. Drag it to set the level directly.
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
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top))
                    .frame(height: max(geo.size.width, geo.size.height * min(max(level, 0), 1)))
                    .opacity(dimmed ? 0.3 : 1)
                    .shadow(color: colors[1].opacity(dimmed ? 0 : 0.5), radius: active || hovering ? 5 : 2)
            }
            .contentShape(Rectangle().inset(by: -10))
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let v = min(max(Float(1 - g.location.y / geo.size.height), 0), 1)
                    if control == .brightness {
                        SystemControls.setBrightness(v)
                    } else {
                        SystemControls.setVolume(v)
                    }
                    LiveState.shared.refreshLevels()
                }
            )
        }
        .frame(width: active || hovering ? 8 : 6)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: level)
        .animation(.easeOut(duration: 0.15), value: active || hovering)
        .help("Drag to adjust")
        .accessibilityLabel(control == .brightness ? "Brightness" : "Volume")
        .accessibilityValue("\(Int((level * 100).rounded())) percent")
    }
}

// MARK: - Banners

/// Trial, license and update notices.
struct NoticeBanners: View {
    @ObservedObject var licensing = Licensing.shared
    @ObservedObject var updater = Updater.shared

    var body: some View {
        switch licensing.state {
        case .expired:
            Banner(icon: "clock.badge.exclamationmark.fill", tint: .orange,
                   text: "Your trial has ended, so edge gestures are paused.",
                   primary: ("Buy Brim…", { licensing.openCheckout() }),
                   secondary: ("Enter Key…", { AppActions.shared.showLicense() }))
        case .trial(let days) where days <= 3:
            Banner(icon: "clock.fill", tint: .brimAccent,
                   text: "\(days) day\(days == 1 ? "" : "s") left in your trial.",
                   primary: ("Buy Brim…", { licensing.openCheckout() }),
                   secondary: ("Enter Key…", { AppActions.shared.showLicense() }))
        default:
            EmptyView()
        }

        switch updater.phase {
        case .available(let info):
            Banner(icon: "arrow.down.circle.fill", tint: .brimAccent,
                   text: "Brim \(info.version) is available." + (info.notes?.first.map { " \($0)" } ?? ""),
                   primary: ("Install & Relaunch", { Task { await updater.install(info) } }))
        case .downloading, .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(updater.phase == .downloading ? "Downloading update…" : "Installing update…")
                    .font(.system(size: 11.5))
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.brimAccent.opacity(0.11)))
        case .upToDate:
            Banner(icon: "checkmark.circle.fill", tint: .green, text: "Brim \(AppConfig.version) is up to date.")
        case .failed(let message):
            Banner(icon: "exclamationmark.triangle.fill", tint: .orange, text: message)
        default:
            EmptyView()
        }
    }
}

struct AccessBanner: View {
    var body: some View {
        Banner(icon: "lock.shield.fill", tint: .orange,
               text: "Allow Accessibility so Brim can show the system volume and brightness display and control media.",
               primary: ("Allow Access…", {
                   Permissions.requestAccess()
                   Permissions.openAccessibilitySettings()
               }))
    }
}
