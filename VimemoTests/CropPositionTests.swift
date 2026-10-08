import XCTest
import UIKit
import CoreImage
@testable import Vimemo

final class CropPositionTests: XCTestCase {
    func testDraggingImageDownSelectsUpperRegionAndClampsEdges() {
        let layout = CropPositionGeometry(imageSize: CGSize(width: 400, height: 800), viewport: CGSize(width: 200, height: 200))
        let position = layout.position(from: CGPoint(x: 0.4, y: 0.5), translation: CGSize(width: 80, height: 50))
        XCTAssertEqual(position.x, 0.4, "An axis with no cropped content must not move")
        XCTAssertEqual(position.y, 0.25)
        XCTAssertEqual(layout.position(from: position, translation: CGSize(width: 0, height: 500)).y, 0)
        XCTAssertEqual(layout.position(from: position, translation: CGSize(width: 0, height: -500)).y, 1)
    }
    func testDraggingWideImageRightSelectsLeftRegion() {
        let layout = CropPositionGeometry(imageSize: CGSize(width: 800, height: 400), viewport: CGSize(width: 200, height: 200))
        let position = layout.position(from: CGPoint(x: 0.5, y: 0.7), translation: CGSize(width: 100, height: 40))
        XCTAssertEqual(position.x, 0)
        XCTAssertEqual(position.y, 0.7)
    }
    func testPinchKeepsImagePointUnderMovingFingersAndAllowsBothAxesToPan() {
        let start = CropPositionGeometry(imageSize: CGSize(width: 800, height: 400), viewport: CGSize(width: 200, height: 200))
        let point = start.imagePoint(at: CGPoint(x: 80, y: 100), position: CGPoint(x: 0.5, y: 0.5))
        let zoomed = CropPositionGeometry(imageSize: start.imageSize, viewport: start.viewport, zoom: 2)
        let anchor = CGPoint(x: 100, y: 120)
        let position = zoomed.position(keeping: point, at: anchor)
        let actual = zoomed.imagePoint(at: anchor, position: position)
        XCTAssertEqual(actual.x, point.x, accuracy: 0.0001)
        XCTAssertEqual(actual.y, point.y, accuracy: 0.0001)
        let moved = zoomed.position(from: position, translation: CGSize(width: 30, height: 20))
        XCTAssertLessThan(moved.x, position.x); XCTAssertLessThan(moved.y, position.y)
        XCTAssertEqual(zoomed.position(from: moved, translation: CGSize(width: 9999, height: -9999)), CGPoint(x: 0, y: 1))
    }
    func testOldSettingsDefaultToOneAndZoomRoundTripsWithoutChangingOutputSize() throws {
        let decoder = JSONDecoder(), encoder = JSONEncoder()
        var settings = try decoder.decode(EditSettings.self, from: encoder.encode(EditSettings()))
        XCTAssertEqual(settings.effectiveCropZoom, 1)
        let base = MediaProcessor.dimensions(CGSize(width: 960, height: 1280), settings: settings)
        settings.cropZoom = 2.25; settings.cropX = 0.25
        let restored = try decoder.decode(EditSettings.self, from: encoder.encode(settings))
        XCTAssertEqual(restored.effectiveCropZoom, 2.25); XCTAssertEqual(restored.cropX, 0.25)
        XCTAssertEqual(MediaProcessor.dimensions(CGSize(width: 960, height: 1280), settings: restored), base)
        settings.cropZoom = 0.1; XCTAssertEqual(settings.effectiveCropZoom, 1)
        settings.cropZoom = 99; XCTAssertEqual(settings.effectiveCropZoom, 4)
        settings.cropZoom = .nan; XCTAssertEqual(settings.effectiveCropZoom, 1)
    }
    func testUncroppedCanvasRegionMatchesVideoAndPhotoCoverPipeline() async throws {
        let source = try XCTUnwrap(Bundle(for: ProjectStore.self).url(forResource: "Demo", withExtension: "mov"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = folder.appendingPathComponent("cover.png")
        let painted = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 800)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 400, width: 400, height: 400))
        }
        try XCTUnwrap(painted.pngData()).write(to: photo)
        for input in [URL?.none, photo] {
            for rotation in [0, 1] {
                var project = VideoProject(title: "Crop", filename: "source.mov", thumbnailFilename: "cover.jpg", duration: 6, width: 960, height: 1280, frameRate: 30, clips: [Clip(start: 0, end: 3, cover: 1.5)])
                project.settings.ratio = .square; project.settings.rotation = rotation
                project.settings.mirrored = true; project.settings.look = .warm
                let full = try await MediaProcessor.uncroppedCover(source: source, project: project, clip: project.clips[0], photo: input)
                for zoom in [1.0, 2.25] {
                project.settings.cropZoom = zoom
                let layout = CropPositionGeometry(imageSize: CGSize(width: full.width, height: full.height), viewport: CGSize(width: 200, height: 200), zoom: zoom)
                for position in [0.0, 0.25, 1.0] {
                    project.settings.cropX = position; project.settings.cropY = position
                    let rect = CGRect(x: layout.overflow.width * position / layout.scale, y: layout.overflow.height * position / layout.scale,
                                      width: 200 / layout.scale, height: 200 / layout.scale)
                    let canvas = try XCTUnwrap(full.cropping(to: rect))
                    let expected = try await MediaProcessor.cover(source: source, project: project, clip: project.clips[0], photo: input)
                    let lhs = sample(canvas), rhs = sample(expected)
                    for channel in 0..<3 { XCTAssertEqual(Double(lhs[channel]), Double(rhs[channel]), accuracy: 3, "Dragged canvas must agree with the saved cover, including photo rotation and mirroring") }
                }
                }
            }
        }
    }
    private func sample(_ image: CGImage) -> [UInt8] {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return pixel
    }
}
