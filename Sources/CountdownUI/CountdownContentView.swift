import AppKit

#if SWIFT_PACKAGE
  import CountdownCore
#endif

public enum SystemLanguages {
  public static var preferred: [String] {
    (CFPreferencesCopyValue(
      "AppleLanguages" as CFString, kCFPreferencesAnyApplication,
      kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String]) ?? Locale.preferredLanguages
  }
}

@MainActor public final class CountdownContentView: NSView {
  public var configuration = Configuration()
  public var configurationError: Error?
  public var previewMode = false
  public var preferredLanguages: [String] = SystemLanguages.preferred
  public private(set) var state: CountdownState = .empty
  private var engine = CountdownEngine()
  private var lastUptime: TimeInterval = 0
  private struct RenderSnapshot: Equatable {
    let state: CountdownState
    let configuration: Configuration
    let language: UILanguage
    let preview: Bool
    let movementStep: Int?
    let errorMessage: String?
  }
  private var lastRenderSnapshot: RenderSnapshot?
  public override var isFlipped: Bool { true }
  public override var isOpaque: Bool { true }
  public func reset() {
    engine.reset()
    lastRenderSnapshot = nil
  }
  @discardableResult public func update(
    now: Date = Date(), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) -> Bool {
    state = engine.tick(configuration: configuration, now: now, uptime: uptime)
    lastUptime = uptime
    let l = Localization(
      preference: configuration.languagePreference, preferredLanguages: preferredLanguages)
    let snapshot = RenderSnapshot(
      state: state, configuration: configuration, language: l.language, preview: previewMode,
      movementStep: configuration.appearance.moveContent && !previewMode ? Int(uptime / 60) : nil,
      errorMessage: configurationError.map { l.error($0) })
    if snapshot != lastRenderSnapshot {
      needsDisplay = true
      lastRenderSnapshot = snapshot
      return true
    }
    return false
  }
  public override func draw(_ dirtyRect: NSRect) {
    NSColor.black.setFill()
    bounds.fill()
    let movement = ContentLayout(
      width: bounds.width, height: bounds.height, dayDigits: 2,
      move: configuration.appearance.moveContent, preview: previewMode, uptime: lastUptime)
    let context = NSGraphicsContext.current?.cgContext
    context?.saveGState()
    context?.translateBy(x: movement.offsetX, y: movement.offsetY)
    defer { context?.restoreGState() }
    let l = Localization(
      preference: configuration.languagePreference, preferredLanguages: preferredLanguages)
    if let error = configurationError {
      drawText(
        l.error(error), rect: bounds.insetBy(dx: bounds.width * 0.06, dy: bounds.height * 0.3),
        size: max(8, min(28, bounds.width / 36)), alpha: 0.7)
      return
    }
    let digits: [String]
    let title: String
    var detail = ""
    var position = ""
    var nextText = ""
    switch state {
    case .empty:
      drawText(
        l.text(.empty), rect: bounds.insetBy(dx: bounds.width * 0.06, dy: bounds.height * 0.3),
        size: max(8, min(28, bounds.width / 36)), alpha: 0.7)
      return
    case .completed(let event):
      drawText(
        l.text(.completed),
        rect: NSRect(
          x: 20, y: bounds.height * 0.38, width: bounds.width - 40, height: bounds.height * 0.14),
        size: max(12, bounds.width / 30))
      if configuration.appearance.showTargetDate {
        drawText(
          l.title(event, position: configuration.events.count) + "\n" + l.date(event),
          rect: NSRect(
            x: 20, y: bounds.height * 0.55, width: bounds.width - 40, height: bounds.height * 0.25),
          size: max(9, bounds.width / 55), alpha: 0.5)
      }
      return
    case .reached(let group):
      digits = ["00", "00", "00", "00"]
      title = l.text(.reached, group.title(using: l))
      detail = l.date(group.events[0])
      position = group.position(using: l, total: configuration.events.count)
    case .counting(let group, let remaining, let next):
      digits = remaining.digits
      title = l.text(.countdown, group.title(using: l))
      detail = l.date(group.events[0])
      position = group.position(using: l, total: configuration.events.count)
      if let next {
        nextText = l.text(.next, next.title(using: l)) + " · " + l.date(next.events[0])
      }
    }
    let layout = ContentLayout(
      width: bounds.width, height: bounds.height, dayDigits: digits[0].count,
      move: configuration.appearance.moveContent, preview: previewMode, uptime: lastUptime)
    let area = bounds.insetBy(dx: bounds.width * 0.06, dy: bounds.height * 0.08)

    let smallSize = max(8, min(22, bounds.width / 48, bounds.height / 17))
    drawText(
      title,
      rect: NSRect(x: area.minX, y: area.minY, width: area.width, height: area.height * 0.18),
      size: max(8, bounds.width / 35))
    let units: [TextKey] =
      bounds.width < 240
      ? [.days, .hoursShort, .minutesShort, .secondsShort] : [.days, .hours, .minutes, .seconds]
    let columnCount = layout.compact ? 2 : 4
    let rowHeight = area.height * (layout.compact ? 0.26 : 0.34)
    let row = DigitRowLayout(
      rowHeight: rowHeight, screenWidth: bounds.width,
      screenHeight: bounds.height, compact: layout.compact)
    for index in 0..<4 {
      let width = area.width / CGFloat(columnCount)
      let x = area.minX + CGFloat(index % columnCount) * width
      let y = area.minY + area.height * 0.22 + CGFloat(index / columnCount) * rowHeight
      let font = NSFont.monospacedDigitSystemFont(ofSize: layout.digitSize, weight: .thin)
      let stringWidth = (digits[index] as NSString).size(withAttributes: [.font: font]).width
      let fittedSize = min(
        min(layout.digitSize, row.digitHeight / 1.2),
        layout.digitSize * (width * 0.95) / max(1, stringWidth))
      drawText(
        digits[index], rect: NSRect(x: x, y: y, width: width, height: row.digitHeight),
        size: fittedSize, numeric: true)
      drawText(
        l.text(units[index]),
        rect: NSRect(
          x: x, y: y + row.unitOffset, width: width,
          height: row.unitHeight), size: row.unitSize, alpha: 0.65, weight: .regular)
    }
    let footer = FooterLayout(
      height: bounds.height, compact: layout.compact,
      showDate: configuration.appearance.showTargetDate,
      showNext: configuration.appearance.showNextTarget && layout.showNext && !nextText.isEmpty)
    if let y = footer.dateY {
      drawText(
        detail,
        rect: NSRect(
          x: area.minX, y: area.minY + area.height * y, width: area.width,
          height: area.height * 0.12),
        size: smallSize, alpha: 0.5)
    }
    if let y = footer.positionY {
      drawText(
        position,
        rect: NSRect(
          x: area.minX, y: area.minY + area.height * y, width: area.width,
          height: max(area.height * 0.07, smallSize * 1.4)
        ), size: smallSize, alpha: 0.5)
    }
    if let y = footer.nextY {
      drawText(
        nextText,
        rect: NSRect(
          x: area.minX, y: area.minY + area.height * y, width: area.width,
          height: area.height * 0.1), size: smallSize * 0.85, alpha: 0.4)
    }
  }
  private func drawText(
    _ text: String, rect: NSRect, size: CGFloat, alpha: CGFloat = 1, numeric: Bool = false,
    weight: NSFont.Weight = .light
  ) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = numeric ? .byClipping : .byWordWrapping
    let font =
      numeric
      ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .thin)
      : NSFont.systemFont(ofSize: size, weight: weight)
    (text as NSString).draw(
      in: rect,
      withAttributes: [
        .font: font, .foregroundColor: NSColor(white: 0.96, alpha: alpha),
        .paragraphStyle: paragraph,
      ])
  }
}
