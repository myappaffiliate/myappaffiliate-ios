import XCTest

@testable import MyAppAffiliate

/// Records requests and returns a canned response per URL. Locked because
/// HTTPPosting is Sendable — the SDK posts from detached Tasks.
final class MockHTTP: HTTPPosting, @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [(url: URL, body: Data)] = []
  let responder: @Sendable (URL) -> (Data, Int)

  init(responder: @escaping @Sendable (URL) -> (Data, Int)) { self.responder = responder }

  var requests: [(url: URL, body: Data)] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  func post(url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
    lock.lock()
    recorded.append((url, body))
    lock.unlock()
    return responder(url)
  }
}

/// Thread-safe flag for tests that flip a mock from offline to online.
final class Flag: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Bool
  init(_ value: Bool) { self.value = value }
  var isOn: Bool {
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

final class AffiliateSDKTests: XCTestCase {
  private func makeClient(_ http: HTTPPosting, store: KeyValueStore = InMemoryStore()) -> Client {
    Client(
      apiKey: "pk_test",
      baseURL: URL(string: "https://api.test")!,
      store: store,
      http: http,
      now: { Date(timeIntervalSince1970: 1000) }
    )
  }

  func testDeviceIdIsStableAndPersisted() {
    let store = InMemoryStore()
    let client = makeClient(MockHTTP { _ in (Data(), 200) }, store: store)
    XCTAssertEqual(client.deviceId, client.deviceId)
    XCTAssertNotNil(store.string(forKey: "maa.deviceId"))
  }

  func testClaimTokenParsing() {
    XCTAssertEqual(
      Client.claimToken(from: URL(string: "https://go.x/jess?claim_token=abc123")!), "abc123")
    XCTAssertEqual(Client.claimToken(from: URL(string: "https://go.x/jess?ct=xyz")!), "xyz")
    XCTAssertNil(Client.claimToken(from: URL(string: "https://go.x/jess")!))
  }

  func testAttributeStoresAffiliateIdAndPostsInstall() async {
    let http = MockHTTP { _ in
      (Data(#"{"attributionId":"at_1","affiliateId":"aff_1"}"#.utf8), 200)
    }
    let client = makeClient(http)
    let ok = await client.attribute(url: URL(string: "https://go.x/jess?claim_token=abc")!)
    XCTAssertTrue(ok)
    XCTAssertEqual(client.attributedAffiliateId(), "aff_1")
    XCTAssertEqual(http.requests.count, 1)
    XCTAssertTrue(http.requests[0].url.absoluteString.hasSuffix("/sdk/install"))
    let body = String(data: http.requests[0].body, encoding: .utf8)!
    XCTAssertTrue(body.contains("abc"))
    XCTAssertTrue(body.contains("\"deviceId\""))
  }

  func testAttributeWithoutClaimTokenDoesNothing() async {
    let http = MockHTTP { _ in (Data(), 200) }
    let client = makeClient(http)
    let ok = await client.attribute(url: URL(string: "https://go.x/jess")!)
    XCTAssertFalse(ok)
    XCTAssertEqual(http.requests.count, 0)
  }

  func testApplyCodePostsAffiliateCode() async {
    let http = MockHTTP { _ in (Data(#"{"affiliateId":"aff_2"}"#.utf8), 200) }
    let client = makeClient(http)
    let ok = await client.applyCode("JESS20")
    XCTAssertTrue(ok)
    XCTAssertEqual(client.attributedAffiliateId(), "aff_2")
    XCTAssertTrue(String(data: http.requests[0].body, encoding: .utf8)!.contains("JESS20"))
  }

  func testIdentifyPostsUser() async {
    let http = MockHTTP { _ in (Data("{}".utf8), 200) }
    let client = makeClient(http)
    let ok = await client.identify(userId: "user_9")
    XCTAssertTrue(ok)
    XCTAssertTrue(http.requests[0].url.absoluteString.hasSuffix("/sdk/identify"))
    XCTAssertTrue(String(data: http.requests[0].body, encoding: .utf8)!.contains("user_9"))
  }

  func testIdentifyNon200ReturnsFalse() async {
    let http = MockHTTP { _ in (Data(), 404) }
    let client = makeClient(http)
    let ok = await client.identify(userId: "x")
    XCTAssertFalse(ok)
  }
}

// MARK: - Deferred attribution, retry, and reset (docs/30 Part 1)

extension AffiliateSDKTests {
  /// A fresh App Store install: the store dropped the claim token, so the SDK
  /// posts an install with neither token nor code and the server matches on its
  /// side. This is the path that makes link-driven installs attributable at all.
  func testBootstrapAsksForADeferredMatchOnAFreshInstall() async {
    let http = MockHTTP { _ in
      (Data(#"{"affiliateId":"aff_9","matchMethod":"deferred_ip"}"#.utf8), 200)
    }
    let client = makeClient(http)
    let ok = await client.bootstrap()
    XCTAssertTrue(ok)
    XCTAssertEqual(client.attributedAffiliateId(), "aff_9")
    let body = String(data: http.requests[0].body, encoding: .utf8)!
    XCTAssertFalse(body.contains("claimToken"))
    XCTAssertFalse(body.contains("affiliateCode"))
  }

  func testBootstrapDoesNothingWhenAlreadyAttributed() async {
    let store = InMemoryStore()
    store.set("aff_existing", forKey: "maa.affiliateId")
    let http = MockHTTP { _ in (Data(), 200) }
    let client = makeClient(http, store: store)
    let ok = await client.bootstrap()
    XCTAssertFalse(ok)
    XCTAssertEqual(http.requests.count, 0)
  }

  /// The deferred ask costs a round trip and can only ever succeed once, so it
  /// must not fire on every cold launch.
  func testDeferredMatchIsAttemptedOnlyOncePerInstall() async {
    let store = InMemoryStore()
    let http = MockHTTP { _ in (Data(#"{}"#.utf8), 404) }
    let client = makeClient(http, store: store)
    await client.bootstrap()
    await client.bootstrap()
    await client.bootstrap()
    XCTAssertEqual(http.requests.count, 1)
  }

  /// First launch is when a device is most likely offline. Losing the code
  /// there would lose the creator their commission permanently.
  func testFailedApplyCodeIsRetriedOnTheNextLaunch() async {
    let store = InMemoryStore()
    let online = Flag(false)
    let http = MockHTTP { _ in
      online.isOn ? (Data(#"{"affiliateId":"aff_2"}"#.utf8), 200) : (Data(), 500)
    }

    let offlineClient = makeClient(http, store: store)
    let firstTry = await offlineClient.applyCode("JESS20")
    XCTAssertFalse(firstTry)
    XCTAssertNil(offlineClient.attributedAffiliateId())

    online.isOn = true
    let nextLaunch = makeClient(http, store: store)
    let retried = await nextLaunch.bootstrap()
    XCTAssertTrue(retried)
    XCTAssertEqual(nextLaunch.attributedAffiliateId(), "aff_2")
    XCTAssertTrue(String(data: http.requests[1].body, encoding: .utf8)!.contains("JESS20"))
  }

  func testFailedUniversalLinkTokenIsRetriedOnTheNextLaunch() async {
    let store = InMemoryStore()
    let online = Flag(false)
    let http = MockHTTP { _ in
      online.isOn ? (Data(#"{"affiliateId":"aff_3"}"#.utf8), 200) : (Data(), 500)
    }

    let offlineClient = makeClient(http, store: store)
    _ = await offlineClient.attribute(url: URL(string: "https://go.x/jess?claim_token=tok1")!)

    online.isOn = true
    let nextLaunch = makeClient(http, store: store)
    let retried = await nextLaunch.bootstrap()
    XCTAssertTrue(retried)
    XCTAssertEqual(nextLaunch.attributedAffiliateId(), "aff_3")
    XCTAssertTrue(String(data: http.requests[1].body, encoding: .utf8)!.contains("tok1"))
  }

  /// 404 (no click) and 409 (ambiguous — the server refused to guess) are final
  /// answers. Retrying them forever would hammer the API for nothing.
  func testFinalRejectionsClearThePendingPayload() async {
    for status in [404, 409] {
      let store = InMemoryStore()
      let http = MockHTTP { _ in (Data(), status) }
      let client = makeClient(http, store: store)
      _ = await client.applyCode("NOPE")
      XCTAssertNil(store.string(forKey: "maa.pendingCode"), "status \(status)")

      let nextLaunch = makeClient(http, store: store)
      _ = await nextLaunch.bootstrap()
      XCTAssertEqual(http.requests.count, 2, "status \(status): must not retry a final rejection")
    }
  }

  func testResetClearsEveryPersistedKey() async {
    let store = InMemoryStore()
    let http = MockHTTP { _ in (Data(#"{"affiliateId":"aff_1"}"#.utf8), 200) }
    let client = makeClient(http, store: store)
    _ = client.deviceId
    _ = await client.applyCode("JESS20")
    XCTAssertNotNil(client.attributedAffiliateId())

    client.reset()
    XCTAssertNil(client.attributedAffiliateId())
    for key in [
      "maa.deviceId", "maa.affiliateId", "maa.pendingToken", "maa.pendingCode",
      "maa.deferredTried",
    ] {
      XCTAssertNil(store.string(forKey: key), key)
    }
  }
}
