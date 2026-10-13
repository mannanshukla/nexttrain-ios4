import AppKit
// Composite app icon: the three agency logos stacked on white, rounded.
let a = CommandLine.arguments   // logos dir, out dir
func bitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep { return NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)! }
let logos = ["logo-caltrain.png", "logo-bart.png", "logo-muni.png"].map { NSImage(contentsOfFile: a[1] + "/" + $0)! }
func icon(_ size: Int, _ path: String) {
    let rep = bitmap(size, size); NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)
    NSGradient(starting: NSColor(white: 1, alpha: 1), ending: NSColor(white: 0.90, alpha: 1))!.draw(in: NSRect(x: 0, y: 0, width: s, height: s), angle: -90)
    let rowH = s / 3, pad = s * 0.10
    for (i, img) in logos.enumerated() {
        let boxW = s - 2 * pad, boxH = rowH - s * 0.07
        let ratio = img.size.width / img.size.height
        var w = boxW, h = w / ratio; if h > boxH { h = boxH; w = h * ratio }
        let y = s - rowH * CGFloat(i + 1) + (rowH - h) / 2
        img.draw(in: NSRect(x: (s - w) / 2, y: y, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1)
        if i < 2 { NSColor(white: 0.8, alpha: 1).setFill(); NSRect(x: pad, y: s - rowH * CGFloat(i + 1), width: s - 2 * pad, height: max(1, s * 0.008)).fill() }
    }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
icon(57, a[2] + "/Icon.png"); icon(114, a[2] + "/Icon@2x.png"); icon(256, a[2] + "/Icon-preview.png"); print("icon ok")
