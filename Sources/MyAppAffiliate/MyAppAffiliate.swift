import Foundation

/// Concurrency-safe holder for the configured client.
///
/// The public API is deliberately synchronous — `attributedAffiliateId()` is
/// read on the purchase path — so an actor would force `await` on every caller.
/// A lock is the right tool here.
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
/// The whole integration is two calls:
///
/// ```swift
/// MyAppAffiliate.start(apiKey: "pk_live_…")   // once, at launch
/// MyAppAffiliate.identify(userId: yourUserId) // once you know the user
/// ```
///
/// In SwiftUI it collapses to a single modifier, which also wires up incoming
/// Universal Links for you:
///
/// ```swift
/// WindowGroup { ContentView().myAppAffiliate(apiKey: "pk_live_…") }
/// ```
///
/// The API host is compiled in — you never type a URL. Everything beyond the
/// two calls (a staging host, manual link handling, reading the attributed
/// affiliate) is optional and lives on ``Options`` or the methods below.
public enum MyAppAffiliate {
  private static let box = ClientBox()

  static var shared: Client? {
    get { box.client }
    set { box.client = newValue }
  }

  /// Optional settings. Every field has a working default — reach for this only
  /// when you have a reason to.
  public struct Options: Sendable {
    /// Point at a staging API or a self-hosted deployment. Leave nil in
    /// production: the host is compiled in, and can also be set once in
    /// Info.plist under `MyAppAffiliateAPIBaseURL`.
    public var apiBaseURL: URL?
    /// Print what the SDK decided, to the console. Off by default.
    public var debug: Bool

    public init(apiBaseURL: URL? = nil, debug: Bool = false) {
      self.apiBaseURL = apiBaseURL
      self.debug = debug
    }
  }

  /// True once ``start(apiKey:options:)`` has run. Useful in a debug assert;
  /// every other call is a safe no-op before it.
  public static var isStarted: Bool { shared != nil }

  /// Start the SDK. Call once at launch.
  ///
  /// Pass your key, or omit it and put it in Info.plist under
  /// `MyAppAffiliateAPIKey` — then `MyAppAffiliate.start()` takes no arguments.
  ///
  /// This also kicks off first-open attribution in the background: it retries
  /// any payload an earlier launch failed to deliver, and on a fresh install
  /// with nothing pending it asks the API for a deferred match. A user who
  /// installed from a creator's link is attributed without you calling anything
  /// else.
  @discardableResult
  public static func start(apiKey: String? = nil, options: Options = Options()) -> Bool {
    guard let key = MyAppAffiliateConfiguration.resolveAPIKey(apiKey) else {
      // The one failure loud enough to print: with no key nothing can ever
      // attribute, and every other error path here is silent by design.
      print(
        """
        [myappaffiliate] no API key — pass one to MyAppAffiliate.start(apiKey:) or set \
        \(MyAppAffiliateConfiguration.apiKeyInfoPlistKey) in Info.plist. The SDK is inactive.
        """
      )
      return false
    }

    #if canImport(Security)
      let store: KeyValueStore = KeychainStore(service: "com.myappaffiliate.sdk")
    #else
      let store: KeyValueStore = InMemoryStore()
    #endif
    let client = Client(
      apiKey: key,
      baseURL: MyAppAffiliateConfiguration.resolveAPIBaseURL(options.apiBaseURL),
      store: store,
      http: URLSessionHTTPClient(),
      debug: options.debug
    )
    shared = client
    Task { await client.bootstrap() }
    return true
  }

  /// Bind your user id to the attribution — call once you know the user.
  ///
  /// This id is the join key for every revenue event that follows, whoever bills
  /// the customer: it must be the same string your billing provider reports back
  /// to us (RevenueCat / Adapty / Superwall app user id, Stripe
  /// `metadata.customer_user_id`, Paddle custom data).
  public static func identify(userId: String) {
    guard let client = shared else { return }
    Task { await client.identify(userId: userId) }
  }

  /// Claim the referral carried by an incoming link — a `claim_token`/`ct` from
  /// a tracked link, or a `via`/`ref`/`code` param.
  ///
  /// Wired for you by the SwiftUI `.myAppAffiliate(apiKey:)` modifier; call it
  /// yourself from `.onOpenURL` / `application(_:open:options:)` in UIKit.
  public static func attribute(url: URL) {
    guard let client = shared else { return }
    Task { await client.attribute(url: url) }
  }

  /// Manual-code entry (e.g. a "Got a creator code?" field). Works with no
  /// deep-link setup at all.
  public static func applyCode(_ code: String) {
    guard let client = shared else { return }
    Task { await client.applyCode(code) }
  }

  /// The affiliate id this install was attributed to, if any. You do not need
  /// this for attribution to work — it is here for your own UI and analytics.
  public static func attributedAffiliateId() -> String? { shared?.attributedAffiliateId() }

  /// Clear all persisted SDK state — call on logout or a data-erasure request.
  ///
  /// The SDK stays started: the next launch (or the next link) attributes
  /// again from scratch, exactly as a fresh install would.
  public static func reset() { shared?.reset() }

  /// Test hook — drop the configured client so `isStarted` reads false again.
  /// Internal, so it never appears in a customer's autocomplete.
  static func tearDownForTesting() { shared = nil }
}
