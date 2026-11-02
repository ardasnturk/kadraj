// Draws the Kadraj app icon and writes Resources/AppIcon.icns.
//   swift scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func linearGradient(_ ctx: CGContext, in path: CGPath, colors: [CGColor], from: CGPoint, to: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func drawIcon(_ ctx: CGContext) {
    // Body: the standard macOS icon grid, an 824pt rounded square with a soft drop shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0x241F5C))
    ctx.fillPath()
    ctx.restoreGState()
    linearGradient(ctx, in: bodyPath, colors: [color(0x6A4CF0), color(0x2A1F72)],
                   from: CGPoint(x: body.minX, y: body.maxY), to: CGPoint(x: body.maxX, y: body.minY))

    // Faint top sheen.
    linearGradient(ctx, in: bodyPath, colors: [color(0xFFFFFF, 0.16), color(0xFFFFFF, 0)],
                   from: CGPoint(x: 0, y: body.maxY), to: CGPoint(x: 0, y: body.midY))

    // The framed subject: a warm card, tilted slightly as if just caught.
    let card = CGRect(x: 0, y: 0, width: 360, height: 280)
    ctx.saveGState()
    ctx.translateBy(x: body.midX, y: body.midY)
    ctx.rotate(by: -0.06)
    ctx.translateBy(x: -card.width / 2, y: -card.height / 2)
    let cardPath = CGPath(roundedRect: card, cornerWidth: 44, cornerHeight: 44, transform: nil)
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0x10082E, 0.55))
    ctx.addPath(cardPath)
    ctx.setFillColor(color(0xFF8A3D))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    linearGradient(ctx, in: cardPath, colors: [color(0xFFC24B), color(0xFF5E62)],
                   from: CGPoint(x: 0, y: card.maxY), to: CGPoint(x: card.maxX, y: 0))
    // A sun and a hill, so the card reads as a picture.
    ctx.setFillColor(color(0xFFFFFF, 0.92))
    ctx.fillEllipse(in: CGRect(x: 238, y: 162, width: 70, height: 70))
    let hill = CGMutablePath()
    hill.move(to: CGPoint(x: 0, y: 0))
    hill.addLine(to: CGPoint(x: 0, y: 92))
    hill.addCurve(to: CGPoint(x: 360, y: 70), control1: CGPoint(x: 110, y: 190), control2: CGPoint(x: 230, y: 20))
    hill.addLine(to: CGPoint(x: 360, y: 0))
    hill.closeSubpath()
    ctx.saveGState()
    ctx.addPath(cardPath)
    ctx.clip()
    ctx.addPath(hill)
    ctx.setFillColor(color(0xFFFFFF, 0.38))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.restoreGState()

    // Viewfinder corners framing the card.
    let frame = body.insetBy(dx: 150, dy: 150)
    let arm: CGFloat = 118
    let corners = CGMutablePath()
    for (x, y, dx, dy) in [(frame.minX, frame.minY, 1.0, 1.0), (frame.maxX, frame.minY, -1.0, 1.0),
                           (frame.minX, frame.maxY, 1.0, -1.0), (frame.maxX, frame.maxY, -1.0, -1.0)] {
        corners.move(to: CGPoint(x: x, y: y + dy * arm))
        corners.addLine(to: CGPoint(x: x, y: y))
        corners.addLine(to: CGPoint(x: x + dx * arm, y: y))
    }
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 12, color: color(0x10082E, 0.4))
    ctx.addPath(corners)
    ctx.setStrokeColor(color(0xFFFFFF))
    ctx.setLineWidth(40)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawIcon(ctx)
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
try png(size: 1024).write(to: root.appendingPathComponent("Resources/AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
print("Wrote Resources/AppIcon.icns")
