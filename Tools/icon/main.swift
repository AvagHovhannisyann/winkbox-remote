// Draws the app icon (1024 px): a Siri-Remote-style clickpad on a deep night-sky gradient, with Wink's orange
// chevron in the middle. usage: icon <out.png>
import AppKit

let px = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let s = CGFloat(px)
let c = CGPoint(x: s / 2, y: s / 2)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map { color($0.0, $0.1) } as CFArray, locations: stops.map { $0.2 })!
}

// Background: indigo night falling to black, lit warm from the lower left.
ctx.drawLinearGradient(gradient([(0x2A1F6E, 1, 0), (0x120E33, 1, 0.55), (0x05060A, 1, 1)]),
                       start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
ctx.drawRadialGradient(gradient([(0xFF6A2C, 0.38, 0), (0xFF6A2C, 0, 1)]),
                       startCenter: CGPoint(x: s * 0.12, y: s * 0.08), startRadius: 0,
                       endCenter: CGPoint(x: s * 0.12, y: s * 0.08), endRadius: s * 0.62, options: [])
ctx.drawRadialGradient(gradient([(0x7C6CFF, 0.30, 0), (0x7C6CFF, 0, 1)]),
                       startCenter: CGPoint(x: s * 0.85, y: s * 0.95), startRadius: 0,
                       endCenter: CGPoint(x: s * 0.85, y: s * 0.95), endRadius: s * 0.55, options: [])

// Soft shadow under the clickpad.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.025), blur: s * 0.07, color: color(0x000000, 0.65))
ctx.setFillColor(color(0x1A1B22))
ctx.fillEllipse(in: CGRect(x: c.x - s * 0.335, y: c.y - s * 0.335, width: s * 0.67, height: s * 0.67))
ctx.restoreGState()

// Brushed-aluminium ring.
let outer = s * 0.335
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2))
ctx.clip()
ctx.drawLinearGradient(gradient([(0xF4F4F8, 1, 0), (0xB9BAC4, 1, 0.45), (0x7D7E89, 1, 1)]),
                       start: CGPoint(x: c.x, y: c.y + outer), end: CGPoint(x: c.x, y: c.y - outer), options: [])
ctx.restoreGState()

// Dark glass clickpad inside the ring.
let inner = s * 0.268
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2))
ctx.clip()
ctx.drawLinearGradient(gradient([(0x2A2B35, 1, 0), (0x121318, 1, 0.6), (0x0B0C10, 1, 1)]),
                       start: CGPoint(x: c.x, y: c.y + inner), end: CGPoint(x: c.x, y: c.y - inner), options: [])
// glossy highlight across the top
ctx.drawRadialGradient(gradient([(0xFFFFFF, 0.16, 0), (0xFFFFFF, 0, 1)]),
                       startCenter: CGPoint(x: c.x, y: c.y + inner * 0.9), startRadius: 0,
                       endCenter: CGPoint(x: c.x, y: c.y + inner * 0.9), endRadius: inner * 1.1, options: [])
ctx.restoreGState()

// Four direction dots on the clickpad.
ctx.setFillColor(color(0xFFFFFF, 0.55))
for (dx, dy) in [(0.0, 1.0), (1.0, 0.0), (0.0, -1.0), (-1.0, 0.0)] {
    let r = s * 0.013
    let p = CGPoint(x: c.x + CGFloat(dx) * inner * 0.74, y: c.y + CGFloat(dy) * inner * 0.74)
    ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
}

// Wink's orange chevron, glowing, in the middle.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: s * 0.05, color: color(0xFF6A2C, 0.9))
let h = s * 0.085
let w = s * 0.072
let t = s * 0.034
let chevron = CGMutablePath()
chevron.move(to: CGPoint(x: c.x - w / 2, y: c.y + h))
chevron.addLine(to: CGPoint(x: c.x - w / 2 + t, y: c.y + h))
chevron.addLine(to: CGPoint(x: c.x + w / 2 + t, y: c.y))
chevron.addLine(to: CGPoint(x: c.x - w / 2 + t, y: c.y - h))
chevron.addLine(to: CGPoint(x: c.x - w / 2, y: c.y - h))
chevron.addLine(to: CGPoint(x: c.x + w / 2, y: c.y))
chevron.closeSubpath()
ctx.addPath(chevron)
ctx.clip()
ctx.drawLinearGradient(gradient([(0xFFB547, 1, 0), (0xFF6A2C, 1, 0.55), (0xF0431A, 1, 1)]),
                       start: CGPoint(x: c.x, y: c.y + h), end: CGPoint(x: c.x, y: c.y - h), options: [])
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print(out)
