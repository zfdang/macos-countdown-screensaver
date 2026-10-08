import XCTest

@testable import CountdownCore

final class CalendarBoundaryTests: XCTestCase {
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
