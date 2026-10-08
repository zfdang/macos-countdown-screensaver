import XCTest

@testable import CountdownCore

final class MemoryBackend: ConfigurationBackend {
  var data: Data?
  var fail = false
  func read() -> Data? { data }
  func write(_ data: Data) throws {
    if fail { throw CountdownError.saveFailed }
    self.data = data
  }
}

final class ConfigurationTests: XCTestCase {
  let service = CalendarConversionService()
  func testUnchangedSnapshotsRetainIdentityAndChangesStillValidate() throws {
    let backend = MemoryBackend()
    let store = ConfigurationStore(backend: backend)
    let empty = try store.load()
    XCTAssertEqual(try store.load(), empty)
    let external = ConfigurationStore(backend: backend)
    var changed = Configuration()
    changed.languagePreference = .zhHans
    let saved = try external.save(changed)
    XCTAssertEqual(try store.load(), saved)
    XCTAssertEqual(try store.load(), saved)
    let validData = backend.data
    backend.data = Data("corrupt".utf8)
    XCTAssertThrowsError(try store.load())
    XCTAssertThrowsError(try store.load())
    backend.data = validData
    XCTAssertEqual(try store.load(), saved)
    backend.data = nil
    let deleted = try store.load()
    XCTAssertTrue(deleted.events.isEmpty)
    XCTAssertNotEqual(deleted.revision, saved.revision)
    XCTAssertEqual(try store.load(), deleted)
  }
  func testSaveLoadAndLanguageAppearancePersistence() throws {
    let backend = MemoryBackend()
    XCTAssertTrue(try ConfigurationStore(backend: backend).load().events.isEmpty)
    let actual = ConfigurationStore(backend: backend)
    let draft = DraftConfiguration(Configuration())
    _ = try draft.add(zone: "UTC")
    draft.setLanguage(.zhHans)
    var appearance = AppearanceSettings()
    appearance.showNextTarget = true
    appearance.moveContent = false
    draft.setAppearance(appearance)
    let saved = try actual.save(draft.validated())
    XCTAssertNotEqual(saved.revision, draft.value.revision)
    XCTAssertEqual(try actual.load(), saved)
    XCTAssertEqual(try actual.load().appearance, appearance)
  }
  func testDefaultsBackendPersistsAcrossInstances() throws {
    let name = "CountdownTests.\(UUID())"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let store = ConfigurationStore(backend: DefaultsBackend(defaults: defaults))
    let saved = try store.save(Configuration())
    let reopened = ConfigurationStore(
      backend: DefaultsBackend(defaults: UserDefaults(suiteName: name)!))
    XCTAssertEqual(try reopened.load(), saved)
  }
  func testDefaultsBackendSeesChangesFromAnotherProcess() throws {
    let name = "CountdownTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = ConfigurationStore(backend: DefaultsBackend(defaults: defaults))
    _ = try store.load()
    var changed = Configuration()
    changed.languagePreference = .zhHans
    let data = try JSONEncoder().encode(changed)
    let writer = Process()
    writer.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    writer.arguments = [
      "write", name, DefaultsBackend.dataKey, "-data",
      data.map { String(format: "%02x", $0) }.joined(),
    ]
    try writer.run()
    writer.waitUntilExit()
    XCTAssertEqual(writer.terminationStatus, 0)
    let deadline = Date().addingTimeInterval(3)
    var received = try store.load()
    while received != changed && Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.01))
      received = try store.load()
    }
    XCTAssertEqual(received, changed)
  }
  func testMaximumCountDeleteAndNewIdentity() throws {
    let draft = DraftConfiguration(Configuration())
    for _ in 0..<5 { _ = try draft.add(zone: "UTC") }
    XCTAssertThrowsError(try draft.add()) { XCTAssertEqual($0 as? CountdownError, .maximumEvents) }
    let removed = draft.value.events[2]
    draft.delete(id: removed.id)
    let new = try draft.add(zone: "UTC")
    XCTAssertNotEqual(new, removed.id)
    XCTAssertEqual(draft.value.events.count, 5)
    XCTAssertEqual(Set(draft.value.events.map(\.createdOrder)).count, 5)
  }
  func testAddDefaultsToTomorrowAndZeroSeconds() throws {
    let now = try service.resolve(
      DateInput(
        year: 2026, month: 12, day: 31, hour: 16, minute: 42, second: 55, timeZoneIdentifier: "UTC")
    )
    let draft = DraftConfiguration(Configuration())
    _ = try draft.add(now: now, zone: "UTC")
    XCTAssertEqual(
      draft.value.events[0].input,
      DateInput(year: 2027, month: 1, day: 1, hour: 16, minute: 42, timeZoneIdentifier: "UTC"))
  }
  func testInvalidDraftCannotSaveAndCanBeCorrectedOrDeleted() throws {
    let draft = DraftConfiguration(Configuration())
    let backend = MemoryBackend()
    let id = try draft.add(zone: "UTC")
    var input = draft.value.events[0].input
    input.month = 0
    XCTAssertThrowsError(try draft.update(id: id, title: "Bad", input: input))
    XCTAssertEqual(draft.value.events[0].input.month, 0)
    let store = ConfigurationStore(backend: backend)
    XCTAssertThrowsError(try store.save(draft.value))
    XCTAssertNil(backend.data)
    input.month = 1
    try draft.update(id: id, title: "Corrected", input: input)
    XCTAssertNoThrow(try draft.validated())
    draft.delete(id: id)
    XCTAssertTrue(try draft.validated().events.isEmpty)
  }
  func testTitleLimitAllowsFortyUnicodeCharactersAndPreservesEmpty() throws {
    let draft = DraftConfiguration(Configuration())
    let id = try draft.add(zone: "UTC")
    let input = draft.value.events[0].input
    try draft.update(id: id, title: String(repeating: "中", count: 40), input: input)
    XCTAssertNoThrow(try draft.validated())
    XCTAssertThrowsError(
      try draft.update(id: id, title: String(repeating: "中", count: 41), input: input))
    try draft.update(id: id, title: "", input: input)
    XCTAssertEqual(draft.value.events[0].title, "")
  }
  func testCalendarSwitchPreservesInstantAndRoundTrip() throws {
    let draft = DraftConfiguration(Configuration())
    let id = try draft.add(zone: "America/Los_Angeles")
    let before = draft.value.events[0]
    try draft.switchCalendar(id: id, to: .chinese)
    XCTAssertEqual(draft.value.events[0].resolvedTimestamp, before.resolvedTimestamp)
    XCTAssertEqual(draft.value.events[0].input.calendar, .chinese)
    try draft.switchCalendar(id: id, to: .gregorian)
    XCTAssertEqual(draft.value.events[0], before)
  }
  func testFailedOutOfRangeSwitchRetainsOriginal() throws {
    let draft = DraftConfiguration(Configuration())
    let id = try draft.add(zone: "UTC")
    let input = DateInput(year: 2200, month: 1, day: 1, timeZoneIdentifier: "UTC")
    try draft.update(id: id, title: "Future", input: input)
    let before = draft.value
    XCTAssertThrowsError(try draft.switchCalendar(id: id, to: .chinese))
    XCTAssertEqual(draft.value, before)
  }
  func testCancelDraftDoesNotMutateSavedValue() throws {
    let backend = MemoryBackend()
    let actual = ConfigurationStore(backend: backend)
    let saved = try actual.save(Configuration())
    let draft = DraftConfiguration(try actual.load())
    _ = try draft.add()
    draft.setLanguage(.en)
    XCTAssertEqual(try actual.load(), saved)
  }
  func testCorruptUnsupportedAndMissingLanguage() throws {
    let backend = MemoryBackend()
    let actual = ConfigurationStore(backend: backend)
    let saved = try actual.save(Configuration())
    var json = try JSONSerialization.jsonObject(with: backend.data!) as! [String: Any]
    json.removeValue(forKey: "languagePreference")
    backend.data = try JSONSerialization.data(withJSONObject: json)
    XCTAssertEqual(try actual.load().languagePreference, .system)
    json["schemaVersion"] = 99
    backend.data = try JSONSerialization.data(withJSONObject: json)
    let original = backend.data
    XCTAssertThrowsError(try actual.load()) {
      XCTAssertEqual($0 as? CountdownError, .unsupportedVersion)
    }
    XCTAssertEqual(backend.data, original)
    backend.data = Data("broken".utf8)
    XCTAssertThrowsError(try actual.load()) {
      XCTAssertEqual($0 as? CountdownError, .invalidConfiguration)
    }
    XCTAssertEqual(backend.data, Data("broken".utf8))
    backend.data = try JSONEncoder().encode(saved)
    backend.fail = true
    XCTAssertThrowsError(try actual.save(saved)) {
      XCTAssertEqual($0 as? CountdownError, .saveFailed)
    }
    XCTAssertEqual(try actual.load(), saved)
  }
  func testRejectMalformedConfiguration() throws {
    let draft = DraftConfiguration(Configuration())
    _ = try draft.add(zone: "UTC")
    let valid = draft.value
    var duplicate = valid
    duplicate.events.append(duplicate.events[0])
    XCTAssertThrowsError(try duplicate.validated())
    var nonfinite = valid
    nonfinite.events[0].resolvedTimestamp = .infinity
    XCTAssertThrowsError(try nonfinite.validated())
    var excessive = valid
    excessive.events = (0..<6).map { i in
      var e = valid.events[0]
      e.id = UUID()
      e.createdOrder = i
      return e
    }
    XCTAssertThrowsError(try excessive.validated())
    var negativeOrder = valid
    negativeOrder.events[0].createdOrder = -1
    XCTAssertThrowsError(try negativeOrder.validated())
  }
  func testPastDateAllowedAndLanguageDoesNotChangeEvents() throws {
    let draft = DraftConfiguration(Configuration())
    let id = try draft.add(zone: "UTC")
    try draft.update(
      id: id, title: "User title 中文",
      input: DateInput(year: 2000, month: 1, day: 1, timeZoneIdentifier: "UTC"))
    let events = draft.value.events
    for language in LanguagePreference.allCases {
      draft.setLanguage(language)
      XCTAssertEqual(draft.value.events, events)
    }
    XCTAssertNoThrow(try draft.validated())
  }
  func testWrongDefaultsValueTypeIsPreservedAndRejected() throws {
    let name = "CountdownTests.\(UUID())"
    let actual = UserDefaults(suiteName: name)!
    defer { actual.removePersistentDomain(forName: name) }
    actual.set("wrong type", forKey: DefaultsBackend.dataKey)
    let store = ConfigurationStore(backend: DefaultsBackend(defaults: actual))
    XCTAssertThrowsError(try store.load()) {
      XCTAssertEqual($0 as? CountdownError, .invalidConfiguration)
    }
    XCTAssertEqual(actual.string(forKey: DefaultsBackend.dataKey), "wrong type")
  }

}
