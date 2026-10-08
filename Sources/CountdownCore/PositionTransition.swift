import Foundation

/// Move only while invisible: fade the old position out, then fade the new position in.
public struct PositionTransition {
  public static let duration: TimeInterval = 1.2
  public struct Frame: Equatable {
    public let step: Double
    public let opacity: Double
    public var layoutUptime: TimeInterval { step * 60 }
  }
  private struct Fade {
    let from: Double
    let to: Double
    let started: TimeInterval
  }
  public private(set) var frame = Frame(step: 0, opacity: 1)
  public var isAnimating: Bool { fade != nil }
  private var fade: Fade?
  private var lastTime: TimeInterval?
  public init() {}
  public mutating func reset() {
    self = PositionTransition()
  }
  public mutating func cancel() {
    frame = Frame(step: fade?.to ?? frame.step, opacity: 1)
    fade = nil
  }
  @discardableResult public mutating func update(uptime: TimeInterval, enabled: Bool) -> Frame {
    let time = uptime.isFinite ? max(0, uptime) : 0
    let step = floor(time / 60)
    defer { lastTime = time }
    // Startup, wake/long stalls and backwards uptime settle immediately; never replay old fades.
    guard enabled, let lastTime, time >= lastTime, time - lastTime <= 5 else {
      frame = Frame(step: step, opacity: 1)
      fade = nil
      return frame
    }
    if let active = fade, time - active.started >= Self.duration {
      frame = Frame(step: active.to, opacity: 1)
      fade = nil
    }
    if fade == nil, frame.step != step {
      fade = Fade(from: frame.step, to: step, started: time)
    }
    if let active = fade {
      let progress = max(0, (time - active.started) / (Self.duration / 2))
      if progress < 1 {
        frame = Frame(step: active.from, opacity: 1 - Self.ease(progress))
      } else {
        frame = Frame(step: active.to, opacity: Self.ease(progress - 1))
      }
    }
    return frame
  }
  private static func ease(_ fraction: Double) -> Double {
    let t = min(1, max(0, fraction))
    return t * t * (3 - 2 * t)
  }
}
