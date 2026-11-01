import AppKit

/// Brim's colors and artwork, drawn in code so the icon, the menu bar glyph
/// and the website all come from one source.
enum Brand {
    static let amberTop = NSColor(srgbRed: 1.00, green: 0.84, blue: 0.36, alpha: 1)
    static let amberBottom = NSColor(srgbRed: 1.00, green: 0.45, blue: 0.20, alpha: 1)
    static let cyanTop = NSColor(srgbRed: 0.45, green: 0.92, blue: 1.00, alpha: 1)
    static let violetBottom = NSColor(srgbRed: 0.42, green: 0.36, blue: 1.00, alpha: 1)
    static let accent = NSColor(srgbRed: 0.07, green: 0.62, blue: 0.80, alpha: 1)
    static let backgroundTop = NSColor(srgbRed: 0.19, green: 0.18, blue: 0.47, alpha: 1)
    static let backgroundBottom = NSColor(srgbRed: 0.05, green: 0.05, blue: 0.16, alpha: 1)

    // MARK: App icon

    /// Draws the app icon into a square of the given side length (macOS icon grid).
    static func appIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            drawAppIcon(scale: size / 1024)
            return true
        }
    }

    /// The icon body only (no margin or shadow), for use inside the app's own UI.
    static func badge(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let s = size / 824
            ctx.scaleBy(x: s, y: s)
            ctx.translateBy(x: -100, y: -100)
            drawAppIcon(scale: 1, shadow: false)
            return true
        }
    }

    /// Draws at 1024×1024 scaled by `scale`, into the current graphics context.
    static func drawAppIcon(scale s: CGFloat, shadow: Bool = true) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.scaleBy(x: s, y: s)

        // Body: the standard 824pt squircle with a soft drop shadow.
        let body = NSRect(x: 100, y: 100, width: 824, height: 824)
        let bodyPath = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)
        ctx.saveGState()
        if shadow {
            ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        }
        backgroundTop.setFill()
        bodyPath.fill()
        ctx.restoreGState()

        ctx.saveGState()
        bodyPath.addClip()
        NSGradient(starting: backgroundTop, ending: backgroundBottom)!.draw(in: body, angle: -90)
        // A soft light from the top.
        let glow = NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0)])!
        glow.draw(fromCenter: NSPoint(x: 512, y: 980), radius: 0, toCenter: NSPoint(x: 512, y: 980), radius: 640, options: [])

        // The trackpad.
        let pad = NSRect(x: 212, y: 262, width: 600, height: 460)
        let padPath = NSBezierPath(roundedRect: pad, xRadius: 64, yRadius: 64)
        NSGradient(starting: NSColor.white.withAlphaComponent(0.13), ending: NSColor.white.withAlphaComponent(0.05))!
            .draw(in: padPath, angle: -90)
        NSColor.white.withAlphaComponent(0.24).setStroke()
        padPath.lineWidth = 6
        padPath.stroke()

        // Edge sliders: brightness (warm) on the left, volume (cool) on the right.
        let barWidth: CGFloat = 40
        let barBottom = pad.minY + 58
        let barHeight = pad.height - 116
        let left = NSRect(x: pad.minX + 40, y: barBottom, width: barWidth, height: barHeight)
        let right = NSRect(x: pad.maxX - 40 - barWidth, y: barBottom, width: barWidth, height: barHeight)
        drawBar(ctx, track: left, level: 0.66, top: amberTop, bottom: amberBottom)
        drawBar(ctx, track: right, level: 0.44, top: cyanTop, bottom: violetBottom)

        // Media strip along the bottom edge.
        let strip = NSRect(x: 512 - 90, y: pad.minY + 26, width: 180, height: 14)
        NSColor.white.withAlphaComponent(0.28).setFill()
        NSBezierPath(roundedRect: strip, xRadius: 7, yRadius: 7).fill()

        // A fingertip riding the volume edge.
        let tip = NSPoint(x: right.midX, y: right.minY + right.height * 0.44)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 46, color: cyanTop.withAlphaComponent(0.95).cgColor)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: tip.x - 40, y: tip.y - 40, width: 80, height: 80)).fill()
        ctx.restoreGState()
        NSColor.white.withAlphaComponent(0.55).setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: tip.x - 58, y: tip.y - 58, width: 116, height: 116))
        ring.lineWidth = 5
        ring.stroke()

        ctx.restoreGState() // clip
        // Fine highlight on the rim.
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let rim = NSBezierPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), xRadius: 185, yRadius: 185)
        rim.lineWidth = 3
        rim.stroke()
        ctx.restoreGState()
    }

    private static func drawBar(_ ctx: CGContext, track: NSRect, level: CGFloat, top: NSColor, bottom: NSColor) {
        let radius = track.width / 2
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        var fill = track
        fill.size.height = max(track.width, track.height * level)
        let fillPath = NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 40, color: top.withAlphaComponent(0.8).cgColor)
        bottom.setFill()
        fillPath.fill()
        ctx.restoreGState()
        NSGradient(starting: bottom, ending: top)!.draw(in: fillPath, angle: 90)
    }

    // MARK: Menu bar glyph

    /// A template image for the status item: a trackpad with two edge levels.
    /// `attention` adds a small dot, like an unread badge, when Brim needs the user.
    static func menuBarGlyph(paused: Bool = false, attention: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { _ in
            NSColor.black.set()
            let pad = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2, width: 17, height: 12), xRadius: 3, yRadius: 3)
            pad.lineWidth = 1.4
            pad.stroke()
            if paused {
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: 4, y: 3.5))
                slash.line(to: NSPoint(x: 16, y: 12.5))
                slash.lineWidth = 1.4
                slash.stroke()
            } else {
                NSBezierPath(roundedRect: NSRect(x: 4, y: 4, width: 2, height: 6.5), xRadius: 1, yRadius: 1).fill()
                NSBezierPath(roundedRect: NSRect(x: 14, y: 4, width: 2, height: 4), xRadius: 1, yRadius: 1).fill()
            }
            if attention, let ctx = NSGraphicsContext.current {
                ctx.compositingOperation = .clear
                NSBezierPath(ovalIn: NSRect(x: 13, y: 9.5, width: 7.5, height: 7.5)).fill()
                ctx.compositingOperation = .sourceOver
                NSColor.black.set()
                NSBezierPath(ovalIn: NSRect(x: 14.5, y: 11, width: 4.5, height: 4.5)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Brim"
        return image
    }
}
