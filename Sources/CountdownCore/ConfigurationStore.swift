import Foundation

public protocol ConfigurationBackend {
  func read() throws -> Data?
  func write(_ data: Data) throws
}

public final class DefaultsBackend: ConfigurationBackend {
  public static let dataKey = "CountdownConfiguration"
  private let defaults: UserDefaults
  public init(defaults: UserDefaults) { self.defaults = defaults }
  public func read() throws -> Data? {
    defaults.synchronize()
    guard let object = defaults.object(forKey: Self.dataKey) else { return nil }
    guard let data = object as? Data else { throw CountdownError.invalidConfiguration }
    return data
  }
  public func write(_ data: Data) throws {
    defaults.set(data, forKey: Self.dataKey)
    guard defaults.synchronize(), defaults.data(forKey: Self.dataKey) == data else {
      throw CountdownError.saveFailed
    }
  }
}

public final class ConfigurationStore {
  private let backend: ConfigurationBackend
  private let service: CalendarConversionService
  public init(
    backend: ConfigurationBackend, service: CalendarConversionService = CalendarConversionService()
  ) {
    self.backend = backend
    self.service = service
  }
  public func load() throws -> Configuration {
    guard let data = try backend.read() else { return Configuration() }
    do {
      let value = try JSONDecoder().decode(Configuration.self, from: data)
      try value.validated(using: service)
      return value
    } catch let error as CountdownError { throw error } catch {
      throw CountdownError.invalidConfiguration
    }
  }
  @discardableResult public func save(_ value: Configuration) throws -> Configuration {
    try value.validated(using: service)
    var result = value
    result.revision = UUID()
    let data = try JSONEncoder().encode(result)
    do { try backend.write(data) } catch { throw CountdownError.saveFailed }
    return result
  }
}

public final class DraftConfiguration {
  public private(set) var value: Configuration
  public let service: CalendarConversionService
  public init(
    _ configuration: Configuration, service: CalendarConversionService = CalendarConversionService()
  ) {
    value = configuration
    self.service = service
  }
  public func setLanguage(_ preference: LanguagePreference) {
    value.languagePreference = preference
  }
  public func setAppearance(_ appearance: AppearanceSettings) { value.appearance = appearance }
  @discardableResult public func add(now: Date = Date(), zone: String = TimeZone.current.identifier)
    throws -> UUID
  {
    guard value.events.count < 5 else { throw CountdownError.maximumEvents }
    guard let timeZone = TimeZone(identifier: zone) else { throw CountdownError.invalidTimeZone }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
    var input = try service.input(for: tomorrow, calendar: .gregorian, timeZoneIdentifier: zone)
    input.second = 0
    let previousOrder = value.events.map(\.createdOrder).max() ?? -1
    guard previousOrder < Int.max - 1 else { throw CountdownError.invalidConfiguration }
    let order = previousOrder + 1
    let event = CountdownEvent(
      createdOrder: order, input: input,
      resolvedTimestamp: try service.resolve(input).timeIntervalSince1970)
    value.events.append(event)
    return event.id
  }
  public func delete(id: UUID) { value.events.removeAll { $0.id == id } }
  public func update(id: UUID, title: String, input: DateInput) throws {
    guard let index = value.events.firstIndex(where: { $0.id == id }) else {
      throw CountdownError.invalidConfiguration
    }
    // Retain invalid input as a draft so Save cannot silently use an older valid value.
    value.events[index].title = title
    value.events[index].input = input
    guard title.count <= 40 else { throw CountdownError.longTitle }
    value.events[index].resolvedTimestamp = try service.resolve(input).timeIntervalSince1970
  }
  public func switchCalendar(id: UUID, to calendar: InputCalendar) throws {
    guard let event = value.events.first(where: { $0.id == id }) else {
      throw CountdownError.invalidConfiguration
    }
    let instant = try service.resolve(event.input)
    let input = try service.input(
      for: instant, calendar: calendar, timeZoneIdentifier: event.input.timeZoneIdentifier)
    try update(id: id, title: event.title, input: input)
  }
  public func validated() throws -> Configuration {
    try value.validated(using: service)
    return value
  }
}
