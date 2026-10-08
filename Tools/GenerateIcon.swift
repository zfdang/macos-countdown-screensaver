import AppKit
import Foundation

// Deterministic vector artwork rendered at each macOS icon resolution.
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let pixels = size * scale
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let p = CGFloat(pixels)
    let tile = NSBezierPath(
      roundedRect: NSRect(x: p * 0.06, y: p * 0.06, width: p * 0.88, height: p * 0.88),
      xRadius: p * 0.20, yRadius: p * 0.20)
    NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.14, alpha: 1).setFill()
    tile.fill()
    let ring = NSBezierPath()
    ring.appendArc(
      withCenter: NSPoint(x: p / 2, y: p / 2), radius: p * 0.30, startAngle: 90, endAngle: 390,
      clockwise: false)
    ring.lineWidth = p * 0.035
    ring.lineCapStyle = .round
    NSColor(calibratedRed: 0.35, green: 0.79, blue: 0.91, alpha: 1).setStroke()
    ring.stroke()
    let hands = NSBezierPath()
    hands.move(to: NSPoint(x: p * 0.50, y: p * 0.70))
    hands.line(to: NSPoint(x: p * 0.50, y: p * 0.50))
    hands.line(to: NSPoint(x: p * 0.64, y: p * 0.43))
    hands.lineWidth = p * 0.035
    hands.lineCapStyle = .round
    hands.lineJoinStyle = .round
    NSColor.white.setStroke()
    hands.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 2 ? "@2x" : ""
    try bitmap.representation(using: .png, properties: [:])!.write(
      to: URL(fileURLWithPath: "\(directory)/icon_\(size)x\(size)\(suffix).png"))
  }
}
