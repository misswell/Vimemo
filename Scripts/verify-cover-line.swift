import Foundation
import AVFoundation

// Inspect a simulator recording of slow alternating cover-line drags.
// Usage: swift verify-cover-line.swift recording.mov y0 y1 x0 x1
// The pixel ROI must contain the marker's vertical stem and exclude labels.
let args = CommandLine.arguments
guard args.count == 6, let y0 = Int(args[2]), let y1 = Int(args[3]),
      let x0 = Int(args[4]), let x1 = Int(args[5]), y0 < y1, x0 < x1 else {
    fputs("Usage: swift verify-cover-line.swift recording.mov y0 y1 x0 x1\n", stderr)
    exit(2)
}
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let track = asset.tracks(withMediaType: .video)[0]
let reader = try AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
])
reader.add(output)
guard reader.startReading() else { throw reader.error! }
var positions = [(time: Double, x: Double)]()
while let sample = output.copyNextSampleBuffer() {
    guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
    guard x0 >= 0, y0 >= 0, x1 <= CVPixelBufferGetWidth(buffer), y1 <= CVPixelBufferGetHeight(buffer) else {
        fputs("ROI is outside the recording\n", stderr); exit(2)
    }
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    var runs = [(start: Int, width: Int)]()
    for x in x0..<x1 {
        var red = 0
        for y in y0..<y1 {
            let p = y * stride + x * 4
            if base[p + 2] > 200 && base[p + 1] < 100 && base[p] < 150 { red += 1 }
        }
        if Double(red) > Double(y1 - y0) * 0.85 {
            if let last = runs.last, x == last.start + last.width { runs[runs.count - 1].width += 1 }
            else { runs.append((x, 1)) }
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
    // Trim handles are wider; only the thin stem is the cover marker.
    let stems = runs.filter { (4...15).contains($0.width) }
    if stems.count == 1, let stem = stems.first {
        positions.append((CMSampleBufferGetPresentationTimeStamp(sample).seconds,
                          Double(stem.start) + Double(stem.width) / 2))
    }
}
if reader.status == .failed { throw reader.error! }
var reversals = 0, moves = 0
if positions.count >= 3 {
    for index in 2..<positions.count {
        let a = positions[index - 2], b = positions[index - 1], c = positions[index]
        let previous = b.x - a.x, next = c.x - b.x
        if abs(next) >= 4 { moves += 1 }
        if b.time - a.time < 0.15 && c.time - b.time < 0.15 &&
            abs(previous) >= 4 && abs(next) >= 4 && previous * next < 0 { reversals += 1 }
    }
}
print("Detected frames: \(positions.count), movements: \(moves), rapid reversals: \(reversals)")
guard positions.count >= 30, moves >= 20 else {
    fputs("Insufficient continuous drag footage or incorrect ROI\n", stderr); exit(2)
}
guard reversals <= 4 else {
    fputs("FAIL: Cover line flickers between old and new positions\n", stderr); exit(1)
}
print("PASS: Cover line follows continuous drags without rapid position flicker")
