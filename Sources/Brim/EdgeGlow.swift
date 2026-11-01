import AppKit
import BrimCore
import SwiftUI

/// A thin glowing level bar on the edge of the screen that mirrors the trackpad edge being slid.
final class EdgeGlow {
    static let shared = EdgeGlow()

    final class Model: ObservableObject {
        @Published var function: EdgeFunction = .volume
        @Published var side: EdgeSide = .right
        @Published var level: Float = 0
        @Published var muted = false
        @Published var visible = false
    }

    private let model = Model()
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private static let thickness: CGFloat = 26

    /// A static bar for screenshots.
    static func preview(level: Float, function: EdgeFunction = .volume, side: EdgeSide = .right) -> some View {
        let m = Model()
        m.level = level
        m.function = function
        m.side = side
        m.visible = true
        return GlowBar(model: m)
    }

    func show(_ function: EdgeFunction, on side: EdgeSide, level: Float, muted: Bool) {
        hideWork?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel

        // The screen the pointer is on.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let t = Self.thickness
        let rect: NSRect
        if side.isVertical {
            let height = min(frame.height * 0.5, 420)
            rect = NSRect(x: side == .left ? frame.minX : frame.maxX - t, y: frame.midY - height / 2, width: t, height: height)
        } else {
            let width = min(frame.width * 0.4, 520)
            rect = NSRect(x: frame.midX - width / 2, y: side == .bottom ? frame.minY : frame.maxY - t, width: width, height: t)
        }
        panel.setFrame(rect, display: false)

        model.function = function
        model.side = side
        model.level = level
        model.muted = muted
        panel.orderFrontRegardless()
        withAnimation(.easeOut(duration: 0.18)) { model.visible = true }
    }

    func update(level: Float, muted: Bool) {
        guard model.visible else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            model.level = level
            model.muted = muted
        }
    }

    func hide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(.easeIn(duration: 0.35)) { self.model.visible = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                if self?.model.visible == false { self?.panel?.orderOut(nil) }
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: GlowBar(model: model))
        return panel
    }
}

extension EdgeFunction {
    /// Bottom-to-top colors used for this function's level.
    var levelColors: [Color] {
        switch self {
        case .brightness: return [.brimAmber, .brimAmberTop]
        case .keyboardBrightness: return [Color(white: 0.7), .white]
        case .micVolume: return [Color(red: 0.16, green: 0.62, blue: 0.45), Color(red: 0.5, green: 0.95, blue: 0.72)]
        case .nightShift: return [Color(red: 0.95, green: 0.42, blue: 0.12), Color(red: 1.0, green: 0.72, blue: 0.38)]
        default: return [.brimViolet, .brimCyan]
        }
    }
}

private struct GlowBar: View {
    @ObservedObject var model: EdgeGlow.Model

    var body: some View {
        let colors = model.function.levelColors
        let vertical = model.side.isVertical
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        GeometryReader { geo in
            let length = max(10, (vertical ? geo.size.height : geo.size.width) - 16)
            ZStack(alignment: vertical ? .bottom : .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.35))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: vertical ? .bottom : .leading, endPoint: vertical ? .top : .trailing))
                    .frame(width: vertical ? nil : max(6, length * CGFloat(model.level)),
                           height: vertical ? max(6, length * CGFloat(model.level)) : nil)
                    .opacity(model.muted ? 0.35 : 1)
                    .shadow(color: colors[1].opacity(0.7), radius: 6)
            }
            .frame(width: vertical ? 6 : length, height: vertical ? length : 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding(vertical ? .horizontal : .vertical, 6)
        }
        .opacity(model.visible ? 1 : 0)
        .offset(x: !vertical || reduceMotion || model.visible ? 0 : (model.side == .left ? -14 : 14),
                y: vertical || reduceMotion || model.visible ? 0 : (model.side == .bottom ? 14 : -14))
    }

    private var alignment: Alignment {
        switch model.side {
        case .left: return .leading
        case .right: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        }
    }
}
