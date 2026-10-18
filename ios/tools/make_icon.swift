// Generate a 1024 x 1024 PNG App icon matching the paper-style isometric low-poly scene.
// From ios: swift tools/make_icon.swift StreetWalk/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

// Palette matches SceneStyle.
let bg = rgb(0xF6F5F1)
let paving = rgb(0xFBFBFC), plinthL = rgb(0xEDEDF0), plinthR = rgb(0xE2E2E7)
let white = (top: rgb(0xFFFFFF), left: rgb(0xF3F3F5), right: rgb(0xE6E6EA), line: rgb(0xC9C9CE))
let home = (top: rgb(0xFEE7DB), left: rgb(0xFAD9C8), right: rgb(0xF2C9B5), line: rgb(0xD85A30))
let lawn = rgb(0xDCEAD3), tree = rgb(0xC7DFBB), treeDark = rgb(0xB5D3A8)
let accent = rgb(0xD85A30)

let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// Move origin to top-left.
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)
ctx.setFillColor(bg)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
ctx.setLineJoin(.round)
ctx.setLineCap(.round)

// Isometric projection: x down-right, y down-left, z upward.
let s = 44.0, ox = 512.0
func raw(_ x: Double, _ y: Double, _ z: Double) -> Double { (x + y) * sin(.pi / 6) * s - z * s }
// Center between the tallest roof and base bottom, slightly below the image midpoint for visual balance.
let oy = 530.0 - (raw(3.8, 0.8, 8.2) + raw(10, 10, -0.6)) / 2
func p(_ x: Double, _ y: Double, _ z: Double = 0) -> CGPoint {
    CGPoint(x: ox + (x - y) * cos(.pi / 6) * s, y: oy + raw(x, y, z))
}

func poly(_ pts: [CGPoint], fill: CGColor, line: CGColor?, width: Double = 4) {
    ctx.beginPath()
    ctx.addLines(between: pts)
    ctx.closePath()
    ctx.setFillColor(fill)
    if let line {
        ctx.setStrokeColor(line)
        ctx.setLineWidth(width)
        ctx.drawPath(using: .fillStroke)
    } else {
        ctx.fillPath()
    }
}

/// Draw a cuboid's top and two front-facing sides, y=y1 and x=x1.
func box(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ h: Double, _ c: (top: CGColor, left: CGColor, right: CGColor, line: CGColor), z: Double = 0, width: Double = 4) {
    poly([p(x0, y1, z), p(x1, y1, z), p(x1, y1, z + h), p(x0, y1, z + h)], fill: c.left, line: c.line, width: width)
    poly([p(x1, y0, z), p(x1, y1, z), p(x1, y1, z + h), p(x1, y0, z + h)], fill: c.right, line: c.line, width: width)
    poly([p(x0, y0, z + h), p(x1, y0, z + h), p(x1, y1, z + h), p(x0, y1, z + h)], fill: c.top, line: c.line, width: width)
}

/// Thin horizontal window lines on both sides suggest paper-cut architecture.
func floors(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ h: Double, step: Double, color: CGColor) {
    ctx.setStrokeColor(color)
    ctx.setLineWidth(2.5)
    var z = step
    while z < h - step * 0.6 {
        ctx.strokeLineSegments(between: [p(x0 + 0.25, y1, z), p(x1 - 0.25, y1, z), p(x1, y1 - 0.25, z), p(x1, y0 + 0.25, z)])
        z += step
    }
}

func disc(_ c: CGPoint, r: Double, fill: CGColor) {
    ctx.setFillColor(fill)
    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
}

// Base is 10 x 10, thickness 0.6.
let n = 10.0, t = 0.6
poly([p(0, n, -t), p(n, n, -t), p(n, n, 0), p(0, n, 0)], fill: plinthL, line: white.line)
poly([p(n, 0, -t), p(n, n, -t), p(n, n, 0), p(n, 0, 0)], fill: plinthR, line: white.line)
poly([p(0, 0), p(n, 0), p(n, n), p(0, n)], fill: paving, line: white.line)

// Grass and two trees.
poly([p(5.6, 5.4), p(9.2, 5.4), p(9.2, 9.2), p(5.6, 9.2)], fill: lawn, line: nil)
disc(p(7.0, 6.6, 0.75), r: 30, fill: tree)
disc(p(8.2, 8.0, 0.65), r: 25, fill: treeDark)

// Draw buildings back-to-front, smallest x+y first.
box(0.9, 0.9, 2.7, 5.8, 5.2, white)
floors(0.9, 0.9, 2.7, 5.8, 5.2, step: 1.05, color: white.line)
box(3.8, 0.8, 5.9, 2.9, 8.2, home, width: 5)
floors(3.8, 0.8, 5.9, 2.9, 8.2, step: 1.05, color: home.right.copy(alpha: 1)!)
box(6.9, 1.4, 9.1, 3.3, 4.2, white)
floors(6.9, 1.4, 9.1, 3.3, 4.2, step: 1.05, color: white.line)

// Orange figure: shadow, body and head.
let foot = p(4.6, 7.0)
ctx.setFillColor(CGColor(gray: 0, alpha: 0.10))
ctx.fillEllipse(in: CGRect(x: foot.x - 30, y: foot.y - 11, width: 60, height: 22))
let body = CGRect(x: foot.x - 19, y: foot.y - 82, width: 38, height: 78)
ctx.setFillColor(accent)
ctx.addPath(CGPath(roundedRect: body, cornerWidth: 19, cornerHeight: 19, transform: nil))
ctx.fillPath()
disc(CGPoint(x: foot.x, y: foot.y - 104), r: 19, fill: accent)

let img = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
