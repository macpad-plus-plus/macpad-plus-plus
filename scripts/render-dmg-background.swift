// Renders the DMG window background with the axolotl mascot.
//
//   swift scripts/render-dmg-background.swift
//
// Writes AppIcon/dmg/dmg-background.tiff (1x + 2x). The layout matches create-dmg:
// a 660×400 window with 160-pt icons centred at (180, 170) and (480, 170),
// measured from the top-left. scripts/build-dmg.sh swaps it into the DMG.

import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let size = NSSize(width: 660, height: 400)
let mascotURL = root.appendingPathComponent("AppIcon/axolote/axolote-1024.png")
let outputDirectory = root.appendingPathComponent("AppIcon/dmg")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Converts create-dmg's top-left coordinates to AppKit's bottom-left ones.
func flipped(_ y: CGFloat) -> CGFloat { size.height - y }

func drawBackground() {
    // Soft, slightly green paper.
    NSGradient(colors: [color(0xF7FAF5), color(0xEDF4E8)])!.draw(in: NSRect(origin: .zero, size: size), angle: -90)

    // A gentle hill along the bottom for the axolotl to sit on.
    let hill = NSBezierPath()
    hill.move(to: NSPoint(x: 0, y: 0))
    hill.line(to: NSPoint(x: 0, y: 58))
    hill.curve(to: NSPoint(x: 660, y: 64), controlPoint1: NSPoint(x: 200, y: 96), controlPoint2: NSPoint(x: 460, y: 30))
    hill.line(to: NSPoint(x: 660, y: 0))
    hill.close()
    NSGradient(colors: [color(0xB9E59A, 0.85), color(0x7FCB63, 0.9)])!.draw(in: hill, angle: -90)

    // Dashed arrow from the app (left) to Applications (right), above the labels.
    let arrowY = flipped(170)
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 272, y: arrowY + 6))
    arrow.curve(to: NSPoint(x: 384, y: arrowY + 6), controlPoint1: NSPoint(x: 305, y: arrowY + 34), controlPoint2: NSPoint(x: 351, y: arrowY + 34))
    arrow.lineWidth = 5
    arrow.lineCapStyle = .round
    arrow.setLineDash([2, 12], count: 2, phase: 0)
    color(0x2E9E4F).setStroke()
    arrow.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: 372, y: arrowY + 20))
    head.line(to: NSPoint(x: 388, y: arrowY + 4))
    head.line(to: NSPoint(x: 366, y: arrowY + 1))
    head.lineWidth = 5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    // The mascot, sitting on the hill between and below the two icons.
    if let mascot = NSImage(contentsOf: mascotURL) {
        let height: CGFloat = 104
        let width = height * mascot.size.width / mascot.size.height
        let rect = NSRect(x: (size.width - width) / 2, y: 18, width: width, height: height)
        let shadow = NSShadow()
        shadow.shadowColor = color(0x1B4D0E, 0.25)
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.shadowBlurRadius = 8
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        mascot.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawBackground()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let reps = [render(scale: 1), render(scale: 2)]
try reps[0].representation(using: .png, properties: [:])!.write(to: outputDirectory.appendingPathComponent("dmg-background.png"))
try reps[1].representation(using: .png, properties: [:])!.write(to: outputDirectory.appendingPathComponent("dmg-background@2x.png"))
// A two-resolution TIFF, which Finder picks from on Retina displays.
let tiff = NSBitmapImageRep.tiffRepresentationOfImageReps(in: reps, using: .lzw, factor: 0)!
try tiff.write(to: outputDirectory.appendingPathComponent("dmg-background.tiff"))
print("Wrote \(outputDirectory.path)/dmg-background.{png,@2x.png,tiff}")
