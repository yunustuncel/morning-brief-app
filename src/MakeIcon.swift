import Cocoa

func makeIcon(_ size: Int) -> NSImage {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()

    let bg = NSColor(srgbRed: 0.094, green: 0.094, blue: 0.102, alpha: 1)
    bg.setFill()
    let r = s * 0.22
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s), xRadius: r, yRadius: r).fill()

    let clay = NSColor(srgbRed: 0.831, green: 0.443, blue: 0.290, alpha: 1)
    clay.setFill()
    clay.setStroke()

    let cx = s / 2, cy = s * 0.52
    let sr = s * 0.185
    let lw = max(1.5, s * 0.028)

    // Sun disc
    NSBezierPath(ovalIn: NSRect(x: cx - sr, y: cy - sr, width: sr * 2, height: sr * 2)).fill()

    // Rays
    for i in 0..<8 {
        let angle = Double(i) * .pi / 4 + .pi / 8
        let ri = sr * 1.38, ro = sr * 1.78
        let x1 = cx + CGFloat(cos(angle)) * ri, y1 = cy + CGFloat(sin(angle)) * ri
        let x2 = cx + CGFloat(cos(angle)) * ro, y2 = cy + CGFloat(sin(angle)) * ro
        let p = NSBezierPath()
        p.move(to: NSPoint(x: x1, y: y1))
        p.line(to: NSPoint(x: x2, y: y2))
        p.lineWidth = lw
        p.lineCapStyle = .round
        p.stroke()
    }

    // Horizon line
    let hy = cy - s * 0.16
    let h = NSBezierPath()
    h.move(to: NSPoint(x: s * 0.18, y: hy))
    h.line(to: NSPoint(x: s * 0.82, y: hy))
    h.lineWidth = lw * 0.85
    h.lineCapStyle = .round
    h.stroke()

    img.unlockFocus()
    return img
}

func savePNG(_ img: NSImage, to path: String) {
    guard let tiff = img.tiffRepresentation,
          let bm = NSBitmapImageRep(data: tiff),
          let png = bm.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

let iconsetPath = "/tmp/MorningBrief.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let specs: [(Int, String)] = [
    (16,  "icon_16x16"),    (32,  "icon_16x16@2x"),
    (32,  "icon_32x32"),    (64,  "icon_32x32@2x"),
    (128, "icon_128x128"),  (256, "icon_128x128@2x"),
    (256, "icon_256x256"),  (512, "icon_256x256@2x"),
    (512, "icon_512x512"),  (1024,"icon_512x512@2x")
]

for (size, name) in specs {
    savePNG(makeIcon(size), to: "\(iconsetPath)/\(name).png")
}
