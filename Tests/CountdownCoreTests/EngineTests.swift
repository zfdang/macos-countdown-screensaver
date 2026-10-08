import XCTest

@testable import CountdownCore

final class EngineTests: XCTestCase {
  func testUnitLabelsHaveGapAndFitCompactRows() {
    let wide = DigitRowLayout(rowHeight: 185, screenWidth: 1000, screenHeight: 650, compact: false)
    XCTAssertGreaterThan(wide.unitSize, 22)
    XCTAssertGreaterThan(wide.unitOffset - wide.digitHeight, 12)
    for (width, height) in [(320.0, 240.0), (450, 800), (590, 400)] {
      let rowHeight = height * 0.84 * 0.26
      let row = DigitRowLayout(
        rowHeight: rowHeight, screenWidth: width, screenHeight: height, compact: true)
      XCTAssertGreaterThan(row.unitOffset, row.digitHeight)
      XCTAssertLessThanOrEqual(row.unitOffset + row.unitHeight, rowHeight)
    }
  }
  func testFooterCollapsesHiddenDateWithoutLeavingEmptyRow() {
    for compact in [false, true] {
      let withDate = FooterLayout(height: 650, compact: compact, showDate: true, showNext: true)
      let withoutDate = FooterLayout(height: 650, compact: compact, showDate: false, showNext: true)
      XCTAssertEqual(withDate.dateY, withoutDate.positionY)
      XCTAssertEqual(withDate.positionY! - withoutDate.positionY!, 0.13, accuracy: 0.0001)
      XCTAssertEqual(withDate.nextY! - withoutDate.nextY!, 0.13, accuracy: 0.0001)
      XCTAssertNil(withoutDate.dateY)
      XCTAssertNil(
        FooterLayout(height: 80, compact: compact, showDate: true, showNext: false).positionY)
      XCTAssertNil(
        FooterLayout(height: 650, compact: compact, showDate: false, showNext: false).nextY)
    }
  }

  func configuration(_ timestamps: [Double]) -> Configuration {
    var result = Configuration()
    result.events = timestamps.enumerated().map {
      CountdownEvent(
        createdOrder: $0.offset, input: DateInput(year: 2026, month: 1, day: 1),
        resolvedTimestamp: $0.element)
    }
    return result
  }
  func tick(
    _ engine: inout CountdownEngine, _ config: Configuration, _ time: Double, _ uptime: Double
  ) -> CountdownState {
    engine.tick(configuration: config, now: Date(timeIntervalSince1970: time), uptime: uptime)
  }
  func testEmptyAndAllExpired() {
    var engine = CountdownEngine()
    XCTAssertEqual(tick(&engine, configuration([]), 100, 0), .empty)
    let c = configuration([90, 95])
    XCTAssertEqual(tick(&engine, c, 100, 0), .completed(c.events[1]))
  }
  func testSortingAndNearestFutureEvent() {
    var engine = CountdownEngine()
    let c = configuration([300, 50, 200, 100, 400])
    guard case .counting(let group, let remaining, let next) = tick(&engine, c, 100, 0) else {
      return XCTFail()
    }
    XCTAssertEqual(group.timestamp, 200)
    XCTAssertEqual(group.firstPosition, 3)
    XCTAssertEqual(remaining.seconds, 40)
    XCTAssertEqual(remaining.minutes, 1)
    XCTAssertEqual(next?.timestamp, 300)
  }
  func testFiveEventsAdvanceAndKeepConfiguration() {
    var engine = CountdownEngine()
    let c = configuration([10, 20, 30, 40, 50])
    _ = tick(&engine, c, 9, 0)
    for index in 0..<5 {
      let t = Double((index + 1) * 10)
      _ = tick(&engine, c, t - 1, t - 10)
      guard case .reached(let group) = tick(&engine, c, t, t - 9) else {
        return XCTFail("No expiration at \(t)")
      }
      XCTAssertEqual(group.firstPosition, index + 1)
      let state = tick(&engine, c, t + 2, t - 7)
      if index == 4 {
        XCTAssertEqual(state, .completed(c.events[4]))
      } else if case .counting(let next, _, _) = state {
        XCTAssertEqual(next.firstPosition, index + 2)
      } else {
        XCTFail()
      }
    }
    XCTAssertEqual(c.events.count, 5)
  }
  func testSimultaneousGroupsAndStableOrder() {
    let c = configuration([20, 10, 20, 30])
    let groups = CountdownEngine.groups(in: c)
    XCTAssertEqual(groups.map(\.timestamp), [10, 20, 30])
    XCTAssertEqual(groups[1].events.map(\.createdOrder), [0, 2])
    XCTAssertEqual(groups[1].firstPosition, 2)
    XCTAssertEqual(groups[1].lastPosition, 3)
  }
  func testNearbyExpirationReplacesPreviousMessage() {
    var engine = CountdownEngine()
    let c = configuration([10, 11])
    _ = tick(&engine, c, 9, 0)
    _ = tick(&engine, c, 10, 1)
    guard case .reached(let group) = tick(&engine, c, 11, 2) else { return XCTFail() }
    XCTAssertEqual(group.timestamp, 11)
  }
  func testSleepClockJumpsResetAndRevisionChangesDoNotReplay() {
    var engine = CountdownEngine()
    var c = configuration([10, 20, 30])
    _ = tick(&engine, c, 9, 0)
    guard case .counting(let group, _, _) = tick(&engine, c, 25, 16) else { return XCTFail() }
    XCTAssertEqual(group.timestamp, 30)
    guard case .counting(let back, _, _) = tick(&engine, c, 5, 17) else { return XCTFail() }
    XCTAssertEqual(back.timestamp, 10)
    _ = tick(&engine, c, 9, 21)
    c.revision = UUID()
    guard case .counting(let afterSave, _, _) = tick(&engine, c, 10, 22) else { return XCTFail() }
    XCTAssertEqual(afterSave.timestamp, 20)
    engine.reset()
    guard case .counting = tick(&engine, c, 20, 23) else { return XCTFail() }
  }
  func testWallClockJumpWithShortMonotonicInterval() {
    var engine = CountdownEngine()
    let c = configuration([10, 20, 40])
    _ = tick(&engine, c, 9, 0)
    guard case .counting(let group, _, _) = tick(&engine, c, 30, 1) else { return XCTFail() }
    XCTAssertEqual(group.timestamp, 40)
  }
  func testFixedDayRoundingZeroAndLargeCounts() {
    XCTAssertEqual(RemainingTime(target: 86400 + 3661, now: 0).digits, ["01", "01", "01", "01"])
    XCTAssertEqual(RemainingTime(target: 0.1, now: 0).seconds, 1)
    XCTAssertEqual(RemainingTime(target: 0, now: 0).digits, ["00", "00", "00", "00"])
    XCTAssertEqual(RemainingTime(target: -100, now: 0).days, 0)
    XCTAssertEqual(RemainingTime(target: 1234 * 86400, now: 0).digits[0], "1234")
    XCTAssertEqual(RemainingTime(target: .infinity, now: 0).seconds, 0)
  }
  func testMovementOncePerMinuteAndSafeBounds() {
    for (w, h) in [(1000.0, 600.0), (320, 240), (450, 800), (1, 1)] {
      func layout(_ time: Double, _ preview: Bool = false, _ move: Bool = true) -> ContentLayout {
        ContentLayout(width: w, height: h, dayDigits: 5, move: move, preview: preview, uptime: time)
      }
      XCTAssertEqual(layout(0), layout(59.99))
      XCTAssertNotEqual(layout(59.99), layout(60))
      XCTAssertEqual(layout(60, true).offsetX, 0)
      XCTAssertEqual(layout(60, true).offsetY, 0)
      XCTAssertEqual(layout(60, false, false).offsetY, 0)
      for step in 0..<100 {
        let l = layout(Double(step * 60))
        XCTAssertLessThanOrEqual(abs(l.offsetX), w * 0.02)
        XCTAssertLessThanOrEqual(abs(l.offsetY), h * 0.02)
        XCTAssertGreaterThan(l.digitSize, 0)
      }
    }
  }
  func testResponsiveLayoutAndNextHint() {
    XCTAssertTrue(
      ContentLayout(width: 320, height: 240, dayDigits: 2, move: true, preview: true, uptime: 0)
        .compact)
    XCTAssertFalse(
      ContentLayout(width: 320, height: 240, dayDigits: 2, move: true, preview: true, uptime: 0)
        .showNext)
    XCTAssertTrue(
      ContentLayout(width: 1200, height: 800, dayDigits: 2, move: true, preview: true, uptime: 0)
        .showNext)
  }
}
