import AppKit
import Foundation

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "dist/AppIcon.iconset")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

struct IconImage {
    let filename: String
    let pixels: Int
}

let images = [
    IconImage(filename: "icon_16x16.png", pixels: 16),
    IconImage(filename: "icon_16x16@2x.png", pixels: 32),
    IconImage(filename: "icon_32x32.png", pixels: 32),
    IconImage(filename: "icon_32x32@2x.png", pixels: 64),
    IconImage(filename: "icon_128x128.png", pixels: 128),
    IconImage(filename: "icon_128x128@2x.png", pixels: 256),
    IconImage(filename: "icon_256x256.png", pixels: 256),
    IconImage(filename: "icon_256x256@2x.png", pixels: 512),
    IconImage(filename: "icon_512x512.png", pixels: 512),
    IconImage(filename: "icon_512x512@2x.png", pixels: 1024)
]

for image in images {
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: image.pixels,
            pixelsHigh: image.pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    else {
        throw NSError(domain: "TEXnologia.Icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap."])
    }

    bitmap.size = NSSize(width: image.pixels, height: image.pixels)
    let previousContext = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    drawIcon(in: NSRect(x: 0, y: 0, width: image.pixels, height: image.pixels))
    NSGraphicsContext.current = previousContext

    guard
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "TEXnologia.Icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render icon."])
    }

    try png.write(to: outputDirectory.appendingPathComponent(image.filename))
}

func drawIcon(in rect: NSRect) {
    let scale = min(rect.width, rect.height)
    let bounds = NSRect(x: 0, y: 0, width: scale, height: scale)

    NSGraphicsContext.current?.imageInterpolation = .high

    let background = NSBezierPath(roundedRect: bounds, xRadius: scale * 0.18, yRadius: scale * 0.18)
    let gradient = NSGradient(colors: [
        NSColor(red: 0.10, green: 0.22, blue: 0.47, alpha: 1),
        NSColor(red: 0.10, green: 0.58, blue: 0.50, alpha: 1)
    ])
    gradient?.draw(in: background, angle: -45)

    let glow = NSBezierPath(ovalIn: NSRect(x: scale * 0.18, y: scale * 0.16, width: scale * 0.64, height: scale * 0.62))
    NSColor(calibratedWhite: 1, alpha: 0.13).setFill()
    glow.fill()

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
    shadow.shadowBlurRadius = scale * 0.035
    shadow.shadowOffset = NSSize(width: 0, height: -scale * 0.015)

    NSGraphicsContext.saveGraphicsState()
    shadow.set()

    let torso = NSBezierPath()
    torso.move(to: NSPoint(x: scale * 0.36, y: scale * 0.17))
    torso.curve(
        to: NSPoint(x: scale * 0.64, y: scale * 0.17),
        controlPoint1: NSPoint(x: scale * 0.39, y: scale * 0.33),
        controlPoint2: NSPoint(x: scale * 0.61, y: scale * 0.33)
    )
    torso.line(to: NSPoint(x: scale * 0.71, y: scale * 0.13))
    torso.line(to: NSPoint(x: scale * 0.29, y: scale * 0.13))
    torso.close()
    NSColor(red: 0.07, green: 0.14, blue: 0.30, alpha: 1).setFill()
    torso.fill()

    let head = NSBezierPath(ovalIn: NSRect(x: scale * 0.40, y: scale * 0.29, width: scale * 0.20, height: scale * 0.20))
    NSColor(red: 0.96, green: 0.78, blue: 0.56, alpha: 1).setFill()
    head.fill()

    NSColor(red: 0.05, green: 0.10, blue: 0.22, alpha: 1).setFill()
    let hair = NSBezierPath()
    hair.move(to: NSPoint(x: scale * 0.40, y: scale * 0.39))
    hair.curve(
        to: NSPoint(x: scale * 0.58, y: scale * 0.43),
        controlPoint1: NSPoint(x: scale * 0.41, y: scale * 0.53),
        controlPoint2: NSPoint(x: scale * 0.56, y: scale * 0.55)
    )
    hair.curve(
        to: NSPoint(x: scale * 0.44, y: scale * 0.48),
        controlPoint1: NSPoint(x: scale * 0.55, y: scale * 0.45),
        controlPoint2: NSPoint(x: scale * 0.50, y: scale * 0.49)
    )
    hair.curve(
        to: NSPoint(x: scale * 0.40, y: scale * 0.39),
        controlPoint1: NSPoint(x: scale * 0.42, y: scale * 0.46),
        controlPoint2: NSPoint(x: scale * 0.40, y: scale * 0.43)
    )
    hair.fill()

    NSGraphicsContext.restoreGraphicsState()

    NSColor(red: 0.96, green: 0.78, blue: 0.56, alpha: 1).setStroke()
    let leftArm = NSBezierPath()
    leftArm.lineWidth = scale * 0.055
    leftArm.lineCapStyle = .round
    leftArm.move(to: NSPoint(x: scale * 0.42, y: scale * 0.35))
    leftArm.curve(
        to: NSPoint(x: scale * 0.22, y: scale * 0.55),
        controlPoint1: NSPoint(x: scale * 0.33, y: scale * 0.40),
        controlPoint2: NSPoint(x: scale * 0.27, y: scale * 0.48)
    )
    leftArm.stroke()

    let rightArm = NSBezierPath()
    rightArm.lineWidth = scale * 0.055
    rightArm.lineCapStyle = .round
    rightArm.move(to: NSPoint(x: scale * 0.58, y: scale * 0.35))
    rightArm.curve(
        to: NSPoint(x: scale * 0.78, y: scale * 0.55),
        controlPoint1: NSPoint(x: scale * 0.67, y: scale * 0.40),
        controlPoint2: NSPoint(x: scale * 0.73, y: scale * 0.48)
    )
    rightArm.stroke()

    NSGraphicsContext.saveGraphicsState()
    shadow.set()

    let signRect = NSRect(x: scale * 0.16, y: scale * 0.51, width: scale * 0.68, height: scale * 0.25)
    let sign = NSBezierPath(roundedRect: signRect, xRadius: scale * 0.055, yRadius: scale * 0.055)
    NSColor(red: 0.97, green: 0.98, blue: 0.95, alpha: 1).setFill()
    sign.fill()
    NSColor(red: 0.92, green: 0.72, blue: 0.22, alpha: 1).setStroke()
    sign.lineWidth = scale * 0.018
    sign.stroke()
    NSGraphicsContext.restoreGraphicsState()

    NSColor(red: 0.96, green: 0.78, blue: 0.56, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: scale * 0.18, y: scale * 0.52, width: scale * 0.08, height: scale * 0.08)).fill()
    NSBezierPath(ovalIn: NSRect(x: scale * 0.74, y: scale * 0.52, width: scale * 0.08, height: scale * 0.08)).fill()

    let text = "TEX" as NSString
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: scale * 0.145, weight: .black),
        .foregroundColor: NSColor(red: 0.07, green: 0.21, blue: 0.43, alpha: 1),
        .paragraphStyle: paragraph,
        .kern: scale * 0.004
    ]
    text.draw(
        in: NSRect(x: signRect.minX, y: signRect.minY + scale * 0.048, width: signRect.width, height: signRect.height * 0.68),
        withAttributes: attributes
    )
}
