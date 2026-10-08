import XCTest

@testable import CountdownCore

final class ReferenceCalendarTests: XCTestCase {
  struct LunarDate: Decodable {
    let year: Int
    let month: Int
    let day: Int
    let isLeapMonth: Bool
  }
  struct Conversion: Decodable {
    let solar: String
    let lunar: LunarDate
  }
  struct MonthDays: Decodable {
    let year: Int
    let month: Int
    let isLeapMonth: Bool
    let days: Int
  }
  struct Fixtures: Decodable {
    let conversions: [Conversion]
    let leapMonthByYear: [String: Int]
    let monthDays: [MonthDays]
  }
  func fixtures() throws -> Fixtures {
    let url = Bundle.module.url(
      forResource: "day-memory-lunar", withExtension: "json", subdirectory: "Fixtures")!
    return try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
  }
  func testDayMemoryConversionFixturesInBothDirections() throws {
    let service = CalendarConversionService()
    for fixture in try fixtures().conversions {
      let parts = fixture.solar.split(separator: "-").map { Int($0)! }
      let solarInput = DateInput(
        year: parts[0], month: parts[1], day: parts[2], hour: 12,
        timeZoneIdentifier: "Asia/Shanghai")
      let l = fixture.lunar
      let lunarInput = DateInput(
        year: l.year, month: l.month, day: l.day, calendar: .chinese, isLeapMonth: l.isLeapMonth,
        hour: 12, timeZoneIdentifier: "Asia/Shanghai")
      XCTAssertEqual(
        try service.resolve(lunarInput), try service.resolve(solarInput), fixture.solar)
      XCTAssertEqual(
        try service.input(
          for: service.resolve(solarInput), calendar: .chinese, timeZoneIdentifier: "Asia/Shanghai"),
        lunarInput)
    }
  }
  func testDayMemoryLeapMonthsIncluding2033() throws {
    let service = CalendarConversionService()
    for (year, leap) in try fixtures().leapMonthByYear {
      XCTAssertEqual(
        try service.lunarMonths(in: Int(year)!).first(where: \.isLeap)?.number ?? 0, leap, year)
    }
  }
  func testDayMemoryMonthLengths() throws {
    let service = CalendarConversionService()
    for month in try fixtures().monthDays {
      let input = DateInput(
        year: month.year, month: month.month, day: 1, calendar: .chinese,
        isLeapMonth: month.isLeapMonth)
      XCTAssertEqual(try service.days(in: input), month.days)
    }
  }
  func testKnownFoundationDayZeroBoundariesUseCivilTable() throws {
    let service = CalendarConversionService()
    for (year, month, day, solarMonth, solarDay) in [(2057, 9, 1, 9, 28), (2097, 7, 1, 8, 7)] {
      let lunar = DateInput(
        year: year, month: month, day: day, calendar: .chinese, hour: 12, timeZoneIdentifier: "UTC")
      let solar = DateInput(
        year: year, month: solarMonth, day: solarDay, hour: 12, timeZoneIdentifier: "UTC")
      XCTAssertEqual(try service.resolve(lunar), try service.resolve(solar))
    }
  }
  func testInvalidOnceDateNeverUsesRecurrenceFallback() {
    let service = CalendarConversionService()
    for input in [
      DateInput(year: 2026, month: 6, day: 15, calendar: .chinese, isLeapMonth: true),
      DateInput(year: 2026, month: 8, day: 30, calendar: .chinese),
    ] {
      XCTAssertThrowsError(try service.resolve(input)) {
        XCTAssertEqual($0 as? CountdownError, .invalidDate)
      }
    }
  }
}
