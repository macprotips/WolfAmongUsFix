// Draws Resources/AppIcon.iconset:  swift Tools/make_icon.swift Resources/AppIcon.iconset
// A neon pink gear on deep plum.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let neon = NSColor(srgbRed: 1.0, green: 0.22, blue: 0.62, alpha: 1).cgColor
let core = NSColor(srgbRed: 1.0, green: 0.72, blue: 0.86, alpha: 1).cgColor

/// A gear outline: `teeth` flat-topped teeth between radii `inner` and `outer`, centered at 512,512.
func gear(teeth: Int, inner: CGFloat, outer: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let step = 2 * CGFloat.pi / CGFloat(teeth)
    func point(_ r: CGFloat, _ a: CGFloat) -> CGPoint { CGPoint(x: 512 + r * cos(a), y: 512 + r * sin(a)) }
    for i in 0..<teeth {
        let a = CGFloat(i) * step - .pi / 2
        let pts = [point(inner, a - step * 0.30), point(outer, a - step * 0.20),
                   point(outer, a + step * 0.20), point(inner, a + step * 0.30)]
        if i == 0 { path.move(to: pts[0]) } else { path.addLine(to: pts[0]) }
        pts.dropFirst().forEach { path.addLine(to: $0) }
        path.addArc(center: CGPoint(x: 512, y: 512), radius: inner, startAngle: a + step * 0.30,
                    endAngle: a + step * 0.70, clockwise: false)
    }
    path.closeSubpath()
    return path
}

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)

    // macOS icon grid: 824 x 824 body, corner radius 185, soft shadow
    let body = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 18, color: NSColor(white: 0, alpha: 0.4).cgColor)
    ctx.addPath(body)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    let plum = CGGradient(colorsSpace: nil, colors: [NSColor(srgbRed: 0.33, green: 0.07, blue: 0.24, alpha: 1).cgColor,
                                                     NSColor(srgbRed: 0.13, green: 0.03, blue: 0.11, alpha: 1).cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(plum, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // the gear, as a neon tube: a wide soft glow, then the tube, then its bright core
    let shape = CGMutablePath()
    shape.addPath(gear(teeth: 8, inner: 206, outer: 276))
    shape.addEllipse(in: CGRect(x: 512 - 90, y: 512 - 90, width: 180, height: 180))
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    for (width, color, blur) in [(CGFloat(40), neon, CGFloat(60)), (40, neon, 14), (12, core, 0)] {
        ctx.saveGState()
        if blur > 0 { ctx.setShadow(offset: .zero, blur: blur, color: neon) }
        ctx.addPath(shape)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.strokePath()
        ctx.restoreGState()
    }
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        try draw(size * scale).write(to: out.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
try draw(1024).write(to: out.deletingLastPathComponent().appendingPathComponent("icon-preview.png"))
