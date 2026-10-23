#!/usr/bin/env swift
// Renders the Sixty app icon and the website images.
// Run from the repo root:  swift scripts/make-icon.swift
// Writes: Resources/AppIcon.icns, site/assets/{icon-512,apple-touch-icon,favicon-32,og-image}.png
import AppKit
import CoreGraphics

let accent = NSColor(srgbRed: 1.0, green: 0.541, blue: 0.239, alpha: 1)      // #FF8A3D
let bgTop = NSColor(srgbRed: 0.102, green: 0.133, blue: 0.188, alpha: 1)     // #1A2230
let bgBottom = NSColor(srgbRed: 0.020, green: 0.031, blue: 0.051, alpha: 1)  // #05080D

func bitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: w, height: h)
    return rep
}

func png(_ rep: NSBitmapImageRep, to path: String) {
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

/// Superellipse (n = 5) approximates Apple's continuous-corner squircle.
func squircle(in r: CGRect) -> CGPath {
    let path = CGMutablePath()
    let n = 5.0, steps = 240
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = (c < 0 ? -1.0 : 1.0) * pow(abs(c), 2 / n)
        let y = (s < 0 ? -1.0 : 1.0) * pow(abs(s), 2 / n)
        let p = CGPoint(x: r.midX + x * r.width / 2, y: r.midY + y * r.height / 2)
        i == 0 ? path.move(to: p) : path.addLine(to: p)
    }
    path.closeSubpath()
    return path
}

func roundedFont(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .heavy)
    if let d = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { return f }
    return base
}

func drawText(_ s: String, font: NSFont, color: NSColor, centeredAt c: CGPoint, kern: CGFloat = 0) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
    let str = NSAttributedString(string: s, attributes: attrs)
    let sz = str.size()
    // Centre on the cap height, not the line box, so digits sit optically centred.
    let capH = font.capHeight
    str.draw(at: CGPoint(x: c.x - sz.width / 2, y: c.y - capH / 2 - (font.descender.magnitude - font.descender.magnitude)) )
    _ = sz
}

/// Draws the icon artwork into the current context inside `box` (the visible icon body).
func drawIcon(box: CGRect, px: CGFloat) {
    let ctx = NSGraphicsContext.current!.cgContext
    let body = squircle(in: box)
    let u = box.width / 824  // 1 unit = 1px of Apple's 1024 template body

    // Soft drop shadow under the body (skipped when tiny).
    if px >= 64 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * u), blur: 24 * u,
                      color: NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.addPath(body); ctx.setFillColor(bgBottom.cgColor); ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(body); ctx.clip()
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [bgTop.cgColor, bgBottom.cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: box.midX, y: box.maxY), end: CGPoint(x: box.midX, y: box.minY), options: [])

    let small = px <= 40
    let center = CGPoint(x: box.midX, y: box.midY)
    let tiny = px <= 20
    let radius = (tiny ? 325 : small ? 300 : 292) * u
    let lw = (tiny ? 70 : small ? 96 : 60) * u

    // Track
    ctx.setLineWidth(lw); ctx.setLineCap(.round)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(small ? 0.16 : 0.10).cgColor)
    ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Accent arc: 300 degrees, from 12 o'clock, clockwise.
    let start = CGFloat.pi / 2, end = start - 300 * .pi / 180
    if px >= 64 {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 28 * u, color: accent.withAlphaComponent(0.55).cgColor)
        ctx.setStrokeColor(accent.cgColor)
        ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
        ctx.strokePath()
        ctx.restoreGState()
    }
    ctx.setStrokeColor(accent.cgColor)
    ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
    ctx.strokePath()

    // "60", fitted into the ring's inner circle.
    let inner = (radius - lw / 2) * 2
    let targetW = inner * (tiny ? 0.98 : small ? 0.84 : 0.78)
    var fs: CGFloat = 100
    let w100 = NSAttributedString(string: "60", attributes: [.font: roundedFont(fs)]).size().width
    fs = fs * targetW / w100
    let font = roundedFont(fs)
    let str = NSAttributedString(string: "60", attributes: [.font: font, .foregroundColor: NSColor.white])
    let sz = str.size()
    let y = center.y - font.capHeight / 2 - font.descender.magnitude * 0 - (sz.height - font.capHeight) / 2 + (font.ascender - font.capHeight) / 2 - 0
    str.draw(at: CGPoint(x: center.x - sz.width / 2, y: y - (font.ascender - font.capHeight) / 2 + (sz.height - font.ascender + font.descender) * 0))

    // Subtle top highlight
    if px >= 64 {
        let hl = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                            colors: [NSColor.white.withAlphaComponent(0.10).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                            locations: [0, 1])!
        ctx.drawLinearGradient(hl, start: CGPoint(x: box.midX, y: box.maxY), end: CGPoint(x: box.midX, y: box.midY + box.height * 0.2), options: [])
    }
    ctx.restoreGState()

    // Hairline edge
    if px >= 64 {
        ctx.addPath(body); ctx.setLineWidth(max(1, 2 * u))
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor); ctx.strokePath()
    }
}

func renderIcon(pixels: Int, fullBleed: Bool = false) -> NSBitmapImageRep {
    let rep = bitmap(pixels, pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.cgContext.interpolationQuality = .high
    let p = CGFloat(pixels)
    // Apple template: body is 824/1024 of the canvas (100 px margin). Favicons use less margin.
    let box: CGRect
    if fullBleed { box = CGRect(x: p * 0.03, y: p * 0.03, width: p * 0.94, height: p * 0.94) }
    else { box = CGRect(x: p * 100 / 1024, y: p * 100 / 1024, width: p * 824 / 1024, height: p * 824 / 1024) }
    drawIcon(box: box, px: p)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func renderOG() -> NSBitmapImageRep {
    let w = 1200, h = 630
    let rep = bitmap(w, h)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [NSColor(srgbRed: 0.051, green: 0.071, blue: 0.098, alpha: 1).cgColor,
                                NSColor(srgbRed: 0.020, green: 0.031, blue: 0.051, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(h)), end: CGPoint(x: 0, y: 0), options: [])
    // Warm glow behind the icon
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [accent.withAlphaComponent(0.20).cgColor, accent.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 290, y: 315), startRadius: 0, endCenter: CGPoint(x: 290, y: 315), endRadius: 420, options: [])
    // Icon (render at 2x then draw scaled)
    let icon = renderIcon(pixels: 1024)
    let size: CGFloat = 440 * 1024 / 824
    NSImage(size: icon.size).addRepresentation(icon)
    let img = NSImage(size: NSSize(width: 1024, height: 1024)); img.addRepresentation(icon)
    img.draw(in: CGRect(x: 290 - size / 2, y: 315 - size / 2, width: size, height: size))

    func text(_ s: String, _ font: NSFont, _ color: NSColor, x: CGFloat, y: CGFloat, kern: CGFloat = 0) {
        NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .kern: kern]).draw(at: CGPoint(x: x, y: y))
    }
    text("Sixty", roundedFont(168), .white, x: 560, y: 320, kern: -3)
    text("A break reminder you", NSFont.systemFont(ofSize: 44, weight: .semibold), NSColor.white.withAlphaComponent(0.92), x: 566, y: 238)
    text("can\u{2019}t skip on autopilot.", NSFont.systemFont(ofSize: 44, weight: .semibold), accent, x: 566, y: 180)
    text("Free \u{00B7} Open source \u{00B7} macOS 14+", NSFont.systemFont(ofSize: 30, weight: .medium),
         NSColor.white.withAlphaComponent(0.62), x: 566, y: 100)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
for d in ["Resources", "site/assets"] { try? fm.createDirectory(atPath: d, withIntermediateDirectories: true) }

// iconset -> icns
let tmp = NSTemporaryDirectory() + "Sixty-\(getpid()).iconset"
try? fm.removeItem(atPath: tmp)
try! fm.createDirectory(atPath: tmp, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    png(renderIcon(pixels: base), to: "\(tmp)/icon_\(base)x\(base).png")
    png(renderIcon(pixels: base * 2), to: "\(tmp)/icon_\(base)x\(base)@2x.png")
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", tmp, "-o", "Resources/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
precondition(p.terminationStatus == 0, "iconutil failed")
try? fm.removeItem(atPath: tmp)

png(renderIcon(pixels: 512), to: "site/assets/icon-512.png")
png(renderIcon(pixels: 180, fullBleed: true), to: "site/assets/apple-touch-icon.png")
png(renderIcon(pixels: 32, fullBleed: true), to: "site/assets/favicon-32.png")
png(renderOG(), to: "site/assets/og-image.png")

// Hand-written SVG equivalent (circumference of r=19: 119.38; 300/360 -> 99.48)
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">
  <defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1A2230"/><stop offset="1" stop-color="#05080D"/></linearGradient></defs>
  <rect x="2" y="2" width="60" height="60" rx="14" fill="url(#g)"/>
  <circle cx="32" cy="32" r="20" fill="none" stroke="#fff" stroke-opacity=".16" stroke-width="6"/>
  <circle cx="32" cy="32" r="20" fill="none" stroke="#FF8A3D" stroke-width="6" stroke-linecap="round" stroke-dasharray="104.7 125.7" transform="rotate(-90 32 32)"/>
  <text x="32" y="32" text-anchor="middle" dominant-baseline="central" font-family="ui-rounded,'SF Pro Rounded',-apple-system,system-ui,sans-serif" font-weight="900" font-size="19" fill="#fff">60</text>
</svg>
"""
try! svg.write(toFile: "site/assets/favicon.svg", atomically: true, encoding: .utf8)
print("done")
