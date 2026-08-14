# Step 03 — CLI Contract

Commands:

```bash
deeplink_setup init --domain example.com
deeplink_setup generate
deeplink_setup configure
deeplink_setup validate --local
deeplink_setup validate --live
deeplink_setup check-cdn
deeplink_setup test-live
deeplink_setup doctor
```

All commands accept `--config` where configuration is required.

Exit codes:
- 0 success (including `init` with detection warnings)
- 1 failure/diagnostic error
- 64 invalid usage

`init` treats missing `keytool`, debug keystore, package, bundle ID, or team ID as warnings. The config file is still written so those values can be filled in manually.

`validate --local` treats missing or stale `.well-known` files as errors (exit 1).

`validate --live` compares the public origin association files to generated config output. Redirects and origin/config mismatches are errors.

`check-cdn` compares origin AASA JSON to Apple's CDN copy. A mismatch is a warning (possible cache delay), not an error. Cache cannot be cleared by this CLI.

`doctor` runs local + live + CDN. Exit 1 only when there are errors.
