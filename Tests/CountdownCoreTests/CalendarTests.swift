import XCTest

@testable import CountdownCore

final class CalendarTests: XCTestCase {
  let service = CalendarConversionService()
  func assertError(
    _ error: CountdownError, _ action: () throws -> Void, file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(try action(), file: file, line: line) {
      XCTAssertEqual($0 as? CountdownError, error, file: file, line: line)
    }
  }
  func testGregorianRoundTripAndLeapDay() throws {
    for input in [
      DateInput(
        year: 2024, month: 2, day: 29, hour: 23, minute: 59, second: 59, timeZoneIdentifier: "UTC"),
      DateInput(year: 2026, month: 12, day: 31, timeZoneIdentifier: "Asia/Shanghai"),
      DateInput(year: 9999, month: 12, day: 31, timeZoneIdentifier: "UTC"),
    ] {
      let date = try service.resolve(input)
      XCTAssertEqual(
        try service.input(
          for: date, calendar: .gregorian, timeZoneIdentifier: input.timeZoneIdentifier), input)
    }
  }
  func testRejectInvalidInputsWithoutNormalization() {
    let inputs = [
      DateInput(year: 2023, month: 2, day: 29), DateInput(year: 2026, month: 4, day: 31),
      DateInput(year: 2026, month: 0, day: 1), DateInput(year: 2026, month: 1, day: 0),
      DateInput(year: 2026, month: 1, day: 1, hour: 24),
      DateInput(year: 2026, month: 1, day: 1, minute: 60),
      DateInput(year: 2026, month: 1, day: 1, second: -1),
      DateInput(year: 2026, month: 1, day: 1, isLeapMonth: true),
    ]
    for input in inputs { assertError(.invalidDate) { _ = try service.resolve(input) } }
    assertError(.invalidTimeZone) {
      _ = try service.resolve(
        DateInput(year: 2026, month: 1, day: 1, timeZoneIdentifier: "bad/zone"))
    }
  }
  func testDSTGapAndRepeatedTime() throws {
    let gap = DateInput(
      year: 2026, month: 3, day: 8, hour: 2, minute: 30, timeZoneIdentifier: "America/New_York")
    assertError(.nonexistentTime) { _ = try service.resolve(gap) }
    var repeated = DateInput(
      year: 2026, month: 11, day: 1, hour: 1, minute: 30, timeZoneIdentifier: "America/New_York")
    assertError(.repeatedTime) { _ = try service.resolve(repeated) }
    let candidates = try service.candidates(for: repeated)
    XCTAssertEqual(candidates.count, 2)
    repeated.repeatedTimeChoice = .first
    let first = try service.resolve(repeated)
    repeated.repeatedTimeChoice = .second
    let second = try service.resolve(repeated)
    XCTAssertEqual(second.timeIntervalSince(first), 3600)
    XCTAssertEqual(
      try service.input(
        for: second, calendar: .gregorian, timeZoneIdentifier: repeated.timeZoneIdentifier),
      repeated)
  }
  func testThirtyMinuteDSTAndSkippedCivilDay() throws {
    let gap = DateInput(
      year: 2026, month: 10, day: 4, hour: 2, minute: 15, timeZoneIdentifier: "Australia/Lord_Howe")
    assertError(.nonexistentTime) { _ = try service.resolve(gap) }
    let repeated = DateInput(
      year: 2026, month: 4, day: 5, hour: 1, minute: 45, timeZoneIdentifier: "Australia/Lord_Howe")
    let dates = try service.candidates(for: repeated)
    XCTAssertEqual(dates.count, 2)
    if dates.count == 2 { XCTAssertEqual(dates[1].timeIntervalSince(dates[0]), 1800) }
    let skipped = DateInput(
      year: 2011, month: 12, day: 30, hour: 12, timeZoneIdentifier: "Pacific/Apia")
    assertError(.nonexistentTime) { _ = try service.resolve(skipped) }
  }
  func testTimeZoneChangesMoveWallTimeButNotSavedInstant() throws {
    let input = DateInput(
      year: 2027, month: 1, day: 1, hour: 9, timeZoneIdentifier: "Asia/Shanghai")
    var utc = input
    utc.timeZoneIdentifier = "UTC"
    XCTAssertEqual(try service.resolve(utc).timeIntervalSince(service.resolve(input)), 8 * 3600)
  }
  // New Year and leap-month fixtures are cross-checked against Hong Kong Observatory conversion tables.
  func testAuthoritativeLunarFixtures() throws {
    let fixtures: [(Int, Int, Int, Bool, Int, Int, Int)] = [
      (1901, 1, 1, false, 1901, 2, 19), (2023, 1, 1, false, 2023, 1, 22),
      (2023, 2, 1, true, 2023, 3, 22), (2024, 1, 1, false, 2024, 2, 10),
      (2025, 6, 1, true, 2025, 7, 25), (2026, 1, 1, false, 2026, 2, 17),
      (2027, 1, 1, false, 2027, 2, 6), (2100, 1, 1, false, 2100, 2, 9),
    ]
    for (year, month, day, leap, gy, gm, gd) in fixtures {
      let input = DateInput(
        year: year, month: month, day: day, calendar: .chinese, isLeapMonth: leap, hour: 12,
        timeZoneIdentifier: "Asia/Shanghai")
      let expected = try service.resolve(
        DateInput(year: gy, month: gm, day: gd, hour: 12, timeZoneIdentifier: "Asia/Shanghai"))
      XCTAssertEqual(try service.resolve(input), expected)
      XCTAssertEqual(
        try service.input(for: expected, calendar: .chinese, timeZoneIdentifier: "Asia/Shanghai"),
        input)
    }
  }
  func testEverySupportedLunarDateRoundTrips() throws {
    var monthCount = 0
    var leapCount = 0
    for year in CalendarConversionService.lunarYears {
      let months = try service.lunarMonths(in: year)
      XCTAssertTrue((12...13).contains(months.count))
      XCTAssertEqual(months.first?.number, 1)
      XCTAssertEqual(months.first?.isLeap, false)
      XCTAssertEqual(months.last?.number, 12)
      for month in months {
        monthCount += 1
        if month.isLeap { leapCount += 1 }
        XCTAssertTrue((29...30).contains(month.days))
        for day in 1...month.days {
          let input = DateInput(
            year: year, month: month.number, day: day, calendar: .chinese,
            isLeapMonth: month.isLeap, hour: 12, timeZoneIdentifier: "Asia/Shanghai")
          let date: Date
          do { date = try service.resolve(input) } catch {
            XCTFail("Resolve \(year)-\(month.number)-\(day) leap=\(month.isLeap): \(error)")
            continue
          }
          XCTAssertEqual(
            try service.input(for: date, calendar: .chinese, timeZoneIdentifier: "Asia/Shanghai"),
            input)
        }
        assertError(.invalidDate) {
          _ = try service.resolve(
            DateInput(
              year: year, month: month.number, day: month.days + 1, calendar: .chinese,
              isLeapMonth: month.isLeap))
        }
      }
    }
    XCTAssertGreaterThan(monthCount, 2400)
    XCTAssertGreaterThan(leapCount, 60)
  }
  func testLunarRangeAndMissingLeapMonth() {
    for year in [1900, 2101] { assertError(.lunarRange) { _ = try service.lunarMonths(in: year) } }
    assertError(.invalidDate) {
      _ = try service.resolve(
        DateInput(year: 2024, month: 2, day: 1, calendar: .chinese, isLeapMonth: true))
    }
  }
  func testLunarMappingIsIndependentOfEventZoneAndNewYearBoundary() throws {
    let lunar = DateInput(
      year: 2025, month: 12, day: 29, calendar: .chinese, hour: 9,
      timeZoneIdentifier: "America/Los_Angeles")
    let date = try service.resolve(lunar)
    XCTAssertEqual(
      try service.input(
        for: date, calendar: .chinese, timeZoneIdentifier: lunar.timeZoneIdentifier), lunar)
    XCTAssertEqual(
      try service.input(
        for: date, calendar: .gregorian, timeZoneIdentifier: lunar.timeZoneIdentifier
      ).year, 2026)
  }
}
