import Foundation

public enum InputCalendar: String, Codable, CaseIterable { case gregorian, chinese }
public enum LanguagePreference: String, Codable, CaseIterable { case system, en, zhHans }
public enum RepeatedTimeChoice: String, Codable { case first, second }

public enum CountdownError: Error, Equatable {
  case maximumEvents, invalidDate, lunarRange, nonexistentTime, repeatedTime
  case invalidTimeZone, longTitle, invalidConfiguration, unsupportedVersion, saveFailed
}

public struct DateInput: Codable, Equatable {
  public var calendar: InputCalendar = .gregorian
  public var year: Int
  public var month: Int
  public var day: Int
  public var isLeapMonth: Bool = false
  public var hour: Int = 0
  public var minute: Int = 0
  public var second: Int = 0
  public var timeZoneIdentifier: String = TimeZone.current.identifier
  public var repeatedTimeChoice: RepeatedTimeChoice? = nil
  public init(
    year: Int, month: Int, day: Int, calendar: InputCalendar = .gregorian,
    isLeapMonth: Bool = false, hour: Int = 0, minute: Int = 0, second: Int = 0,
    timeZoneIdentifier: String = TimeZone.current.identifier,
    repeatedTimeChoice: RepeatedTimeChoice? = nil
  ) {
    self.year = year
    self.month = month
    self.day = day
    self.calendar = calendar
    self.isLeapMonth = isLeapMonth
    self.hour = hour
    self.minute = minute
    self.second = second
    self.timeZoneIdentifier = timeZoneIdentifier
    self.repeatedTimeChoice = repeatedTimeChoice
  }
}

public struct CountdownEvent: Codable, Equatable, Identifiable {
  public var id: UUID
  public var title: String
  public var createdOrder: Int
  public var input: DateInput
  public var resolvedTimestamp: TimeInterval
  public init(
    id: UUID = UUID(), title: String = "", createdOrder: Int, input: DateInput,
    resolvedTimestamp: TimeInterval
  ) {
    self.id = id
    self.title = title
    self.createdOrder = createdOrder
    self.input = input
    self.resolvedTimestamp = resolvedTimestamp
  }
}

public struct AppearanceSettings: Codable, Equatable {
  public var showTargetDate = true
  public var showNextTarget = false
  public var moveContent = true
  public init() {}
}

public struct Configuration: Codable, Equatable {
  public static let currentVersion = 1
  // 1901-01-01 00:00:00 through 9999-12-31 23:59:59 UTC; bounds for saved absolute instants.
  private static let supportedTimestamps: ClosedRange<TimeInterval> =
    -2_177_452_800...253_402_300_799
  public var schemaVersion = currentVersion
  public var revision = UUID()
  public var languagePreference: LanguagePreference = .system
  public var events: [CountdownEvent] = []
  public var appearance = AppearanceSettings()
  public init() {}
  enum CodingKeys: String, CodingKey {
    case schemaVersion, revision, languagePreference, events, appearance
  }
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
    guard schemaVersion == Self.currentVersion else { throw CountdownError.unsupportedVersion }
    revision = try values.decode(UUID.self, forKey: .revision)
    languagePreference =
      try values.decodeIfPresent(LanguagePreference.self, forKey: .languagePreference) ?? .system
    events = try values.decode([CountdownEvent].self, forKey: .events)
    appearance = try values.decode(AppearanceSettings.self, forKey: .appearance)
  }
  public var sortedEvents: [CountdownEvent] {
    events.sorted {
      if $0.resolvedTimestamp != $1.resolvedTimestamp {
        return $0.resolvedTimestamp < $1.resolvedTimestamp
      }
      if $0.createdOrder != $1.createdOrder { return $0.createdOrder < $1.createdOrder }
      return $0.id.uuidString < $1.id.uuidString
    }
  }
  public func validated(using service: CalendarConversionService = CalendarConversionService())
    throws
  {
    guard schemaVersion == Self.currentVersion else { throw CountdownError.unsupportedVersion }
    guard events.count <= 5 else { throw CountdownError.maximumEvents }
    guard Set(events.map(\.id)).count == events.count,
      Set(events.map(\.createdOrder)).count == events.count
    else { throw CountdownError.invalidConfiguration }
    for event in events {
      guard event.title.count <= 40 else { throw CountdownError.longTitle }
      guard event.createdOrder >= 0, event.createdOrder < Int.max,
        event.resolvedTimestamp.isFinite,
        Self.supportedTimestamps.contains(event.resolvedTimestamp)
      else {
        throw CountdownError.invalidConfiguration
      }
      // Check input validity but retain the saved absolute instant on ordinary loading.
      _ = try service.resolve(event.input)
    }
  }
}
