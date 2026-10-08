import CountdownCore
import XCTest

final class PositionTransitionTests: XCTestCase {
  func testOldPositionFadesOutBeforeNewPositionFadesIn() {
    var fade = PositionTransition()
    XCTAssertEqual(fade.update(uptime: 59, enabled: true).opacity, 1)
    XCTAssertFalse(fade.isAnimating)
    let start = fade.update(uptime: 60, enabled: true)
    XCTAssertEqual(start.step, 0)
    XCTAssertEqual(start.opacity, 1)
    XCTAssertTrue(fade.isAnimating)
    let out = fade.update(uptime: 60.3, enabled: true)
    XCTAssertEqual(out.step, 0)
    XCTAssertEqual(out.opacity, 0.5, accuracy: 1e-9)
    let midpoint = fade.update(uptime: 60.6, enabled: true)
    XCTAssertEqual(midpoint.step, 1)
    XCTAssertEqual(midpoint.opacity, 0, accuracy: 1e-9)
    let into = fade.update(uptime: 60.9, enabled: true)
    XCTAssertEqual(into.step, 1)
    XCTAssertEqual(into.opacity, 0.5, accuracy: 1e-9)
    let end = fade.update(uptime: 61.2, enabled: true)
    XCTAssertEqual(end.opacity, 1)
    XCTAssertEqual(end.layoutUptime, 60)
    XCTAssertFalse(fade.isAnimating)
    XCTAssertEqual(fade.update(uptime: 119, enabled: true), end)
    fade.update(uptime: 120, enabled: true)
    XCTAssertTrue(fade.isAnimating)
    XCTAssertEqual(fade.frame.step, 1)
  }
  func testDisabledPreviewStartupResetAndCancelStayOpaque() {
    var fade = PositionTransition()
    fade.update(uptime: 59, enabled: true)
    fade.update(uptime: 60.3, enabled: true)
    fade.update(uptime: 60.5, enabled: false)
    XCTAssertFalse(fade.isAnimating)
    XCTAssertEqual(fade.frame.opacity, 1)
    fade.reset()
    fade.update(uptime: 10000.3, enabled: true)
    XCTAssertFalse(fade.isAnimating)
    XCTAssertEqual(fade.frame.opacity, 1)
    fade.update(uptime: 10019, enabled: true)
    fade.update(uptime: 10020, enabled: true)
    XCTAssertTrue(fade.isAnimating)
    fade.cancel()
    XCTAssertFalse(fade.isAnimating)
    XCTAssertEqual(fade.frame.opacity, 1)
    XCTAssertEqual(fade.frame.step, 167)
  }
  func testSleepAndClockDiscontinuitiesDoNotReplayFades() {
    var fade = PositionTransition()
    fade.update(uptime: 59, enabled: true)
    fade.update(uptime: 60, enabled: true)
    let wake = fade.update(uptime: 3600, enabled: true)
    XCTAssertEqual(wake.step, 60)
    XCTAssertEqual(wake.opacity, 1)
    XCTAssertFalse(fade.isAnimating)
    XCTAssertEqual(fade.update(uptime: 0, enabled: true).opacity, 1)
    XCTAssertFalse(fade.isAnimating)
    for invalid in [Double.nan, .infinity, -.infinity, -1] {
      XCTAssertEqual(fade.update(uptime: invalid, enabled: true).opacity, 1)
      XCTAssertFalse(fade.isAnimating)
    }
  }
  func testFadeOpacityIsBoundedMonotonicAndSmoothAtEndpoints() {
    var fade = PositionTransition()
    fade.update(uptime: 59, enabled: true)
    fade.update(uptime: 60, enabled: true)
    var previous = 1.0
    for tick in 1...60 {
      let frame = fade.update(uptime: 60 + Double(tick) / 100, enabled: true)
      XCTAssertLessThanOrEqual(frame.opacity, previous)
      XCTAssertGreaterThanOrEqual(frame.opacity, 0)
      previous = frame.opacity
    }
    for tick in 61...120 {
      let frame = fade.update(uptime: 60 + Double(tick) / 100, enabled: true)
      XCTAssertGreaterThanOrEqual(frame.opacity, previous)
      XCTAssertLessThanOrEqual(frame.opacity, 1)
      previous = frame.opacity
    }
    XCTAssertFalse(fade.isAnimating)
  }
}
