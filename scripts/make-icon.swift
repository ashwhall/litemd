// Renders Design/AppIcon.svg into the app icon set.
// Usage: swift scripts/make-icon.swift
import AppKit

let svg = URL(fileURLWithPath: "Design/AppIcon.svg")
let output = URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset")
guard let image = NSImage(contentsOf: svg) else { fatalError("Couldn't load \(svg.path)") }
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

var entries: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
        entries.append(#"{"filename":"\#(name)","idiom":"mac","scale":"\#(scale)x","size":"\#(points)x\#(points)"}"#)
    }
}
let contents = #"{"images":[\#(entries.joined(separator: ","))],"info":{"author":"xcode","version":1}}"#
try contents.write(to: output.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try #"{"info":{"author":"xcode","version":1}}"#.write(
    to: output.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(entries.count) icons to \(output.path)")
