# Step 07 — Apple CDN

`check-cdn` fetches the origin AASA and Apple's observable CDN copy:

- origin: `https://<domain>/.well-known/apple-app-site-association`
- CDN: `https://app-site-association.cdn-apple.com/a/v1/<domain>`

It compares **JSON content**, not raw bytes, so pretty vs minified files still match.

A content mismatch is a **warning** (`APPLE_CDN_ORIGIN_MISMATCH`):

> may indicate propagation/cache delay. Re-check later; cache invalidation cannot be forced by this CLI.

This is not compared against `deeplink_config.yaml`. Origin vs config is `validate --live`. Origin vs Apple CDN is the cache diagnosis.

It does not promise a 24/48-hour SLA and does not claim a cache-clear API exists.

iOS `bundle_id` + `team_id` are required; otherwise the check is skipped (`CDN_SKIPPED`).
