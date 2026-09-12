# MyAppAffiliate iOS SDK

The drop-in Swift SDK that connects an iOS app to MyAppAffiliate attribution. Zero
runtime dependencies, iOS 15+.

**The whole integration is two calls.** Start the SDK with your key; tell it who the
user is. Everything else — capturing the link, retrying an offline first launch,
asking for a deferred match on a fresh install — happens inside.

You never type an API URL. The production host is compiled in.

## Install (Swift Package Manager)

In Xcode: **File → Add Package Dependencies…** and point at this package, or add to
your `Package.swift`:

```swift
.package(url: "https://github.com/myappaffiliate/myappaffiliate-ios", from: "0.3.0")
```

Then add `MyAppAffiliate` to your target's dependencies.

## 1. Start it

**SwiftUI — one line.** The modifier starts the SDK *and* forwards incoming Universal
Links to it, so you write no `.onOpenURL` of your own:

```swift
import MyAppAffiliate

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView().myAppAffiliate(apiKey: "pk_live_…")
        }
    }
}
```

**UIKit / manual:**

```swift
MyAppAffiliate.start(apiKey: "pk_live_…")

// …and wherever links arrive:
func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    if let url = userActivity.webpageURL {
        MyAppAffiliate.attribute(url: url)
    }
}
```

### Keeping the key out of source

Put it in **Info.plist** under `MyAppAffiliateAPIKey` — driven by a build setting, so
it varies per scheme — and the call takes no arguments at all:

```swift
MyAppAffiliate.start()
// or: ContentView().myAppAffiliate()
```

## 2. Identify the user

```swift
MyAppAffiliate.identify(userId: yourAppUserId)
```

The id must be the **same string your billing provider reports back to us**:
RevenueCat's `logIn(...)` id, Adapty's customer user id, Superwall's app user id,
Stripe's `metadata.customer_user_id`, Paddle's custom data. That is the only join key
there is — if the two differ, everything looks healthy and no commission is ever
created.

That's it. There is no third step. In particular you do **not** need to set an
`affiliate_id` subscriber attribute in RevenueCat or anywhere else: nothing reads it,
and it is no longer part of the integration.

## Optional

```swift
// A "Got a creator code?" field — attributes with no deep-link setup at all.
MyAppAffiliate.applyCode("JESS20")

// The attributed affiliate, for your own UI or analytics.
let affiliateId = MyAppAffiliate.attributedAffiliateId()   // String?

// Logout / data-erasure request.
MyAppAffiliate.reset()

// Staging or self-hosted API, and debug logging.
MyAppAffiliate.start(
    apiKey: "pk_live_…",
    options: .init(apiBaseURL: URL(string: "https://staging.example.com"), debug: true)
)
```

The host override also lives in Info.plist, under `MyAppAffiliateAPIBaseURL`, so a
staging build needs no code change at all.

Universal Links need the **Associated Domains** capability in Xcode
(`applinks:<your-link-domain>`). Skip it and creator codes plus deferred matching
still attribute.

## API

| Call | Purpose |
|---|---|
| `MyAppAffiliate.start(apiKey:options:)` | Start once at launch; also runs first-open attribution |
| `MyAppAffiliate.identify(userId:)` | Bind your user id to the attribution |
| `.myAppAffiliate(apiKey:)` | SwiftUI modifier: start + link handling in one line |
| `MyAppAffiliate.attribute(url:)` | Record attribution from an incoming link (UIKit) |
| `MyAppAffiliate.applyCode(_:)` | Creator-code entry |
| `MyAppAffiliate.attributedAffiliateId()` | The attributed affiliate id (or `nil`) |
| `MyAppAffiliate.reset()` | Clear all persisted state (logout / erasure requests) |
| `MyAppAffiliate.isStarted` | Whether `start` has run |

Every call is non-blocking and silent-safe — network failures never throw into your
app, and calls before `start` are no-ops. An attribution that fails to reach us is
persisted and retried on the next launch, so a user who was offline on first open
still attributes.

## How accurate is the attribution?

Three of the four match paths are exact. The fourth is a best guess, and we'd rather
you know which is which:

| How it matched | Exact? | When |
|---|---|---|
| Universal Link claim token | ✅ | app already installed, user taps the link |
| Referral code in a link (`?via=`) | ✅ | creator shares a plain link |
| Creator code | ✅ | user entered `JESS20` |
| Deferred (IP + time window) | ⚠️ probabilistic | fresh install from a link — the App Store drops the token, so we match a hashed IP against clicks in the last hour |

The deferred path never guesses between two creators: if clicks from two different
affiliates are in the window, we attribute to neither. No IDFA, no device
fingerprinting, no cross-app graph — the match uses a hashed IP and a timestamp,
nothing else.

## Privacy

No IDFA, no fingerprinting, no cross-app tracking. The SDK stores only a generated
device id (Keychain) and the attributed affiliate id. Attribution is first-party and
deterministic — see [myappaffiliate.com/privacy](https://myappaffiliate.com/privacy).

## Development

```bash
swift test
```

Storage and HTTP are injectable (`KeyValueStore`, `HTTPPosting`) so the engine is
unit-tested without Keychain or the network (see `Tests/`).

> A runnable example Xcode app that exercises the full click→install→purchase flow
> against staging is a follow-up (ENG-19); the snippets above are the integration.

## License

MIT — see [LICENSE](LICENSE).
