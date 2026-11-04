// Renders the app icon PNGs from the rat SVG. Usage: swift scripts/render-icon.swift <svg> <outDir>
import AppKit

let rat = NSImage(contentsOfFile: CommandLine.arguments[1])!
let outDir = CommandLine.arguments[2]

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let body = NSRect(x: s * 0.098, y: s * 0.098, width: s * 0.804, height: s * 0.804)
    let path = NSBezierPath(roundedRect: body, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(colors: [NSColor(calibratedRed: 0.36, green: 0.55, blue: 0.98, alpha: 1),
                        NSColor(calibratedRed: 0.13, green: 0.25, blue: 0.75, alpha: 1)])!.draw(in: path, angle: -90)
    let w = body.width * 0.8, h = w * 366 / 377
    rat.draw(in: NSRect(x: body.midX - w / 2, y: body.midY - h / 2, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16", 16), ("32", 32), ("64", 64), ("128", 128), ("256", 256), ("512", 512), ("1024", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(outDir)/icon_\(name).png"))
}
