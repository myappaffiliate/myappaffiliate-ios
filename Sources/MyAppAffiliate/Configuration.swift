import Foundation

/// How the SDK finds its API key and host without either being typed into your
/// source code.
///
/// A hard-coded host in application code is the thing integrations get wrong:
/// it gets copied between environments, pasted with a trailing path, or left
/// pointing at staging in a shipped build. So the production host is compiled
/// in, and the two escape hatches are places that are already part of a build
/// configuration rather than a source file.
public enum MyAppAffiliateConfiguration {
  /// Where the SDK talks to when nothing overrides it. Mirrors `SITE.api` in
  /// @maa/brand.
  public static let defaultAPIBaseURL = URL(string: "https://api.myappaffiliate.com")!

  /// Info.plist key holding your SDK key, so `MyAppAffiliate.start()` can take
  /// no arguments at all. Set it from a build setting to vary it per scheme.
  public static let apiKeyInfoPlistKey = "MyAppAffiliateAPIKey"

  /// Info.plist key holding an API host override — for a staging API or a
  /// self-hosted deployment. Omit it in production.
  public static let apiBaseURLInfoPlistKey = "MyAppAffiliateAPIBaseURL"

  /// Resolves the key: explicit argument first, then Info.plist. Returns nil
  /// when neither exists, which is the one misconfiguration worth surfacing.
  static func resolveAPIKey(_ explicit: String?, bundle: Bundle = .main) -> String? {
    if let explicit = trimmed(explicit) { return explicit }
    return trimmed(bundle.object(forInfoDictionaryKey: apiKeyInfoPlistKey) as? String)
  }

  /// Resolves the host: explicit argument, then Info.plist, then the compiled-in
  /// production default. A blank or unparseable value falls through rather than
  /// producing a URL that silently fails every request.
  static func resolveAPIBaseURL(_ explicit: URL?, bundle: Bundle = .main) -> URL {
    if let explicit { return explicit }
    if let raw = trimmed(bundle.object(forInfoDictionaryKey: apiBaseURLInfoPlistKey) as? String),
      let url = URL(string: raw)
    {
      return url
    }
    return defaultAPIBaseURL
  }

  private static func trimmed(_ value: String?) -> String? {
    guard let value else { return nil }
    let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return result.isEmpty ? nil : result
  }
}
