import BrimCore
import SwiftUI

/// First-run guide: try a slide, optionally allow Accessibility, then finish in the menu bar.
struct SetupView: View {
    @ObservedObject var live = LiveState.shared
    @ObservedObject var prefs = Prefs.shared
    @State private var slidesAtOpen = LiveState.shared.slideCount

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
                                .accessibilityAddTraits(.isHeader)
                            Text("Slide along the edges of your trackpad to change things like volume and brightness. You choose what each edge and corner does.")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                        Spacer()
                    }
                    TrackpadDemo(left: prefs.edge(.left), right: prefs.edge(.right), bottom: prefs.edge(.bottom))
                        .frame(height: 180)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.top, 34)
                .padding(.bottom, 22)
            }
            .environment(\.colorScheme, .dark)
            .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                StepRow(number: 1, done: triedSlide,
                        title: live.deviceCount == 0 ? "Connect a trackpad" : "Try it now",
                        detail: live.deviceCount == 0
                            ? "Brim can't find a trackpad. Turn on or connect your Magic Trackpad, then try again."
                            : firstTryText) {
                    EmptyView()
                }

                StepRow(number: 2, done: live.trusted,
                        title: "Allow Accessibility (optional)",
                        detail: accessDetail) {
                    if !live.trusted {
                        Button(prefs.didPromptAccess ? "Open System Settings" : "Allow…") { Permissions.ask() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .keyboardShortcut(.defaultAction)
                    }
                }

                HStack {
                    Text("You can open this guide again from Brim's menu bar icon.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if live.trusted {
                        Button("Done") { AppActions.shared.finishSetup() }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Done") { AppActions.shared.finishSetup() }
                    }
                }
                .padding(.top, 6)
            }
            .padding(22)
        }
        .frame(width: 440)
        .animation(.easeOut(duration: 0.2), value: live.trusted)
    }

    /// Points at the edge that does something the user will notice, preferring volume.
    private var firstTryText: String {
        let order: [EdgeFunction] = [.volume, .brightness, .keyboardBrightness]
        for f in order {
            if let side = EdgeSide.allCases.first(where: { prefs.edge($0) == f }) {
                let way = side.isVertical ? "up" : "to the right"
                let what = f == .volume ? "The volume goes up." : f == .brightness ? "The screen gets brighter." : "The keyboard lights up."
                return "Rest one finger on the \(side.title.lowercased().replacingOccurrences(of: " edge", with: "")) edge of your trackpad and slide \(way). \(what)"
            }
        }
        return "Slide one finger along an edge of your trackpad. You can choose what each edge does in Brim's menu."
    }

    private var accessDetail: String {
        if live.trusted {
            return "All set. You'll see the usual volume and brightness display, and gestures that press keys, like songs, desktops and Spotlight, work too."
        }
        if prefs.didPromptAccess {
            return "In System Settings, turn on Brim in the Accessibility list. macOS may ask for your password. Then come back here."
        }
        return "Brim already works. Allowing this once lets it show the usual volume and brightness display and use gestures that press keys, like songs, desktops and Spotlight. Brim is open source, so anyone can check what it does."
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
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(done ? "Done" : "Not done")
            Spacer(minLength: 8)
            accessory()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(done ? Color.green.opacity(0.08) : Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(done ? Color.green.opacity(0.25) : Color.primary.opacity(0.06)))
        .animation(.easeOut(duration: 0.2), value: done)
    }
}

/// A trackpad showing a finger sliding up the volume edge. Still under Reduce Motion.
private struct TrackpadDemo: View {
    let left: EdgeFunction
    let right: EdgeFunction
    let bottom: EdgeFunction
    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Demonstrate on the volume edge when there is one, otherwise the right edge.
    private var fingerOnLeft: Bool { left == .volume && right != .volume || (right == .off && left != .off) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1.5)

                if left != .off { edge(colors: left.levelColors, label: left.shortTitle, x: 18, h: h) }
                if right != .off { edge(colors: right.levelColors, label: right.shortTitle, x: w - 18, h: h) }

                if bottom != .off {
                    Capsule().fill(Color.primary.opacity(0.18))
                        .frame(width: 70, height: 4)
                        .position(x: w / 2, y: h - 12)
                    Text(bottom.shortTitle).font(.system(size: 10)).foregroundStyle(.secondary)
                        .position(x: w / 2, y: h - 25)
                }

                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                    .overlay(Circle().stroke(Color.primary.opacity(0.15)))
                    .frame(width: 22, height: 22)
                    .position(x: fingerOnLeft ? 18 : w - 18, y: up ? h * 0.25 : h * 0.78)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Illustration: a finger slides up the \(fingerOnLeft ? "left" : "right") edge of the trackpad.")
        .onAppear {
            guard !reduceMotion else { up = true; return }
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
