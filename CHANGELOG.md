# Changelog

## 0.3.0

**Two calls, and no API URL.** `configure(apiKey:baseURL:)` is gone: the production
host is compiled into the SDK, so nothing about our infrastructure is typed into an
app any more. The entry point is renamed to match the product and the other platforms.

Breaking:

- `AffiliateSDK` → `MyAppAffiliate`. Same methods, one name on every platform.
- `configure(apiKey:baseURL:)` → `start(apiKey:options:)`. The base URL moved to
  `Options.apiBaseURL` and defaults to `https://api.myappaffiliate.com`; a staging or
  self-hosted host also reads from the `MyAppAffiliateAPIBaseURL` Info.plist key, so a
  build variant needs no code change.

Added:

- `.myAppAffiliate(apiKey:)` SwiftUI view modifier — starts the SDK and forwards
  incoming Universal Links in one line, replacing a hand-written `.onOpenURL`.
- `start()` reads the key from the `MyAppAffiliateAPIKey` Info.plist entry, so the key
  need not appear in source at all. It returns `false` and logs once when no key is
  found anywhere — the one misconfiguration that silently disables everything.
- `attribute(url:)` now also claims a referral code from a plain link (`?via=`,
  `?ref=`, `?maa_code=`, `?code=`). Creators share those at least as often as tracked
  links; previously every one of them was dropped.
- `MyAppAffiliate.isStarted`, and `Options.debug` for console logging.

Removed from the documented integration:

- The `affiliate_id` RevenueCat subscriber attribute step. Nothing in the pipeline ever
  read it — attribution joins on the user id from `identify(userId:)` — so it was work
  with no outcome.

## 0.2.0

**Fresh installs from a creator's link now attribute.** Previously they could
not: the App Store drops the claim token, the user opens from the home screen,
and no Universal Link ever reaches the app — so only a manually entered code
worked. `configure()` now runs first-open attribution in the background and asks
the API for a deferred match (hashed IP + a short time window, server-side).

- Added: automatic first-open attribution from `configure()`, attempted once per
  install.
- Added: `AffiliateSDK.reset()` — clears all persisted state for logout and
  data-erasure requests.
- Added: failed install calls are persisted and retried on the next launch, so a
  device that was offline on first open still attributes. Final rejections
  (404 no click, 409 ambiguous match) are dropped rather than retried forever.
- Fixed: Keychain items are now written with `kSecAttrAccessibleAfterFirstUnlock`.
  With the previous default, a background launch before the first unlock after a
  reboot read nothing, minted a new device id, and silently detached the
  attribution.
- Fixed: `deviceId` generation is now atomic — concurrent first calls could mint
  two ids and persist the loser.
- Fixed: compiles clean under the Swift 6 language mode; the shared client is no
  longer nonisolated global mutable state.
- Added: `InstallResponse.matchMethod`, so the caller can tell a deterministic
  match from a probabilistic one.

## 0.1.0

- Initial release: `configure`, `attribute(url:)` (claim_token | ct),
  `applyCode`, `identify`, `attributedAffiliateId`.
- Injectable `KeyValueStore` (Keychain in production, in-memory for tests) and
  `HTTPPosting` transport.
- Silent-safe networking — failures never throw into the host app.
