import Foundation

/// Concurrency-safe holder for the configured client.
///
/// The public API is deliberately synchronous — `attributedAffiliateId()` is
/// read on the purchase path, right before handing the id to RevenueCat — so an
/// actor would force `await` on every caller. A lock is the right tool here.
private final class ClientBox: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Client?

  var client: Client? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return value
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      value = newValue
    }
  }
}

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
  private static let box = ClientBox()

  static var shared: Client? {
    get { box.client }
    set { box.client = newValue }
  }

  /// Initialize the SDK. Call once at launch.
  ///
  /// This also kicks off first-open attribution in the background: it retries
  /// any payload an earlier launch failed to deliver, and on a fresh install
  /// with nothing pending it asks the API for a deferred match. You do not need
  /// to call anything else for a user who installed from a creator's link.
  public static func configure(apiKey: String, baseURL: URL) {
    #if canImport(Security)
      let store: KeyValueStore = KeychainStore(service: "com.myappaffiliate.sdk")
    #else
      let store: KeyValueStore = InMemoryStore()
    #endif
    let client = Client(apiKey: apiKey, baseURL: baseURL, store: store, http: URLSessionHTTPClient())
    shared = client
    Task { await client.bootstrap() }
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

  /// Clear all persisted SDK state — call on logout or a data-erasure request.
  public static func reset() { shared?.reset() }
}
