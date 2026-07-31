# Changelog

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
