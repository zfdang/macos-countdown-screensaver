import Foundation

// Owns only a Foundation timer, never actor-isolated UI state. Cleanup also works from deinit.
final class TimerLifetime: @unchecked Sendable {
  private let lock = NSLock()
  private var timer: Timer?

  func replace(with replacement: Timer?) {
    lock.lock()
    defer { lock.unlock() }
    timer?.invalidate()
    timer = replacement
  }

  deinit { timer?.invalidate() }
}
