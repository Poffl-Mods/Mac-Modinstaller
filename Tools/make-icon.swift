import AppKit
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let box = NSRect(x: 70, y: 70, width: 884, height: 884)
let shape = NSBezierPath(roundedRect: box, xRadius: 198, yRadius: 198)
NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.063, alpha: 1).setFill(); shape.fill()
NSColor(calibratedRed: 0.76, green: 0.55, blue: 0.27, alpha: 1).setStroke()
shape.lineWidth = 9; shape.stroke()
// Cogitator insignia: brass cog with a divided flesh/machine skull.
let brass = NSColor(calibratedRed: 0.73, green: 0.59, blue: 0.36, alpha: 1)
brass.setFill()
for tooth in 0..<12 {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: 512, yBy: 512)
    transform.rotate(byDegrees: CGFloat(tooth) * 30)
    transform.concat()
    NSBezierPath(rect: NSRect(x: -39, y: 287, width: 78, height: 110)).fill()
    NSGraphicsContext.restoreGraphicsState()
}
let ring = NSBezierPath(ovalIn: NSRect(x: 202, y: 202, width: 620, height: 620))
ring.lineWidth = 36; brass.setStroke(); ring.stroke()
NSGraphicsContext.saveGraphicsState()
let skullTransform = NSAffineTransform()
skullTransform.translateX(by: 512, yBy: 512)
skullTransform.scale(by: 1.29)
skullTransform.translateX(by: -512, yBy: -565)
skullTransform.concat()
let skull = NSBezierPath()
skull.move(to: NSPoint(x: 400, y: 475))
skull.curve(to: NSPoint(x: 365, y: 635), controlPoint1: NSPoint(x: 340, y: 510), controlPoint2: NSPoint(x: 350, y: 605))
skull.curve(to: NSPoint(x: 659, y: 635), controlPoint1: NSPoint(x: 380, y: 795), controlPoint2: NSPoint(x: 644, y: 795))
skull.curve(to: NSPoint(x: 624, y: 475), controlPoint1: NSPoint(x: 674, y: 605), controlPoint2: NSPoint(x: 684, y: 510))
skull.line(to: NSPoint(x: 605, y: 416)); skull.line(to: NSPoint(x: 419, y: 416)); skull.close()
NSColor(calibratedRed: 0.91, green: 0.86, blue: 0.74, alpha: 1).setFill(); skull.fill()
NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.063, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 403, y: 557, width: 72, height: 56)).fill()
NSBezierPath(ovalIn: NSRect(x: 549, y: 557, width: 72, height: 56)).fill()
NSBezierPath(rect: NSRect(x: 505, y: 413, width: 14, height: 312)).fill()
for x in [448, 478, 538, 568] { NSBezierPath(rect: NSRect(x: x, y: 416, width: 8, height: 32)).fill() }
NSColor(calibratedRed: 0.56, green: 0.83, blue: 0.63, alpha: 1).setStroke()
let eye = NSBezierPath(ovalIn: NSRect(x: 552, y: 552, width: 67, height: 67)); eye.lineWidth = 12; eye.stroke()
NSGraphicsContext.restoreGraphicsState()
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
