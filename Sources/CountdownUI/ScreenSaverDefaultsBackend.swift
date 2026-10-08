import Foundation
import ScreenSaver

#if SWIFT_PACKAGE
  import CountdownCore
#endif

/// ScreenSaverDefaults maintains its own dictionary, unlike ordinary UserDefaults.
/// Synchronize at configuration reload/save boundaries to exchange values with other hosts.
public final class ScreenSaverDefaultsBackend: ConfigurationBackend {
  private let defaults: ScreenSaverDefaults
  private let backend: DefaultsBackend
  public init(defaults: ScreenSaverDefaults) {
    self.defaults = defaults
    backend = DefaultsBackend(defaults: defaults)
  }
  public func read() throws -> Data? {
    guard defaults.synchronize() else { throw CountdownError.invalidConfiguration }
    return try backend.read()
  }
  public func write(_ data: Data) throws {
    try backend.write(data)
    // Flush before notifying other instances; local readback alone only verifies the cache.
    guard defaults.synchronize(), try backend.read() == data else {
      throw CountdownError.saveFailed
    }
  }
}
