import AppKit
import ScreenSaver

// This host deliberately does not link CountdownUI: Bundle must resolve the actual plug-in class.
@main enum AcceptanceHost {
  @MainActor static func main() throws {
    _ = NSApplication.shared
    guard CommandLine.arguments.count >= 3,
      let bundle = Bundle(path: CommandLine.arguments[1])
    else { fatalError("Usage: AcceptanceHost saver-path output-directory") }
    try bundle.loadAndReturnError()
    guard let type = bundle.principalClass as? ScreenSaverView.Type,
      let view = type.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600), isPreview: true)
    else {
      fatalError("Screen saver principal class failed to instantiate")
    }
    precondition(view.hasConfigureSheet)
    view.startAnimation()
    precondition(view.isAnimating)
    view.animateOneFrame()
    view.stopAnimation()
    precondition(!view.isAnimating)
    view.startAnimation()
    precondition(view.isAnimating)
    view.animateOneFrame()
    view.stopAnimation()
    guard let sheet = view.configureSheet, let content = sheet.contentView else {
      fatalError("Missing configuration sheet")
    }
    sheet.layoutIfNeeded()
    content.layoutSubtreeIfNeeded()
    let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
    content.cacheDisplay(in: content.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])!.write(
      to: URL(fileURLWithPath: CommandLine.arguments[2] + "/bundle-settings.png"))
    // Present the actual bundle's sheet, rather than only rendering its detached contents.
    // Returning a window from configureSheet alone does not verify that Options can open it.
    let parent = NSWindow(
      contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
    parent.isReleasedWhenClosed = false
    parent.contentView = view
    parent.orderFront(nil)
    for _ in 0..<3 {
      guard let options = view.configureSheet else { fatalError("Missing reopened sheet") }
      precondition(view.configureSheet === options, "Repeated queries must reuse the sheet")
      parent.beginSheet(options)
      RunLoop.main.run(until: Date().addingTimeInterval(0.1))
      precondition(
        options.sheetParent === parent && options.isVisible,
        "Options must present a visible sheet attached to its host window")
      guard let cancel = findButton("cancel", in: options.contentView!) else {
        fatalError("Missing Cancel action")
      }
      cancel.performClick(nil)
      RunLoop.main.run(until: Date().addingTimeInterval(0.1))
      precondition(options.sheetParent == nil && !options.isVisible)
      precondition(view.configureSheet !== options, "Finished sheets must be replaced")
    }
    parent.close()
    // A second instance models independent display views and repeated sheet opening.
    let second = type.init(frame: NSRect(x: 0, y: 0, width: 320, height: 240), isPreview: false)!
    second.startAnimation()
    second.animateOneFrame()
    second.stopAnimation()
    precondition(second.configureSheet != nil)
    print(
      "PASS: real bundle load, principal class, visible configuration sheet with three cancel/reopen cycles, preview/full-size instances, start/stop/restart"
    )
  }
  @MainActor private static func findButton(_ id: String, in view: NSView) -> NSButton? {
    if let button = view as? NSButton, button.accessibilityIdentifier() == id { return button }
    for child in view.subviews {
      if let button = findButton(id, in: child) { return button }
    }
    return nil
  }
}
