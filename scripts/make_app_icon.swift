import AppKit
import CoreText

// Draw every size from vectors so the Dock, Finder, and Retina icons stay crisp.
// Keep the folded-page mark in sync with TEXnologia/Resources/TEXnologiaIcon.svg.
let outputDirectory = CommandLine.arguments.dropFirst().first ?? "dist/AppIcon.iconset"
let outputURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func texWordmark() -> CGPath {
    let font = CTFontCreateWithName("TimesNewRomanPS-BoldMT" as CFString, 180, nil)
    let path = CGMutablePath()
    var cursor: CGFloat = 0
    for (character, baseline) in [("T", 0.0), ("E", -40.0), ("X", 0.0)] {
        var code = character.utf16.first!
        var glyph: CGGlyph = 0
        CTFontGetGlyphsForCharacters(font, &code, &glyph, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        if let outline = CTFontCreatePathForGlyph(font, glyph, nil) {
            path.addPath(outline, transform: CGAffineTransform(translationX: cursor, y: baseline))
        }
        cursor += advance.width - 18
    }
    let bounds = path.boundingBoxOfPath
    let target = CGRect(x: 363, y: 373, width: 308, height: 200)
    let scale = min(target.width / bounds.width, target.height / bounds.height)
    var transform = CGAffineTransform(
        a: scale, b: 0, c: 0, d: scale,
        tx: target.midX - bounds.midX * scale,
        ty: target.midY - bounds.midY * scale
    )
    return path.copy(using: &transform)!
}

let wordmark = texWordmark()

func drawIcon(pixels: Int, name: String) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not create the icon bitmap.")
    }

    bitmap.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let cg = context.cgContext
    let scale = CGFloat(pixels) / 1024
    cg.scaleBy(x: scale, y: scale)
    cg.setShouldAntialias(true)

    let tile = NSBezierPath(roundedRect: NSRect(x: 82, y: 82, width: 860, height: 860), xRadius: 193, yRadius: 193)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -17), blur: 28, color: color(23, 54, 93, 0.22).cgColor)
    color(47, 111, 208).setFill()
    tile.fill()
    cg.restoreGState()
    NSGradient(starting: color(104, 174, 243), ending: color(35, 99, 188))!.draw(in: tile, angle: -62)

    let border = NSBezierPath(roundedRect: NSRect(x: 84, y: 84, width: 856, height: 856), xRadius: 191, yRadius: 191)
    color(255, 255, 255, 0.18).setStroke()
    border.lineWidth = 3
    border.stroke()

    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -5), blur: 11, color: color(29, 70, 115, 0.22).cgColor)
    let page = NSBezierPath()
    page.move(to: NSPoint(x: 318, y: 242))
    page.line(to: NSPoint(x: 318, y: 784))
    page.line(to: NSPoint(x: 587, y: 784))
    page.line(to: NSPoint(x: 715, y: 655))
    page.line(to: NSPoint(x: 715, y: 242))
    page.close()
    page.lineWidth = 33
    page.lineJoinStyle = .round
    NSColor.white.setStroke()
    page.stroke()

    let fold = NSBezierPath()
    fold.move(to: NSPoint(x: 584, y: 774))
    fold.line(to: NSPoint(x: 584, y: 655))
    fold.line(to: NSPoint(x: 704, y: 655))
    fold.lineWidth = 31
    fold.lineJoinStyle = .round
    fold.lineCapStyle = .round
    fold.stroke()
    cg.restoreGState()

    cg.setFillColor(NSColor.white.cgColor)
    cg.addPath(wordmark)
    cg.fillPath()
    cg.flush()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode the icon PNG.")
    }
    try png.write(to: outputURL.appendingPathComponent(name))
}

for size in [16, 32, 128, 256, 512] {
    try drawIcon(pixels: size, name: "icon_\(size)x\(size).png")
    try drawIcon(pixels: size * 2, name: "icon_\(size)x\(size)@2x.png")
}
print("Created TEXnologia icon PNGs in \(outputURL.path)")
