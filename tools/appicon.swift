import AppKit
// App icon: stylized Bay Area transit map on Caltrain red.
// A darker "bay" sits center-right; a white route line with station rings runs
// down the peninsula from SF (top-left) to San Jose (bottom), BART-style.
let a = CommandLine.arguments   // out dir
func bitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep { return NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)! }
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { return NSColor(calibratedRed: r/255, green: g/255, blue: b/255, alpha: 1) }

func icon(_ size: Int, _ path: String) {
    let rep = bitmap(size, size); NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size); let u = s / 100          // 100-unit design grid
    func P(_ x: CGFloat, _ y: CGFloat) -> NSPoint { return NSPoint(x: x * u, y: s - y * u) }  // y down
    // ground: Caltrain red, slightly deeper toward the bottom
    NSGradient(starting: rgb(232, 28, 48), ending: rgb(188, 8, 30))!.draw(in: NSRect(x: 0, y: 0, width: s, height: s), angle: -90)
    // bay water: darker red, elongated and tilted like SF Bay
    let bay = NSBezierPath()
    bay.move(to: P(44, -4))
    bay.curve(to: P(82, 34), controlPoint1: P(62, 2), controlPoint2: P(84, 16))
    bay.curve(to: P(60, 82), controlPoint1: P(80, 54), controlPoint2: P(70, 74))
    bay.curve(to: P(37, 42), controlPoint1: P(50, 78), controlPoint2: P(37, 64))
    bay.curve(to: P(44, -4), controlPoint1: P(37, 22), controlPoint2: P(40, 6))
    bay.close()
    rgb(150, 0, 22).setFill(); bay.fill()
    // a lighter shoreline edge so the bay reads as water
    rgb(255, 120, 130).withAlphaComponent(0.35).setStroke(); bay.lineWidth = 1.2 * u; bay.stroke()
    // thinner transbay line: SF across the bay, then down the east shore
    let east = NSBezierPath()
    east.move(to: P(20, 12))
    east.curve(to: P(86, 36), controlPoint1: P(48, 4), controlPoint2: P(84, 10))
    east.curve(to: P(60, 90), controlPoint1: P(88, 58), controlPoint2: P(84, 86))
    east.lineWidth = 5 * u; east.lineCapStyle = .round
    NSColor(white: 0, alpha: 0.15).setStroke()
    let esh = east.copy() as! NSBezierPath; esh.transform(using: AffineTransform(translationByX: 0, byY: -1.2 * u)); esh.stroke()
    NSColor(white: 1, alpha: 0.92).setStroke(); east.stroke()
    // route line down the peninsula: SF -> SJ
    let line = NSBezierPath()
    line.move(to: P(20, 12))
    line.curve(to: P(58, 90), controlPoint1: P(22, 44), controlPoint2: P(36, 76))
    line.lineWidth = 9 * u; line.lineCapStyle = .round
    // soft shadow under the line
    NSColor(white: 0, alpha: 0.18).setStroke()
    let sh = line.copy() as! NSBezierPath; sh.transform(using: AffineTransform(translationByX: 0, byY: -1.5 * u)); sh.stroke()
    NSColor.white.setStroke(); line.stroke()
    // stations: hollow rings on the line (big at termini, interchange in the middle)
    func ring(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ w: CGFloat) {
        let c = P(x, y)
        let p = NSBezierPath(ovalIn: NSRect(x: c.x - r * u, y: c.y - r * u, width: 2 * r * u, height: 2 * r * u))
        NSColor.white.setFill(); p.fill()
        let inner = NSBezierPath(ovalIn: NSRect(x: c.x - (r - w) * u, y: c.y - (r - w) * u, width: 2 * (r - w) * u, height: 2 * (r - w) * u))
        rgb(210, 16, 40).setFill(); inner.fill()
    }
    ring(20, 12, 9, 3.2)       // San Francisco
    ring(24.5, 38, 5.5, 2.4)   // Millbrae-ish
    ring(33, 61, 5.5, 2.4)     // Palo Alto-ish
    ring(58, 90, 9, 3.2)       // San Jose
    ring(86, 36, 4.2, 1.9)     // Oakland-ish
    ring(84, 68, 4.2, 1.9)     // Fremont-ish
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
icon(57, a[1] + "/Icon.png"); icon(114, a[1] + "/Icon@2x.png"); icon(256, a[1] + "/Icon-preview.png"); print("icon ok")
