import AppKit
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
  print("PASS: rendered English, Chinese, small and portrait countdown views")
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

@main enum PreviewMain {
  @MainActor static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    if CommandLine.arguments.contains("--acceptance-close") {
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
