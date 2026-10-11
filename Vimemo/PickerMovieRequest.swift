import Foundation
import PhotosUI

/// Owns a system Photos transfer until completion; a preview in Photos is not
/// sufficient to create a draft. Cancellation also reclaims a late delivery.
final class PickerMovieRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ImportedMovie?, Error>?
    private var progress: Progress?
    private var completed = false
    private var cancelled = false

    var fractionCompleted: Double? {
        lock.lock(); defer { lock.unlock() }
        guard let progress, progress.totalUnitCount > 0 else { return nil }
        return min(1, max(0, progress.fractionCompleted))
    }

    func load(start: (@escaping @Sendable (Result<ImportedMovie?, Error>) -> Void) -> Progress) async throws -> ImportedMovie? {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if completed { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                lock.unlock()
                let progress = start { [self] result in finish(result) }
                lock.lock(); self.progress = progress; let shouldCancel = cancelled; lock.unlock()
                if shouldCancel { progress.cancel() }
            }
        } onCancel: { self.cancel() }
    }

    func cancel() {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        cancelled = true
        let progress = progress
        lock.unlock()
        finish(.failure(CancellationError()))
        progress?.cancel()
    }

    private func finish(_ result: Result<ImportedMovie?, Error>) {
        lock.lock()
        guard !completed else {
            let reclaim = cancelled
            lock.unlock()
            if reclaim, case .success(let movie?) = result { try? FileManager.default.removeItem(at: movie.url) }
            return
        }
        completed = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
