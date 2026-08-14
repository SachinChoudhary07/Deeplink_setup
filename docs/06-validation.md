# Step 06 — Validation

`validate --local` checks:

- domain / package / SHA-256 / iOS completeness
- Android-only and iOS-only configs (the other platform is skipped)
- local `.well-known` files exist for each complete platform
- those files match deterministic generated output

Missing or stale local files are errors so CI fails before deploy. Run `generate` to fix them.

`validate --live` fetches the public origin (not Apple CDN, not local files) and compares that JSON to what `generate` would produce from `deeplink_config.yaml`:

- `https://<domain>/.well-known/assetlinks.json`
- `https://<domain>/.well-known/apple-app-site-association`

It requires HTTPS 200 with **no redirects**. Pretty vs minified JSON still matches. An origin/config mismatch is an error; re-upload the generated files.

HTTP 200 is not sufficient proof that a mobile app will open correctly.
