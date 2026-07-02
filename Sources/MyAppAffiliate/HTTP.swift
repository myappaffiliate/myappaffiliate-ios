import Foundation

/// Minimal POST abstraction so the SDK is testable with a mock transport.
protocol HTTPPosting {
  func post(url: URL, headers: [String: String], body: Data) async throws -> (Data, Int)
}

struct URLSessionHTTPClient: HTTPPosting {
  let session: URLSession
  init(session: URLSession = .shared) { self.session = session }

  func post(url: URL, headers: [String: String], body: Data) async throws -> (Data, Int) {
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.httpBody = body
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (key, value) in headers { req.setValue(value, forHTTPHeaderField: key) }
    let (data, response) = try await session.data(for: req)
    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
    return (data, code)
  }
}

// Wire DTOs — mirror the @maa/types contracts (InstallEvent / Identify).
struct InstallRequest: Encodable {
  let deviceId: String
  let claimToken: String?
  let affiliateCode: String?
  let firstOpenAt: Int
}

struct IdentifyRequest: Encodable {
  let deviceId: String
  let customerUserId: String
  let identifiedAt: Int
}

struct InstallResponse: Decodable {
  let attributionId: String?
  let affiliateId: String?
}
