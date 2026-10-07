import XCTest
import UIKit
import AVFoundation
@testable import Vimemo

final class CoverPreviewTests: XCTestCase {
    @MainActor func testScrubbingKeepsDisplayedFrameWhileNextFrameDecodes() async throws {
        let preview = CoverPreview()
        let initial = expectation(description: "First frame displayed")
        let nextStarted = expectation(description: "Next frame decoding")
        let frame = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }.cgImage)
        preview.configure { time, _, _ in
            if time == 0 { initial.fulfill() }
            else {
                nextStarted.fulfill()
                try await Task.sleep(for: .seconds(1))
            }
            return frame
        }
        preview.request(time: 0, photo: nil)
        await fulfillment(of: [initial], timeout: 2)
        await Task.yield()
        XCTAssertNotNil(preview.image)
        preview.request(time: 1, photo: nil)
        await fulfillment(of: [nextStarted], timeout: 2)
        XCTAssertNotNil(preview.image, "Dragging must keep the last frame, rather than show a loading spinner")
        preview.stop()
    }

    @MainActor func testRapidScrubbingCoalescesPendingFramesAndFinishesExactly() async throws {
        let preview = CoverPreview()
        let started = expectation(description: "Decode in progress")
        let finished = expectation(description: "Latest exact frame decoded")
        let frame = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }.cgImage)
        var release: CheckedContinuation<Void, Never>?
        var requests: [Double] = []
        var exactRequests: [Bool] = []
        preview.configure { time, _, exact in
            requests.append(time); exactRequests.append(exact)
            if time == 0 {
                await withCheckedContinuation { release = $0; started.fulfill() }
            } else { finished.fulfill() }
            return frame
        }
        preview.request(time: 0, photo: nil, exact: false)
        await fulfillment(of: [started], timeout: 2)
        for time in 1...50 { preview.request(time: Double(time), photo: nil, exact: false) }
        preview.request(time: 50, photo: nil, exact: true)
        release?.resume()
        await fulfillment(of: [finished], timeout: 2)
        await Task.yield()
        XCTAssertEqual(requests, [0, 50], "Obsolete drag positions must not form a decoding backlog")
        XCTAssertEqual(exactRequests, [false, true])
        XCTAssertTrue(preview.isSettled)
        preview.stop()
    }

    @MainActor func testClosingPickerRejectsInFlightFrame() async throws {
        let preview = CoverPreview()
        let started = expectation(description: "Frame started")
        let returned = expectation(description: "Frame returned after cancellation")
        let frame = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }.cgImage)
        var release: CheckedContinuation<Void, Never>?
        preview.configure { _, _, _ in
            await withCheckedContinuation { release = $0; started.fulfill() }
            returned.fulfill()
            return frame
        }
        preview.request(time: 0, photo: nil)
        await fulfillment(of: [started], timeout: 2)
        preview.stop()
        release?.resume()
        await fulfillment(of: [returned], timeout: 2)
        await Task.yield()
        XCTAssertNil(preview.image)
        XCTAssertFalse(preview.isSettled)
    }

    @MainActor func testIdleScrubRefinesLastFrameWithoutAnEditingEndEvent() async throws {
        let preview = CoverPreview()
        let refined = expectation(description: "Idle scrub refined exactly")
        let frame = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }.cgImage)
        preview.configure { time, _, exact in
            XCTAssertEqual(time, 1)
            if exact { refined.fulfill() }
            return frame
        }
        preview.request(time: 1, photo: nil, exact: false)
        await fulfillment(of: [refined], timeout: 2)
        await Task.yield()
        XCTAssertTrue(preview.isSettled)
        XCTAssertNotNil(preview.image)
        preview.stop()
    }

    func testReusableDecoderMatchesExactCoverPipelineAndCachesFrames() async throws {
        let source = try XCTUnwrap(Bundle(for: ProjectStore.self).url(forResource: "Demo", withExtension: "mov"))
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        var project = VideoProject(title: "Scrub", filename: "Demo.mov", thumbnailFilename: "", duration: duration,
                                   width: 960, height: 1280, frameRate: 30, clips: [Clip()])
        project.settings.ratio = .square
        project.settings.rotation = 1
        project.settings.mirrored = true
        project.settings.look = .film
        project.settings.speed = 0.5
        let renderer = CoverFrameRenderer(source: source, project: project)
        let expected = try await MediaProcessor.frame(url: source, time: 1.25, settings: project.settings)
        let fast = try await renderer.frame(time: 1.25, photo: nil, exact: false)
        XCTAssertLessThanOrEqual(max(fast.width, fast.height), 480)
        let actual = try await renderer.frame(time: 1.25, photo: nil, exact: true)
        XCTAssertEqual(actual.width, expected.width)
        XCTAssertEqual(actual.height, expected.height)
        XCTAssertEqual(pixelSample(actual), pixelSample(expected), "Settled cover must keep the export's geometry, filters and selected time")
        let cached = try await renderer.frame(time: 1.25, photo: nil, exact: true)
        XCTAssertTrue(cached === actual)
        // Measure cold requests versus reusing the prepared decoder on distinct frames.
        let times = [0.25, 0.5, 0.75, 1.0, 1.5, 2.0]
        let coldStart = ContinuousClock.now
        for time in times { _ = try await MediaProcessor.frame(url: source, time: time, settings: project.settings) }
        let cold = coldStart.duration(to: .now)
        let warmStart = ContinuousClock.now
        for time in times { _ = try await renderer.frame(time: time, photo: nil, exact: false) }
        let warm = warmStart.duration(to: .now)
        print("Cover scrubbing: fresh decoder \(cold), reused decoder \(warm), \(times.count) distinct positions")
        await renderer.cancel()
    }

    private func pixelSample(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        return pixels
    }
}
