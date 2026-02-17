#!/usr/bin/env swift

import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first
    ?? (FileManager.default.currentDirectoryPath + "/assets/AppIcon-1024.png")
let outputURL = URL(fileURLWithPath: outputPath)

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let size = 1024
let canvas = CGRect(x: 0, y: 0, width: size, height: size)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
    NSColor(srgbRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a).cgColor
}

func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Failed to create bitmap context.\n", stderr)
    exit(1)
}

context.setAllowsAntialiasing(true)
context.interpolationQuality = .high

let card = canvas.insetBy(dx: 72, dy: 72)
let cardPath = roundedPath(card, radius: 220)

context.saveGState()
context.addPath(cardPath)
context.clip()

if let baseGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        color(17, 24, 36),
        color(26, 61, 98),
        color(29, 96, 145)
    ] as CFArray,
    locations: [0.0, 0.52, 1.0]
) {
    context.drawLinearGradient(
        baseGradient,
        start: CGPoint(x: card.minX, y: card.maxY),
        end: CGPoint(x: card.maxX, y: card.minY),
        options: []
    )
}

if let ambientGlow = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        color(255, 255, 255, 0.14),
        color(255, 255, 255, 0.0)
    ] as CFArray,
    locations: [0.0, 1.0]
) {
    context.drawRadialGradient(
        ambientGlow,
        startCenter: CGPoint(x: card.minX + 170, y: card.maxY - 160),
        startRadius: 10,
        endCenter: CGPoint(x: card.minX + 170, y: card.maxY - 160),
        endRadius: 420,
        options: []
    )
}

context.restoreGState()

context.setStrokeColor(color(255, 255, 255, 0.24))
context.setLineWidth(2.5)
context.addPath(cardPath)
context.strokePath()

let haloRect = CGRect(x: 220, y: 220, width: 584, height: 584)
context.setFillColor(color(255, 255, 255, 0.08))
context.fillEllipse(in: haloRect)

let top = CGPoint(x: 512, y: 744)
let center = CGPoint(x: 512, y: 528)
let left = CGPoint(x: 302, y: 422)
let right = CGPoint(x: 722, y: 422)
let bottom = CGPoint(x: 512, y: 288)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -3), blur: 10, color: color(0, 0, 0, 0.26))
context.setStrokeColor(color(247, 251, 255, 0.97))
context.setLineWidth(58)
context.setLineCap(.round)
context.setLineJoin(.round)

func stroke(_ from: CGPoint, _ to: CGPoint) {
    context.beginPath()
    context.move(to: from)
    context.addLine(to: to)
    context.strokePath()
}

stroke(top, center)
stroke(center, bottom)
stroke(center, left)
stroke(center, right)
context.restoreGState()

let nodes: [(CGPoint, CGFloat)] = [
    (top, 33),
    (center, 28),
    (left, 31),
    (right, 31),
    (bottom, 33)
]

for (point, radius) in nodes {
    let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
    context.setFillColor(color(247, 251, 255, 0.98))
    context.fillEllipse(in: rect)

    context.setStrokeColor(color(19, 53, 85, 0.32))
    context.setLineWidth(5)
    context.strokeEllipse(in: rect)
}

guard let cgImage = context.makeImage() else {
    fputs("Failed to render icon image.\n", stderr)
    exit(1)
}

let bitmap = NSBitmapImageRep(cgImage: cgImage)

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Failed to encode PNG icon.\n", stderr)
    exit(1)
}

do {
    try pngData.write(to: outputURL)
    print("Generated icon: \(outputURL.path)")
} catch {
    fputs("Failed to write icon: \(error.localizedDescription)\n", stderr)
    exit(1)
}
