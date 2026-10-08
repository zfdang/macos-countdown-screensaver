import AppKit
import Darwin
import ScreenSaver

#if SWIFT_PACKAGE
  import CountdownCore
  import CountdownUI
#endif

@MainActor func runAcceptance() throws {
  let arguments = CommandLine.arguments
  let directory = arguments.firstIndex(of: "--output").map { arguments[$0 + 1] } ?? ".acceptance"
  try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
  let view = CountdownContentView(frame: NSRect(x: 0, y: 0, width: 1000, height: 650))
  view.previewMode = true
  let now = Date(timeIntervalSince1970: 1_791_417_600)
  let service = CalendarConversionService()
  var configuration = Configuration()
  let input = DateInput(year: 2027, month: 1, day: 1, hour: 9, timeZoneIdentifier: "Asia/Shanghai")
  configuration.events = [
    CountdownEvent(
      title: "Project Launch 项目发布", createdOrder: 0, input: input,
      resolvedTimestamp: try service.resolve(input).timeIntervalSince1970)
  ]
  let hostWindow = NSWindow(
    contentRect: view.frame, styleMask: [], backing: .buffered, defer: false)
  hostWindow.contentView = view
  for (name, preference, size) in [
    ("english", LanguagePreference.en, NSSize(width: 1000, height: 650)),
    ("chinese", .zhHans, NSSize(width: 1000, height: 650)),
    ("small", .en, NSSize(width: 320, height: 240)),
    ("portrait", .zhHans, NSSize(width: 450, height: 800)),
    ("system-thumbnail", .en, NSSize(width: 143, height: 80)),
    ("settings-preview", .zhHans, NSSize(width: 500, height: 165)),
  ] {
    configuration.languagePreference = preference
    configuration.events[0].title = preference == .zhHans ? "项目发布" : "Project launch"
    view.configuration = configuration
    view.setFrameSize(size)
    view.update(now: now, uptime: 0)
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
      throw CountdownError.invalidConfiguration
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])!.write(
      to: URL(fileURLWithPath: directory + "/" + name + ".png"))
  }
  let suite = "com.zfdang.CountdownAcceptance." + UUID().uuidString
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }
  let store = ConfigurationStore(backend: DefaultsBackend(defaults: defaults))
  for (name, language) in [
    ("settings-english", LanguagePreference.en), ("settings-chinese", .zhHans),
  ] {
    configuration.languagePreference = language
    try store.save(configuration)
    let controller = ConfigurationWindowController(store: store)
    let window = controller.window!
    window.layoutIfNeeded()
    let content = window.contentView!
    content.layoutSubtreeIfNeeded()
    window.display()
    let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
    content.cacheDisplay(in: content.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])!.write(
      to: URL(fileURLWithPath: directory + "/" + name + ".png"))
    window.setContentSize(NSSize(width: 520, height: 420))
    window.layoutIfNeeded()
    content.layoutSubtreeIfNeeded()
    window.display()
    let small = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
    content.cacheDisplay(in: content.bounds, to: small)
    try small.representation(using: .png, properties: [:])!.write(
      to: URL(fileURLWithPath: directory + "/" + name + "-small.png"))
    controller.cancelPressed()
  }
  view.reset()
  view.previewMode = false
  configuration.languagePreference = .en
  configuration.events[0].title = "Project launch"
  configuration.appearance.moveContent = true
  view.configuration = configuration
  view.setFrameSize(NSSize(width: 1000, height: 650))
  for (name, uptime) in [
    ("old", 59.0), ("out", 60.3), ("black", 60.6),
    ("in", 60.9), ("new", 61.2),
  ] {
    if uptime == 60.3 { view.update(now: now, uptime: 60) }
    view.update(now: now, uptime: uptime)
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])!.write(
      to: URL(fileURLWithPath: directory + "/movement-" + name + ".png"))
  }
  view.reset()
  view.setFrameSize(NSSize(width: 3840, height: 2160))
  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
  func cpuSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
      + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
  }
  let started = cpuSeconds()
  for minute in 1...5 {
    let boundary = Double(minute * 60)
    view.update(now: now, uptime: boundary - 1)
    for frame in 0...29 {
      view.update(now: now, uptime: boundary + Double(frame) / 24)
      view.cacheDisplay(in: view.bounds, to: bitmap)
    }
  }
  let cpuPerFade = (cpuSeconds() - started) / 5
  view.reset()
  let report = String(
    format:
      "3840x2160 offscreen, 30 renders/fade, 5 fades: %.1f ms CPU/fade; %.3f%% of one core averaged over a minute. This is a drawing microbenchmark, not a battery/GPU measurement.\n",
    cpuPerFade * 1000, cpuPerFade / 60 * 100)
  try report.write(
    to: URL(fileURLWithPath: directory + "/movement-performance.txt"),
    atomically: true, encoding: .utf8)
  print(report, terminator: "")
  print(
    "PASS: rendered English, Chinese, small and portrait countdown views and movement fade phases")
}

// Keep the run loop alive after closure to exercise the old timer's crash window.
@MainActor func runCloseAcceptance(_ app: NSApplication) {
  let suite = "com.zfdang.CountdownCloseAcceptance." + UUID().uuidString
  let defaults = UserDefaults(suiteName: suite)!
  let delegate = PreviewApplicationDelegate(
    store: ConfigurationStore(backend: DefaultsBackend(defaults: defaults)),
    terminateAfterLastWindowClosed: false)
  app.delegate = delegate
  Timer.scheduledTimer(withTimeInterval: 1.25, repeats: false) { _ in
    MainActor.assumeIsolated {
      delegate.window.title = "Closed preview"
      delegate.window.performClose(nil)
    }
  }
  Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { _ in
    MainActor.assumeIsolated {
      precondition(!delegate.window.isVisible)
      precondition(
        delegate.window.title == "Closed preview", "Timer must stop updating a closed window")
      UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
      print(
        "PASS: preview closed; event loop stayed alive for two timer intervals without crash or updates"
      )
      fflush(stdout)
      app.terminate(nil)
    }
  }
  withExtendedLifetime(delegate) { app.run() }
}

// Exercise the real ScreenSaverDefaults implementation across separately launched processes.
@MainActor func runPreferencesWriter(domain: String, encoded: String) throws {
  guard let data = Data(base64Encoded: encoded),
    let defaults = ScreenSaverDefaults(forModuleWithName: domain)
  else { throw CountdownError.invalidConfiguration }
  let value = try JSONDecoder().decode(Configuration.self, from: data)
  let saved = try ConfigurationStore(backend: ScreenSaverDefaultsBackend(defaults: defaults)).save(
    value)
  print(try JSONEncoder().encode(saved).base64EncodedString())
}

@MainActor func runPreferencesAcceptance() throws {
  let domain = "com.zfdang.CountdownPreferencesAcceptance." + UUID().uuidString
  let defaults = ScreenSaverDefaults(forModuleWithName: domain)!
  defer {
    defaults.removeObject(forKey: DefaultsBackend.dataKey)
    _ = defaults.synchronize()
  }
  let store = ConfigurationStore(backend: ScreenSaverDefaultsBackend(defaults: defaults))
  _ = try store.save(Configuration())
  let saver = CountdownScreenSaverView(
    frame: NSRect(x: 0, y: 0, width: 1000, height: 650), isPreview: false, store: store)!
  saver.startAnimation()
  saver.stopAnimation()
  let draft = DraftConfiguration(Configuration())
  let id = try draft.add(zone: "UTC")
  try draft.update(
    id: id, title: "Saved in another host",
    input: DateInput(year: 2033, month: 12, day: 22, hour: 9, timeZoneIdentifier: "UTC"))
  draft.setLanguage(.zhHans)
  for index in 0..<2 {
    var value = try draft.validated()
    value.events[0].title += " \(index)"
    value.events[0].input.minute = index
    value.events[0].resolvedTimestamp = try CalendarConversionService().resolve(
      value.events[0].input
    ).timeIntervalSince1970
    let writer = Process()
    writer.executableURL = Bundle.main.executableURL!
    writer.arguments = [
      "--acceptance-write-preferences", domain,
      try JSONEncoder().encode(value).base64EncodedString(),
    ]
    let pipe = Pipe()
    writer.standardOutput = pipe
    try writer.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    writer.waitUntilExit()
    precondition(writer.terminationStatus == 0, "Preferences writer failed")
    let encoded = String(decoding: output, as: UTF8.self).trimmingCharacters(
      in: .whitespacesAndNewlines)
    guard let data = Data(base64Encoded: encoded) else { fatalError("Invalid writer output") }
    let saved = try JSONDecoder().decode(Configuration.self, from: data)
    if index == 0 { saver.startAnimation() } else { saver.reloadConfiguration() }
    precondition(
      saver.content.configuration == saved,
      "Full-size saver must see another host's edited title, time and language")
    saver.stopAnimation()
  }
  print("PASS: ScreenSaverDefaults save/flush and full-size restart/reload across processes")
}

@main enum PreviewMain {
  @MainActor static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    if let index = CommandLine.arguments.firstIndex(of: "--acceptance-write-preferences") {
      do {
        guard CommandLine.arguments.count == index + 3 else {
          throw CountdownError.invalidConfiguration
        }
        try runPreferencesWriter(
          domain: CommandLine.arguments[index + 1], encoded: CommandLine.arguments[index + 2])
      } catch {
        fputs("Preferences writer failed: \(error)\n", stderr)
        exit(1)
      }
    } else if CommandLine.arguments.contains("--acceptance-preferences") {
      do { try runPreferencesAcceptance() } catch {
        fputs("Preferences acceptance failed: \(error)\n", stderr)
        exit(1)
      }
    } else if CommandLine.arguments.contains("--acceptance-close") {
      runCloseAcceptance(app)
    } else if CommandLine.arguments.contains("--acceptance") {
      do { try runAcceptance() } catch {
        fputs("Acceptance failed: \(error)\n", stderr)
        exit(1)
      }
    } else {
      let delegate = PreviewApplicationDelegate()
      app.delegate = delegate
      withExtendedLifetime(delegate) { app.run() }
    }
  }
}
