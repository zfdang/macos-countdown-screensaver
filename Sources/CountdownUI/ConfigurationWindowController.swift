import AppKit

#if SWIFT_PACKAGE
  import CountdownCore
#endif

@MainActor private final class SettingsBackgroundView: NSView {
  override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill()
    bounds.fill()
  }
}

@MainActor
public final class ConfigurationWindowController: NSWindowController, NSTableViewDataSource,
  NSTableViewDelegate, NSTextFieldDelegate
{
  public private(set) var draft: DraftConfiguration
  public private(set) var selectedID: UUID?
  public private(set) var loadError: Error?
  public var onSave: ((Configuration) -> Void)?
  public var onCancel: (() -> Void)?
  private let store: ConfigurationStore
  private let service = CalendarConversionService()
  private let table = NSTableView()
  private var titleField = NSTextField()
  private var yearField = NSTextField()
  private var monthPicker = NSPopUpButton()
  private var dayPicker = NSPopUpButton()
  private var hourField = NSTextField(), minuteField = NSTextField(), secondField = NSTextField()
  private var zonePicker = NSPopUpButton()
  private var calendarPicker = NSPopUpButton()
  private var languagePicker = NSPopUpButton()
  private var occurrencePicker = NSPopUpButton()
  private var occurrenceRow = NSStackView()
  private var calendarConverted = false
  private var errorLabel = NSTextField(wrappingLabelWithString: "")
  private var equivalentLabel = NSTextField(wrappingLabelWithString: "")
  private var saveButton = NSButton(), addButton = NSButton(), deleteButton = NSButton()
  private var showDate = NSButton(), showNext = NSButton(), move = NSButton()
  private var preview = CountdownContentView()
  private var refreshing = false
  private var pendingFormError: Error?
  private var invalidText: [String: String] = [:]
  private var previewTimer: Timer?
  private var l: Localization {
    Localization(
      preference: draft.value.languagePreference, preferredLanguages: SystemLanguages.preferred)
  }
  private var event: CountdownEvent? { draft.value.events.first { $0.id == selectedID } }

  public init(store: ConfigurationStore) {
    self.store = store
    do { draft = DraftConfiguration(try store.load()) } catch {
      calendarConverted = false
      draft = DraftConfiguration(Configuration())
      loadError = error
    }
    super.init(window: nil)
    selectedID = draft.value.sortedEvents.first?.id
    buildWindow()
  }
  required init?(coder: NSCoder) { fatalError("Use init(store:)") }
  deinit { previewTimer?.invalidate() }

  private func buildWindow() {
    if window == nil {
      window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
        styleMask: [.titled], backing: .buffered, defer: false)
      window?.isReleasedWhenClosed = false
    }
    window?.title = l.text(.settings)
    refreshing = true
    let root = vertical(spacing: 18)
    root.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 20, right: 24)
    let heading = NSTextField(labelWithString: l.text(.settings))
    heading.font = .systemFont(ofSize: 22, weight: .semibold)
    root.addArrangedSubview(heading)
    let subtitle = NSTextField(labelWithString: l.text(.settingsHint))
    subtitle.font = .systemFont(ofSize: 12)
    subtitle.textColor = .secondaryLabelColor
    root.addArrangedSubview(subtitle)
    root.setCustomSpacing(5, after: heading)

    let columns = NSStackView()
    columns.orientation = .horizontal
    columns.alignment = .top
    columns.spacing = 18
    let left = vertical(spacing: 12)
    left.addArrangedSubview(sectionTitle(.targets))
    let count = NSTextField(labelWithString: l.text(.sorted, draft.value.events.count))
    count.font = .systemFont(ofSize: 11)
    count.textColor = .secondaryLabelColor
    left.addArrangedSubview(count)
    if table.tableColumns.isEmpty {
      table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("event")))
    }
    table.headerView = nil
    table.rowHeight = 78
    table.intercellSpacing = NSSize(width: 0, height: 6)
    table.backgroundColor = .clear
    table.style = .sourceList
    table.dataSource = self
    table.delegate = self
    table.setAccessibilityIdentifier("eventList")
    let scroll = NSScrollView()
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    scroll.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      scroll.widthAnchor.constraint(equalToConstant: 208),
      scroll.heightAnchor.constraint(equalToConstant: 348),
    ])
    left.addArrangedSubview(scroll)
    addButton = button(.add, action: #selector(addEvent), id: "addEvent")
    deleteButton = button(.delete, action: #selector(deleteEvent), id: "deleteEvent")
    left.addArrangedSubview(NSStackView(views: [addButton, deleteButton]))
    let sidebar = card(left)
    sidebar.widthAnchor.constraint(equalToConstant: 240).isActive = true
    columns.addArrangedSubview(sidebar)

    let right = vertical(spacing: 14)
    let editor = vertical(spacing: 10)
    editor.addArrangedSubview(sectionTitle(.eventDetails))
    titleField = field(id: "title")
    yearField = field(id: "year")
    hourField = field(id: "hour")
    minuteField = field(id: "minute")
    secondField = field(id: "second")
    editor.addArrangedSubview(row(.name, [titleField]))
    calendarPicker = popup(id: "calendar", action: #selector(calendarChanged))
    calendarPicker.addItems(withTitles: [l.text(.gregorian), l.text(.lunar)])
    editor.addArrangedSubview(row(.calendar, [calendarPicker]))
    monthPicker = popup(id: "month", action: #selector(dateChanged))
    dayPicker = popup(id: "day", action: #selector(dateChanged))
    editor.addArrangedSubview(row(.date, [yearField, monthPicker, dayPicker]))
    editor.addArrangedSubview(
      row(
        .time,
        [
          hourField, NSTextField(labelWithString: ":"),
          minuteField, NSTextField(labelWithString: ":"), secondField,
        ]))
    zonePicker = popup(id: "timeZone", action: #selector(dateChanged))
    zonePicker.addItems(
      withTitles: Array(
        Set(TimeZone.knownTimeZoneIdentifiers + ["UTC", TimeZone.current.identifier])
      ).sorted())
    editor.addArrangedSubview(row(.zone, [zonePicker]))
    occurrencePicker = popup(id: "occurrence", action: #selector(dateChanged))
    occurrenceRow = row(.occurrence, [occurrencePicker])
    editor.addArrangedSubview(occurrenceRow)
    equivalentLabel = NSTextField(wrappingLabelWithString: "")
    equivalentLabel.font = .systemFont(ofSize: 11)
    equivalentLabel.textColor = .secondaryLabelColor
    equivalentLabel.setAccessibilityIdentifier("equivalent")
    errorLabel = NSTextField(wrappingLabelWithString: "")
    errorLabel.font = .systemFont(ofSize: 11)
    errorLabel.setAccessibilityIdentifier("status")
    for label in [equivalentLabel, errorLabel] {
      label.translatesAutoresizingMaskIntoConstraints = false
      label.widthAnchor.constraint(equalToConstant: 540).isActive = true
      label.heightAnchor.constraint(equalToConstant: 24).isActive = true
      editor.addArrangedSubview(label)
    }
    right.addArrangedSubview(card(editor))
    let previewSection = vertical(spacing: 8)
    previewSection.addArrangedSubview(sectionTitle(.livePreview))
    preview = CountdownContentView()
    preview.previewMode = true
    preview.wantsLayer = true
    preview.layer?.cornerRadius = 8
    preview.layer?.masksToBounds = true
    preview.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      preview.widthAnchor.constraint(equalToConstant: 572),
      preview.heightAnchor.constraint(equalToConstant: 150),
    ])
    previewSection.addArrangedSubview(preview)
    right.addArrangedSubview(previewSection)
    columns.addArrangedSubview(right)
    root.addArrangedSubview(columns)

    let preferences = NSStackView()
    preferences.orientation = .horizontal
    preferences.alignment = .top
    preferences.spacing = 30
    let language = vertical(spacing: 10)
    language.addArrangedSubview(sectionTitle(.language))
    languagePicker = popup(id: "language", action: #selector(languageChanged))
    languagePicker.addItems(withTitles: [l.text(.system), "English", "中文"])
    languagePicker.selectItem(
      at: LanguagePreference.allCases.firstIndex(of: draft.value.languagePreference) ?? 0)
    language.addArrangedSubview(languagePicker)
    language.widthAnchor.constraint(equalToConstant: 208).isActive = true
    preferences.addArrangedSubview(language)
    let appearance = vertical(spacing: 8)
    appearance.addArrangedSubview(sectionTitle(.appearance))
    showDate = checkbox(.showDate, value: draft.value.appearance.showTargetDate, id: "showDate")
    showNext = checkbox(.showNext, value: draft.value.appearance.showNextTarget, id: "showNext")
    move = checkbox(.move, value: draft.value.appearance.moveContent, id: "moveContent")
    appearance.addArrangedSubview(NSStackView(views: [showDate, showNext]))
    appearance.addArrangedSubview(move)
    preferences.addArrangedSubview(appearance)
    let preferencesCard = card(preferences)
    root.addArrangedSubview(preferencesCard)
    let footer = NSStackView()
    footer.orientation = .horizontal
    footer.spacing = 10
    if loadError != nil {
      footer.addArrangedSubview(button(.repair, action: #selector(repairPressed), id: "repair"))
    }
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    footer.addArrangedSubview(spacer)
    let cancel = button(.cancel, action: #selector(cancelPressed), id: "cancel")
    cancel.keyEquivalent = "\u{1b}"
    saveButton = button(.save, action: #selector(savePressed), id: "save")
    saveButton.keyEquivalent = "\r"
    footer.addArrangedSubview(cancel)
    footer.addArrangedSubview(saveButton)
    root.addArrangedSubview(footer)
    let content = (window?.contentView as? SettingsBackgroundView) ?? SettingsBackgroundView()
    content.subviews.forEach { $0.removeFromSuperview() }
    if window?.contentView !== content { window?.contentView = content }
    root.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(root)
    NSLayoutConstraint.activate([
      root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      root.topAnchor.constraint(equalTo: content.topAnchor),
      root.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
      preferencesCard.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -48),
      footer.widthAnchor.constraint(equalTo: preferencesCard.widthAnchor),
    ])
    NSAccessibility.post(element: content, notification: .layoutChanged)
    refreshing = false
    populateEditor()
    reloadTable()
    updatePreview()
    window?.layoutIfNeeded()
    window?.display()
    previewTimer?.invalidate()
    previewTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.updatePreview() }
    }
  }
  private func vertical(spacing: CGFloat) -> NSStackView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = spacing
    return stack
  }
  private func sectionTitle(_ key: TextKey) -> NSTextField {
    let label = NSTextField(labelWithString: l.text(key))
    label.font = .systemFont(ofSize: 12, weight: .semibold)
    return label
  }
  private func card(_ stack: NSStackView) -> NSBox {
    let box = NSBox()
    box.boxType = .custom
    box.borderColor = .separatorColor
    box.borderWidth = 0.5
    box.fillColor = .controlBackgroundColor
    box.cornerRadius = 10
    box.contentViewMargins = .zero
    box.translatesAutoresizingMaskIntoConstraints = false
    let container = NSView()
    box.contentView = container
    stack.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
      stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
    ])
    return box
  }
  private func field(id: String) -> NSTextField {
    let result = NSTextField()
    result.delegate = self
    result.font = .systemFont(ofSize: 13)
    if id != "title" { result.alignment = .center }
    result.setAccessibilityIdentifier(id)
    result.translatesAutoresizingMaskIntoConstraints = false
    result.widthAnchor.constraint(equalToConstant: id == "title" ? 432 : id == "year" ? 76 : 48)
      .isActive = true
    return result
  }
  private func row(_ key: TextKey, _ views: [NSView]) -> NSStackView {
    let label = NSTextField(labelWithString: l.text(key))
    label.translatesAutoresizingMaskIntoConstraints = false
    label.widthAnchor.constraint(equalToConstant: 96).isActive = true
    label.textColor = .secondaryLabelColor
    label.font = .systemFont(ofSize: 12)
    let result = NSStackView(views: [label] + views)
    result.orientation = .horizontal
    result.spacing = 6
    return result
  }
  private func button(_ key: TextKey, action: Selector, id: String) -> NSButton {
    let result = NSButton(title: l.text(key), target: self, action: action)
    result.setAccessibilityIdentifier(id)
    return result
  }
  private func popup(id: String, action: Selector) -> NSPopUpButton {
    let result = NSPopUpButton()
    result.target = self
    result.action = action
    result.setAccessibilityIdentifier(id)
    result.translatesAutoresizingMaskIntoConstraints = false
    result.widthAnchor.constraint(
      lessThanOrEqualToConstant: id == "timeZone" ? 432 : id == "occurrence" ? 260 : 180
    )
    .isActive = true
    return result
  }
  private func checkbox(_ key: TextKey, value: Bool, id: String) -> NSButton {
    let result = NSButton(
      checkboxWithTitle: l.text(key), target: self, action: #selector(appearanceChanged))
    result.state = value ? .on : .off
    result.setAccessibilityIdentifier(id)
    return result
  }
  private func populateEditor() {
    refreshing = true
    defer { refreshing = false }
    let controls: [NSControl] = [
      titleField, yearField, monthPicker, dayPicker, hourField, minuteField, secondField,
      zonePicker, calendarPicker, occurrencePicker,
    ]
    controls.forEach { $0.isEnabled = event != nil && loadError == nil }
    guard let event else {
      occurrenceRow.isHidden = true
      titleField.stringValue = ""
      yearField.stringValue = ""
      monthPicker.removeAllItems()
      dayPicker.removeAllItems()
      equivalentLabel.stringValue = ""
      pendingFormError = nil
      updateStatus()
      return
    }
    titleField.stringValue = invalidText["title"] ?? event.title
    yearField.stringValue = invalidText["year"] ?? String(event.input.year)
    hourField.stringValue = invalidText["hour"] ?? String(format: "%02d", event.input.hour)
    minuteField.stringValue = invalidText["minute"] ?? String(format: "%02d", event.input.minute)
    secondField.stringValue = invalidText["second"] ?? String(format: "%02d", event.input.second)
    calendarPicker.selectItem(at: event.input.calendar == .gregorian ? 0 : 1)
    zonePicker.selectItem(withTitle: event.input.timeZoneIdentifier)
    refreshDateOptions(input: event.input)
    updateStatus()
  }
  private func refreshDateOptions(input: DateInput) {
    refreshing = true
    defer { refreshing = false }
    monthPicker.removeAllItems()
    var tokens: [(Int, Bool)] = []
    if input.calendar == .chinese {
      tokens = ((try? service.lunarMonths(in: input.year)) ?? []).map { ($0.number, $0.isLeap) }
    } else {
      tokens = (1...12).map { ($0, false) }
    }
    for (number, leap) in tokens {
      monthPicker.addItem(
        withTitle: input.calendar == .chinese ? l.month(number, leap: leap) : String(number))
      monthPicker.lastItem?.representedObject = "\(number):\(leap)"
    }
    if let index = tokens.firstIndex(where: { $0.0 == input.month && $0.1 == input.isLeapMonth }) {
      monthPicker.selectItem(at: index)
    } else {
      monthPicker.insertItem(withTitle: "—", at: 0)
      monthPicker.item(at: 0)?.representedObject = "0:false"
      monthPicker.selectItem(at: 0)
    }
    dayPicker.removeAllItems()
    let count = (try? service.days(in: input)) ?? 0
    if count > 0 {
      for day in 1...count {
        dayPicker.addItem(withTitle: input.calendar == .chinese ? l.day(day) : String(day))
        dayPicker.lastItem?.tag = day
      }
    }
    if input.day > 0 && input.day <= count {
      dayPicker.selectItem(at: input.day - 1)
    } else {
      dayPicker.insertItem(withTitle: "—", at: 0)
      dayPicker.item(at: 0)?.tag = 0
      dayPicker.selectItem(at: 0)
    }
    occurrencePicker.removeAllItems()
    occurrencePicker.addItem(withTitle: "—")
    let candidates = (try? service.candidates(for: input)) ?? []
    if candidates.count > 1, let zone = TimeZone(identifier: input.timeZoneIdentifier) {
      for (index, candidate) in candidates.enumerated() {
        let offset = zone.secondsFromGMT(for: candidate)
        let sign = offset >= 0 ? "+" : "−"
        let utc = String(
          format: "UTC%@%02d:%02d", sign, abs(offset) / 3600, (abs(offset) % 3600) / 60)
        occurrencePicker.addItem(withTitle: l.text(index == 0 ? .first : .second) + " · " + utc)
      }
      occurrencePicker.selectItem(
        at: input.repeatedTimeChoice == .first ? 1 : input.repeatedTimeChoice == .second ? 2 : 0)
      occurrencePicker.isEnabled = true
      occurrenceRow.isHidden = false
    } else {
      occurrencePicker.isEnabled = false
      occurrenceRow.isHidden = true
    }
  }
  public func numberOfRows(in tableView: NSTableView) -> Int { draft.value.events.count }
  public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
    -> NSView?
  {
    let events = draft.value.sortedEvents
    guard events.indices.contains(row) else { return nil }
    let e = events[row]
    let cell = NSTableCellView()
    let name = NSTextField(labelWithString: l.title(e, position: row + 1))
    name.font = .systemFont(ofSize: 12, weight: .medium)
    name.lineBreakMode = .byTruncatingTail
    cell.textField = name
    let date = NSTextField(labelWithString: l.gregorianDate(e).components(separatedBy: " · ")[0])
    date.font = .systemFont(ofSize: 10)
    date.textColor = .secondaryLabelColor
    date.lineBreakMode = .byTruncatingTail
    let status = NSTextField(
      labelWithString: l.text(e.input.calendar == .chinese ? .lunar : .gregorian)
        + " · " + l.text(e.resolvedTimestamp > Date().timeIntervalSince1970 ? .upcoming : .expired))
    status.font = .systemFont(ofSize: 10)
    status.textColor = .secondaryLabelColor
    let stack = vertical(spacing: 4)
    for label in [name, date, status] {
      label.translatesAutoresizingMaskIntoConstraints = false
      stack.addArrangedSubview(label)
      label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    stack.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
      stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
      stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    return cell
  }
  public func tableViewSelectionDidChange(_ notification: Notification) {
    guard !refreshing else { return }
    let events = draft.value.sortedEvents
    selectedID = events.indices.contains(table.selectedRow) ? events[table.selectedRow].id : nil
    pendingFormError = nil
    calendarConverted = false
    invalidText = [:]
    populateEditor()
    updatePreview()
  }
  private func reloadTable() {
    refreshing = true
    table.reloadData()
    if let index = draft.value.sortedEvents.firstIndex(where: { $0.id == selectedID }) {
      table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    } else {
      table.deselectAll(nil)
    }
    refreshing = false
    addButton.isEnabled = draft.value.events.count < 5 && loadError == nil
    deleteButton.isEnabled = selectedID != nil && loadError == nil
  }
  public func controlTextDidChange(_ obj: Notification) { dateChanged() }
  @objc private func dateChanged() {
    guard !refreshing, let event else { return }
    calendarConverted = false
    var input = event.input
    invalidText = [:]
    for (key, field) in [
      ("year", yearField), ("hour", hourField), ("minute", minuteField), ("second", secondField),
    ] {
      if Int(field.stringValue) == nil { invalidText[key] = field.stringValue }
    }
    input.year = Int(yearField.stringValue) ?? -1
    input.hour = Int(hourField.stringValue) ?? -1
    input.minute = Int(minuteField.stringValue) ?? -1
    input.second = Int(secondField.stringValue) ?? -1
    let month = (monthPicker.selectedItem?.representedObject as? String ?? "0:false").split(
      separator: ":")
    input.month = Int(month.first ?? "0") ?? 0
    input.isLeapMonth = month.last == "true"
    input.day = dayPicker.selectedItem?.tag ?? 0
    input.timeZoneIdentifier = zonePicker.titleOfSelectedItem ?? ""
    input.repeatedTimeChoice =
      occurrencePicker.indexOfSelectedItem == 1
      ? .first : occurrencePicker.indexOfSelectedItem == 2 ? .second : nil
    do {
      try draft.update(id: event.id, title: titleField.stringValue, input: input)
      pendingFormError = nil
    } catch { pendingFormError = error }
    refreshDateOptions(input: input)
    reloadTable()
    updateStatus()
    updatePreview()
  }
  @objc private func calendarChanged() {
    guard !refreshing, let id = selectedID else { return }
    guard pendingFormError == nil else {
      populateEditor()
      return
    }
    do {
      try draft.switchCalendar(
        id: id, to: calendarPicker.indexOfSelectedItem == 0 ? .gregorian : .chinese)
      calendarConverted = true
      pendingFormError = nil
    } catch { pendingFormError = error }
    populateEditor()
    reloadTable()
    updatePreview()
  }
  @objc public func addEvent() {
    do {
      selectedID = try draft.add()
      calendarConverted = false
      pendingFormError = nil
      invalidText = [:]
      buildWindow()
    } catch {
      pendingFormError = error
      updateStatus()
    }
  }
  @objc public func deleteEvent() {
    if let id = selectedID { draft.delete(id: id) }
    selectedID = draft.value.sortedEvents.first?.id
    pendingFormError = nil
    calendarConverted = false
    invalidText = [:]
    buildWindow()
  }
  @objc private func languageChanged() {
    draft.setLanguage(LanguagePreference.allCases[languagePicker.indexOfSelectedItem])
    buildWindow()
  }
  @objc private func appearanceChanged() {
    var value = draft.value.appearance
    value.showTargetDate = showDate.state == .on
    value.showNextTarget = showNext.state == .on
    value.moveContent = move.state == .on
    draft.setAppearance(value)
    updatePreview()
  }
  private func updateStatus() {
    let error = loadError ?? pendingFormError ?? validationError()
    errorLabel.stringValue =
      error.map { l.error($0) }
      ?? (calendarConverted ? l.text(.converted) : nil)
      ?? (event.map { $0.resolvedTimestamp <= Date().timeIntervalSince1970 ? l.text(.past) : "" }
        ?? "")
    errorLabel.textColor =
      error != nil ? .systemOrange : calendarConverted ? .systemGreen : .secondaryLabelColor
    errorLabel.isHidden = errorLabel.stringValue.isEmpty
    equivalentLabel.isHidden = event?.input.calendar != .chinese
    saveButton.isEnabled = error == nil
    equivalentLabel.stringValue = event.map { l.text(.equivalent, l.gregorianDate($0)) } ?? ""
  }
  private func validationError() -> Error? {
    do {
      _ = try draft.validated()
      return nil
    } catch { return error }
  }
  private func updatePreview() {
    preview.configuration = draft.value
    preview.configurationError = loadError ?? pendingFormError ?? validationError()
    preview.preferredLanguages = SystemLanguages.preferred
    preview.update()
  }
  @objc private func repairPressed() {
    // Replacement is an explicit user action; opening damaged settings never overwrites data.
    loadError = nil
    pendingFormError = nil
    calendarConverted = false
    draft = DraftConfiguration(Configuration())
    selectedID = nil
    buildWindow()
  }
  @discardableResult public func saveDraft() throws -> Configuration {
    if let loadError { throw loadError }
    if let pendingFormError { throw pendingFormError }
    let saved = try store.save(draft.validated())
    onSave?(saved)
    finish()
    return saved
  }
  @objc private func savePressed() {
    window?.makeFirstResponder(nil)
    do { _ = try saveDraft() } catch {
      pendingFormError = error
      updateStatus()
    }
  }
  @objc public func cancelPressed() {
    onCancel?()
    finish()
  }
  private func finish() {
    previewTimer?.invalidate()
    previewTimer = nil
    if let window, let parent = window.sheetParent {
      parent.endSheet(window)
    } else {
      window?.close()
    }
  }
}
