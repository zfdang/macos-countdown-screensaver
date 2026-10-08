import XCTest

@testable import CountdownCore

final class LocalizationTests: XCTestCase {
  func testSharedFormattersKeepLanguageAndZoneIndependent() {
    let event = CountdownEvent(
      createdOrder: 0, input: DateInput(year: 2027, month: 1, day: 1, timeZoneIdentifier: "UTC"),
      resolvedTimestamp: 1_798_761_600)
    for _ in 0..<20 {
      var shanghai = event
      shanghai.input.timeZoneIdentifier = "Asia/Shanghai"
      let en = Localization(preference: .en)
      let zh = Localization(preference: .zhHans)
      XCTAssertEqual(en.gregorianDate(event), "Jan 1, 2027 00:00:00 · UTC")
      XCTAssertEqual(zh.gregorianDate(shanghai), "2027年01月01日 08:00:00 · Asia/Shanghai")
      XCTAssertEqual(zh.gregorianDate(event), "2027年01月01日 00:00:00 · UTC")
      XCTAssertEqual(en.gregorianDate(shanghai), "Jan 1, 2027 08:00:00 · Asia/Shanghai")
    }
  }
  func testFormatterCacheSupportsConcurrentDistinctFormatsAndZones() {
    let cache = DateFormatterCache()
    DispatchQueue.concurrentPerform(iterations: 100) { index in
      let utc = index.isMultiple(of: 2)
      let text = cache.string(
        from: Date(timeIntervalSince1970: 1_798_761_600), locale: Locale(identifier: "en_US_POSIX"),
        zone: utc ? "UTC" : "Asia/Shanghai",
        format: utc ? "yyyy-MM-dd HH:mm:ss" : "HH:mm yyyy-MM-dd")
      XCTAssertEqual(text, utc ? "2027-01-01 00:00:00" : "08:00 2027-01-01")
    }
  }
  func testSystemChineseVariantsAndOtherLanguages() {
    for tag in ["zh", "zh-Hans", "zh-Hant", "zh-CN", "zh-TW", "zh-HK", "ZH_hant_TW"] {
      XCTAssertEqual(
        Localization(preference: .system, preferredLanguages: [tag]).language, .chinese)
    }
    for languages in [[], [""], ["en", "zh"], ["fr"], ["ja"], ["ko"], ["de"], ["unknown"]] {
      XCTAssertEqual(
        Localization(preference: .system, preferredLanguages: languages).language, .english)
    }
  }
  func testManualOverrides() {
    XCTAssertEqual(Localization(preference: .en, preferredLanguages: ["zh"]).language, .english)
    XCTAssertEqual(Localization(preference: .zhHans, preferredLanguages: ["en"]).language, .chinese)
  }
  func testEveryTranslationKeyAndErrorHasBothLanguages() {
    XCTAssertEqual(Set(Localization.catalog.keys), Set(TextKey.allCases))
    for pair in Localization.catalog.values {
      XCTAssertFalse(pair.0.isEmpty)
      XCTAssertFalse(pair.1.isEmpty)
    }
    let errors: [CountdownError] = [
      .maximumEvents, .invalidDate, .lunarRange, .nonexistentTime, .repeatedTime, .invalidTimeZone,
      .longTitle, .invalidConfiguration, .unsupportedVersion, .saveFailed,
    ]
    for error in errors {
      XCTAssertNotEqual(
        Localization(preference: .en).error(error), Localization(preference: .zhHans).error(error))
    }
  }
  func testDefaultTitlesLocalizeButUserTitlesRemainVerbatim() {
    var event = CountdownEvent(
      createdOrder: 0, input: DateInput(year: 2026, month: 1, day: 1), resolvedTimestamp: 0)
    XCTAssertEqual(Localization(preference: .en).title(event, position: 2), "Event 2")
    XCTAssertEqual(Localization(preference: .zhHans).title(event, position: 2), "目标 2")
    event.title = "Custom 中文"
    XCTAssertEqual(Localization(preference: .en).title(event, position: 2), event.title)
    XCTAssertEqual(Localization(preference: .zhHans).title(event, position: 2), event.title)
  }
  func testLunarLabels() {
    let zh = Localization(preference: .zhHans)
    let en = Localization(preference: .en)
    XCTAssertEqual(zh.month(1, leap: false), "正月")
    XCTAssertEqual(zh.month(6, leap: true), "闰六月")
    XCTAssertEqual(en.month(6, leap: true), "Leap Month 6")
    XCTAssertEqual(zh.month(11, leap: false), "冬月")
    XCTAssertEqual(zh.month(12, leap: false), "腊月")
    XCTAssertEqual(
      [1, 10, 11, 19, 20, 21, 29, 30].map(zh.day), ["初一", "初十", "十一", "十九", "二十", "廿一", "廿九", "三十"])
    XCTAssertEqual(en.day(30), "Day 30")
    XCTAssertEqual(zh.day(31), "")
    XCTAssertEqual(zh.month(0, leap: false), "")
  }
  func testGregorianAndLunarDateFormattingUsesEventZoneAndTwentyFourHourTime() throws {
    let service = CalendarConversionService()
    let input = DateInput(
      year: 2027, month: 1, day: 1, hour: 19, minute: 42, second: 5,
      timeZoneIdentifier: "Asia/Shanghai")
    var event = CountdownEvent(
      createdOrder: 0, input: input,
      resolvedTimestamp: try service.resolve(input).timeIntervalSince1970)
    for preference in [LanguagePreference.en, .zhHans] {
      let text = Localization(preference: preference).date(event)
      XCTAssertTrue(text.contains("19:42:05"))
      XCTAssertTrue(text.contains("Asia/Shanghai"))
      XCTAssertFalse(text.contains("PM"))
    }
    event.input = try service.input(
      for: Date(timeIntervalSince1970: event.resolvedTimestamp), calendar: .chinese,
      timeZoneIdentifier: "Asia/Shanghai")
    XCTAssertTrue(Localization(preference: .en).date(event).contains("Chinese Lunar"))
    XCTAssertTrue(Localization(preference: .zhHans).date(event).contains("农历"))
  }
  func testGroupPositionAndCompleteMessageFormatting() {
    var c = Configuration()
    c.events = (0..<2).map {
      CountdownEvent(
        createdOrder: $0, input: DateInput(year: 2026, month: 1, day: 1), resolvedTimestamp: 100)
    }
    let group = CountdownEngine.groups(in: c)[0]
    XCTAssertEqual(group.position(using: Localization(preference: .en), total: 2), "Events 1–2 / 2")
    XCTAssertEqual(
      group.position(using: Localization(preference: .zhHans), total: 2), "第 1–2 / 2 个目标")
    XCTAssertEqual(group.title(using: Localization(preference: .zhHans)), "目标 1 / 目标 2")
  }
}
