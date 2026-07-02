import Foundation

/// The internal engine behind `AffiliateSDK`. Holds config + storage + transport.
/// Public methods on `AffiliateSDK` delegate here; tests drive `Client` directly
/// with an in-memory store and a mock HTTP client.
final class Client {
  let apiKey: String
  let baseURL: URL
  let store: KeyValueStore
  let http: HTTPPosting
  let now: () -> Date

  private let deviceIdKey = "maa.deviceId"
  private let affiliateIdKey = "maa.affiliateId"

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

  @discardableResult
  func attribute(url: URL) async -> Bool {
    guard let token = Client.claimToken(from: url) else { return false }
    return await postInstall(claimToken: token, affiliateCode: nil)
  }

  @discardableResult
  func applyCode(_ code: String) async -> Bool {
    await postInstall(claimToken: nil, affiliateCode: code)
  }

  @discardableResult
  func identify(userId: String) async -> Bool {
    let body = IdentifyRequest(deviceId: deviceId, customerUserId: userId, identifiedAt: millis())
    guard let data = try? JSONEncoder().encode(body) else { return false }
    guard let (_, code) = try? await http.post(url: endpoint("sdk/identify"), headers: authHeaders(), body: data),
          code == 200 else { return false }
    return true
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
    guard let (respData, code) = try? await http.post(url: endpoint("sdk/install"), headers: authHeaders(), body: data),
          code == 200 else { return false }
    if let parsed = try? JSONDecoder().decode(InstallResponse.self, from: respData),
       let affiliateId = parsed.affiliateId {
      store.set(affiliateId, forKey: affiliateIdKey)
    }
    return true
  }

  private func millis() -> Int { Int(now().timeIntervalSince1970 * 1000) }
  private func endpoint(_ path: String) -> URL { baseURL.appendingPathComponent(path) }
  private func authHeaders() -> [String: String] { ["Authorization": "Bearer \(apiKey)"] }
}
