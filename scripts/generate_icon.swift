import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSColor(red: 0.97, green: 0.95, blue: 0.91, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
NSColor(red: 0.86, green: 0.85, blue: 0.79, alpha: 1).setStroke()
for radius in [360.0, 316.0] {
    let path = NSBezierPath(ovalIn: NSRect(x: 512-radius, y: 512-radius, width: radius*2, height: radius*2))
    path.lineWidth = 2; path.stroke()
}
NSColor(red: 0.38, green: 0.46, blue: 0.36, alpha: 1).setStroke()
let ring = NSBezierPath()
ring.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 262, startAngle: 90, endAngle: -183, clockwise: true)
ring.lineWidth = 15; ring.lineCapStyle = .round; ring.stroke()
NSColor(red: 0.20, green: 0.23, blue: 0.20, alpha: 1).setFill()
for x in [457, 539] { NSBezierPath(roundedRect: NSRect(x: x, y: 439, width: 27, height: 146), xRadius: 13.5, yRadius: 13.5).fill() }
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("AppIcon.png"))
