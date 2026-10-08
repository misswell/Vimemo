import XCTest
import UIKit
@testable import Vimemo

final class ThumbnailLoaderTests: XCTestCase {
    @MainActor private func fixture(_ color: UIColor = .red) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("thumbnail.jpg")
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 1200), format: format).jpegData(withCompressionQuality: 0.9) { context in
            color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
        }
        try data.write(to: url)
        return url
    }

    @MainActor func testConcurrentCellsAndRevisitedCellsReuseDecodedThumbnail() async throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let loader = ThumbnailLoader()
        let images = await withTaskGroup(of: UIImage?.self, returning: [UIImage].self) { group in
            for _ in 0..<24 { group.addTask { await loader.image(for: url, maxPixelSize: 512) } }
            var result: [UIImage] = []
            for await image in group { if let image { result.append(image) } }
            return result
        }
        XCTAssertEqual(images.count, 24)
        let first = try XCTUnwrap(images.first)
        XCTAssertTrue(images.allSatisfy { $0 === first }, "Visible cells must share one decode")
        let revisited = await loader.image(for: url, maxPixelSize: 512)
        XCTAssertTrue(revisited === first, "Tab transitions and revisiting rows must reuse the decoded image")
        XCTAssertEqual(first.cgImage?.width, 512)
        XCTAssertEqual(first.cgImage?.height, 384)
    }

    @MainActor func testReplacedFileAndDifferentResolutionDoNotReuseStaleImage() async throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let loader = ThumbnailLoader()
        let firstLoaded = await loader.image(for: url, maxPixelSize: 512)
        let first = try XCTUnwrap(firstLoaded)
        let largeLoaded = await loader.image(for: url, maxPixelSize: 1024)
        let large = try XCTUnwrap(largeLoaded)
        XCTAssertEqual(large.cgImage?.width, 1024)
        XCTAssertFalse(first === large)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 123)], ofItemAtPath: url.path)
        let replacedLoaded = await loader.image(for: url, maxPixelSize: 512)
        let replaced = try XCTUnwrap(replacedLoaded)
        XCTAssertFalse(first === replaced)
    }

    @MainActor func testMissingImageCanBeRetriedWithoutCachingFailure() async throws {
        let fixtureURL = try fixture()
        defer { try? FileManager.default.removeItem(at: fixtureURL.deletingLastPathComponent()) }
        let url = fixtureURL.deletingLastPathComponent().appendingPathComponent("later.jpg")
        let loader = ThumbnailLoader()
        let missing = await loader.image(for: url)
        XCTAssertNil(missing)
        try FileManager.default.copyItem(at: fixtureURL, to: url)
        let loaded = await loader.image(for: url)
        XCTAssertNotNil(loaded)
    }
}
