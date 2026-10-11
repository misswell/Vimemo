import XCTest
@testable import Vimemo

final class PickerMovieRequestTests: XCTestCase {
    func testSynchronousDeliveryRemainsOwnedByCaller() async throws {
        let request = PickerMovieRequest()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1, 2, 3]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let movie = try await request.load { completion in
            completion(.success(ImportedMovie(url: url, name: "private")))
            return Progress(totalUnitCount: 100)
        }
        XCTAssertEqual(movie?.url, url)
        request.cancel()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testCancellationBeforeLoadDoesNotStartDownload() async {
        let request = PickerMovieRequest()
        request.cancel()
        do {
            _ = try await request.load { _ in XCTFail("Cancelled download must not start"); return Progress() }
            XCTFail("Cancellation should throw")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testCancellationCompletesWhileProviderWaitsAndReclaimsLateFile() async throws {
        let started = expectation(description: "provider started")
        let provider = ControlledProvider(started: started)
        let request = PickerMovieRequest()
        let task = Task { try await request.load(start: provider.start) }
        await fulfillment(of: [started], timeout: 2)
        request.cancel()
        do { _ = try await task.value; XCTFail("Cancellation should throw") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(provider.progress.isCancelled)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([1, 2, 3]).write(to: url)
        provider.deliver(ImportedMovie(url: url, name: "private"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    private final class ControlledProvider: @unchecked Sendable {
        let progress = Progress(totalUnitCount: 100)
        private let lock = NSLock()
        private let started: XCTestExpectation
        private var callback: (@Sendable (Result<ImportedMovie?, Error>) -> Void)?
        init(started: XCTestExpectation) { self.started = started }
        func start(_ callback: @escaping @Sendable (Result<ImportedMovie?, Error>) -> Void) -> Progress {
            lock.lock(); self.callback = callback; lock.unlock()
            started.fulfill()
            return progress
        }
        func deliver(_ movie: ImportedMovie) {
            lock.lock(); let callback = callback; lock.unlock()
            callback?(.success(movie))
        }
    }
}
