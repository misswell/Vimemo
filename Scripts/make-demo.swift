import Foundation
import AVFoundation
import AppKit
import CoreImage

@main struct MakeDemo {
    static let width = 960, height = 1280
    static func scene(time: Double) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let w = Double(width), h = Double(height)
        let colors = [NSColor(red: 0.07, green: 0.18, blue: 0.31, alpha: 1).cgColor, NSColor(red: 0.5, green: 0.52, blue: 0.59, alpha: 1).cgColor, NSColor(red: 0.95, green: 0.63, blue: 0.42, alpha: 1).cgColor]
        let sky = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0, 0.6, 1])!
        c.drawLinearGradient(sky, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h * 0.43), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        c.setFillColor(NSColor(red: 1, green: 0.85, blue: 0.65, alpha: 1).cgColor)
        c.setShadow(offset: .zero, blur: 55, color: NSColor(red: 1, green: 0.67, blue: 0.37, alpha: 0.6).cgColor)
        c.fillEllipse(in: CGRect(x: w * 0.62, y: h * 0.53, width: 96, height: 96))
        c.setShadow(offset: .zero, blur: 0)
        let sea = CGGradient(colorsSpace: colorSpace, colors: [NSColor(red: 0.32, green: 0.43, blue: 0.47, alpha: 1).cgColor, NSColor(red: 0.07, green: 0.23, blue: 0.29, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
        c.saveGState(); c.clip(to: CGRect(x: 0, y: 0, width: w, height: h * 0.47))
        c.drawLinearGradient(sea, start: CGPoint(x: 0, y: h * 0.47), end: .zero, options: []); c.restoreGState()
        for index in 0..<90 {
            let depth = Double(index) / 90
            let y = h * 0.47 * (1 - depth * depth)
            let wave = CGMutablePath()
            let amplitude = 1 + depth * depth * 13
            wave.move(to: CGPoint(x: 0, y: y))
            for step in 0...60 {
                let x = Double(step) / 60 * w
                let offset = sin(x / (35 + depth * 70) + time * 1.7 + Double(index) * 1.5) * amplitude
                wave.addLine(to: CGPoint(x: x, y: y + offset))
            }
            c.addPath(wave)
            c.setStrokeColor(NSColor(red: 0.67, green: 0.81, blue: 0.78, alpha: 0.12 + depth * 0.35).cgColor)
            c.setLineWidth(0.6 + depth * 2); c.strokePath()
            if index < 50 {
                let center = w * 0.67 + sin(Double(index) * 7.4 + time * 0.2) * (8 + depth * 55)
                let reflectionWidth = 8 + depth * 100
                c.setFillColor(NSColor(red: 1, green: 0.76, blue: 0.5, alpha: 0.35 * (1 - depth)).cgColor)
                c.fill(CGRect(x: center - reflectionWidth / 2, y: y, width: reflectionWidth, height: 2 + depth * 3))
            }
        }
        let coast = CGMutablePath()
        coast.move(to: CGPoint(x: 0, y: h * 0.47)); coast.addLine(to: CGPoint(x: 0, y: h * 0.53))
        for index in 0...20 {
            let x = Double(index) / 20 * w * 0.46
            coast.addLine(to: CGPoint(x: x, y: h * 0.47 + (sin(Double(index) * 0.25) * 32 + sin(Double(index) * 0.8) * 10) * (1 - Double(index) / 20)))
        }
        coast.closeSubpath(); c.addPath(coast); c.setFillColor(NSColor(red: 0.12, green: 0.24, blue: 0.29, alpha: 1).cgColor); c.fillPath()
        let sand = CGMutablePath()
        sand.move(to: .zero); sand.addLine(to: CGPoint(x: w, y: 0)); sand.addLine(to: CGPoint(x: w, y: h * 0.11))
        sand.addCurve(to: CGPoint(x: 0, y: h * 0.27), control1: CGPoint(x: w * 0.55, y: h * 0.03), control2: CGPoint(x: w * 0.26, y: h * 0.25))
        sand.closeSubpath(); c.addPath(sand); c.setFillColor(NSColor(red: 0.22, green: 0.27, blue: 0.30, alpha: 1).cgColor); c.fillPath()
        for line in 0..<3 {
            let foam = CGMutablePath(); let shift = sin(time + Double(line)) * 10
            foam.move(to: CGPoint(x: w, y: h * 0.11 + Double(line) * 17 + shift))
            foam.addCurve(to: CGPoint(x: 0, y: h * 0.27 + Double(line) * 17 + shift), control1: CGPoint(x: w * 0.55, y: h * 0.03 + Double(line) * 20), control2: CGPoint(x: w * 0.26, y: h * 0.25 + Double(line) * 20))
            c.addPath(foam); c.setStrokeColor(NSColor(red: 0.82, green: 0.87, blue: 0.83, alpha: 0.65 - Double(line) * 0.15).cgColor); c.setLineWidth(4 - Double(line)); c.strokePath()
        }
        for bird in 0..<3 {
            let x = 200.0 + Double(bird) * 42 + time * 12, y = h * 0.71 + Double(bird % 2) * 20
            c.setStrokeColor(NSColor(red: 0.13, green: 0.22, blue: 0.31, alpha: 0.9).cgColor); c.setLineWidth(2)
            c.move(to: CGPoint(x: x - 8, y: y + 3)); c.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - 4, y: y + 6)); c.addQuadCurve(to: CGPoint(x: x + 8, y: y + 3), control: CGPoint(x: x + 4, y: y + 6)); c.strokePath()
        }
        // Deterministic film grain gives the sample depth without including third-party media.
        for index in 0..<14000 {
            let x = Double((index * 179 + 31) % width), y = Double((index * 313 + 79) % height)
            c.setFillColor(NSColor(white: index % 2 == 0 ? 1 : 0, alpha: 0.055).cgColor); c.fill(CGRect(x: x, y: y, width: 1.5, height: 1.5))
        }
        return c.makeImage()!
    }
    static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Demo.mov")
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height, AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 3_000_000]])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        let context = CIContext()
        for frame in 0..<180 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            try autoreleasepool {
                let cg = scene(time: Double(frame) / 30)
                var pixel: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixel)
                context.render(CIImage(cgImage: cg), to: pixel!)
                guard adaptor.append(pixel!, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)) else { throw writer.error! }
            }
        }
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error! }
        let poster = NSBitmapImageRep(cgImage: scene(time: 2))
        try poster.representation(using: .jpeg, properties: [.compressionFactor: 0.92])!.write(to: directory.appendingPathComponent("DemoPoster.jpg"))
        let iconDir = directory.deletingLastPathComponent().appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
        try FileManager.default.createDirectory(at: iconDir, withIntermediateDirectories: true)
        let icon = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        icon.setFillColor(NSColor(red: 0.047, green: 0.078, blue: 0.129, alpha: 1).cgColor); icon.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        icon.setStrokeColor(NSColor(red: 0.57, green: 0.866, blue: 0.941, alpha: 1).cgColor)
        icon.setLineWidth(24); icon.strokeEllipse(in: CGRect(x: 290, y: 290, width: 444, height: 444))
        icon.setLineWidth(28); icon.setLineDash(phase: 0, lengths: [3, 42]); icon.setLineCap(.round); icon.strokeEllipse(in: CGRect(x: 190, y: 190, width: 644, height: 644))
        icon.setLineDash(phase: 0, lengths: []); icon.setLineWidth(20); icon.strokeEllipse(in: CGRect(x: 399, y: 399, width: 226, height: 226))
        let png = NSBitmapImageRep(cgImage: icon.makeImage()!).representation(using: .png, properties: [:])!
        try png.write(to: iconDir.appendingPathComponent("AppIcon.png"))
        print("Created Demo.mov, DemoPoster.jpg and AppIcon.png")
    }
}
