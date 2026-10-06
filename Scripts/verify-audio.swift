import Foundation
import AVFoundation

@main struct VerifyAudio {
    static func main() async throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let audioURL = folder.appendingPathComponent("tone.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100 * 6)!
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<2 {
            for index in 0..<Int(buffer.frameLength) { buffer.floatChannelData![channel][index] = Float(sin(Double(index) / 44100 * 440 * .pi * 2) * 0.15) }
        }
        do { let file = try AVAudioFile(forWriting: audioURL, settings: format.settings); try file.write(from: buffer) }
        let video = AVURLAsset(url: source), audio = AVURLAsset(url: audioURL)
        let comp = AVMutableComposition()
        let videoTrack = try await video.loadTracks(withMediaType: .video)[0]
        let audioTrack = try await audio.loadTracks(withMediaType: .audio)[0]
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: 6, preferredTimescale: 600))
        try comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(range, of: videoTrack, at: .zero)
        try comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(range, of: audioTrack, at: .zero)
        let combined = folder.appendingPathComponent("with-audio.mov")
        try? FileManager.default.removeItem(at: combined)
        let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough)!
        print("Creating audio fixture")
        try await session.export(to: combined, as: .mov)
        for speed in [0.5, 1, 1.5, 2] {
            for muted in [false, true] {
                var project = VideoProject(title: "Audio verification", filename: "", thumbnailFilename: "", duration: 6, width: 960, height: 1280, frameRate: 30, clips: [Clip(start: 1, end: 1 + min(3, 3 * speed), cover: 1.5)])
                project.settings.speed = speed; project.settings.muted = muted
                let directory = folder.appendingPathComponent("speed-\(speed)-muted-\(muted)")
                try? FileManager.default.removeItem(at: directory)
                let output = try await LivePhotoExporter().export(source: combined, project: project, clip: project.clips[0], directory: directory) { _ in }
                let asset = AVURLAsset(url: output.urls[1])
                let tracks = try await asset.loadTracks(withMediaType: .audio)
                guard tracks.isEmpty == muted else { throw StudioError.message("Audio mute state incorrect") }
                let duration = try await asset.load(.duration).seconds
                guard abs(duration - project.clips[0].duration / speed) < 0.06 else { throw StudioError.message("Duration incorrect") }
                if !muted {
                    let reader = try AVAssetReader(asset: asset)
                    let output = AVAssetReaderTrackOutput(track: tracks[0], outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
                    reader.add(output); reader.startReading()
                    guard output.copyNextSampleBuffer() != nil else { throw StudioError.message("Audio sample missing") }
                    reader.cancelReading()
                }
                print("PASS: speed=\(speed), muted=\(muted), duration=\(duration)")
            }
        }
        print("All 8 audio combinations passed")
    }
}
