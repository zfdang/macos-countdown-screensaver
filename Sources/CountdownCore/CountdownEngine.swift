import Foundation

public struct RemainingTime: Equatable {
  public let days: Int, hours: Int, minutes: Int, seconds: Int
  public init(target: TimeInterval, now: TimeInterval) {
    let delta = target - now
    // Saturation protects this public API from non-finite or excessively large inputs.
    let total = delta.isFinite ? Int(min(Double(Int.max / 2), max(0, ceil(delta)))) : 0
    days = total / 86400
    hours = (total % 86400) / 3600
    minutes = (total % 3600) / 60
    seconds = total % 60
  }
  public var digits: [String] {
    [days, hours, minutes, seconds].map { String(format: "%02d", $0) }
  }
}

public struct EventGroup: Equatable {
  public let events: [CountdownEvent]
  public let firstPosition: Int
  public var lastPosition: Int { firstPosition + events.count - 1 }
  public var timestamp: TimeInterval { events[0].resolvedTimestamp }
  public func title(using l: Localization) -> String {
    let combined = events.enumerated().map {
      l.title($0.element, position: firstPosition + $0.offset)
    }.joined(separator: " / ")
    if combined.count <= 60 { return combined }
    let first = l.title(events[0], position: firstPosition)
    return events.count == 2
      ? l.text(.additionalOne, first) : l.text(.additionalMany, first, events.count - 1)
  }
  public func position(using l: Localization, total: Int) -> String {
    let range = events.count == 1 ? "\(firstPosition)" : "\(firstPosition)–\(lastPosition)"
    return l.text(events.count == 1 ? .eventPosition : .events, range, total)
  }
}

public enum CountdownState: Equatable {
  case empty
  case counting(EventGroup, RemainingTime, next: EventGroup?)
  case reached(EventGroup)
  case completed(CountdownEvent)
}

public struct CountdownEngine {
  private var previousNow: TimeInterval?
  private var previousUptime: TimeInterval?
  private var reachedGroup: EventGroup?
  private var revision: UUID?
  public init() {}
  public mutating func reset() { self = CountdownEngine() }
  public static func groups(in configuration: Configuration) -> [EventGroup] {
    var result: [EventGroup] = []
    for (index, event) in configuration.sortedEvents.enumerated() {
      if let last = result.last, last.timestamp == event.resolvedTimestamp {
        result[result.count - 1] = EventGroup(
          events: last.events + [event], firstPosition: last.firstPosition)
      } else {
        result.append(EventGroup(events: [event], firstPosition: index + 1))
      }
    }
    return result
  }
  public mutating func tick(
    configuration: Configuration, now: Date,
    uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) -> CountdownState {
    let timestamp = now.timeIntervalSince1970
    let groups = Self.groups(in: configuration)
    if revision != configuration.revision {
      reset()
      revision = configuration.revision
    }
    if let previousNow, let previousUptime {
      let elapsed = uptime - previousUptime
      let wall = timestamp - previousNow
      let continuous = elapsed >= 0 && elapsed <= 3 && wall >= 0 && abs(wall - elapsed) < 0.5
      if continuous {
        if let crossed = groups.last(where: {
          $0.timestamp > previousNow && $0.timestamp <= timestamp
        }) {
          reachedGroup = crossed
        }
      } else {
        reachedGroup = nil
      }
    }
    previousNow = timestamp
    previousUptime = uptime
    if let group = reachedGroup {
      if timestamp >= group.timestamp && timestamp < group.timestamp + 2 { return .reached(group) }
      reachedGroup = nil
    }
    guard !groups.isEmpty else { return .empty }
    if let index = groups.firstIndex(where: { $0.timestamp > timestamp }) {
      let next = index + 1 < groups.count ? groups[index + 1] : nil
      return .counting(
        groups[index], RemainingTime(target: groups[index].timestamp, now: timestamp), next: next)
    }
    guard let last = configuration.sortedEvents.last else { return .empty }
    return .completed(last)
  }
}

public struct ContentLayout: Equatable {
  public let compact: Bool
  public let digitSize: Double
  public let showNext: Bool
  public let offsetX: Double, offsetY: Double
  public init(
    width: Double, height: Double, dayDigits: Int, move: Bool, preview: Bool, uptime: TimeInterval
  ) {
    let w = max(1, width)
    let h = max(1, height)
    compact = w < 600 && w / h < 1.5
    digitSize = max(4, min(h * (compact ? 0.15 : 0.22), w / Double(max(10, dayDigits + 8)) * 1.25))
    showNext = w >= 600 && h >= 360
    let step = floor(max(0, uptime) / 60)
    offsetX = move && !preview ? sin(step * 1.7) * w * 0.02 : 0
    offsetY = move && !preview ? cos(step * 1.7) * h * 0.02 : 0
  }
}

// Footer rows collapse upward when optional content is hidden.
public struct FooterLayout: Equatable {
  public let dateY: Double?, positionY: Double?, nextY: Double?
  public init(height: Double, compact: Bool, showDate: Bool, showNext: Bool) {
    var cursor = compact ? 0.76 : 0.66
    dateY = height >= 140 && showDate ? cursor : nil
    if dateY != nil { cursor += 0.13 }
    positionY = height >= 140 ? cursor : nil
    if positionY != nil { cursor += 0.08 }
    nextY = showNext ? cursor : nil
  }
}
