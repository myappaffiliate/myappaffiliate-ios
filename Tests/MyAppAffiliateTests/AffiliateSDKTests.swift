import XCTest

@testable import MyAppAffiliate

/// Records requests and returns a canned response per URL.
final class MockHTTP: HTTPPosting {
  private(set) var requests: [(url: URL, body: Data)] = []
  let responder: (URL) -> (Data, Int)
  init(responder: @escaping (URL) -> (Data, Int)) { self.responder = responder }

  func post(url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
    requests.append((url, body))
    return responder(url)
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
