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
    // A second instance models independent display views and repeated sheet opening.
    let second = type.init(frame: NSRect(x: 0, y: 0, width: 320, height: 240), isPreview: false)!
    second.startAnimation()
    second.animateOneFrame()
    second.stopAnimation()
    precondition(second.configureSheet != nil)
    print(
      "PASS: real bundle load, principal class, configure sheet, preview/full-size instances, start/stop/restart"
    )
  }
}
