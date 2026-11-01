// Renders Brim's app icon (from Sources/Brim/BrandArt.swift) to an .iconset, .icns and PNGs.
// Usage: swiftc scripts/IconTool/main.swift Sources/Brim/BrandArt.swift -o .build/icontool && .build/icontool <out-dir>
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources")
let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func png(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    Brand.drawAppIcon(scale: CGFloat(pixels) / 1024)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try png(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try png(1024).write(to: outDir.appendingPathComponent("AppIcon-1024.png"))
print("Wrote \(iconset.path)")

// A margin-free tile for small UI spots (website nav, favicon).
func badgePNG(_ pixels: Int) -> Data {
    let image = Brand.badge(size: CGFloat(pixels))
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}
try badgePNG(128).write(to: outDir.appendingPathComponent("Badge-128.png"))
