import Foundation

/// The internal engine behind `AffiliateSDK`. Holds config + storage + transport.
/// Public methods on `AffiliateSDK` delegate here; tests drive `Client` directly
/// with an in-memory store and a mock HTTP client.
final class Client: @unchecked Sendable {
  let apiKey: String
  let baseURL: URL
  let store: KeyValueStore
  let http: HTTPPosting
  let now: () -> Date

  /// Guards the read-then-write in `deviceId` so two concurrent first calls
  /// can't mint two ids and persist the loser.
  private let lock = NSLock()

  private let deviceIdKey = "maa.deviceId"
  private let affiliateIdKey = "maa.affiliateId"
  /// An attribution payload that hasn't reached the API yet. First launch is
  /// exactly when a device is most likely offline, so we keep it and retry.
  private let pendingTokenKey = "maa.pendingToken"
  private let pendingCodeKey = "maa.pendingCode"
  /// Set once the server-side deferred match has been attempted, so we ask for
  /// it once per install instead of on every launch.
  private let deferredTriedKey = "maa.deferredTried"

  init(
    apiKey: String,
    baseURL: URL,
    store: KeyValueStore,
    http: HTTPPosting,
    now: @escaping () -> Date = Date.init
  ) {
    self.apiKey = apiKey
    self.baseURL = baseURL
    self.store = store
    self.http = http
    self.now = now
  }

  /// Stable per-install device id, generated once and persisted.
  var deviceId: String {
    lock.lock()
    defer { lock.unlock() }
    if let existing = store.string(forKey: deviceIdKey) { return existing }
    let id = UUID().uuidString
    store.set(id, forKey: deviceIdKey)
    return id
  }

  func attributedAffiliateId() -> String? { store.string(forKey: affiliateIdKey) }

  /// Extracts the deferred-deep-link claim token from a Universal Link.
  static func claimToken(from url: URL) -> String? {
    guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    return comps.queryItems?.first { $0.name == "claim_token" || $0.name == "ct" }?.value
  }

  /// Runs at launch, before any link or code arrives. In order:
  ///   1. already attributed → nothing to do
  ///   2. a payload we failed to deliver earlier → retry it
  ///   3. otherwise → ask the API for a deferred match, once per install
  ///
  /// Step 3 is what makes a fresh App Store install attributable at all: the
  /// store drops the claim token, so the server matches on a hashed IP and a
  /// short time window instead (docs/30 Part 1).
  @discardableResult
  func bootstrap() async -> Bool {
    if attributedAffiliateId() != nil { return false }

    if let token = store.string(forKey: pendingTokenKey) {
      return await postInstall(claimToken: token, affiliateCode: nil)
    }
    if let code = store.string(forKey: pendingCodeKey) {
      return await postInstall(claimToken: nil, affiliateCode: code)
    }

    if store.string(forKey: deferredTriedKey) != nil { return false }
    store.set("1", forKey: deferredTriedKey)
    return await postInstall(claimToken: nil, affiliateCode: nil)
  }

  @discardableResult
  func attribute(url: URL) async -> Bool {
    guard let token = Client.claimToken(from: url) else { return false }
    store.set(token, forKey: pendingTokenKey)
    return await postInstall(claimToken: token, affiliateCode: nil)
  }

  @discardableResult
  func applyCode(_ code: String) async -> Bool {
    store.set(code, forKey: pendingCodeKey)
    return await postInstall(claimToken: nil, affiliateCode: code)
  }

  @discardableResult
  func identify(userId: String) async -> Bool {
    let body = IdentifyRequest(deviceId: deviceId, customerUserId: userId, identifiedAt: millis())
    guard let data = try? JSONEncoder().encode(body) else { return false }
    guard
      let (_, code) = try? await http.post(
        url: endpoint("sdk/identify"), headers: authHeaders(), body: data),
      code == 200
    else { return false }
    return true
  }

  /// Clears every piece of persisted state. Call on logout or an erasure
  /// request — after this the device is indistinguishable from a fresh install.
  func reset() {
    for key in [deviceIdKey, affiliateIdKey, pendingTokenKey, pendingCodeKey, deferredTriedKey] {
      store.set(nil, forKey: key)
    }
  }

  @discardableResult
  private func postInstall(claimToken: String?, affiliateCode: String?) async -> Bool {
    let body = InstallRequest(
      deviceId: deviceId,
      claimToken: claimToken,
      affiliateCode: affiliateCode,
      firstOpenAt: millis()
    )
    guard let data = try? JSONEncoder().encode(body) else { return false }
    guard
      let (respData, code) = try? await http.post(
        url: endpoint("sdk/install"), headers: authHeaders(), body: data)
    else { return false }

    // 404 = no attributable click; 409 = an ambiguous deferred match the server
    // refused to guess at. Both are final answers, not transient failures, so
    // drop the pending payload instead of retrying it on every launch.
    if code == 404 || code == 409 {
      clearPending()
      return false
    }
    guard code == 200 else { return false }

    if let parsed = try? JSONDecoder().decode(InstallResponse.self, from: respData),
      let affiliateId = parsed.affiliateId
    {
      store.set(affiliateId, forKey: affiliateIdKey)
    }
    clearPending()
    return true
  }

  private func clearPending() {
    store.set(nil, forKey: pendingTokenKey)
    store.set(nil, forKey: pendingCodeKey)
  }

  private func millis() -> Int { Int(now().timeIntervalSince1970 * 1000) }
  private func endpoint(_ path: String) -> URL { baseURL.appendingPathComponent(path) }
  private func authHeaders() -> [String: String] { ["Authorization": "Bearer \(apiKey)"] }
}
