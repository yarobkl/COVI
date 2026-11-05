import AppKit
import CoreGraphics
import Foundation

// Full-resolution COVI iPhone splash, using the approved beige background and
// the existing official logo shapes. No private asset or downloaded font needed.
guard CommandLine.arguments.count == 2 else {
  fputs("Usage: swift make-covi-splash.swift OUTPUT.png\n", stderr)
  exit(1)
}

let side = 2732
let space = CGColorSpaceCreateDeviceRGB()
guard let c = CGContext(
  data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
  fatalError("COVI splash: cannot initialize CoreGraphics")
}

c.setFillColor(CGColor(red: 241 / 255, green: 233 / 255, blue: 221 / 255, alpha: 1))
c.fill(CGRect(x: 0, y: 0, width: side, height: side))

let icon = CGFloat(480)
c.saveGState()
c.translateBy(x: (CGFloat(side) - icon) / 2, y: (CGFloat(side) - icon) / 2)
c.scaleBy(x: icon / 1024, y: icon / 1024)

let rounded = CGPath(
  roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024),
  cornerWidth: 230, cornerHeight: 230, transform: nil
)
c.addPath(rounded)
c.setFillColor(CGColor(red: 23 / 255, green: 64 / 255, blue: 139 / 255, alpha: 1))
c.fillPath()

c.setStrokeColor(CGColor(red: 252 / 255, green: 251 / 255, blue: 248 / 255, alpha: 1))
c.setLineWidth(136)
c.setLineCap(.round)
c.addArc(
  center: CGPoint(x: 512, y: 512), radius: 270,
  startAngle: CGFloat(49) * .pi / 180,
  endAngle: CGFloat(311) * .pi / 180,
  clockwise: false
)
c.strokePath()
c.setFillColor(CGColor(red: 255 / 255, green: 210 / 255, blue: 63 / 255, alpha: 1))
c.fillEllipse(in: CGRect(x: 604, y: 416, width: 192, height: 192))
c.restoreGState()

guard let image = c.makeImage() else { fatalError("COVI splash: render failed") }
let bitmap = NSBitmapImageRep(cgImage: image)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
  fatalError("COVI splash: PNG encoding failed")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
