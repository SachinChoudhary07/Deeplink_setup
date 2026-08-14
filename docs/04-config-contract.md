# Step 04 — Configuration

`deeplink_config.yaml`:

```yaml
domain: example.com
android:
  package: com.example.app
  sha256: "..."
ios:
  bundle_id: com.example.app
  team_id: ABC123
paths:
  - "/*"
```

Domain is required. Platform blocks are optional, but generation of a platform's association file requires that platform's values.

A partial platform block (for example Android `package` without `sha256`, or iOS `bundle_id` without `team_id`) is an error.

`init` fills these from the Flutter project when it can, including Windows `%USERPROFILE%\.android\debug.keystore` and Xcode `DEVELOPMENT_TEAM`. Missing tools or values are warnings; the YAML is still written.

`android.sha256` is accepted as colon-separated, hyphen-separated, or compact hex. The CLI normalizes it to uppercase `AA:BB:...` pairs before generation and validation.
