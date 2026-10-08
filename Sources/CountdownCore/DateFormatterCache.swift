import Foundation

// The lock protects both the bounded cache and use of its mutable Foundation formatters.
final class DateFormatterCache: @unchecked Sendable {
  private struct Key: Hashable {
    let locale: String
    let zone: String
    let format: String
  }
  private let lock = NSLock()
  private var formatters: [Key: DateFormatter] = [:]

  func string(from date: Date, locale: Locale, zone: String, format: String) -> String {
    lock.lock()
    defer { lock.unlock() }
    let key = Key(locale: locale.identifier, zone: zone, format: format)
    let formatter: DateFormatter
    if let cached = formatters[key] {
      formatter = cached
    } else {
      if formatters.count >= 64 { formatters.removeAll() }
      formatter = DateFormatter()
      formatter.locale = locale
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.timeZone = TimeZone(identifier: zone)
      formatter.dateFormat = format
      formatters[key] = formatter
    }
    return formatter.string(from: date)
  }
}
