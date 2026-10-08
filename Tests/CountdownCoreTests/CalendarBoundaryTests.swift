import XCTest

@testable import CountdownCore

final class CalendarBoundaryTests: XCTestCase {
  // HKO annual tables: T2033e.txt and T2034e.txt. The repeated eleventh month is a leap month.
  func test2033LeapEleventhMonthBoundaries() throws {
    let service = CalendarConversionService()
    let months = try service.lunarMonths(in: 2033)
    XCTAssertEqual(months.count, 13)
    XCTAssertEqual(months.filter(\.isLeap).map(\.number), [11])
    XCTAssertEqual(try XCTUnwrap(months.first { $0.number == 11 && !$0.isLeap }).days, 30)
    XCTAssertEqual(try XCTUnwrap(months.first { $0.number == 11 && $0.isLeap }).days, 29)
    for (month, day, leap, solarYear, solarMonth, solarDay) in [
      (11, 1, false, 2033, 11, 22), (11, 30, false, 2033, 12, 21),
      (11, 1, true, 2033, 12, 22), (11, 29, true, 2034, 1, 19),
      (12, 1, false, 2034, 1, 20),
    ] {
      try assertConversion(
        year: 2033, month: month, day: day, leap: leap,
        solarYear: solarYear, solarMonth: solarMonth, solarDay: solarDay)
    }
    XCTAssertThrowsError(
      try service.resolve(
        DateInput(year: 2033, month: 11, day: 30, calendar: .chinese, isLeapMonth: true))
    ) {
      XCTAssertEqual($0 as? CountdownError, .invalidDate)
    }
  }

  // https://www.hko.gov.hk/en/gts/time/calendar/text/files/T2057e.txt
  func test2057SeptemberBoundaryFollowsObservatoryTable() throws {
    for (month, day, solarMonth, solarDay) in [
      (8, 29, 9, 27), (9, 1, 9, 28), (9, 30, 10, 27), (10, 1, 10, 28),
    ] {
      try assertConversion(
        year: 2057, month: month, day: day,
        solarYear: 2057, solarMonth: solarMonth, solarDay: solarDay)
    }
    let service = CalendarConversionService()
    XCTAssertEqual(
      try service.days(in: DateInput(year: 2057, month: 8, day: 1, calendar: .chinese)), 29)
    XCTAssertEqual(
      try service.days(in: DateInput(year: 2057, month: 9, day: 1, calendar: .chinese)), 30)
  }

  // Fixed HKO facts from T1914e.txt, T1916e.txt, and T1920e.txt, independent of Foundation.
  func testHistoricalMonthStartsAndEndsFollowObservatoryTables() throws {
    for (year, month, day, solarMonth, solarDay) in [
      (1914, 10, 1, 11, 17), (1914, 10, 30, 12, 16),
      (1916, 1, 1, 2, 3), (1916, 1, 30, 3, 3),
      (1920, 10, 1, 11, 10), (1920, 10, 30, 12, 9),
    ] {
      try assertConversion(
        year: year, month: month, day: day,
        solarYear: year, solarMonth: solarMonth, solarDay: solarDay)
    }
  }

  private func assertConversion(
    year: Int, month: Int, day: Int, leap: Bool = false,
    solarYear: Int, solarMonth: Int, solarDay: Int,
    file: StaticString = #filePath, line: UInt = #line
  ) throws {
    let service = CalendarConversionService()
    let lunar = DateInput(
      year: year, month: month, day: day, calendar: .chinese, isLeapMonth: leap,
      hour: 12, timeZoneIdentifier: "UTC")
    let solar = DateInput(
      year: solarYear, month: solarMonth, day: solarDay, hour: 12, timeZoneIdentifier: "UTC")
    let expected = try service.resolve(solar)
    XCTAssertEqual(try service.resolve(lunar), expected, file: file, line: line)
    XCTAssertEqual(
      try service.input(for: expected, calendar: .chinese, timeZoneIdentifier: "UTC"),
      lunar, file: file, line: line)
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
