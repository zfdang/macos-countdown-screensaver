import AppKit
import CountdownCore
import ScreenSaver
import XCTest

@testable import CountdownUI

final class ScreenSaverPreferencesTests: XCTestCase {
  private func command(_ arguments: [String], checkStatus: Bool = true) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    process.arguments = ["-currentHost"] + arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = Pipe()
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    if checkStatus { XCTAssertEqual(process.terminationStatus, 0) }
    return data
  }
  private func cleanup(_ domain: String) {
    _ = try? command(["delete", domain], checkStatus: false)
  }
  private func write(_ value: Configuration, to domain: String) throws {
    let data = try JSONEncoder().encode(value)
    _ = try command([
      "write", domain, DefaultsBackend.dataKey, "-data",
      data.map { String(format: "%02x", $0) }.joined(),
    ])
  }
  private func configuration() throws -> Configuration {
    let draft = DraftConfiguration(Configuration())
    let id = try draft.add(zone: "UTC")
    try draft.update(
      id: id, title: "Updated target",
      input: DateInput(year: 2033, month: 12, day: 22, hour: 9, timeZoneIdentifier: "UTC"))
    draft.setLanguage(.zhHans)
    var appearance = AppearanceSettings()
    appearance.showNextTarget = true
    draft.setAppearance(appearance)
    return try draft.validated()
  }
  func testCachedScreenSaverDefaultsReloadsExternalChangesAndDeletion() throws {
    let domain = "com.zfdang.CountdownPreferencesTests." + UUID().uuidString
    let defaults = try XCTUnwrap(ScreenSaverDefaults(forModuleWithName: domain))
    let store = ConfigurationStore(backend: ScreenSaverDefaultsBackend(defaults: defaults))
    _ = try store.save(Configuration())
    defer { cleanup(domain) }
    let changed = try configuration()
    try write(changed, to: domain)
    // Exercise the real subclass after its dictionary has already been populated.
    XCTAssertEqual(try store.load(), changed)
    _ = try command(["delete", domain, DefaultsBackend.dataKey])
    XCTAssertTrue(try store.load().events.isEmpty)
  }
  func testSaveFlushesConfigurationToAnIndependentReader() throws {
    let domain = "com.zfdang.CountdownPreferencesTests." + UUID().uuidString
    let defaults = try XCTUnwrap(ScreenSaverDefaults(forModuleWithName: domain))
    let store = ConfigurationStore(backend: ScreenSaverDefaultsBackend(defaults: defaults))
    let saved = try store.save(configuration())
    defer { cleanup(domain) }
    let output = try command(["export", domain, "-"])
    let plist = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: output, options: [], format: nil)
        as? [String: Any])
    let data = try XCTUnwrap(plist[DefaultsBackend.dataKey] as? Data)
    XCTAssertEqual(try JSONDecoder().decode(Configuration.self, from: data), saved)
  }
  @MainActor func testFullSizeSaverReadsExternalEditsOnRestartAndFallbackPoll() throws {
    _ = NSApplication.shared
    let domain = "com.zfdang.CountdownPreferencesTests." + UUID().uuidString
    let defaults = try XCTUnwrap(ScreenSaverDefaults(forModuleWithName: domain))
    let store = ConfigurationStore(backend: ScreenSaverDefaultsBackend(defaults: defaults))
    _ = try store.save(Configuration())
    defer { cleanup(domain) }
    let saver = try XCTUnwrap(
      CountdownScreenSaverView(
        frame: NSRect(x: 0, y: 0, width: 1000, height: 650), isPreview: false, store: store))
    saver.startAnimation()
    saver.stopAnimation()
    var changed = try configuration()
    try write(changed, to: domain)
    saver.startAnimation()
    XCTAssertEqual(saver.content.configuration, changed)
    let now = Date()
    saver.reloadConfiguration(now: now, uptime: 0)
    changed.revision = UUID()
    changed.events[0].title = "Second edit"
    try write(changed, to: domain)
    saver.advanceFrame(now: now, uptime: 60)
    XCTAssertEqual(saver.content.configuration, changed)
    saver.stopAnimation()
  }
  @MainActor func testDistributedSaveNotificationRefreshesRealScreenSaverDefaults() async throws {
    _ = NSApplication.shared
    let domain = "com.zfdang.CountdownPreferencesTests." + UUID().uuidString
    let defaults = try XCTUnwrap(ScreenSaverDefaults(forModuleWithName: domain))
    let store = ConfigurationStore(backend: ScreenSaverDefaultsBackend(defaults: defaults))
    _ = try store.save(Configuration())
    defer { cleanup(domain) }
    let saver = try XCTUnwrap(
      CountdownScreenSaverView(
        frame: NSRect(x: 0, y: 0, width: 1000, height: 650), isPreview: false, store: store))
    let changed = try configuration()
    try write(changed, to: domain)
    DistributedNotificationCenter.default().postNotificationName(
      CountdownScreenSaverView.configurationChanged, object: nil, userInfo: nil,
      deliverImmediately: true)
    let deadline = Date().addingTimeInterval(2)
    while saver.content.configuration != changed && Date() < deadline {
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertEqual(saver.content.configuration, changed)
  }
}
