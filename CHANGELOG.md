# Changelog

## 0.1.1

- Drop unused `xml` dependency so pub.dev can score latest stable dependencies.

## 0.1.0

- Initial release: `init`, `generate`, `configure`, `validate`, `check-cdn`, `test-live`, `doctor`.
- Detect Flutter Android `applicationId`, debug SHA-256, and iOS bundle / team IDs.
- Compare live origin association files to generated config (no redirects).
- Diagnose Apple CDN vs origin AASA mismatches without claiming cache invalidation. Mismatch copy includes both URLs and a typical few hours–24h refresh (rarely several days, TTL).
