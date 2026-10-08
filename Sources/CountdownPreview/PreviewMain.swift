import AppKit
import ScreenSaver

#if SWIFT_PACKAGE
  import CountdownCore
  import CountdownUI
#endif

@MainActor final class PreviewDelegate: NSObject, NSApplicationDelegate {
  var window: NSWindow!
  var saver: CountdownScreenSaverView!
  var timer: Timer?
  func applicationDidFinishLaunching(_ notification: Notification) {
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = "Countdown Preview"
    saver = CountdownScreenSaverView(
      frame: NSRect(x: 0, y: 0, width: 1000, height: 610), isPreview: true)!
    saver.autoresizingMask = [.width, .height]
    let root = NSView()
    window.contentView = root
    root.addSubview(saver)
    let options = NSButton(
      title: Localization(
        preference: saver.content.configuration.languagePreference,
        preferredLanguages: SystemLanguages.preferred
      ).text(.options), target: self, action: #selector(showOptions))
    options.frame = NSRect(x: 20, y: 615, width: 130, height: 28)
    options.autoresizingMask = [.minYMargin]
    options.setAccessibilityIdentifier("options")
    root.addSubview(options)
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    saver.startAnimation()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
      [weak self, weak options] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.saver.animateOneFrame()
        let l = Localization(
          preference: self.saver.content.configuration.languagePreference,
          preferredLanguages: SystemLanguages.preferred)
        self.window.title = l.text(.preview)
        options?.title = l.text(.options)
      }
    }
  }
  @objc func showOptions() { if let sheet = saver.configureSheet { window.beginSheet(sheet) } }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
  func applicationWillTerminate(_ notification: Notification) {
    timer?.invalidate()
    saver?.stopAnimation()
  }
}

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
  print("PASS: rendered English, Chinese, small and portrait countdown views")
}

@main enum PreviewMain {
  @MainActor static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    if CommandLine.arguments.contains("--acceptance") {
      do { try runAcceptance() } catch {
        fputs("Acceptance failed: \(error)\n", stderr)
        exit(1)
      }
    } else {
      let delegate = PreviewDelegate()
      app.delegate = delegate
      app.run()
    }
  }
}
