import AppKit
import CountdownCore
import ScreenSaver
import XCTest

@testable import CountdownUI

private final class TestBackend: ConfigurationBackend {
  var data: Data?
  var fail = false
  var reads = 0
  func read() -> Data? {
    reads += 1
    return data
  }
  func write(_ data: Data) throws {
    if fail { throw CountdownError.saveFailed }
    self.data = data
  }
}

final class InterfaceTests: XCTestCase {
  func testRenderInvalidationUsesVisibleValuesAndMovement() async {
    await MainActor.run {
      let view = CountdownContentView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
      let now = Date(timeIntervalSince1970: 100)
      view.configuration.appearance.moveContent = false
      view.preferredLanguages = ["en"]
      XCTAssertTrue(view.update(now: now, uptime: 0))
      XCTAssertFalse(view.update(now: now, uptime: 60))
      view.preferredLanguages = ["fr"]
      XCTAssertFalse(view.update(now: now, uptime: 60))
      view.preferredLanguages = ["zh"]
      XCTAssertTrue(view.update(now: now, uptime: 60))
      view.configurationError = CountdownError.invalidConfiguration
      XCTAssertTrue(view.update(now: now, uptime: 60))
      view.configurationError = CountdownError.saveFailed
      XCTAssertTrue(view.update(now: now, uptime: 60))
      view.configurationError = nil
      view.configuration.appearance.moveContent = true
      XCTAssertTrue(view.update(now: now, uptime: 60))
      XCTAssertFalse(view.update(now: now, uptime: 119))
      XCTAssertTrue(view.update(now: now, uptime: 120))
      view.previewMode = true
      XCTAssertTrue(view.update(now: now, uptime: 120))
      XCTAssertFalse(view.update(now: now, uptime: 180))
      view.reset()
      XCTAssertTrue(view.update(now: now, uptime: 180))
    }
  }
  @MainActor func testFallbackPollIsInfrequentAndNotificationsRefreshImmediately() async throws {
    _ = NSApplication.shared
    let backend = TestBackend()
    let store = ConfigurationStore(backend: backend)
    let saver = try XCTUnwrap(
      CountdownScreenSaverView(
        frame: NSRect(x: 0, y: 0, width: 800, height: 600), isPreview: false, store: store))
    saver.startAnimation()
    let now = Date(timeIntervalSince1970: 100)
    saver.reloadConfiguration(now: now, uptime: 0)
    let reads = backend.reads
    let revision = saver.content.configuration.revision
    for second in 1..<60 { saver.advanceFrame(now: now, uptime: Double(second)) }
    XCTAssertEqual(backend.reads, reads)
    saver.advanceFrame(now: now, uptime: 60)
    XCTAssertEqual(backend.reads, reads + 1)
    XCTAssertEqual(saver.content.configuration.revision, revision)
    var updated = Configuration()
    updated.languagePreference = .zhHans
    let saved = try ConfigurationStore(backend: backend).save(updated)
    DistributedNotificationCenter.default().postNotificationName(
      CountdownScreenSaverView.configurationChanged, object: nil, userInfo: nil,
      deliverImmediately: true)
    let deadline = Date().addingTimeInterval(2)
    while saver.content.configuration != saved && Date() < deadline {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertEqual(saver.content.configuration, saved)
    let readsAfterSave = backend.reads
    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
    XCTAssertEqual(backend.reads, readsAfterSave + 1)
    saver.stopAnimation()
  }
  func testTimeZoneSearchKeepsDraftAndSelectionWhileFiltering() async {
    await MainActor.run {
      let c = controller()
      c.addEvent()
      let original = c.draft.value
      let selected = original.events[0].input.timeZoneIdentifier
      let search: NSSearchField = find("searchTimeZones", in: c.window!.contentView!)
      let picker: NSPopUpButton = find("timeZone", in: c.window!.contentView!)
      XCTAssertEqual(picker.itemTitles.first, selected)
      XCTAssertTrue(picker.itemTitles.contains("UTC"))
      search.stringValue = "new york"
      c.controlTextDidChange(
        Notification(name: NSControl.textDidChangeNotification, object: search))
      XCTAssertEqual(Set(picker.itemTitles), Set([selected, "America/New_York"]))
      XCTAssertEqual(c.draft.value, original)
      select(picker, picker.indexOfItem(withTitle: "America/New_York"))
      XCTAssertEqual(c.draft.value.events[0].input.timeZoneIdentifier, "America/New_York")
      search.stringValue = "no such time zone"
      c.controlTextDidChange(
        Notification(name: NSControl.textDidChangeNotification, object: search))
      XCTAssertEqual(picker.itemTitles, ["America/New_York"])
      search.stringValue = ""
      c.controlTextDidChange(
        Notification(name: NSControl.textDidChangeNotification, object: search))
      XCTAssertGreaterThan(picker.numberOfItems, 400)
      XCTAssertEqual(picker.itemTitles.count, Set(picker.itemTitles).count)
      XCTAssertEqual(picker.titleOfSelectedItem, "America/New_York")
      c.cancelPressed()
    }
  }
  func testTimerOwnerInvalidatesReplacementAndOnRelease() {
    var owner: TimerLifetime? = TimerLifetime()
    let first = Timer(timeInterval: 1, repeats: true) { _ in }
    let second = Timer(timeInterval: 1, repeats: true) { _ in }
    owner?.replace(with: first)
    owner?.replace(with: second)
    XCTAssertFalse(first.isValid)
    XCTAssertTrue(second.isValid)
    owner = nil
    XCTAssertFalse(second.isValid)
  }
  @MainActor private func find<T: NSView>(
    _ identifier: String, in view: NSView, as: T.Type = T.self
  ) -> T {
    if view.accessibilityIdentifier() == identifier, let result = view as? T { return result }
    for child in view.subviews {
      if let result: T = optionalFind(identifier, in: child) { return result }
    }
    fatalError("Missing control: \(identifier)")
  }
  @MainActor private func optionalFind<T: NSView>(_ id: String, in view: NSView) -> T? {
    if view.accessibilityIdentifier() == id, let result = view as? T { return result }
    for child in view.subviews { if let result: T = optionalFind(id, in: child) { return result } }
    return nil
  }
  @MainActor private func controller(_ backend: TestBackend = TestBackend())
    -> ConfigurationWindowController
  {
    _ = NSApplication.shared
    return ConfigurationWindowController(store: ConfigurationStore(backend: backend))
  }
  @MainActor private func click(_ button: NSButton) { button.performClick(nil) }
  @MainActor private func select(_ popup: NSPopUpButton, _ index: Int) {
    popup.selectItem(at: index)
    NSApp.sendAction(popup.action!, to: popup.target, from: popup)
  }
  @MainActor private func edit(_ id: String, _ value: String, _ c: ConfigurationWindowController) {
    let field: NSTextField = find(id, in: c.window!.contentView!)
    field.stringValue = value
    c.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
  }
  func testEmptySettingsAndAddDeleteMaximum() async throws {
    await MainActor.run {
      let c = controller()
      XCTAssertNil(c.selectedID)
      for _ in 0..<5 { c.addEvent() }
      let root = c.window!.contentView!
      let add: NSButton = find("addEvent", in: root)
      XCTAssertFalse(add.isEnabled)
      XCTAssertEqual(c.draft.value.events.count, 5)
      c.deleteEvent()
      XCTAssertEqual(c.draft.value.events.count, 4)
      let newAdd: NSButton = find("addEvent", in: c.window!.contentView!)
      XCTAssertTrue(newAdd.isEnabled)
      c.cancelPressed()
    }
  }
  func testSaveAndCancelPreferences() async throws {
    try await MainActor.run {
      let backend = TestBackend()
      let c = controller(backend)
      c.addEvent()
      edit("title", "Keep this 中文", c)
      let popup: NSPopUpButton = find("language", in: c.window!.contentView!)
      select(popup, 2)
      let checkbox: NSButton = find("showNext", in: c.window!.contentView!)
      click(checkbox)
      let saved = try c.saveDraft()
      XCTAssertEqual(saved.languagePreference, .zhHans)
      XCTAssertTrue(saved.appearance.showNextTarget)
      XCTAssertEqual(saved.events.first?.title, "Keep this 中文")
      let original = backend.data
      let reopened = controller(backend)
      reopened.addEvent()
      let language: NSPopUpButton = find("language", in: reopened.window!.contentView!)
      select(language, 1)
      reopened.cancelPressed()
      XCTAssertEqual(backend.data, original)
    }
  }
  func testLanguageUpdatesWindowAndKeepsSelectionAndInvalidInput() async throws {
    try await MainActor.run {
      let c = controller()
      c.addEvent()
      let id = c.selectedID
      let originalRoot = c.window!.contentView!
      edit("title", "Untranslated 中文", c)
      edit("year", "-", c)
      let popup: NSPopUpButton = find("language", in: c.window!.contentView!)
      select(popup, 2)
      XCTAssertTrue(c.window!.contentView === originalRoot)
      XCTAssertEqual(c.window?.title, "倒计时设置")
      XCTAssertEqual(c.selectedID, id)
      let year: NSTextField = find("year", in: c.window!.contentView!)
      let title: NSTextField = find("title", in: c.window!.contentView!)
      XCTAssertEqual(year.stringValue, "-")
      XCTAssertEqual(title.stringValue, "Untranslated 中文")
      XCTAssertThrowsError(try c.saveDraft())
      c.cancelPressed()
    }
  }
  func testInvalidDateBlocksSaveAndCorrectionRestoresIt() async throws {
    try await MainActor.run {
      let c = controller()
      c.addEvent()
      edit("hour", "24", c)
      var save: NSButton = find("save", in: c.window!.contentView!)
      XCTAssertFalse(save.isEnabled)
      XCTAssertThrowsError(try c.saveDraft())
      edit("hour", "09", c)
      save = find("save", in: c.window!.contentView!)
      XCTAssertTrue(save.isEnabled)
      XCTAssertNoThrow(try c.saveDraft())
    }
  }
  func testInvalidMonthDayRequiresExplicitSelection() async throws {
    try await MainActor.run {
      let c = controller()
      c.addEvent()
      edit("year", "2024", c)
      let month: NSPopUpButton = find("month", in: c.window!.contentView!)
      select(month, 0)
      let day: NSPopUpButton = find("day", in: c.window!.contentView!)
      select(day, 30)
      select(month, 1)
      let updatedDay: NSPopUpButton = find("day", in: c.window!.contentView!)
      XCTAssertEqual(updatedDay.titleOfSelectedItem, "—")
      XCTAssertThrowsError(try c.saveDraft())
      select(updatedDay, 29)
      XCTAssertEqual(c.draft.value.events[0].input.day, 29)
      XCTAssertNoThrow(try c.saveDraft())
    }
  }
  func testCalendarConversionAndLocalizedLunarControls() async throws {
    await MainActor.run {
      let c = controller()
      c.addEvent()
      let before = c.draft.value.events[0].resolvedTimestamp
      let calendar: NSPopUpButton = find("calendar", in: c.window!.contentView!)
      select(calendar, 1)
      XCTAssertEqual(c.draft.value.events[0].input.calendar, .chinese)
      XCTAssertEqual(c.draft.value.events[0].resolvedTimestamp, before)
      let status: NSTextField = find("status", in: c.window!.contentView!)
      XCTAssertEqual(
        status.stringValue,
        Localization(preference: c.draft.value.languagePreference).text(.converted))
      let language: NSPopUpButton = find("language", in: c.window!.contentView!)
      select(language, 2)
      let month: NSPopUpButton = find("month", in: c.window!.contentView!)
      XCTAssertTrue(month.itemTitles.contains("正月"))
      XCTAssertTrue(month.itemTitles.contains("腊月"))
      let converted: NSTextField = find("status", in: c.window!.contentView!)
      XCTAssertEqual(converted.stringValue, "已转换历法，目标时刻不变。")
      edit("hour", "12", c)
      XCTAssertFalse(converted.stringValue.contains("已转换"))
      XCTAssertTrue(CountdownContentView().isOpaque)
      c.cancelPressed()
    }
  }
  func testMissingLeapMonthAfterYearChangeRemainsInvalid() async throws {
    try await MainActor.run {
      let c = controller()
      c.addEvent()
      let id = c.selectedID!
      try c.draft.update(
        id: id, title: "Leap",
        input: DateInput(
          year: 2025, month: 6, day: 1, calendar: .chinese, isLeapMonth: true,
          timeZoneIdentifier: "UTC"))
      // Rebuild via language selection to populate the edited event.
      let language: NSPopUpButton = find("language", in: c.window!.contentView!)
      select(language, 1)
      edit("year", "2024", c)
      let month: NSPopUpButton = find("month", in: c.window!.contentView!)
      XCTAssertEqual(month.titleOfSelectedItem, "—")
      XCTAssertThrowsError(try c.saveDraft())
      c.cancelPressed()
    }
  }
  func testDSTRepeatedOccurrenceSelectionIncludesOffsets() async throws {
    try await MainActor.run {
      let c = controller()
      c.addEvent()
      let input = DateInput(
        year: 2026, month: 11, day: 1, hour: 1, minute: 30, timeZoneIdentifier: "America/New_York")
      XCTAssertThrowsError(try c.draft.update(id: c.selectedID!, title: "DST", input: input))
      let language: NSPopUpButton = find("language", in: c.window!.contentView!)
      select(language, 1)
      let occurrences: NSPopUpButton = find("occurrence", in: c.window!.contentView!)
      XCTAssertTrue(occurrences.isEnabled)
      XCTAssertEqual(occurrences.numberOfItems, 3)
      XCTAssertTrue(occurrences.itemTitles[1].contains("UTC−04:00"))
      XCTAssertTrue(occurrences.itemTitles[2].contains("UTC−05:00"))
      select(occurrences, 2)
      XCTAssertEqual(c.draft.value.events[0].input.repeatedTimeChoice, .second)
      XCTAssertNoThrow(try c.saveDraft())
    }
  }
  func testCorruptConfigurationRequiresExplicitRepair() async throws {
    try await MainActor.run {
      let backend = TestBackend()
      backend.data = Data("bad data".utf8)
      let c = controller(backend)
      XCTAssertNotNil(c.loadError)
      XCTAssertThrowsError(try c.saveDraft())
      XCTAssertEqual(backend.data, Data("bad data".utf8))
      let repair: NSButton = find("repair", in: c.window!.contentView!)
      click(repair)
      XCTAssertNil(c.loadError)
      c.addEvent()
      XCTAssertNoThrow(try c.saveDraft())
      XCTAssertNotEqual(backend.data, Data("bad data".utf8))
    }
  }
  func testSaveFailureRetainsDraftAndWindow() async throws {
    try await MainActor.run {
      let backend = TestBackend()
      let c = controller(backend)
      c.addEvent()
      backend.fail = true
      XCTAssertThrowsError(try c.saveDraft())
      XCTAssertNotNil(c.window)
      XCTAssertEqual(c.draft.value.events.count, 1)
      backend.fail = false
      XCTAssertNoThrow(try c.saveDraft())
    }
  }
  func testSheetSaveEndsModalSession() async throws {
    try await MainActor.run {
      let c = controller()
      let parent = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled],
        backing: .buffered, defer: false)
      parent.beginSheet(c.window!)
      c.addEvent()
      _ = try c.saveDraft()
      XCTAssertNil(c.window?.sheetParent)
    }
  }
  func testViewStatesLanguageAndResizeRender() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let view = CountdownContentView(frame: NSRect(x: 0, y: 0, width: 1000, height: 650))
      let window = NSWindow(
        contentRect: view.frame, styleMask: [], backing: .buffered, defer: false)
      window.contentView = view
      for preference in LanguagePreference.allCases {
        view.configuration.languagePreference = preference
        view.update(now: Date(timeIntervalSince1970: 100), uptime: 0)
        XCTAssertEqual(view.state, .empty)
        for size in [
          NSSize(width: 1000, height: 650), NSSize(width: 320, height: 240),
          NSSize(width: 450, height: 800),
        ] {
          view.setFrameSize(size)
          let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
          view.cacheDisplay(in: view.bounds, to: bitmap)
          XCTAssertNotNil(bitmap.representation(using: .png, properties: [:]))
        }
      }
      var c = Configuration()
      let input = DateInput(year: 2026, month: 1, day: 1, timeZoneIdentifier: "UTC")
      c.events = [CountdownEvent(createdOrder: 0, input: input, resolvedTimestamp: 101)]
      view.configuration = c
      view.update(now: Date(timeIntervalSince1970: 100), uptime: 0)
      guard case .counting = view.state else { return XCTFail() }
      view.update(now: Date(timeIntervalSince1970: 101), uptime: 1)
      guard case .reached = view.state else { return XCTFail() }
      view.update(now: Date(timeIntervalSince1970: 103), uptime: 3)
      guard case .completed = view.state else { return XCTFail() }
      view.configurationError = CountdownError.invalidConfiguration
      let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
      view.cacheDisplay(in: view.bounds, to: bitmap)
    }
  }
  func testConfigureSheetReusesDraftAndReleasesOnCancelAndSave() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let backend = TestBackend()
      let saver = try XCTUnwrap(
        CountdownScreenSaverView(
          frame: .zero, isPreview: true,
          store: ConfigurationStore(backend: backend)))
      let first = try XCTUnwrap(saver.configureSheet)
      do {
        let controller = try XCTUnwrap(first.windowController as? ConfigurationWindowController)
        controller.addEvent()
        XCTAssertTrue(saver.configureSheet === first)
        XCTAssertEqual(controller.draft.value.events.count, 1)
        controller.cancelPressed()
        XCTAssertTrue(controller.isFinished)
      }
      XCTAssertNil(backend.data)
      let second = try XCTUnwrap(saver.configureSheet)
      XCTAssertFalse(first === second)
      XCTAssertTrue(saver.configureSheet === second)
      let controller = try XCTUnwrap(second.windowController as? ConfigurationWindowController)
      XCTAssertTrue(controller.draft.value.events.isEmpty)
      controller.addEvent()
      let saved = try controller.saveDraft()
      XCTAssertTrue(controller.isFinished)
      XCTAssertEqual(saver.content.configuration, saved)
      let third = try XCTUnwrap(saver.configureSheet)
      XCTAssertFalse(second === third)
      let reopened = try XCTUnwrap(third.windowController as? ConfigurationWindowController)
      XCTAssertEqual(reopened.draft.value, saved)
      reopened.cancelPressed()
    }
  }
  func testExternalWindowCloseFinishesOnceAndClearsSheetCache() async throws {
    try await MainActor.run {
      let saver = try XCTUnwrap(
        CountdownScreenSaverView(
          frame: .zero, isPreview: true,
          store: ConfigurationStore(backend: TestBackend())))
      let old = try XCTUnwrap(saver.configureSheet)
      let controller = try XCTUnwrap(old.windowController as? ConfigurationWindowController)
      old.close()
      XCTAssertTrue(controller.isFinished)
      XCTAssertFalse(saver.configureSheet === old)
      let standalone = self.controller()
      var finishes = 0
      standalone.onFinish = { finishes += 1 }
      standalone.cancelPressed()
      standalone.cancelPressed()
      XCTAssertEqual(finishes, 1)
    }
  }
  func testSmallResizableSettingsKeepActionsVisibleWhileContentScrolls() async throws {
    try await MainActor.run {
      let c = controller()
      c.addEvent()
      let window = try XCTUnwrap(c.window)
      XCTAssertTrue(window.styleMask.contains(.resizable))
      let initial = ConfigurationWindowController.initialSize(
        visibleFrame: NSRect(x: 0, y: 0, width: 1366, height: 700))
      XCTAssertLessThan(initial.height, 700)
      XCTAssertEqual(
        ConfigurationWindowController.initialSize(visibleFrame: nil),
        NSSize(width: 900, height: 760))
      for language in [1, 2] {
        let popup: NSPopUpButton = find("language", in: window.contentView!)
        select(popup, language)
        window.setContentSize(NSSize(width: 480, height: 360))
        window.layoutIfNeeded()
        let content = window.contentView!
        content.layoutSubtreeIfNeeded()
        let scroll: NSScrollView = find("settingsScroll", in: content)
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertGreaterThan(document.frame.height, scroll.contentView.bounds.height)
        XCTAssertGreaterThan(document.frame.width, scroll.contentView.bounds.width)
        scroll.contentView.scroll(to: NSPoint(x: 300, y: 300))
        scroll.reflectScrolledClipView(scroll.contentView)
        XCTAssertGreaterThan(scroll.contentView.bounds.origin.y, 0)
        for id in ["save", "cancel"] {
          let button: NSButton = find(id, in: content)
          let rect = button.convert(button.bounds, to: content)
          XCTAssertTrue(content.bounds.contains(rect), "\(id) must remain visible")
          XCTAssertLessThanOrEqual(rect.maxY, scroll.frame.minY)
          XCTAssertTrue(button.isEnabled)
        }
      }
      c.cancelPressed()
    }
  }
  func testPreviewCloseStopsTimerBeforeAppTermination() async throws {
    try await MainActor.run {
      let delegate = PreviewApplicationDelegate(store: ConfigurationStore(backend: TestBackend()))
      delegate.applicationDidFinishLaunching(
        Notification(name: NSApplication.didFinishLaunchingNotification))
      let window = try XCTUnwrap(delegate.window)
      let timer = try XCTUnwrap(delegate.timer)
      XCTAssertFalse(window.isReleasedWhenClosed)
      XCTAssertTrue(timer.isValid)
      XCTAssertTrue(delegate.saver.isAnimating)
      timer.fire()
      window.performClose(nil)
      XCTAssertFalse(window.isVisible)
      XCTAssertNil(delegate.timer)
      XCTAssertFalse(timer.isValid)
      XCTAssertFalse(delegate.saver.isAnimating)
      timer.fire()
      delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
      XCTAssertNil(delegate.timer)
    }
  }
  func testIndependentScreenSaverInstancesRestartAndConfigure() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let a = try XCTUnwrap(
        CountdownScreenSaverView(
          frame: NSRect(x: 0, y: 0, width: 800, height: 600), isPreview: true))
      let b = try XCTUnwrap(
        CountdownScreenSaverView(
          frame: NSRect(x: 0, y: 0, width: 320, height: 240), isPreview: false))
      a.startAnimation()
      b.startAnimation()
      a.animateOneFrame()
      b.animateOneFrame()
      a.stopAnimation()
      XCTAssertFalse(a.isAnimating)
      XCTAssertTrue(b.isAnimating)
      a.startAnimation()
      XCTAssertTrue(a.isAnimating)
      XCTAssertTrue(a.hasConfigureSheet)
      XCTAssertNotNil(a.configureSheet)
      XCTAssertNotNil(b.configureSheet)
      a.stopAnimation()
      b.stopAnimation()
    }
  }
  func testRuntimeConfigurationReloadAndLanguageSync() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let backend = TestBackend()
      let actual = ConfigurationStore(backend: backend)
      let saver = try XCTUnwrap(
        CountdownScreenSaverView(
          frame: NSRect(x: 0, y: 0, width: 800, height: 600), isPreview: false, store: actual))
      saver.startAnimation()
      let c = controller(backend)
      c.addEvent()
      c.draft.setLanguage(.zhHans)
      let saved = try c.saveDraft()
      saver.reloadConfiguration()
      XCTAssertEqual(saver.content.configuration, saved)
      XCTAssertEqual(saver.content.configuration.languagePreference, .zhHans)
      backend.data = Data("corrupt".utf8)
      saver.reloadConfiguration()
      XCTAssertNotNil(saver.content.configurationError)
      saver.stopAnimation()
    }
  }
  func testRenderedMovementChangesOnlyAtMinuteBoundaryAndPreviewStaysFixed() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let view = CountdownContentView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
      let window = NSWindow(
        contentRect: view.frame, styleMask: [], backing: .buffered, defer: false)
      window.contentView = view
      @MainActor func render(_ uptime: Double) throws -> Data {
        view.update(now: Date(timeIntervalSince1970: 100), uptime: uptime)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      }
      let first = try render(0)
      let before = try render(59)
      XCTAssertEqual(first, before)
      XCTAssertNotEqual(first, try render(60))
      view.previewMode = true
      XCTAssertEqual(try render(0), try render(60))
      view.previewMode = false
      view.configuration.appearance.moveContent = false
      XCTAssertEqual(try render(0), try render(60))
    }
  }
  func testNextHintLongGroupLunarAndReachedCompletedRendering() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let view = CountdownContentView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
      let window = NSWindow(
        contentRect: view.frame, styleMask: [], backing: .buffered, defer: false)
      window.contentView = view
      var c = Configuration()
      c.appearance.showNextTarget = true
      c.languagePreference = .zhHans
      let input = DateInput(
        year: 2025, month: 6, day: 1, calendar: .chinese, isLeapMonth: true,
        timeZoneIdentifier: "UTC")
      c.events = (0..<3).map {
        CountdownEvent(
          title: String(repeating: "长标题", count: 12), createdOrder: $0, input: input,
          resolvedTimestamp: $0 < 2 ? 101 : 200)
      }
      view.configuration = c
      for (time, uptime) in [(100.0, 0.0), (101, 1), (103, 3), (201, 101)] {
        view.update(now: Date(timeIntervalSince1970: time), uptime: uptime)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        XCTAssertNotNil(bitmap.representation(using: .png, properties: [:]))
      }
    }
  }

}
