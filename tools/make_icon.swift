import AppKit
// args: src out mode(fullbleed|inset) size
let src = NSImage(contentsOfFile: CommandLine.arguments[1])!
let mode = CommandLine.arguments[3]
let size = Int(CommandLine.arguments[4])!
let N: CGFloat = 1024, oldRing: CGFloat = 68, ring: CGFloat = 28
let margin: CGFloat = mode == "inset" ? 24 : 0   // transparent margin so the circle never touches the edge
let gray = NSColor(calibratedWhite: 0.45, alpha: 1)
// Render at 1024 first, then downscale with high-quality interpolation.
let big = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: big)
NSGraphicsContext.current!.imageInterpolation = .high
NSGraphicsContext.current!.shouldAntialias = true
let outer = NSRect(x: margin, y: margin, width: N - 2*margin, height: N - 2*margin)
gray.setFill()
if mode == "fullbleed" { NSBezierPath(rect: outer).fill() } else { NSBezierPath(ovalIn: outer).fill() }
// black disk: for fullbleed, the system's circular mask is the outer edge, so the ring
// is the gap between the mask and this disk.
let disk = outer.insetBy(dx: ring * (N - 2*margin) / N, dy: ring * (N - 2*margin) / N)
NSColor.black.setFill(); NSBezierPath(ovalIn: disk).fill()
// original "$_" content, scaled into the same box
let scale = (N - 2*margin) / N
let contentClip = NSRect(x: margin + oldRing*scale, y: margin + oldRing*scale,
                         width: (N - 2*oldRing)*scale, height: (N - 2*oldRing)*scale)
NSBezierPath(ovalIn: contentClip).addClip()
src.draw(in: outer, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
let final = NSImage(size: NSSize(width: size, height: size))
let small = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
NSGraphicsContext.current!.imageInterpolation = .high
let bigImg = NSImage(size: NSSize(width: 1024, height: 1024)); bigImg.addRepresentation(big)
bigImg.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
_ = final
try! small.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
