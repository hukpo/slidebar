import AppKit
import BrimCore
import SwiftUI

/// A thin glowing level bar on the edge of the screen that mirrors the trackpad edge being slid.
final class EdgeGlow {
    static let shared = EdgeGlow()

    final class Model: ObservableObject {
        @Published var control: EdgeControl = .volume
        @Published var level: Float = 0
        @Published var muted = false
        @Published var visible = false
        @Published var onLeft = false
    }

    private let model = Model()

    /// A static bar for screenshots.
    static func preview(level: Float) -> some View {
        let m = Model()
        m.level = level
        m.visible = true
        return GlowBar(model: m)
    }
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private static let width: CGFloat = 26

    func show(_ control: EdgeControl, onLeft: Bool, level: Float, muted: Bool) {
        hideWork?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel

        // The screen the pointer is on.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let height = min(frame.height * 0.5, 420)
        let x = onLeft ? frame.minX : frame.maxX - Self.width
        panel.setFrame(NSRect(x: x, y: frame.midY - height / 2, width: Self.width, height: height), display: false)

        model.control = control
        model.onLeft = onLeft
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

private struct GlowBar: View {
    @ObservedObject var model: EdgeGlow.Model

    var body: some View {
        let colors: [Color] = model.control == .brightness ? [.brimAmber, .brimAmberTop] : [.brimViolet, .brimCyan]
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.black.opacity(0.35))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top))
                    .frame(height: max(6, geo.size.height * CGFloat(model.level)))
                    .opacity(model.muted ? 0.35 : 1)
                    .shadow(color: colors[1].opacity(0.7), radius: 6)
            }
            .frame(width: 6)
            .frame(maxWidth: .infinity, alignment: model.onLeft ? .leading : .trailing)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .opacity(model.visible ? 1 : 0)
        .offset(x: model.visible ? 0 : (model.onLeft ? -14 : 14))
    }
}
