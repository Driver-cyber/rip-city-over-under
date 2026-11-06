// make-icon.swift — draws the app icon: the pinwheel from Pinwheel.swift
// (five red and five light blades) on black. Run from ios/RipCity:
//   swift tools/make-icon.swift
import AppKit

let size = 1024
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(CGColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
let hub = CGPoint(x: 512, y: 512), k = CGFloat(size) / 64 * 1.05

func blades(_ base: [Double], _ color: CGColor) {
    ctx.setStrokeColor(color); ctx.setLineWidth(3.6 * k); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    for b in base {
        let p = CGMutablePath()
        for i in 0...40 {
            let s = CGFloat(i) / 40
            let r = (3 + 20 * s) * k
            let a = -(b + 58 * Double(s)) * .pi / 180          // Core Graphics' y axis points up
            let pt = CGPoint(x: hub.x + cos(a) * r, y: hub.y + sin(a) * r)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        ctx.addPath(p); ctx.strokePath()
    }
}
blades((0..<5).map { -54 + Double($0) * 72 }, CGColor(red: 0.957, green: 0.949, blue: 0.933, alpha: 1))
blades((0..<5).map { -90 + Double($0) * 72 }, CGColor(red: 0.878, green: 0.227, blue: 0.243, alpha: 1))

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "RipCity/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
