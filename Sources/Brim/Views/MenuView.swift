import BrimCore
import SwiftUI

enum MenuPage {
    case main, settings
}

/// Root view of the menu bar popover.
struct MenuView: View {
    @State private var page: MenuPage = .main

    var body: some View {
        Group {
            switch page {
            case .main: MainPage(page: $page)
            case .settings: SettingsPage(page: $page)
            }
        }
        .frame(width: 330)
        .fixedSize(horizontal: false, vertical: true)
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
                AppIconView()
                Text("Brim").font(.system(size: 15, weight: .semibold))
                Spacer()
                StatusPill()
            }

            LevelsCard()

            if live.status == .needsAccess {
                AccessBanner()
            }
            NoticeBanners()

            VStack(spacing: 10) {
                HStack(spacing: 11) {
                    IconBadge(systemName: "hand.tap.fill", active: prefs.haptics != .off)
                    RowLabel(title: "Haptic Feedback", subtitle: "A light tick as you slide")
                    Spacer(minLength: 8)
                    Picker("", selection: $prefs.haptics) {
                        ForEach(HapticStrength.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .fixedSize()
                    .onChange(of: prefs.haptics) { Haptics.tick($0) }
                }

                ToggleRow(icon: "speaker.slash.fill", title: "Quick Mute",
                          subtitle: "Double-tap the top-right corner", isOn: $prefs.quickMute)

                HStack(spacing: 11) {
                    IconBadge(systemName: "forward.fill", active: prefs.mediaStrip)
                    VStack(alignment: .leading, spacing: 1) {
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) { showMediaOptions.toggle() }
                        } label: {
                            HStack(spacing: 3) {
                                Text("Media Strip").font(.system(size: 13, weight: .medium))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                                    .rotationEffect(.degrees(showMediaOptions ? 180 : 0))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        Text("Swipe the bottom edge to skip")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    BrimSwitch(isOn: $prefs.mediaStrip)
                }

                if showMediaOptions {
                    ToggleRow(icon: nil, title: "Tap to Play or Pause",
                              subtitle: "Clicks near the bottom edge can trigger it", isOn: $prefs.tapToPlay)
                        .disabled(!prefs.mediaStrip)
                        .opacity(prefs.mediaStrip ? 1 : 0.5)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Divider()

            VStack(spacing: 12) {
                SliderRow(icon: "gauge.with.dots.needle.50percent", title: "Sensitivity",
                          valueText: String(format: "%g×", prefs.sensitivity),
                          value: $prefs.sensitivity, range: Prefs.sensitivityRange, step: Prefs.sensitivityStep)
                SliderRow(icon: "arrow.left.and.right", title: "Edge Width",
                          valueText: "\(Int((prefs.edgeWidth * 100).rounded()))%",
                          value: $prefs.edgeWidth, range: Prefs.edgeWidthRange, step: Prefs.edgeWidthStep)
            }

            Divider()

            HStack(spacing: 4) {
                Button {
                    page = .settings
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                Spacer()
                MoreMenu()
                FooterIconButton(systemName: "power", help: "Quit Brim") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
    }
}

// MARK: - Levels card

/// Live brightness and volume, each drawn on the side of the trackpad that controls it.
struct LevelsCard: View {
    @ObservedObject var prefs = Prefs.shared
    @ObservedObject var live = LiveState.shared

    var body: some View {
        HStack(spacing: 12) {
            if prefs.swapSides {
                bar(.volume)
                readout(.volume, alignment: .leading)
                Spacer(minLength: 0)
                readout(.brightness, alignment: .trailing)
                bar(.brightness)
            } else {
                bar(.brightness)
                readout(.brightness, alignment: .leading)
                Spacer(minLength: 0)
                readout(.volume, alignment: .trailing)
                bar(.volume)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    private func value(_ c: EdgeControl) -> Float? {
        c == .brightness ? live.brightness : live.volume
    }

    @ViewBuilder
    private func readout(_ c: EdgeControl, alignment: HorizontalAlignment) -> some View {
        let isVolume = c == .volume
        let icon = isVolume ? (live.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") : "sun.max.fill"
        let tint: Color = isVolume ? .brimViolet : .brimAmber
        VStack(alignment: alignment, spacing: 2) {
            HStack(spacing: 4) {
                if !isVolume { Image(systemName: icon).foregroundStyle(tint) }
                Text(isVolume ? "VOLUME" : "BRIGHTNESS")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(.secondary)
                if isVolume { Image(systemName: icon).foregroundStyle(tint) }
            }
            .font(.system(size: 11))
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                if let v = value(c) {
                    Text("\(Int((v * 100).rounded()))")
                        .font(.system(size: 34, weight: .medium, design: .rounded).monospacedDigit())
                    Text("%").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                } else {
                    Text("—").font(.system(size: 34, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .opacity(isVolume && live.muted ? 0.45 : 1)
            .animation(.easeOut(duration: 0.15), value: value(c))
        }
    }

    private func bar(_ c: EdgeControl) -> some View {
        LevelBar(control: c,
                 level: CGFloat(value(c) ?? 0),
                 active: live.activeControl == c,
                 dimmed: c == .volume && live.muted)
    }
}

/// A thin vertical meter. Drag it to set the level directly.
struct LevelBar: View {
    let control: EdgeControl
    let level: CGFloat
    let active: Bool
    let dimmed: Bool

    var body: some View {
        let colors: [Color] = control == .brightness ? [.brimAmber, .brimAmberTop] : [.brimViolet, .brimCyan]
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top))
                    .frame(height: max(geo.size.width, geo.size.height * min(max(level, 0), 1)))
                    .opacity(dimmed ? 0.35 : 1)
                    .shadow(color: colors[1].opacity(active ? 0.9 : 0), radius: active ? 6 : 0)
            }
            .contentShape(Rectangle().inset(by: -8))
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let v = Float(1 - g.location.y / geo.size.height)
                    let clamped = min(max(v, 0), 1)
                    if control == .brightness {
                        SystemControls.setBrightness(clamped)
                    } else {
                        SystemControls.setVolume(clamped)
                    }
                    LiveState.shared.refreshLevels()
                }
            )
        }
        .frame(width: active ? 7 : 5, height: 64)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: level)
        .animation(.easeOut(duration: 0.15), value: active)
        .help("Drag to adjust")
    }
}

/// Trial, license and update notices.
struct NoticeBanners: View {
    @ObservedObject var licensing = Licensing.shared
    @ObservedObject var updater = Updater.shared

    var body: some View {
        VStack(spacing: 8) {
            switch licensing.state {
            case .expired:
                banner(icon: "clock.badge.exclamationmark.fill", tint: .orange,
                       text: "Your trial has ended, so edge gestures are paused.",
                       primary: ("Buy Brim…", { licensing.openCheckout() }),
                       secondary: ("Enter Key…", { AppActions.shared.showLicense() }))
            case .trial(let days) where days <= 3:
                banner(icon: "clock.fill", tint: .brimAccent,
                       text: "\(days) day\(days == 1 ? "" : "s") left in your trial.",
                       primary: ("Buy Brim…", { licensing.openCheckout() }),
                       secondary: ("Enter Key…", { AppActions.shared.showLicense() }))
            default:
                EmptyView()
            }
            switch updater.phase {
            case .available(let info):
                banner(icon: "arrow.down.circle.fill", tint: .brimAccent,
                       text: "Brim \(info.version) is available.",
                       primary: ("Install & Relaunch", { Task { await updater.install(info) } }), secondary: nil)
            case .downloading, .installing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(updater.phase == .downloading ? "Downloading update…" : "Installing update…")
                        .font(.system(size: 11))
                    Spacer()
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.brimAccent.opacity(0.12)))
            case .upToDate:
                banner(icon: "checkmark.circle.fill", tint: .green, text: "Brim \(AppConfig.version) is up to date.", primary: nil, secondary: nil)
            case .failed(let message):
                banner(icon: "exclamationmark.triangle.fill", tint: .orange, text: message, primary: nil, secondary: nil)
            default:
                EmptyView()
            }
        }
    }

    private func banner(icon: String, tint: Color, text: String,
                        primary: (String, () -> Void)?, secondary: (String, () -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                if primary != nil || secondary != nil {
                    HStack(spacing: 6) {
                        if let primary { Button(primary.0, action: primary.1).controlSize(.small) }
                        if let secondary { Button(secondary.0, action: secondary.1).controlSize(.small) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.12)))
    }
}

struct AccessBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 16))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Allow Accessibility so Brim can show the system volume and brightness display and control media.")
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Allow Access…") {
                    Permissions.requestAccess()
                    Permissions.openAccessibilitySettings()
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
    }
}
