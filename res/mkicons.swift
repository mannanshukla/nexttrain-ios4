import AppKit
func bitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep { return NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)! }
func save(_ rep: NSBitmapImageRep, _ path: String) { try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path)) }
func train(_ s: CGFloat, _ color: NSColor) {   // front view of a train: body, windshield, headlights, rails
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: s*0.22, y: s*0.26, width: s*0.56, height: s*0.56), xRadius: s*0.14, yRadius: s*0.14).fill()
    NSColor(white: 1, alpha: 0.0).setFill()
    let win = NSBezierPath(roundedRect: NSRect(x: s*0.30, y: s*0.52, width: s*0.40, height: s*0.20), xRadius: s*0.05, yRadius: s*0.05)
    NSGraphicsContext.current?.cgContext.setBlendMode(.destinationOut); win.fill()
    for x in [s*0.30, s*0.60] { NSBezierPath(ovalIn: NSRect(x: x, y: s*0.33, width: s*0.10, height: s*0.10)).fill() }
    NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
    color.setFill()
    for x in [s*0.12, s*0.80] { NSBezierPath(roundedRect: NSRect(x: x, y: s*0.08, width: s*0.08, height: s*0.14), xRadius: s*0.03, yRadius: s*0.03).fill() }
    NSBezierPath(roundedRect: NSRect(x: s*0.26, y: s*0.10, width: s*0.48, height: s*0.08), xRadius: s*0.03, yRadius: s*0.03).fill()
}
func icon(_ size: Int, _ path: String) {
    let rep = bitmap(size, size); NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)
    NSGradient(starting: NSColor(deviceRed: 0.90, green: 0.18, blue: 0.26, alpha: 1), ending: NSColor(deviceRed: 0.68, green: 0.06, blue: 0.14, alpha: 1))!.draw(in: NSRect(x: 0, y: 0, width: s, height: s), angle: -90)
    train(s, .white)
    NSGraphicsContext.restoreGraphicsState(); save(rep, path)
}
icon(57, "Icon.png"); icon(114, "Icon@2x.png"); icon(256, "Icon-preview.png")
func glyph(_ name: String, _ draw: (CGFloat) -> Void) { for (sz, suf) in [(30, ""), (60, "@2x")] { let rep = bitmap(sz, sz); NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep); NSColor.white.set(); draw(CGFloat(sz)); NSGraphicsContext.restoreGraphicsState(); save(rep, "\(name)\(suf).png") } }
glyph("tab-departures") { s in train(s, .white) }
glyph("tab-trip") { s in let p = NSBezierPath(); p.lineWidth = s*0.1; p.lineCapStyle = .round; p.move(to: NSPoint(x: s*0.22, y: s*0.22)); p.line(to: NSPoint(x: s*0.78, y: s*0.78)); p.stroke(); NSBezierPath(ovalIn: NSRect(x: s*0.06, y: s*0.06, width: s*0.32, height: s*0.32)).fill(); let o = NSBezierPath(ovalIn: NSRect(x: s*0.64, y: s*0.64, width: s*0.30, height: s*0.30)); o.lineWidth = s*0.08; o.stroke() }
glyph("tab-line") { s in let p = NSBezierPath(); p.lineWidth = s*0.14; p.lineCapStyle = .round; p.move(to: NSPoint(x: s*0.5, y: s*0.12)); p.line(to: NSPoint(x: s*0.5, y: s*0.88)); p.stroke(); NSColor.white.setFill(); for y in [s*0.2, s*0.5, s*0.8] { let o = NSBezierPath(ovalIn: NSRect(x: s*0.5-s*0.13, y: y-s*0.13, width: s*0.26, height: s*0.26)); o.fill() }; NSGraphicsContext.current?.cgContext.setBlendMode(.destinationOut); for y in [s*0.2, s*0.5, s*0.8] { NSBezierPath(ovalIn: NSRect(x: s*0.5-s*0.06, y: y-s*0.06, width: s*0.12, height: s*0.12)).fill() }; NSGraphicsContext.current?.cgContext.setBlendMode(.normal) }
print("icons ok")
