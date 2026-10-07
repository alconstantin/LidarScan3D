import Foundation

/// Cancellation survives slow initialization. Invoke actions outside the lock so
/// a framework callback cannot deadlock by re-entering cancellation.
final class CancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var action: (() -> Void)?
    var isCancelled: Bool { lock.withLock { cancelled } }
    func attach(_ action: @escaping () -> Void) {
        let shouldCancel = lock.withLock {
            if cancelled { return true }
            self.action = action
            return false
        }
        if shouldCancel { action() }
    }
    func cancel() {
        let callback = lock.withLock {
            cancelled = true
            let callback = action
            action = nil
            return callback
        }
        callback?()
    }
    func clear() { lock.withLock { action = nil } }
}

struct CaptureProgress: Sendable {
    private(set) var passes = 0
    private(set) var shots = 0
    private(set) var lastPhotoAt = Date.now
    mutating func start(at date: Date) {
        if passes == 0 { passes = 1 }
        lastPhotoAt = date
    }
    mutating func newPass(at date: Date) { passes += 1; lastPhotoAt = date }
    mutating func update(shots: Int, at date: Date, paused: Bool) {
        if paused || shots != self.shots { lastPhotoAt = date }
        self.shots = shots
    }
    func isStalled(at date: Date) -> Bool { passes > 0 && date.timeIntervalSince(lastPhotoAt) >= 15 }
    // Avoid starting reconstruction from an empty or very sparse capture.
    static let minimumPhotos = 20
}
