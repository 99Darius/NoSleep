import AppKit

// Renders the installer background: a clean light panel with the NoSleep
// S-in-box logo and wordmark anchored at the bottom-left. Usage:
//   swift make_installer_bg.swift <out.png>

func render(width: Int, height: Int) -> Data {
    let w = CGFloat(width), h = CGFloat(height)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Soft top-to-bottom gradient, white → very light blue.
    let bg = NSGradient(colors: [
        NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
        NSColor(srgbRed: 0.90, green: 0.93, blue: 1.0, alpha: 1.0),
    ])!
    bg.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -90)

    // Logo tile + wordmark anchored bottom-left, lifted so the wordmark
    // (descenders included) clears the bottom edge.
    let tile = w * 0.22
    let margin = w * 0.10
    let wordBaseline = h * 0.075           // "NoSleep" sits here
    let tileBottom = wordBaseline + w * 0.135   // tile starts above the word
    let tileRect = NSRect(x: margin, y: tileBottom, width: tile, height: tile)
    let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: tile * 0.225, yRadius: tile * 0.225)
    let blue = NSGradient(colors: [
        NSColor(srgbRed: 0.40, green: 0.47, blue: 0.98, alpha: 1.0),
        NSColor(srgbRed: 0.18, green: 0.22, blue: 0.55, alpha: 1.0),
    ])!
    blue.draw(in: tilePath, angle: -90)

    // Inner box + S.
    let bi = tile * 0.27
    let boxRect = NSRect(x: margin + bi, y: tileBottom + bi, width: tile - 2 * bi, height: tile - 2 * bi)
    let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: tile * 0.085, yRadius: tile * 0.085)
    boxPath.lineWidth = max(1, tile * 0.042)
    NSColor.white.setStroke()
    boxPath.stroke()
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let sAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: tile * 0.40, weight: .bold),
        .foregroundColor: NSColor.white, .paragraphStyle: para,
    ]
    let s = NSAttributedString(string: "S", attributes: sAttrs)
    let sh = s.size().height
    s.draw(in: NSRect(x: margin, y: tileBottom + (tile - sh) / 2, width: tile, height: sh))

    // Wordmark below the tile.
    let word = NSAttributedString(string: "NoSleep", attributes: [
        .font: NSFont.systemFont(ofSize: w * 0.075, weight: .bold),
        .foregroundColor: NSColor(srgbRed: 0.16, green: 0.19, blue: 0.42, alpha: 1.0),
    ])
    word.draw(at: NSPoint(x: margin, y: wordBaseline))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.png"
// Installer background panel — portrait, anchored bottom-left.
let data = render(width: 620, height: 820)
try! data.write(to: URL(fileURLWithPath: out))
print("wrote installer background to \(out)")
