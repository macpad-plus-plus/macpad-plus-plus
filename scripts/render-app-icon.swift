// Renders the app icon: the axolotl mascot with its ++, centred on a white
// squircle that fades to a light grey.
//
//   swift scripts/render-app-icon.swift
//
// Writes every size to AppIcon/png, AppIcon/AppIcon.iconset, AppIcon/AppIcon.appiconset
// and the app's asset catalog, then AppIcon/AppIcon.icns with iconutil. The shape follows
// Apple's macOS icon grid: an 824-pt rounded square centred on a 1024-pt canvas.

import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let mascotURL = root.appendingPathComponent("AppIcon/axolote/axolote-2048.png")
let iconDirectory = root.appendingPathComponent("AppIcon")
let catalogDirectory = root.appendingPathComponent("Sources/MacPad/Resources/Assets.xcassets/AppIcon.appiconset")

let canvas: CGFloat = 1024
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185
/// The mascot's width, as a share of the tile's.
let mascotShare: CGFloat = 0.78

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

guard let mascot = NSImage(contentsOf: mascotURL) else {
    fatalError("could not read \(mascotURL.path)")
}

/// Draws the icon in a 1024-pt space, shown at `scale` pixels per point.
/// Shadows ignore the drawing's scale, so they take it here.
func drawIcon(scale: CGFloat) {
    let shape = NSBezierPath(roundedRect: tile, xRadius: cornerRadius, yRadius: cornerRadius)

    // The tile, with the soft shadow macOS icons sit on.
    NSGraphicsContext.saveGraphicsState()
    let tileShadow = NSShadow()
    tileShadow.shadowColor = color(0x000000, 0.28)
    tileShadow.shadowOffset = NSSize(width: 0, height: -12 * scale)
    tileShadow.shadowBlurRadius = 24 * scale
    tileShadow.set()
    color(0xFFFFFF).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // White at the top to a light grey at the bottom.
    NSGradient(colors: [color(0xFFFFFF), color(0xF3F5F4), color(0xE2E7E4)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: shape, angle: -90)

    // The mascot, centred, with a light shadow so it stands off the white.
    let width = tile.width * mascotShare
    let height = width * mascot.size.height / mascot.size.width
    let rect = NSRect(x: tile.midX - width / 2, y: tile.midY - height / 2, width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    let mascotShadow = NSShadow()
    mascotShadow.shadowColor = color(0x0B3A20, 0.22)
    mascotShadow.shadowOffset = NSSize(width: 0, height: -10 * scale)
    mascotShadow.shadowBlurRadius = 18 * scale
    mascotShadow.set()
    mascot.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    // A hairline that keeps the edge visible on light backgrounds.
    let inset = tile.insetBy(dx: 1.5, dy: 1.5)
    let edge = NSBezierPath(roundedRect: inset, xRadius: cornerRadius - 1.5, yRadius: cornerRadius - 1.5)
    edge.lineWidth = 3
    color(0x000000, 0.08).setStroke()
    edge.stroke()
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.imageInterpolation = .high
    NSGraphicsContext.current = context
    let scale = CGFloat(pixels) / canvas
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    drawIcon(scale: scale)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fileManager = FileManager.default
func write(_ data: Data, to url: URL) throws {
    try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

var rendered: [Int: Data] = [:]
func png(_ pixels: Int) -> Data {
    if let data = rendered[pixels] { return data }
    let data = render(pixels: pixels)
    rendered[pixels] = data
    return data
}

for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    try write(png(pixels), to: iconDirectory.appendingPathComponent("png/AppIcon-\(pixels).png"))
}

// The names iconutil and asset catalogs expect: icon_<points>x<points>[@2x].png.
for points in [16, 32, 128, 256, 512] {
    for (suffix, pixels) in [("", points), ("@2x", points * 2)] {
        let name = "icon_\(points)x\(points)\(suffix).png"
        for directory in ["AppIcon/AppIcon.iconset", "AppIcon/AppIcon.appiconset"] {
            try write(png(pixels), to: root.appendingPathComponent(directory).appendingPathComponent(name))
        }
        try write(png(pixels), to: catalogDirectory.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconDirectory.appendingPathComponent("AppIcon.iconset").path,
                      "-o", iconDirectory.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote the app icon to AppIcon/ and the asset catalog")
