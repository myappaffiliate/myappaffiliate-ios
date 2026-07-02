import Foundation

/// MyAppAffiliate iOS SDK — the public surface an app integrates.
///
///     AffiliateSDK.configure(apiKey: "pk_live_…", baseURL: URL(string: "https://api.myappaffiliate.com")!)
///     // in your SceneDelegate / .onOpenURL:
///     AffiliateSDK.attribute(url: incomingUniversalLink)
///     // when you know the user:
///     AffiliateSDK.identify(userId: "user_123")
///     // before a RevenueCat purchase:
///     if let aff = AffiliateSDK.attributedAffiliateId() {
///         Purchases.shared.attribution.setAttributes(["affiliate_id": aff])
///     }
public enum AffiliateSDK {
  static var shared: Client?

  /// Initialize the SDK. Call once at launch.
  public static func configure(apiKey: String, baseURL: URL) {
    #if canImport(Security)
    let store: KeyValueStore = KeychainStore(service: "com.myappaffiliate.sdk")
    #else
    let store: KeyValueStore = InMemoryStore()
    #endif
    shared = Client(apiKey: apiKey, baseURL: baseURL, store: store, http: URLSessionHTTPClient())
  }

  /// Handle an incoming Universal Link on first open; records attribution.
  public static func attribute(url: URL) {
    guard let client = shared else { return }
    Task { await client.attribute(url: url) }
  }

  /// Manual-code fallback (e.g. a creator's "JESS20") when no Universal Link is available.
  public static func applyCode(_ code: String) {
    guard let client = shared else { return }
    Task { await client.applyCode(code) }
  }

  /// Bind the app's user id to the stored attribution (call once you know the user).
  public static func identify(userId: String) {
    guard let client = shared else { return }
    Task { await client.identify(userId: userId) }
  }

  /// The affiliate id this install was attributed to, if any. Pass into RevenueCat.
  public static func attributedAffiliateId() -> String? { shared?.attributedAffiliateId() }
}
