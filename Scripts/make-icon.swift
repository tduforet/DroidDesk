#!/usr/bin/env swift
// Draws the DroidDesk app icon and writes every size of the AppIcon set.
// Usage: swift Scripts/make-icon.swift DroidDesk/Assets.xcassets/AppIcon.appiconset
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ top: UInt32, _ bottom: UInt32) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(top), color(bottom)] as CFArray,
        locations: [0, 1]
    )!
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Draws on a 1024-point canvas, scaled to the bitmap.
func draw(into context: CGContext, pixels: Int) {
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)

    // Tile with a soft drop shadow, as the macOS icon grid expects.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.28))
    context.addPath(roundedRect(tile, 186))
    context.setFillColor(color(0x1FB86B))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(roundedRect(tile, 186))
    context.clip()
    context.drawLinearGradient(
        gradient(0x63F2A6, 0x16A765),
        start: CGPoint(x: 512, y: 924),
        end: CGPoint(x: 512, y: 100),
        options: []
    )
    // A faint highlight along the top edge.
    context.drawLinearGradient(
        CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)] as CFArray,
            locations: [0, 1]
        )!,
        start: CGPoint(x: 512, y: 924),
        end: CGPoint(x: 512, y: 700),
        options: []
    )

    // The desk: a bar the phone stands on.
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 16, color: color(0x063B25, 0.35))
    context.addPath(roundedRect(CGRect(x: 232, y: 220, width: 560, height: 44), 22))
    context.setFillColor(color(0xFFFFFF, 0.92))
    context.fillPath()

    // The phone.
    let phone = CGRect(x: 362, y: 300, width: 300, height: 512)
    context.addPath(roundedRect(phone, 60))
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0, color: nil)

    // The screen.
    let screen = CGRect(x: 384, y: 322, width: 256, height: 432)
    context.saveGState()
    context.addPath(roundedRect(screen, 40))
    context.clip()
    context.drawLinearGradient(
        gradient(0x12513B, 0x072A1E),
        start: CGPoint(x: 512, y: screen.maxY),
        end: CGPoint(x: 512, y: screen.minY),
        options: []
    )
    context.restoreGState()

    // The camera.
    context.addPath(roundedRect(CGRect(x: 477, y: 769, width: 70, height: 16), 8))
    context.setFillColor(color(0x0B3A29))
    context.fillPath()

    // Play.
    let play = CGMutablePath()
    play.move(to: CGPoint(x: 478, y: 482))
    play.addLine(to: CGPoint(x: 478, y: 594))
    play.addLine(to: CGPoint(x: 574, y: 538))
    play.closeSubpath()
    context.addPath(play)
    context.setFillColor(color(0x63F2A6))
    context.setStrokeColor(color(0x63F2A6))
    context.setLineWidth(22)
    context.setLineJoin(.round)
    context.drawPath(using: .fillStroke)
    context.restoreGState()
}

func png(pixels: Int) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    draw(into: context, pixels: pixels)
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: make-icon.swift <AppIcon.appiconset>\n".utf8))
    exit(2)
}
let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)

let slots: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]
var images: [[String: String]] = []
for slot in slots {
    let pixels = slot.points * slot.scale
    let name = "icon_\(slot.points)x\(slot.points)@\(slot.scale)x.png"
    try png(pixels: pixels).write(to: directory.appending(path: name))
    images.append([
        "filename": name,
        "idiom": "mac",
        "scale": "\(slot.scale)x",
        "size": "\(slot.points)x\(slot.points)",
    ])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: directory.appending(path: "Contents.json"))
print("Wrote \(slots.count) icons to \(directory.path)")
