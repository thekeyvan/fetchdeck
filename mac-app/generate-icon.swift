import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
  fputs("Usage: generate-icon.swift OUTPUT.png\n", stderr)
  exit(2)
}

let canvasSize = NSSize(width: 1024, height: 1024)
let image = NSImage(size: canvasSize)
image.lockFocus()

NSColor.clear.setFill()
NSRect(origin: .zero, size: canvasSize).fill()

let tileRect = NSRect(x: 52, y: 52, width: 920, height: 920)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 215, yRadius: 215)
let gradient = NSGradient(
  starting: NSColor(
    calibratedRed: 0.08,
    green: 0.52,
    blue: 0.98,
    alpha: 1
  ),
  ending: NSColor(
    calibratedRed: 0.31,
    green: 0.22,
    blue: 0.88,
    alpha: 1
  )
)!
gradient.draw(in: tile, angle: -55)

NSColor.white.withAlphaComponent(0.1).setFill()
NSBezierPath(ovalIn: NSRect(x: 112, y: 442, width: 800, height: 430)).fill()

func card(
  _ rect: NSRect,
  fill: NSColor,
  strokeAlpha: CGFloat
) {
  let path = NSBezierPath(roundedRect: rect, xRadius: 68, yRadius: 68)
  fill.setFill()
  path.fill()
  NSColor.white.withAlphaComponent(strokeAlpha).setStroke()
  path.lineWidth = 5
  path.stroke()
}

card(
  NSRect(x: 232, y: 584, width: 560, height: 214),
  fill: NSColor.white.withAlphaComponent(0.16),
  strokeAlpha: 0.2
)
card(
  NSRect(x: 198, y: 494, width: 628, height: 250),
  fill: NSColor.white.withAlphaComponent(0.28),
  strokeAlpha: 0.25
)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
shadow.shadowBlurRadius = 34
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.set()
card(
  NSRect(x: 160, y: 238, width: 704, height: 426),
  fill: NSColor.white.withAlphaComponent(0.96),
  strokeAlpha: 0.5
)
NSGraphicsContext.restoreGraphicsState()

let accent = NSColor(
  calibratedRed: 0.16,
  green: 0.38,
  blue: 0.93,
  alpha: 1
)
accent.withAlphaComponent(0.14).setFill()
NSBezierPath(
  roundedRect: NSRect(x: 256, y: 544, width: 210, height: 34),
  xRadius: 17,
  yRadius: 17
).fill()
NSBezierPath(
  roundedRect: NSRect(x: 256, y: 492, width: 330, height: 24),
  xRadius: 12,
  yRadius: 12
).fill()

accent.setFill()
NSBezierPath(
  roundedRect: NSRect(x: 462, y: 364, width: 100, height: 190),
  xRadius: 50,
  yRadius: 50
).fill()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 342, y: 416))
arrowHead.line(to: NSPoint(x: 682, y: 416))
arrowHead.line(to: NSPoint(x: 512, y: 286))
arrowHead.close()
arrowHead.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
  let bitmap = NSBitmapImageRep(data: tiff),
  let png = bitmap.representation(using: .png, properties: [:])
else {
  fputs("Could not render app icon.\n", stderr)
  exit(1)
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
