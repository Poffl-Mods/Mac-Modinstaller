import AppKit
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let box = NSRect(x: 70, y: 70, width: 884, height: 884)
let shape = NSBezierPath(roundedRect: box, xRadius: 198, yRadius: 198)
NSColor(calibratedRed: 0.14, green: 0.17, blue: 0.19, alpha: 1).setFill(); shape.fill()
NSColor(calibratedRed: 0.76, green: 0.55, blue: 0.27, alpha: 1).setStroke()
shape.lineWidth = 9; shape.stroke()
let symbol = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: nil)!
let config = NSImage.SymbolConfiguration(pointSize: 410, weight: .regular).applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(calibratedRed: 0.83, green: 0.66, blue: 0.39, alpha: 1)]))
let configured = symbol.withSymbolConfiguration(config)!
configured.draw(in: NSRect(x: 260, y: 295, width: 504, height: 455))
let label = "MODS"
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 75, weight: .bold), .foregroundColor: NSColor(calibratedWhite: 0.93, alpha: 1), .kern: 15]
let width = label.size(withAttributes: attrs).width
label.draw(at: NSPoint(x: (1024-width)/2, y: 170), withAttributes: attrs)
image.unlockFocus()
let dir = URL(fileURLWithPath: CommandLine.arguments[1]); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for points in [16,32,128,256,512] {
 for scale in [1,2] {
  let pixels = points*scale
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  image.draw(in: NSRect(x:0,y:0,width:pixels,height:pixels)); NSGraphicsContext.restoreGraphicsState()
  try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"))
 }
}
