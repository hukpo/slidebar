import SlidebarCore
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
                // The app icon's indigo-to-violet, so the guide feels like the icon opened up.
                LinearGradient(colors: [Color(red: 0.11, green: 0.13, blue: 0.42), Color(red: 0.26, green: 0.15, blue: 0.56)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 16) {
                    HStack(spacing: 10) {
                        AppIconView(size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Welcome to Slidebar")
                                .font(.system(size: 20, weight: .semibold))
                                .accessibilityAddTraits(.isHeader)
                            Text("Slide along the edges of your trackpad to change things like volume and brightness. You choose what each edge and corner does.")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                        Spacer()
                    }
                    TrackpadDemo(left: prefs.edge(.left), right: prefs.edge(.right), bottom: prefs.edge(.bottom))
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
                StepRow(number: 1, done: triedSlide,
                        title: live.deviceCount == 0 ? "Connect a trackpad" : "Try it now",
                        detail: live.deviceCount == 0
                            ? "Slidebar can't find a trackpad. Turn on or connect your Magic Trackpad, then try again."
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
                    Text("You can open this guide again from Slidebar's menu bar icon.")
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
        return "Slide one finger along an edge of your trackpad. You can choose what each edge does in Slidebar's menu."
    }

    private var accessDetail: String {
        if live.trusted {
            return "All set. You'll see the usual volume and brightness display, and gestures that press keys, like songs, tabs and Spotlight, work too."
        }
        if prefs.didPromptAccess {
            return "In System Settings, turn on Slidebar in the Accessibility list. macOS may ask for your password. Then come back here."
        }
        return "Slidebar already works. Allowing this once lets it show the usual volume and brightness display and use gestures that press keys, like songs, tabs and Spotlight. Slidebar is open source, so anyone can check what it does."
    }
}

/// One numbered step of the guide, ticked once done.
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

/// The trackpad from the menu, with a fingertip sliding up the volume edge and its strip filling
/// as it goes. Still under Reduce Motion.
private struct TrackpadDemo: View {
    let left: EdgeFunction
    let right: EdgeFunction
    let bottom: EdgeFunction
    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.snapshotMode) private var snapshotMode

    /// Demonstrate on the volume edge when there is one, otherwise the right edge.
    private var fingerOnLeft: Bool { left == .volume && right != .volume || (right == .off && left != .off) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let inset: CGFloat = 40, strip: CGFloat = 4
            let trackLength = h - 2 * inset
            ZStack(alignment: .topLeading) {
                TrackpadSurface()

                if left != .off { sideEdge(left, x: 4, length: trackLength, top: inset, isDemo: fingerOnLeft) }
                if right != .off { sideEdge(right, x: w - 4 - strip, length: trackLength, top: inset, isDemo: !fingerOnLeft) }
                if bottom != .off {
                    Capsule().fill(LinearGradient(colors: bottom.mapColors, startPoint: .leading, endPoint: .trailing))
                        .frame(width: w - 2 * inset - 40, height: strip)
                        .offset(x: inset + 20, y: h - 4 - strip)
                    chip(bottom).frame(width: w).offset(y: h - 4 - strip - 32)
                }

                // The fingertip, riding the top of the demo edge's level.
                let level = up ? 0.82 : 0.22
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    .frame(width: 22, height: 22)
                    .offset(x: (fingerOnLeft ? 4 + strip / 2 : w - 4 - strip / 2) - 11,
                            y: inset + trackLength * (1 - level) - 11)
            }
            .clipShape(TrackpadSurface.shape.inset(by: -12))
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement()
        .accessibilityLabel("Illustration: a finger slides up the \(fingerOnLeft ? "left" : "right") edge of the trackpad.")
        .onAppear {
            guard !reduceMotion, !snapshotMode else { up = true; return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { up = true }
        }
    }

    /// A side edge: a dim track, a colored fill to the current level, and its label chip beside it.
    private func sideEdge(_ function: EdgeFunction, x: CGFloat, length: CGFloat, top: CGFloat, isDemo: Bool) -> some View {
        let level: CGFloat = isDemo ? (up ? 0.82 : 0.22) : 0.6
        return ZStack(alignment: .topLeading) {
            Capsule().fill(Color.white.opacity(0.14))
                .frame(width: 4, height: length)
            Capsule().fill(LinearGradient(colors: function.mapColors, startPoint: .bottom, endPoint: .top))
                .frame(width: 4, height: length * level)
                .offset(y: length * (1 - level))
                .shadow(color: (function.mapColors.last ?? .clear).opacity(isDemo ? 0.8 : 0), radius: 5)
            chip(function)
                .fixedSize()
                .offset(x: x < 40 ? 14 : -14, y: length / 2 - 12)
                .frame(width: 4, alignment: x < 40 ? .leading : .trailing)
        }
        .offset(x: x, y: top)
    }

    private func chip(_ function: EdgeFunction) -> some View {
        HStack(spacing: 4) {
            Image(systemName: function.icon).foregroundStyle(function.mapColors[1])
            Text(function.shortTitle)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.34)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5))
    }
}
