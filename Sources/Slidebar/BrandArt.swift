import AppKit

/// Slidebar's colors, app icon and menu bar glyph.
enum Brand {
    static let amberTop = NSColor(srgbRed: 1.00, green: 0.84, blue: 0.36, alpha: 1)
    static let amberBottom = NSColor(srgbRed: 1.00, green: 0.45, blue: 0.20, alpha: 1)
    static let cyanTop = NSColor(srgbRed: 0.45, green: 0.92, blue: 1.00, alpha: 1)
    static let violetBottom = NSColor(srgbRed: 0.42, green: 0.36, blue: 1.00, alpha: 1)
    static let backgroundTop = NSColor(srgbRed: 0.19, green: 0.18, blue: 0.47, alpha: 1)
    static let backgroundBottom = NSColor(srgbRed: 0.05, green: 0.05, blue: 0.16, alpha: 1)

    // MARK: App icon

    /// The app icon artwork (Resources/AppIcon-1024.png, on the standard macOS 1024 grid).
    private static let iconArtwork: NSImage? = {
        guard let url = Bundle.main.url(forResource: "AppIcon-1024", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    /// The full app icon at the given side length, with its margin and shadow.
    static func appIcon(size: CGFloat) -> NSImage {
        let source = iconArtwork ?? NSApp.applicationIconImage ?? NSImage()
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
    }

    /// The icon tile only (no margin or shadow), for the app's own UI.
    static func badge(size: CGFloat) -> NSImage {
        let source = iconArtwork ?? NSApp.applicationIconImage ?? NSImage()
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            // The tile sits at 100…924 on the 1024 grid.
            let scale = source.size.width / 1024
            let tile = NSRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
            source.draw(in: rect, from: tile, operation: .sourceOver, fraction: 1)
            return true
        }
    }

    // MARK: Menu bar glyph

    /// A template image for the status item, echoing the icon: a rounded tile with a level bar
    /// on its right edge. `attention` adds a small dot, like an unread badge, when Slidebar needs the user.
    static func menuBarGlyph(paused: Bool = false, attention: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: false) { _ in
            NSColor.black.set()
            let tile = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 1.5, width: 15, height: 13), xRadius: 3.5, yRadius: 3.5)
            tile.lineWidth = 1.4
            tile.stroke()
            if paused {
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: 4, y: 3.5))
                slash.line(to: NSPoint(x: 14, y: 12.5))
                slash.lineWidth = 1.4
                slash.stroke()
            } else {
                // The level bar: a faint track with a solid fill from the bottom.
                NSColor.black.withAlphaComponent(0.35).setFill()
                NSBezierPath(roundedRect: NSRect(x: 11.5, y: 4, width: 2.4, height: 8), xRadius: 1.2, yRadius: 1.2).fill()
                NSColor.black.setFill()
                NSBezierPath(roundedRect: NSRect(x: 11.5, y: 4, width: 2.4, height: 5), xRadius: 1.2, yRadius: 1.2).fill()
            }
            if attention, let ctx = NSGraphicsContext.current {
                ctx.compositingOperation = .clear
                NSBezierPath(ovalIn: NSRect(x: 11, y: 9.5, width: 7.5, height: 7.5)).fill()
                ctx.compositingOperation = .sourceOver
                NSColor.black.set()
                NSBezierPath(ovalIn: NSRect(x: 12.5, y: 11, width: 4.5, height: 4.5)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Slidebar"
        return image
    }
}
