import AppKit
import CoreGraphics
import Foundation

// COVI's real brand mark, rasterized at App Store resolution without upscaling a 180px image.
// iOS applies the rounded-corner mask; an opaque square is required for an App Store icon.
guard CommandLine.arguments.count == 2 else {
  fputs("Usage: swift make-covi-icon.swift OUTPUT.png\n", stderr)
  exit(1)
}

let width = 1024
let space = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
  data: nil,
  width: width,
  height: width,
  bitsPerComponent: 8,
  bytesPerRow: 0,
  space: space,
  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
  fatalError("Could not create graphics context")
}

context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)
context.setFillColor(CGColor(red: 23 / 255, green: 64 / 255, blue: 139 / 255, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: width))

// The open C shape follows the SVG source in public/favicon.svg.
context.setStrokeColor(CGColor(red: 252 / 255, green: 251 / 255, blue: 248 / 255, alpha: 1))
context.setLineWidth(136)
context.setLineCap(.round)
context.addArc(
  center: CGPoint(x: 512, y: 512),
  radius: 270,
  startAngle: CGFloat(49) * .pi / 180,
  endAngle: CGFloat(311) * .pi / 180,
  clockwise: false
)
context.strokePath()

context.setFillColor(CGColor(red: 255 / 255, green: 210 / 255, blue: 63 / 255, alpha: 1))
context.fillEllipse(in: CGRect(x: 604, y: 416, width: 192, height: 192))

guard let image = context.makeImage() else { fatalError("Could not render COVI icon") }
let bitmap = NSBitmapImageRep(cgImage: image)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
  fatalError("Could not encode COVI PNG")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
