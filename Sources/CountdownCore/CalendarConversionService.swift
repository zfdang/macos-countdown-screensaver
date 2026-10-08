import Foundation

public struct LunarMonth: Equatable {
  public let number: Int
  public let isLeap: Bool
  public let start: Date
  public let days: Int
}

public final class CalendarConversionService {
  public static let lunarYears = 1901...2100
  private let lock = NSLock()
  private var cache: [Int: [LunarMonth]] = [:]
  private var mappingCalendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(secondsFromGMT: 0)!
    return value
  }
  public init() {}

  public func lunarMonths(in year: Int) throws -> [LunarMonth] {
    guard Self.lunarYears.contains(year) else { throw CountdownError.lunarRange }
    lock.lock()
    let existing = cache[year]
    lock.unlock()
    if let existing { return existing }
    let record = LunarTable.years[year - 1901]
    let gregorian = mappingCalendar
    var cursor = gregorian.date(
      from: DateComponents(year: year, month: record.0, day: record.1, hour: 12))!
    let lengths = record.3.split(separator: ",").map { Int($0)! }
    var result: [LunarMonth] = []
    var month = 1
    var previousWasLeap = false
    for length in lengths {
      let isLeap =
        record.2 != 0 && result.last?.number == record.2 && !previousWasLeap
        && month == record.2 + 1
      let number = isLeap ? record.2 : month
      result.append(LunarMonth(number: number, isLeap: isLeap, start: cursor, days: length))
      cursor = gregorian.date(byAdding: .day, value: length, to: cursor)!
      if !isLeap { month += 1 }
      previousWasLeap = isLeap
    }
    lock.lock()
    cache[year] = result
    lock.unlock()
    return result
  }

  public func days(in input: DateInput) throws -> Int {
    if input.calendar == .chinese {
      guard
        let month = try lunarMonths(in: input.year).first(where: {
          $0.number == input.month && $0.isLeap == input.isLeapMonth
        })
      else { throw CountdownError.invalidDate }
      return month.days
    }
    guard (1901...9999).contains(input.year), (1...12).contains(input.month), !input.isLeapMonth
    else {
      throw CountdownError.invalidDate
    }
    let g = mappingCalendar
    let date = g.date(from: DateComponents(year: input.year, month: input.month, day: 1, hour: 12))!
    return g.range(of: .day, in: .month, for: date)!.count
  }

  public func gregorianComponents(for input: DateInput) throws -> DateComponents {
    guard (1...31).contains(input.day), (0...23).contains(input.hour),
      (0...59).contains(input.minute), (0...59).contains(input.second),
      input.day <= (try days(in: input))
    else { throw CountdownError.invalidDate }
    var result: DateComponents
    if input.calendar == .chinese {
      let month = try lunarMonths(in: input.year).first {
        $0.number == input.month && $0.isLeap == input.isLeapMonth
      }!
      let date = mappingCalendar.date(byAdding: .day, value: input.day - 1, to: month.start)!
      result = mappingCalendar.dateComponents([.year, .month, .day], from: date)
    } else {
      result = DateComponents(year: input.year, month: input.month, day: input.day)
    }
    result.hour = input.hour
    result.minute = input.minute
    result.second = input.second
    return result
  }

  public func candidates(for input: DateInput) throws -> [Date] {
    guard let zone = TimeZone(identifier: input.timeZoneIdentifier) else {
      throw CountdownError.invalidTimeZone
    }
    let components = try gregorianComponents(for: input)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(secondsFromGMT: 0)!
    guard let nominal = utc.date(from: components) else { throw CountdownError.invalidDate }
    // Enumerate possible UTC offsets around this civil date. Unlike nextDate's repeated-time
    // policies, this also handles half-hour rollbacks and entire skipped civil days.
    let offsets = Set(
      stride(from: -48, through: 48, by: 6).map {
        zone.secondsFromGMT(for: nominal.addingTimeInterval(Double($0 * 3600)))
      })
    let dates = offsets.compactMap { offset -> Date? in
      let candidate = nominal.addingTimeInterval(-Double(offset))
      guard
        calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: candidate)
          == components
      else { return nil }
      return candidate
    }
    return Array(Set(dates)).sorted()
  }

  public func resolve(_ input: DateInput) throws -> Date {
    let options = try candidates(for: input)
    guard let first = options.first else { throw CountdownError.nonexistentTime }
    if options.count > 1 {
      guard let choice = input.repeatedTimeChoice else { throw CountdownError.repeatedTime }
      return choice == .first ? first : options.last!
    }
    return first
  }

  public func input(for date: Date, calendar type: InputCalendar, timeZoneIdentifier: String) throws
    -> DateInput
  {
    guard let zone = TimeZone(identifier: timeZoneIdentifier) else {
      throw CountdownError.invalidTimeZone
    }
    var local = Calendar(identifier: .gregorian)
    local.timeZone = zone
    let c = local.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    var input = DateInput(
      year: c.year!, month: c.month!, day: c.day!, calendar: type,
      hour: c.hour!, minute: c.minute!, second: c.second!, timeZoneIdentifier: timeZoneIdentifier)
    if type == .chinese {
      let mappingDate = mappingCalendar.date(
        from: DateComponents(year: c.year, month: c.month, day: c.day, hour: 12))!
      var year = c.year!
      if year == 2101 {
        year = 2100
      } else if let first = try? lunarMonths(in: year).first, mappingDate < first.start {
        year -= 1
      }
      guard Self.lunarYears.contains(year) else { throw CountdownError.lunarRange }
      let months = try lunarMonths(in: year)
      guard let month = months.last(where: { $0.start <= mappingDate }),
        let end = mappingCalendar.date(byAdding: .day, value: month.days, to: month.start),
        mappingDate < end
      else {
        throw CountdownError.lunarRange
      }
      input.year = year
      input.month = month.number
      input.day =
        mappingCalendar.dateComponents([.day], from: month.start, to: mappingDate).day! + 1
      input.isLeapMonth = month.isLeap
    }
    let options = try candidates(for: input)
    if options.count > 1 {
      input.repeatedTimeChoice = abs(options[0].timeIntervalSince(date)) < 1 ? .first : .second
    }
    guard abs(try resolve(input).timeIntervalSince(date)) < 1 else {
      throw CountdownError.invalidDate
    }
    return input
  }
}
