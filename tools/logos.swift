import AppKit
// Usage: swift logos.swift <svg> <outbase>  : renders color PNG (200px tall) and white-silhouette tab icons (30/60 px, alpha only)
let a = CommandLine.arguments
let img = NSImage(contentsOfFile: a[1])!
func render(_ h: CGFloat, silhouette: Bool, path: String) {
    let ratio = img.size.width / img.size.height; let w = h * ratio
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w.rounded()), pixelsHigh: Int(h), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: w.rounded(), height: h), from: .zero, operation: .sourceOver, fraction: 1)
    if silhouette { NSColor.white.set(); NSRect(x: 0, y: 0, width: w.rounded(), height: h).fill(using: .sourceIn) }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
render(200, silhouette: false, path: a[2] + ".png")
// tab icons: fit into a 30x30 box (max dimension 30), silhouette
func tab(_ box: CGFloat, path: String) {
    let ratio = img.size.width / img.size.height; let w = ratio >= 1 ? box : box * ratio, h = ratio >= 1 ? box / ratio : box
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(box), pixelsHigh: Int(box), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: (box - w) / 2, y: (box - h) / 2, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    // silhouette: colored (non-white) pixels become opaque white, white lettering becomes transparent. Raw RGBA, premultiplied.
    let bpr = rep.bytesPerRow, data = rep.bitmapData!
    for y in 0..<Int(box) { for x in 0..<Int(box) {
        let p = data + y * bpr + x * 4
        let a = CGFloat(p[3]) / 255
        let r = a > 0 ? CGFloat(p[0]) / 255 / a : 0, g = a > 0 ? CGFloat(p[1]) / 255 / a : 0, b = a > 0 ? CGFloat(p[2]) / 255 / a : 0
        let lum = 0.299*r + 0.587*g + 0.114*b
        let on: UInt8 = (a > 0.3 && lum < 0.85) ? 255 : 0
        p[0] = on; p[1] = on; p[2] = on; p[3] = on
    } }
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
tab(30, path: a[2] + "-tab.png"); tab(60, path: a[2] + "-tab@2x.png")
print("ok", img.size)
