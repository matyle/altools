// Renders Resources/AppIcon.icns: a dark tile with a notch island over a 3×3 grid of
// One Dark colours. Run: swift scripts/make-icon.swift
import AppKit

func color(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
  NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(_ size: Int) -> Data {
  let s = CGFloat(size)
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let k = s / 1024
  // macOS icon grid: an 824-pt tile centred on the 1024 canvas, with room for the shadow.
  let tile = NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
  let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * k, yRadius: 185 * k)
  let shadow = NSShadow()
  shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
  shadow.shadowBlurRadius = 24 * k
  shadow.shadowOffset = NSSize(width: 0, height: -10 * k)
  NSGraphicsContext.saveGraphicsState()
  shadow.set()
  color(0x282C34).setFill()
  shape.fill()
  NSGraphicsContext.restoreGraphicsState()

  NSGraphicsContext.saveGraphicsState()
  shape.addClip()
  NSGradient(colors: [color(0x353B47), color(0x21252B)])!.draw(in: tile, angle: -90)
  // A soft glow behind the grid.
  NSGradient(colors: [color(0x61AFEF, 0.22), color(0x61AFEF, 0)])!
    .draw(fromCenter: NSPoint(x: 512 * k, y: 430 * k), radius: 0, toCenter: NSPoint(x: 512 * k, y: 430 * k), radius: 420 * k, options: [])
  NSGraphicsContext.restoreGraphicsState()

  // Notch island across the top.
  let island = NSRect(x: 352 * k, y: 760 * k, width: 320 * k, height: 92 * k)
  NSColor.black.setFill()
  NSBezierPath(roundedRect: island, xRadius: 46 * k, yRadius: 46 * k).fill()
  color(0x98C379).setFill()
  NSBezierPath(ovalIn: NSRect(x: 396 * k, y: 788 * k, width: 36 * k, height: 36 * k)).fill()
  color(0xD19A66).setFill()
  for (i, h) in [20, 34, 26, 40].enumerated() {
    let x = (566 + CGFloat(i) * 18) * k, height = CGFloat(h) * k
    NSBezierPath(roundedRect: NSRect(x: x, y: 806 * k - height / 2, width: 10 * k, height: height), xRadius: 5 * k, yRadius: 5 * k).fill()
  }

  // 3×3 grid of tiles in the palette; the centre one is brighter.
  let palette = [0xC678DD, 0x56B6C2, 0x61AFEF, 0xE06C75, 0xD7DAE0, 0x98C379, 0xD19A66, 0xE5C07B, 0x61AFEF]
  let cell: CGFloat = 132, gap: CGFloat = 40
  let origin = NSPoint(x: 512 - (cell * 3 + gap * 2) / 2, y: 190)
  for row in 0..<3 {
    for col in 0..<3 {
      let r = NSRect(x: (origin.x + CGFloat(col) * (cell + gap)) * k, y: (origin.y + CGFloat(2 - row) * (cell + gap)) * k,
                     width: cell * k, height: cell * k)
      color(palette[row * 3 + col]).setFill()
      NSBezierPath(roundedRect: r, xRadius: 38 * k, yRadius: 38 * k).fill()
    }
  }
  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
  try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
  try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! render(1024).write(to: root.appendingPathComponent("Resources/AppIcon.png"))
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
print("Wrote Resources/AppIcon.icns")

// DMG window background (540×380 pt, drawn at 2x): a light panel with an arrow from the
// app to the Applications shortcut.
func background(scale: CGFloat) -> Data {
  let w = Int(540 * scale), h = Int(380 * scale)
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  rep.size = NSSize(width: 540, height: 380)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  NSGradient(colors: [color(0xF7F8FA), color(0xE9ECF1)])!.draw(in: NSRect(x: 0, y: 0, width: 540, height: 380), angle: -90)
  let arrow = NSBezierPath()
  arrow.lineWidth = 3
  arrow.lineCapStyle = .round
  arrow.move(to: NSPoint(x: 222, y: 200))
  arrow.line(to: NSPoint(x: 318, y: 200))
  arrow.move(to: NSPoint(x: 304, y: 212))
  arrow.line(to: NSPoint(x: 320, y: 200))
  arrow.line(to: NSPoint(x: 304, y: 188))
  color(0x8A93A3).setStroke()
  arrow.stroke()
  let text = "Drag Altools to Applications" as NSString
  let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: color(0x6B7280)]
  let size = text.size(withAttributes: attrs)
  text.draw(at: NSPoint(x: (540 - size.width) / 2, y: 72), withAttributes: attrs)
  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}
// dmgbuild pairs foo.png with foo@2x.png for Retina screens.
try! background(scale: 1).write(to: root.appendingPathComponent("Resources/dmg-background.png"))
try! background(scale: 2).write(to: root.appendingPathComponent("Resources/dmg-background@2x.png"))
print("Wrote Resources/dmg-background.png and @2x")
