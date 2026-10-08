import Foundation

public enum UILanguage: String { case english, chinese }
public enum TextKey: String, CaseIterable {
  case settings, language, system, days, hours, minutes, seconds, gregorian, lunar, hoursShort,
    minutesShort, secondsShort
  case empty, completed, reached, countdown, event, events, next, add, delete, cancel, save
  case name, calendar, date, time, zone, equivalent, showDate, showNext, move, sorted, upcoming,
    expired
  case maximumEvents, invalidDate, lunarRange, nonexistentTime, repeatedTime, invalidTimeZone
  case longTitle, invalidConfiguration, unsupportedVersion, saveFailed, past, first, second,
    occurrence
  case lunarMonth, leapMonth, lunarDay, converted, options, preview, repair, eventPosition,
    additionalOne, additionalMany, targets, eventDetails, appearance, livePreview, settingsHint,
    searchZones
}

public struct Localization {
  private static let dateFormatters = DateFormatterCache()
  public let language: UILanguage
  public init(
    preference: LanguagePreference, preferredLanguages: [String] = Locale.preferredLanguages
  ) {
    switch preference {
    case .en: language = .english
    case .zhHans: language = .chinese
    case .system:
      let tag = preferredLanguages.first?.replacingOccurrences(of: "_", with: "-").lowercased()
      language = tag?.split(separator: "-").first == "zh" ? .chinese : .english
    }
  }
  public var locale: Locale {
    Locale(identifier: language == .chinese ? "zh_Hans_CN" : "en_US_POSIX")
  }
  // Explicit complete message templates; user text never goes through translation lookup.
  public static let catalog: [TextKey: (String, String)] = [
    .settings: ("Countdown Settings", "倒计时设置"), .language: ("Language", "语言"),
    .system: ("System", "跟随系统"), .days: ("DAYS", "天"), .hours: ("HOURS", "小时"),
    .minutes: ("MINUTES", "分"), .seconds: ("SECONDS", "秒"), .hoursShort: ("HRS", "小时"),
    .minutesShort: ("MIN", "分"), .secondsShort: ("SEC", "秒"), .gregorian: ("Gregorian", "公历"),
    .lunar: ("Chinese Lunar", "农历"),
    .empty: ("Add an event in screen saver options.", "请在屏幕保护程序选项中添加目标时间。"),
    .completed: ("All events completed.", "所有目标已完成。"), .reached: ("%@ has arrived.", "「%@」已到达。"),
    .countdown: ("Countdown to %@", "距离「%@」还有"), .event: ("Event %d", "目标 %d"),
    .events: ("Events %@ / %d", "第 %@ / %d 个目标"), .next: ("Next: %@", "下一目标：%@"),
    .add: ("Add", "添加"), .delete: ("Delete", "删除"), .cancel: ("Cancel", "取消"),
    .save: ("Save", "保存"),
    .name: ("Name", "名称"), .calendar: ("Calendar", "历法"), .date: ("Date", "日期"),
    .time: ("Time", "时间"),
    .zone: ("Time zone", "时区"), .equivalent: ("Gregorian equivalent: %@", "对应公历：%@"),
    .searchZones: ("Search zones", "搜索时区"),
    .showDate: ("Show date", "显示日期"), .showNext: ("Show next event", "显示下一目标"),
    .move: ("Move content slowly", "缓慢移动内容"),
    .sorted: ("Sorted chronologically · %d / 5", "按时间自动排序 · %d / 5"),
    .upcoming: ("Upcoming", "待到期"), .expired: ("Expired", "已到期"),
    .maximumEvents: ("You can configure at most five events.", "最多可设置 5 个目标。"),
    .invalidDate: ("Select a valid date and time.", "请选择有效的日期和时间。"),
    .lunarRange: ("Chinese lunar years must be between 1901 and 2100.", "农历年份须在 1901 至 2100 之间。"),
    .nonexistentTime: ("This local time does not exist. Choose another time.", "该本地时间不存在，请选择其他时间。"),
    .repeatedTime: (
      "This time occurs twice. Choose the first or second occurrence.", "该时间出现两次，请选择第一次或第二次。"
    ),
    .invalidTimeZone: ("Select a valid time zone.", "请选择有效的时区。"),
    .longTitle: ("Keep event names within 40 characters.", "目标名称不能超过 40 个字符。"),
    .invalidConfiguration: ("Configuration is damaged. Repair it in settings.", "配置已损坏，请在设置中修复。"),
    .unsupportedVersion: (
      "This configuration requires a different application version.", "此配置需要其他版本的程序。"
    ),
    .saveFailed: ("Could not save. Your edits have been retained.", "保存失败，已保留当前编辑内容。"),
    .past: ("This event has expired and will be skipped.", "该目标已到期，运行时将跳过。"),
    .first: ("First", "第一次"), .second: ("Second", "第二次"), .occurrence: ("Occurrence", "重复时刻"),
    .lunarMonth: ("Lunar Month %d", "%@"), .leapMonth: ("Leap Month %d", "闰%@"),
    .lunarDay: ("Day %d", "%@"),
    .targets: ("Targets", "目标列表"),
    .eventDetails: ("Date & time", "日期与时间"),
    .appearance: ("Display preferences", "显示偏好"),
    .livePreview: ("Live preview", "实时预览"),
    .settingsHint: (
      "Choose up to five moments. Countdown follows their chronological order.",
      "最多设置五个目标，倒计时将按时间顺序自动切换。"
    ),
    .converted: ("Calendar converted; the target instant is unchanged.", "已转换历法，目标时刻不变。"),
    .options: ("Options…", "选项…"), .preview: ("Countdown Preview", "倒计时预览"),
    .repair: ("Replace damaged configuration", "替换损坏的配置"),
    .eventPosition: ("Event %@ / %d", "第 %@ / %d 个目标"),
    .additionalOne: ("%@ and 1 other event", "%@，另 1 个目标"),
    .additionalMany: ("%@ and %d other events", "%@，另 %d 个目标"),
  ]
  public func text(_ key: TextKey, _ arguments: CVarArg...) -> String {
    let entry = Self.catalog[key]!
    return String(
      format: language == .chinese ? entry.1 : entry.0, locale: locale, arguments: arguments)
  }
  public func error(_ error: Error) -> String {
    let key: TextKey
    switch error as? CountdownError {
    case .maximumEvents: key = .maximumEvents
    case .invalidDate: key = .invalidDate
    case .lunarRange: key = .lunarRange
    case .nonexistentTime: key = .nonexistentTime
    case .repeatedTime: key = .repeatedTime
    case .invalidTimeZone: key = .invalidTimeZone
    case .longTitle: key = .longTitle
    case .unsupportedVersion: key = .unsupportedVersion
    case .saveFailed: key = .saveFailed
    default: key = .invalidConfiguration
    }
    return text(key)
  }
  public func title(_ event: CountdownEvent, position: Int) -> String {
    event.title.isEmpty ? text(.event, position) : event.title
  }
  public func month(_ number: Int, leap: Bool) -> String {
    guard (1...12).contains(number) else { return "" }
    if language == .english { return text(leap ? .leapMonth : .lunarMonth, number) }
    let names = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
    return text(leap ? .leapMonth : .lunarMonth, names[number - 1])
  }
  public func day(_ number: Int) -> String {
    guard (1...30).contains(number) else { return "" }
    if language == .english { return text(.lunarDay, number) }
    let digits = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
    if number <= 10 { return "初" + digits[number - 1] }
    if number < 20 { return "十" + digits[number - 11] }
    if number == 20 { return "二十" }
    if number < 30 { return "廿" + digits[number - 21] }
    return "三十"
  }
  public func gregorianDate(_ event: CountdownEvent) -> String {
    return Self.dateFormatters.string(
      from: Date(timeIntervalSince1970: event.resolvedTimestamp), locale: locale,
      zone: event.input.timeZoneIdentifier,
      format: language == .chinese ? "yyyy年MM月dd日 HH:mm:ss" : "MMM d, yyyy HH:mm:ss") + " · "
      + event.input.timeZoneIdentifier
  }
  public func date(_ event: CountdownEvent) -> String {
    let gregorian = gregorianDate(event)
    if event.input.calendar == .gregorian { return gregorian }
    let lunar =
      language == .chinese
      ? "农历 \(event.input.year)年\(month(event.input.month, leap: event.input.isLeapMonth))\(day(event.input.day))"
      : "Chinese Lunar \(event.input.year), \(month(event.input.month, leap: event.input.isLeapMonth)), \(day(event.input.day))"
    return lunar + "\n" + gregorian
  }
}
