# Step 05 — Generate

`generate` writes only the association files whose platform config is complete:

```text
.well-known/assetlinks.json
.well-known/apple-app-site-association
```

Android-only config writes `assetlinks.json`. iOS-only config writes `apple-app-site-association`. Missing optional platforms are skipped with an info line. Partial platform blocks fail.

Output is deterministic to make review and diffs useful.
