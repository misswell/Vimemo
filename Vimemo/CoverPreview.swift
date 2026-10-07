import SwiftUI

/// Owns the displayed frame independently of the slider's selected time.
@MainActor final class CoverPreview: ObservableObject {
    typealias Render = (Double, URL?, Bool) async throws -> CGImage
    @Published private(set) var image: UIImage?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSettled = false
    private var task: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var render: Render?
    private var cancel: (() -> Void)?
    private var generation = UUID()
    private var latest: Request?
    private struct Request: Equatable {
        let time: Double
        let photo: URL?
        let exact: Bool
    }

    func configure(cancel: (() -> Void)? = nil, render: @escaping Render) {
        stop()
        self.render = render
        self.cancel = cancel
    }

    func request(time: Double, photo: URL?, exact: Bool = true) {
        guard render != nil else { return }
        let request = Request(time: time, photo: photo, exact: exact)
        if latest == request, task != nil || isSettled { return }
        latest = request
        isSettled = false
        errorMessage = nil
        settleTask?.cancel()
        if !exact {
            let session = generation
            settleTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(150)) }
                catch { return }
                guard let self, self.generation == session, self.latest == request else { return }
                // Also refine after an idle interval: accessibility slider updates and
                // interrupted gestures can omit or reorder the final editing event.
                self.request(time: request.time, photo: request.photo, exact: true)
            }
        }
        guard task == nil else { return }
        let session = generation
        task = Task { [weak self] in
            guard let self, let render = self.render else { return }
            // Finish the current decode, then chase the latest selection. Restarting on
            // every slider event starves the decoder and leaves the preview frozen.
            while let request = self.latest {
                do {
                    let frame = try await render(request.time, request.photo, request.exact)
                    guard !Task.isCancelled, self.generation == session else { return }
                    if request.photo == self.latest?.photo {
                        self.image = UIImage(cgImage: frame)
                    }
                    if request == self.latest {
                        self.isSettled = request.exact
                        break
                    }
                } catch {
                    guard !Task.isCancelled, self.generation == session else { return }
                    if request == self.latest {
                        self.errorMessage = error.localizedDescription
                        break
                    }
                }
            }
            if self.generation == session { self.task = nil }
        }
    }

    func stop() {
        generation = UUID()
        settleTask?.cancel(); settleTask = nil
        task?.cancel(); task = nil; latest = nil
        cancel?()
        isSettled = false
    }
}
