# MyAppAffiliate iOS SDK

The drop-in Swift SDK that connects an iOS app to MyAppAffiliate attribution. Zero
runtime dependencies, iOS 15+. Target: a working integration in **under 30 minutes**.

It does four things: stores a stable device id, records the attribution from a
Universal Link (or a manual code), binds your user id to it, and hands you the
attributed affiliate id to pass into RevenueCat.

## Install (Swift Package Manager)

In Xcode: **File → Add Package Dependencies…** and point at this package, or add to
your `Package.swift`:

```swift
.package(url: "https://github.com/your-org/myappaffiliate-ios", from: "0.1.0")
```

Then add `MyAppAffiliate` to your target's dependencies.

## 1. Configure (once, at launch)

```swift
import MyAppAffiliate

AffiliateSDK.configure(
    apiKey: "pk_live_…",                                   // your app's SDK key
    baseURL: URL(string: "https://api.myappaffiliate.com")! // your API base URL
)
```

## 2. Capture the attribution from the Universal Link

Add the **Associated Domains** capability in Xcode with
`applinks:<your-link-domain>` so taps on a creator's branded link open your app.
Then forward the incoming URL:

```swift
// SwiftUI
.onOpenURL { url in
    AffiliateSDK.attribute(url: url)
}

// UIKit (SceneDelegate)
func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    if let url = userActivity.webpageURL {
        AffiliateSDK.attribute(url: url)
    }
}
```

**Manual-code fallback** (creator gives followers a code like `JESS20`):

```swift
AffiliateSDK.applyCode("JESS20")
```

## 3. Identify the user (once you know who they are)

```swift
AffiliateSDK.identify(userId: yourAppUserId)   // same id you use with RevenueCat
```

## 4. Pass the affiliate into RevenueCat (before the purchase)

This is what closes the loop — RevenueCat sends the `affiliate_id` back to us in the
purchase webhook, and we map the subscription revenue to that creator.

```swift
import RevenueCat

if let affiliateId = AffiliateSDK.attributedAffiliateId() {
    Purchases.shared.attribution.setAttributes(["affiliate_id": affiliateId])
}
// then make the purchase as usual
```

## API

| Call | Purpose |
|---|---|
| `AffiliateSDK.configure(apiKey:baseURL:)` | Initialize once at launch |
| `AffiliateSDK.attribute(url:)` | Record attribution from a Universal Link |
| `AffiliateSDK.applyCode(_:)` | Manual-code attribution fallback |
| `AffiliateSDK.identify(userId:)` | Bind your user id to the attribution |
| `AffiliateSDK.attributedAffiliateId()` | The attributed affiliate id (or `nil`) |

## Privacy

No IDFA, no fingerprinting, no cross-app tracking. The SDK stores only a generated
device id (Keychain) and the attributed affiliate id. Attribution is first-party and
deterministic — see [`../../docs/04-product-vision-and-positioning.md`](../../docs/04-product-vision-and-positioning.md).

## Development

```bash
swift test --package-path prototype/ios-sdk
```

Storage and HTTP are injectable (`KeyValueStore`, `HTTPPosting`) so the engine is
unit-tested without Keychain or the network (see `Tests/`).

> A runnable example Xcode app that exercises the full click→install→purchase flow
> against staging is a follow-up (ENG-19); the snippets above are the integration.
