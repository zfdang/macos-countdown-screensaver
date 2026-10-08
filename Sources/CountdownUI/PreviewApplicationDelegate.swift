import AppKit
import ScreenSaver

#if SWIFT_PACKAGE
  import CountdownCore
#endif

@MainActor
public final class PreviewApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  public private(set) var window: NSWindow!
  private(set) var saver: CountdownScreenSaverView!
  private(set) var timer: Timer?
  private let store: ConfigurationStore?
  private let terminateAfterClose: Bool
  public init(store: ConfigurationStore? = nil, terminateAfterLastWindowClosed: Bool = true) {
    self.store = store
    self.terminateAfterClose = terminateAfterLastWindowClosed
    super.init()
  }
  public func applicationDidFinishLaunching(_ notification: Notification) {
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    // Swift owns this window; AppKit must not release it behind the strong reference.
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.title = "Countdown Preview"
    let frame = NSRect(x: 0, y: 0, width: 1000, height: 610)
    saver =
      store.map { CountdownScreenSaverView(frame: frame, isPreview: true, store: $0)! }
      ?? CountdownScreenSaverView(frame: frame, isPreview: true)!
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
      [weak self, weak options] timer in
      MainActor.assumeIsolated {
        guard let self else {
          timer.invalidate()
          return
        }
        guard self.window.isVisible, self.saver.isAnimating else { return }
        self.saver.animateOneFrame()
        let l = Localization(
          preference: self.saver.content.configuration.languagePreference,
          preferredLanguages: SystemLanguages.preferred)
        self.window.title = l.text(.preview)
        options?.title = l.text(.options)
      }
    }
  }
  @objc func showOptions() {
    guard window.attachedSheet == nil else { return }
    if let sheet = saver.configureSheet { window.beginSheet(sheet) }
  }
  public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    terminateAfterClose
  }
  public func windowWillClose(_ notification: Notification) { stopUpdates() }
  public func applicationWillTerminate(_ notification: Notification) { stopUpdates() }
  private func stopUpdates() {
    timer?.invalidate()
    timer = nil
    saver?.stopAnimation()
  }
}
