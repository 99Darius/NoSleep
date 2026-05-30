import AppKit

// Renders the NoSleep app icon (an "S" inside a rounded square box, on a blue
// gradient tile) into an .iconset directory. Usage: swift make_icon.swift <outDir>

func renderPNG(px: Int) -> Data {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Background rounded-square tile with a blue→indigo gradient.
    let pad = size * 0.06
    let bgRect = NSRect(x: pad, y: pad, width: size - 2 * pad, height: size - 2 * pad)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: size * 0.225, yRadius: size * 0.225)
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.40, green: 0.47, blue: 0.98, alpha: 1.0),
        NSColor(srgbRed: 0.18, green: 0.22, blue: 0.55, alpha: 1.0),
    ])!
    gradient.draw(in: bgPath, angle: -90)

    // Inner box outline (echoes the menu bar icon).
    let boxInset = size * 0.27
    let boxRect = NSRect(x: boxInset, y: boxInset, width: size - 2 * boxInset, height: size - 2 * boxInset)
    let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: size * 0.085, yRadius: size * 0.085)
    boxPath.lineWidth = max(1, size * 0.042)
    NSColor.white.setStroke()
    boxPath.stroke()

    // Centered bold "S".
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size * 0.40, weight: .bold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: para,
    ]
    let s = NSAttributedString(string: "S", attributes: attrs)
    let h = s.size().height
    s.draw(in: NSRect(x: 0, y: (size - h) / 2, width: size, height: h))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// (filename, pixel size) per Apple's iconset naming.
let specs: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in specs {
    let data = renderPNG(px: px)
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
print("wrote \(specs.count) icons to \(outDir)")
