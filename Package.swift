// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "MyAppAffiliate",
  platforms: [.iOS(.v15), .macOS(.v12)],
  products: [
    .library(name: "MyAppAffiliate", targets: ["MyAppAffiliate"]),
  ],
  targets: [
    .target(name: "MyAppAffiliate"),
    .testTarget(name: "MyAppAffiliateTests", dependencies: ["MyAppAffiliate"]),
  ]
)
