import XCTest
import AVFoundation
import Photos
import UIKit
@testable import Vimemo

final class DurationAndCoverTests: XCTestCase {
    @MainActor func testUnlimitedSettingUpdatesExistingDraftsAndSurvivesRelaunch() async throws {
        let previous = UserDefaults.standard.object(forKey: "unlimitedDuration")
        defer { if let previous { UserDefaults.standard.set(previous, forKey: "unlimitedDuration") } else { UserDefaults.standard.removeObject(forKey: "unlimitedDuration") } }
        UserDefaults.standard.set(false, forKey: "unlimitedDuration")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(root: root)
        let source = try XCTUnwrap(Bundle(for: ProjectStore.self).url(forResource: "Demo", withExtension: "mov"))
        let project = try await store.importVideo(source, title: "Duration")
        XCTAssertEqual(project.clips[0].duration, 3, accuracy: 0.01)
        store.setUnlimitedDuration(true)
        var draft = store.projects[0]
        draft.clips[0].end = draft.duration
        draft.settings.speed = 0.5
        draft.clips[0].normalize(sourceDuration: draft.duration, speed: 0.5, maxOutputDuration: draft.settings.maxOutputDuration)
        store.update(draft); store.persist()
        let restored = ProjectStore(root: root)
        XCTAssertNil(restored.projects[0].settings.maxOutputDuration)
        XCTAssertEqual(restored.projects[0].clips[0].end, draft.duration)
        restored.setUnlimitedDuration(false)
        XCTAssertEqual(restored.projects[0].clips[0].duration / 0.5, 3, accuracy: 0.01)
        let unlimitedImport = ProjectStore(root: root.appendingPathComponent("New"))
        unlimitedImport.setUnlimitedDuration(true)
        let full = try await unlimitedImport.importVideo(source, title: "Full")
        XCTAssertEqual(full.clips[0].duration, full.duration, accuracy: 0.01)
    }

    func testLegacyDraftsStillDecodeWithThreeSecondLimitAndVideoCover() throws {
        let clip = Clip(start: 0, end: 3, cover: 1)
        var oldClip = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(clip)) as? [String: Any])
        oldClip.removeValue(forKey: "coverPhotoFilename")
        let decodedClip = try JSONDecoder().decode(Clip.self, from: JSONSerialization.data(withJSONObject: oldClip))
        XCTAssertNil(decodedClip.coverPhotoFilename)
        var oldSettings = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(EditSettings())) as? [String: Any])
        oldSettings.removeValue(forKey: "unlimitedDuration")
        let decoded = try JSONDecoder().decode(EditSettings.self, from: JSONSerialization.data(withJSONObject: oldSettings))
        XCTAssertEqual(decoded.maxOutputDuration, 3)
    }

    @MainActor func testLongLivePhotoUsesLateSelectedVideoFrame() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(root: root)
        let source = try XCTUnwrap(Bundle(for: ProjectStore.self).url(forResource: "Demo", withExtension: "mov"))
        var project = try await store.importVideo(source, title: "Long Live")
        project.settings.unlimitedDuration = true
        project.settings.speed = 0.5
        project.clips[0] = Clip(start: 0, end: 5, cover: 4)
        let output = try await LivePhotoExporter().export(source: store.url(for: project.filename), project: project, clip: project.clips[0], directory: root.appendingPathComponent("Export")) { _ in }
        XCTAssertEqual(output.duration, 10)
        let movie = AVURLAsset(url: output.urls[1])
        let duration = try await movie.load(.duration).seconds
        XCTAssertEqual(duration, 10, accuracy: 0.05)
        let metadataTracks = try await movie.loadTracks(withMediaType: .metadata)
        let metadataTrack = try XCTUnwrap(metadataTracks.first)
        let reader = try AVAssetReader(asset: movie)
        let trackOutput = AVAssetReaderTrackOutput(track: metadataTrack, outputSettings: nil)
        reader.add(trackOutput)
        let adaptor = AVAssetReaderOutputMetadataAdaptor(assetReaderTrackOutput: trackOutput)
        XCTAssertTrue(reader.startReading())
        XCTAssertEqual(try XCTUnwrap(adaptor.nextTimedMetadataGroup()).timeRange.start.seconds, 8, accuracy: 0.05)
        reader.cancelReading()
        await assertLivePhotoRecognized(output.urls)
    }

    @MainActor func testAlbumCoverPersistsMatchesPreviewAndKeepsLivePair() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProjectStore(root: root)
        let source = try XCTUnwrap(Bundle(for: ProjectStore.self).url(forResource: "Demo", withExtension: "mov"))
        var project = try await store.importVideo(source, title: "Album Cover")
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 640)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 320, height: 640))
        }
        let filename = try store.importCoverPhoto(try XCTUnwrap(photo.pngData()), project: project)
        project.settings.ratio = .square; project.settings.rotation = 1; project.settings.mirrored = true
        project.clips[0].coverPhotoFilename = filename
        store.update(project); store.persist()
        let restored = ProjectStore(root: root)
        project = try XCTUnwrap(restored.projects.first)
        XCTAssertEqual(project.clips[0].coverPhotoFilename, filename)
        let preview = try await MediaProcessor.cover(source: store.url(for: project.filename), project: project, clip: project.clips[0], photo: store.url(for: filename))
        XCTAssertEqual(preview.width, preview.height)
        let output = try await LivePhotoExporter().export(source: store.url(for: project.filename), project: project, clip: project.clips[0], directory: root.appendingPathComponent("Export")) { _ in }
        let exported = try XCTUnwrap(UIImage(contentsOfFile: output.thumbnailURL.path)?.cgImage)
        XCTAssertEqual(exported.width, exported.height)
        var rgba = [UInt8](repeating: 0, count: 4)
        let color = try XCTUnwrap(CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        color.draw(exported, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertGreaterThan(rgba[0], 230); XCTAssertLessThan(rgba[1], 20); XCTAssertLessThan(rgba[2], 20)
        await assertLivePhotoRecognized(output.urls)
    }

    private func assertLivePhotoRecognized(_ urls: [URL]) async {
        let recognized = expectation(description: "System accepts cover and motion pair")
        var actual: PHLivePhoto?
        let request = PHLivePhoto.request(withResourceFileURLs: urls, placeholderImage: nil, targetSize: CGSize(width: 200, height: 200), contentMode: .aspectFit) { photo, info in
            if info[PHLivePhotoInfoIsDegradedKey] as? Bool == true { return }
            actual = photo; recognized.fulfill()
        }
        await fulfillment(of: [recognized], timeout: 20)
        PHLivePhoto.cancelRequest(withRequestID: request)
        XCTAssertNotNil(actual)
    }
}
