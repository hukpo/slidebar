import SwiftUI

/// First-run guide: grant Accessibility, then try a first slide.
struct SetupView: View {
    @ObservedObject var live = LiveState.shared
    @ObservedObject var prefs = Prefs.shared
    @State private var slidesAtOpen = LiveState.shared.slideCount
    let onDone: () -> Void

    private var triedSlide: Bool { live.slideCount > slidesAtOpen }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                NightBackground(cornerRadius: 0)
                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        AppIconView(size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Welcome to Brim")
                                .font(.system(size: 20, weight: .semibold))
                            Text("Your trackpad's edges are now sliders.")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        Spacer()
                    }
                    TrackpadDemo(swap: prefs.swapSides)
                        .frame(height: 190)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.top, 34)
                .padding(.bottom, 22)
            }
            .environment(\.colorScheme, .dark)
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                StepRow(number: 1, done: live.trusted,
                        title: "Allow Accessibility",
                        detail: "Lets Brim show the system on-screen display and control media.") {
                    Button("Open Settings…") {
                        Permissions.requestAccess()
                        Permissions.openAccessibilitySettings()
                    }
                    .controlSize(.small)
                }
                StepRow(number: 2, done: triedSlide,
                        title: "Try your first slide",
                        detail: "Rest one finger on the \(prefs.swapSides ? "left" : "right") edge of the trackpad and slide up.") {
                    EmptyView()
                }

                HStack {
                    Text(triedSlide ? "You've got it." : "Open this guide again any time from the ⋯ menu.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(triedSlide && live.trusted ? "Done" : "Skip for Now") {
                        prefs.hasCompletedSetup = true
                        onDone()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brimAccent)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 6)
            }
            .padding(22)
        }
        .frame(width: 440)
    }
}

private struct StepRow<Accessory: View>: View {
    let number: Int
    let done: Bool
    let title: String
    let detail: String
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.primary.opacity(0.1))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.system(size: 12, weight: .semibold))
                }
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !done { accessory() }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(done ? Color.green.opacity(0.08) : Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(done ? Color.green.opacity(0.25) : Color.primary.opacity(0.06)))
        .animation(.easeOut(duration: 0.2), value: done)
    }
}

/// An animated trackpad showing a finger sliding up the volume edge.
private struct TrackpadDemo: View {
    let swap: Bool
    @State private var up = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1.5)

                edge(colors: [.brimAmber, .brimAmberTop], label: "Brightness", x: swap ? w - 18 : 18, h: h)
                edge(colors: [.brimViolet, .brimCyan], label: "Volume", x: swap ? 18 : w - 18, h: h)

                Capsule().fill(Color.primary.opacity(0.18))
                    .frame(width: 70, height: 4)
                    .position(x: w / 2, y: h - 12)
                Text("Media Strip").font(.system(size: 9)).foregroundStyle(.secondary)
                    .position(x: w / 2, y: h - 24)

                Circle()
                    .fill(Color.white)
                    .shadow(color: .brimCyan.opacity(0.9), radius: 8)
                    .overlay(Circle().stroke(Color.primary.opacity(0.15)))
                    .frame(width: 22, height: 22)
                    .position(x: swap ? 18 : w - 18, y: up ? h * 0.25 : h * 0.78)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { up = true }
        }
    }

    private func edge(colors: [Color], label: String, x: CGFloat, h: CGFloat) -> some View {
        ZStack {
            Capsule()
                .fill(LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top))
                .frame(width: 6, height: h - 50)
                .position(x: x, y: h / 2)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(-90))
                .fixedSize()
                .position(x: x < 50 ? x + 18 : x - 18, y: h / 2)
        }
    }
}
