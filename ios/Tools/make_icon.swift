// Renders the 1024×1024 app icon: the checklist from the web version's apple-touch-icon.png, redrawn at full size.
// Usage: swift ios/Tools/make_icon.swift ios/DailyGames/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit

let size = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("no context") }

// Draw in the 180-point grid the touch icon was made on, top-down.
let scale = CGFloat(size) / 180
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: scale, y: -scale)

let orange = CGColor(srgbRed: 232 / 255, green: 89 / 255, blue: 12 / 255, alpha: 1)
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
let faint = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55)

ctx.setFillColor(orange)
ctx.fill(CGRect(x: 0, y: 0, width: 180, height: 180))

let rows: [CGFloat] = [55, 89, 123]
let circleX: CGFloat = 52
let radius: CGFloat = 14
let barX: CGFloat = 76
let barHeight: CGFloat = 14

func bar(y: CGFloat, width: CGFloat, color: CGColor) {
    let rect = CGRect(x: barX, y: y - barHeight / 2, width: width, height: barHeight)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: barHeight / 2, cornerHeight: barHeight / 2, transform: nil))
    ctx.setFillColor(color)
    ctx.fillPath()
}

// Two ticked rows.
for y in rows.prefix(2) {
    ctx.setFillColor(white)
    ctx.fillEllipse(in: CGRect(x: circleX - radius, y: y - radius, width: radius * 2, height: radius * 2))
    ctx.setStrokeColor(orange)
    ctx.setLineWidth(4)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: circleX - 6.5, y: y))
    ctx.addLine(to: CGPoint(x: circleX - 2, y: y + 4.5))
    ctx.addLine(to: CGPoint(x: circleX + 7, y: y - 5))
    ctx.strokePath()
    bar(y: y, width: 60, color: white)
}

// One still to play.
ctx.setStrokeColor(white)
ctx.setLineWidth(4)
ctx.strokeEllipse(in: CGRect(x: circleX - radius + 2, y: rows[2] - radius + 2, width: (radius - 2) * 2, height: (radius - 2) * 2))
bar(y: rows[2], width: 44, color: faint)

guard let image = ctx.makeImage() else { fatalError("no image") }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("no png") }
try png.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
