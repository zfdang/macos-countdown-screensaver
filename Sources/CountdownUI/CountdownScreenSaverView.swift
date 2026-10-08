import AppKit
import ScreenSaver

#if SWIFT_PACKAGE
  import CountdownCore
#endif

@objc(CountdownScreenSaverView)
@MainActor public final class CountdownScreenSaverView: ScreenSaverView {
  public static let preferencesDomain = "com.zfdang.CountdownScreenSaver"
  public static let configurationChanged = Notification.Name(
    "com.zfdang.CountdownScreenSaver.configurationChanged")
  public let content = CountdownContentView()
  private var store: ConfigurationStore!
  private var controller: ConfigurationWindowController?
  private var lastPoll: TimeInterval = -.infinity
  static let configurationPollInterval: TimeInterval = 60
  public override init?(frame: NSRect, isPreview: Bool) {
    super.init(frame: frame, isPreview: isPreview)
    configure(isPreview: isPreview)
  }
  public convenience init?(frame: NSRect, isPreview: Bool, store: ConfigurationStore) {
    self.init(frame: frame, isPreview: isPreview)
    self.store = store
    content.reset()
    reloadConfiguration()
  }
  public required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure(isPreview: false)
  }
  private func configure(isPreview: Bool) {
    let defaults =
      ScreenSaverDefaults(forModuleWithName: Self.preferencesDomain) ?? UserDefaults(
        suiteName: Self.preferencesDomain)!
    store = ConfigurationStore(backend: DefaultsBackend(defaults: defaults))
    animationTimeInterval = 1
    content.previewMode = isPreview
    content.frame = bounds
    content.autoresizingMask = [.width, .height]
    addSubview(content)
    reloadConfiguration()
    DistributedNotificationCenter.default().addObserver(
      self, selector: #selector(settingsChanged), name: Self.configurationChanged, object: nil)
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(resumed), name: NSWorkspace.didWakeNotification, object: nil)
  }
  deinit {
    DistributedNotificationCenter.default().removeObserver(self)
    NSWorkspace.shared.notificationCenter.removeObserver(self)
  }
  @objc private func settingsChanged() { reloadConfiguration() }
  @objc private func resumed() {
    content.reset()
    reloadConfiguration()
  }
  public func reloadConfiguration(
    now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) {
    do {
      let config = try store.load()
      if config.revision != content.configuration.revision { content.reset() }
      content.configuration = config
      content.configurationError = nil
    } catch { content.configurationError = error }
    content.preferredLanguages = SystemLanguages.preferred
    content.update(now: now, uptime: uptime)
    lastPoll = uptime
  }
  public override func startAnimation() {
    super.startAnimation()
    content.reset()
    reloadConfiguration()
  }
  public override func stopAnimation() {
    super.stopAnimation()
    content.reset()
  }
  public override func animateOneFrame() {
    advanceFrame(now: Date(), uptime: ProcessInfo.processInfo.systemUptime)
  }
  func advanceFrame(now: Date, uptime: TimeInterval) {
    guard isAnimating else { return }
    if uptime - lastPoll >= Self.configurationPollInterval || uptime < lastPoll {
      reloadConfiguration(now: now, uptime: uptime)
    } else {
      content.update(now: now, uptime: uptime)
    }
  }
  public override var hasConfigureSheet: Bool { true }
  public override var configureSheet: NSWindow? {
    if let controller { return controller.window }
    let settings = ConfigurationWindowController(store: store)
    controller = settings
    settings.onFinish = { [weak self] in self?.controller = nil }
    settings.onSave = { [weak self] _ in
      self?.reloadConfiguration()
      DistributedNotificationCenter.default().postNotificationName(
        Self.configurationChanged, object: nil, userInfo: nil, deliverImmediately: true)
    }
    return settings.window
  }
}
