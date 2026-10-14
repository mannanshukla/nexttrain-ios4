import AppKit
// Stylized Caltrain mark: the red disc with heavy italic lettering, stacked.
let a = CommandLine.arguments   // out dir [, font name]
func bitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep { return NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)! }
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { return NSColor(calibratedRed: r/255, green: g/255, blue: b/255, alpha: 1) }
let fontName = a.count > 2 ? a[2] : "Helvetica-BoldOblique"
func icon(_ size: Int, _ path: String) {
    let rep = bitmap(size, size); NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size); let u = s / 100
    NSGradient(starting: rgb(240, 44, 64), ending: rgb(205, 12, 38))!.draw(in: NSRect(x: 0, y: 0, width: s, height: s), angle: -90)
    // the disc: deeper red, slightly right of center like the wordmark's emblem
    let disc = NSBezierPath(ovalIn: NSRect(x: 16 * u, y: 8 * u, width: 84 * u, height: 84 * u))
    NSColor(white: 0, alpha: 0.18).setFill(); let dsh = disc.copy() as! NSBezierPath; dsh.transform(using: AffineTransform(translationByX: 0, byY: -1.5 * u)); dsh.fill()
    rgb(132, 0, 18).setFill(); disc.fill()
    func word(_ t: String, _ color: NSColor, _ pt: CGFloat, _ x: CGFloat, _ y: CGFloat) {
        let f = NSFont(name: fontName, size: pt * u) ?? NSFont.boldSystemFont(ofSize: pt * u)
        let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color, .kern: -1.2 * u]
        let str = NSAttributedString(string: t, attributes: attrs)
        let sz = str.size()
        str.draw(at: NSPoint(x: x * u, y: s - y * u - sz.height))
    }
    word("Cal", NSColor.black, 37, 4, 17)
    word("train", NSColor.white, 37, 13, 49)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
icon(57, a[1] + "/Icon.png"); icon(114, a[1] + "/Icon@2x.png"); icon(256, a[1] + "/Icon-preview.png"); print("icon ok")
