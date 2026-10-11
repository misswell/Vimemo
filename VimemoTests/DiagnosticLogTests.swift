import XCTest
@testable import Vimemo

final class DiagnosticLogTests: XCTestCase {
    func testSnapshotRedactsSystemErrorPayloadAndKeepsUnderlyingCodes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = DiagnosticLog(directory: directory)
        let underlying = NSError(domain: NSOSStatusErrorDomain, code: -12784, userInfo: [NSLocalizedDescriptionKey: "private recording location"])
        let error = NSError(domain: "AVFoundationErrorDomain", code: -11800, userInfo: [
            NSUnderlyingErrorKey: underlying,
            NSFilePathErrorKey: "/private/user/movie.mov",
            NSLocalizedDescriptionKey: "private recording title"
        ])
        log.record("export.failed", "stage=cover", error: error)
        let snapshot = try await log.snapshot()
        defer { try? FileManager.default.removeItem(at: snapshot.deletingLastPathComponent()) }
        let text = try String(contentsOf: snapshot, encoding: .utf8)
        XCTAssertTrue(text.contains("export.failed"))
        XCTAssertTrue(text.contains("AVFoundationErrorDomain(-11800) > NSOSStatusErrorDomain(-12784)"))
        XCTAssertFalse(text.contains("private recording"))
        XCTAssertFalse(text.contains("/private/user"))
        XCTAssertFalse(text.contains("movie.mov"))
    }

    func testRotationBoundsDiskUseAndSharesRecentEventsInOrder() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = DiagnosticLog(directory: directory, limit: 1024)
        for index in 0..<100 { log.record("test.event", "index=\(index) " + String(repeating: "x", count: 40)) }
        let snapshot = try await log.snapshot()
        defer { try? FileManager.default.removeItem(at: snapshot.deletingLastPathComponent()) }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        XCTAssertEqual(files.count, 2)
        for file in files { XCTAssertLessThanOrEqual(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 1024) }
        let text = try String(contentsOf: snapshot, encoding: .utf8)
        XCTAssertTrue(text.contains("index=99"))
        XCTAssertFalse(text.contains("index=0 "))
        let a = try XCTUnwrap(text.range(of: "index=98"))
        let b = try XCTUnwrap(text.range(of: "index=99"))
        XCTAssertLessThan(a.lowerBound, b.lowerBound)
    }
}
