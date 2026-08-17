# Step 07 — Apple CDN

`check-cdn` fetches the origin AASA and Apple's observable CDN copy:

- origin: `https://<domain>/.well-known/apple-app-site-association`
- CDN: `https://app-site-association.cdn-apple.com/a/v1/<domain>`

It compares **JSON content**, not raw bytes, so pretty vs minified files still match.

A content mismatch is a **warning** (`APPLE_CDN_ORIGIN_MISMATCH`). The CLI prints both URLs and says Apple’s CDN typically re-crawls in a **few hours, often within 24 hours**, and in rare cases **several days** depending on TTL. That window is developer guidance, not an official Apple SLA. Cache cannot be cleared by this CLI.

This is not compared against `deeplink_config.yaml`. Origin vs config is `validate --live`. Origin vs Apple CDN is the cache diagnosis.

iOS `bundle_id` + `team_id` are required; otherwise the check is skipped (`CDN_SKIPPED`).
