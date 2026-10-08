import AppKit
import CountdownCore
import XCTest

@testable import CountdownUI

final class MovementRenderingTests: XCTestCase {
  @MainActor private func bitmap(_ view: CountdownContentView) throws -> NSBitmapImageRep {
    let image = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: image)
    return image
  }
  private func brightness(_ image: NSBitmapImageRep) throws -> Double {
    var total = 0.0
    for y in stride(from: 0, to: image.pixelsHigh, by: 8) {
      for x in stride(from: 0, to: image.pixelsWide, by: 8) {
        let color = try XCTUnwrap(image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        total += color.redComponent + color.greenComponent + color.blueComponent
      }
    }
    return total
  }
  func testTextFadesThroughBlackAndCountdownUpdatesDuringTransition() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let view = CountdownContentView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
      let host = NSWindow(contentRect: view.frame, styleMask: [], backing: .buffered, defer: false)
      host.isReleasedWhenClosed = false
      host.contentView = view
      defer {
        host.contentView = nil
        host.close()
      }
      let draft = DraftConfiguration(Configuration())
      _ = try draft.add(now: Date(timeIntervalSince1970: 100), zone: "UTC")
      view.configuration = try draft.validated()
      view.preferredLanguages = ["en"]
      view.update(now: Date(timeIntervalSince1970: 100), uptime: 59)
      let state = view.state
      let full = try bitmap(view)
      let initial = try brightness(full)
      XCTAssertGreaterThan(initial, 0)
      view.update(now: Date(timeIntervalSince1970: 100), uptime: 60)
      XCTAssertEqual(
        try full.representation(using: .png, properties: [:]),
        try bitmap(view).representation(using: .png, properties: [:]))
      XCTAssertTrue(view.advanceMovement(uptime: 60.3))
      XCTAssertEqual(view.state, state, "Extra fade frames must not tick the countdown engine")
      let half = try brightness(bitmap(view))
      XCTAssertLessThan(half, initial * 0.7)
      XCTAssertGreaterThan(half, initial * 0.3)
      view.update(now: Date(timeIntervalSince1970: 101), uptime: 60.4)
      XCTAssertNotEqual(view.state, state, "Normal countdown ticks continue during the fade")
      view.advanceMovement(uptime: 60.6)
      XCTAssertEqual(try brightness(bitmap(view)), 0, accuracy: 1e-9)
      view.advanceMovement(uptime: 60.9)
      XCTAssertGreaterThan(try brightness(bitmap(view)), 0)
      view.advanceMovement(uptime: 61.2)
      XCTAssertGreaterThan(try brightness(bitmap(view)), half)
    }
  }
  func testStoppingSaverAndDisablingMovementCancelPartialFade() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let saver = try XCTUnwrap(
        CountdownScreenSaverView(
          frame: NSRect(x: 0, y: 0, width: 800, height: 600), isPreview: false))
      saver.content.configuration = Configuration()
      let host = NSWindow(contentRect: saver.frame, styleMask: [], backing: .buffered, defer: false)
      host.isReleasedWhenClosed = false
      host.contentView = saver
      defer {
        host.contentView = nil
        host.close()
      }
      let now = Date(timeIntervalSince1970: 100)
      saver.content.update(now: now, uptime: 59)
      saver.content.update(now: now, uptime: 60)
      saver.content.advanceMovement(uptime: 60.3)
      let faded = try brightness(bitmap(saver.content))
      saver.stopAnimation()
      XCTAssertFalse(saver.content.movementTimerRunning)
      saver.content.update(now: now, uptime: 60.4)
      XCTAssertGreaterThan(try brightness(bitmap(saver.content)), faded)
      saver.content.update(now: now, uptime: 119)
      saver.content.update(now: now, uptime: 120)
      saver.content.advanceMovement(uptime: 120.3)
      saver.content.configuration.appearance.moveContent = false
      saver.content.update(now: now, uptime: 120.4)
      XCTAssertFalse(saver.content.movementTimerRunning)
      XCTAssertGreaterThan(try brightness(bitmap(saver.content)), faded)
      XCTAssertFalse(saver.content.advanceMovement(uptime: 121))
    }
  }
  @MainActor func testTemporaryTimerRunsFadeAndStopsAfterCompletion() async throws {
    _ = NSApplication.shared
    let view = CountdownContentView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let host = NSWindow(contentRect: view.frame, styleMask: [], backing: .buffered, defer: false)
    host.isReleasedWhenClosed = false
    host.contentView = view
    defer {
      host.contentView = nil
      host.close()
    }
    view.update(uptime: 59)
    let bright = try brightness(bitmap(view))
    var time = 60.0
    view.movementUptime = { time }
    view.update(uptime: time)
    XCTAssertTrue(view.movementTimerRunning)
    time = 60.3
    try await Task.sleep(nanoseconds: 300_000_000)
    let faded = try brightness(bitmap(view))
    XCTAssertLessThan(faded, bright * 0.8)
    time = 61.2
    let deadline = Date().addingTimeInterval(3)
    while view.movementTimerRunning && Date() < deadline {
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTAssertFalse(view.movementTimerRunning)
    XCTAssertGreaterThan(try brightness(bitmap(view)), faded)
  }
  func testDetachingAnAnimatingViewDoesNotRetainIt() async {
    await MainActor.run {
      _ = NSApplication.shared
      let host = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
        styleMask: [], backing: .buffered, defer: false)
      host.isReleasedWhenClosed = false
      weak var weakView: CountdownContentView?
      autoreleasepool {
        let view = CountdownContentView(frame: host.frame)
        weakView = view
        host.contentView = view
        view.update(uptime: 59)
        view.update(uptime: 60)
        view.advanceMovement(uptime: 60.3)
        host.contentView = nil
      }
      XCTAssertNil(weakView)
      host.close()
    }
  }
}
