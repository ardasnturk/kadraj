// Draws the DMG window background and writes it to the path given as the first argument (a TIFF
// holding 1x and 2x images). Icon positions must match scripts/dmg-settings.py.
//   swift scripts/make-dmg-background.swift build/dmg-background.tiff
import AppKit

let size = CGSize(width: 640, height: 400)
let appCenter = CGPoint(x: 170, y: 200)      // top-left origin, like dmg-settings.py
let linkCenter = CGPoint(x: 470, y: 200)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func draw() {
    // Flip so coordinates match Finder's top-left origin.
    let flip = NSAffineTransform()
    flip.translateX(by: 0, yBy: size.height)
    flip.scaleX(by: 1, yBy: -1)
    flip.concat()

    NSGradient(colors: [color(0xF7F5FF), color(0xE9E4FF)])!
        .draw(in: CGRect(origin: .zero, size: size), angle: 90)

    // Soft glows behind the two icons.
    for center in [appCenter, linkCenter] {
        let glow = NSGradient(colors: [color(0xFFFFFF, 0.9), color(0xFFFFFF, 0)])!
        glow.draw(fromCenter: center, radius: 0, toCenter: center, radius: 110, options: [])
    }

    // Curved, dashed arrow from the app to Applications.
    let start = CGPoint(x: appCenter.x + 88, y: appCenter.y - 6)
    let end = CGPoint(x: linkCenter.x - 92, y: linkCenter.y - 6)
    let arrow = NSBezierPath()
    arrow.move(to: start)
    arrow.curve(to: end, controlPoint1: CGPoint(x: start.x + 40, y: start.y - 38),
                controlPoint2: CGPoint(x: end.x - 40, y: end.y - 38))
    arrow.lineWidth = 5
    arrow.lineCapStyle = .round
    arrow.setLineDash([2, 13], count: 2, phase: 0)
    color(0x6A4CF0).setStroke()
    arrow.stroke()

    // Arrowhead along the curve's final tangent (end minus its last control point).
    let angle = atan2(38.0, 40.0)
    let wing: CGFloat = 20
    let head = NSBezierPath()
    for (i, spread) in [CGFloat.pi * 0.8, -CGFloat.pi * 0.8].enumerated() {
        let point = CGPoint(x: end.x + wing * cos(angle + spread), y: end.y + wing * sin(angle + spread))
        if i == 0 { head.move(to: point); head.line(to: end) } else { head.line(to: point) }
    }
    head.lineWidth = 5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    // Caption under the icons.
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let caption = NSAttributedString(string: "Drag Kadraj into Applications to install", attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: color(0x4B3F8F),
        .paragraphStyle: paragraph,
    ])
    // NSString drawing expects a flipped context to be marked as such.
    NSGraphicsContext.current = NSGraphicsContext(cgContext: NSGraphicsContext.current!.cgContext, flipped: true)
    caption.draw(in: CGRect(x: 0, y: 318, width: size.width, height: 24))
}

func image(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let tiff = NSBitmapImageRep.tiffRepresentationOfImageReps(in: [image(scale: 1), image(scale: 2)], using: .lzw, factor: 0)!
try tiff.write(to: output)
print("Wrote \(output.path)")
