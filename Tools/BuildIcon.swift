import AppKit

// Traditional .icns assets need their own silhouette for macOS 14/15.
// Keep the original artwork intact and apply the same geometry at every size.
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
guard let artwork = NSImage(contentsOf: source),
  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
  let context = NSGraphicsContext(bitmapImageRep: bitmap)
else { fatalError("Cannot load or render application icon") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
let bounds = NSRect(x: 100, y: 100, width: 824, height: 824)
NSBezierPath(roundedRect: bounds, xRadius: 184, yRadius: 184).addClip()
artwork.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
  fatalError("Cannot encode application icon")
}
try png.write(to: destination)
