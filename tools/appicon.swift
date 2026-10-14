import AppKit
// App icon: the AIGA / DOT "rail transportation" pictogram (public domain) in
// white on Caltrain red. Geometry transcribed from the 310x475 SVG.
let a = CommandLine.arguments   // out dir
func bitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep { return NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)! }
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { return NSColor(calibratedRed: r/255, green: g/255, blue: b/255, alpha: 1) }

func icon(_ size: Int, _ path: String) {
    let rep = bitmap(size, size); NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)
    NSGradient(starting: rgb(238, 40, 60), ending: rgb(198, 10, 34))!.draw(in: NSRect(x: 0, y: 0, width: s, height: s), angle: -90)
    // glyph box 310x475 scaled to ~80% of the icon height, centered
    let k = s * 0.80 / 475, gw = 310 * k, gh = 475 * k, ox = (s - gw) / 2, oy = (s - gh) / 2
    func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ rx: CGFloat) -> NSBezierPath {   // svg coords, y down
        return NSBezierPath(roundedRect: NSRect(x: ox + x * k, y: s - oy - (y + h) * k, width: w * k, height: h * k), xRadius: rx * k, yRadius: rx * k)
    }
    func C(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> NSBezierPath { return NSBezierPath(ovalIn: NSRect(x: ox + (cx - r) * k, y: s - oy - (cy + r) * k, width: 2 * r * k, height: 2 * r * k)) }
    let white = NSColor.white, glass = rgb(150, 0, 26)
    // soft drop shadow for the body
    NSColor(white: 0, alpha: 0.22).setFill()
    let sh = R(20, 40, 270, 330, 65); sh.transform(using: AffineTransform(translationByX: 0, byY: -s * 0.012)); sh.fill()
    white.setFill()
    R(20, 40, 270, 330, 65).fill()                       // body
    C(135, 20, 15).fill(); C(175, 20, 15).fill()         // pantograph knobs
    let legs = NSBezierPath()                            // rails / skirt polygon
    let pts: [(CGFloat, CGFloat)] = [(0,475),(70,360),(240,360),(310,475),(265,475),(220,400),(90,400),(45,475)]
    for (i, p) in pts.enumerated() { let q = NSPoint(x: ox + p.0 * k, y: s - oy - p.1 * k); if i == 0 { legs.move(to: q) } else { legs.line(to: q) } }
    legs.close(); legs.fill()
    glass.setFill()
    R(55, 100, 200, 100, 30).fill()                      // windshield
    R(115, 50, 80, 40, 10).fill()                        // destination sign
    C(85, 315, 25).fill(); C(225, 315, 25).fill()        // headlights
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
icon(57, a[1] + "/Icon.png"); icon(114, a[1] + "/Icon@2x.png"); icon(256, a[1] + "/Icon-preview.png"); print("icon ok")
