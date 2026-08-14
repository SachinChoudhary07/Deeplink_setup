# deeplink_setup

A Dart CLI for Android App Links and iOS Universal Links.

## Implemented features

- `generate`
- `validate --local`
- `validate --live`
- `check-cdn`
- `doctor`
- `test-live`
- Android Gradle `applicationId` detection
- Android signing SHA-256 detection from `keytool`
- iOS bundle identifier detection from Xcode project / Info.plist
- safe AndroidManifest App Links on `.MainActivity` / launcher activity
- safe iOS Associated Domains insertion
- HTTPS/status/redirect/content-type checks
- local/generated and origin/generated comparisons
- origin/Apple CDN AASA comparison
- deterministic association-file generation
- structured diagnostics and exit codes
- feature-by-feature documentation under `docs/`
- AI-agent/Cursor implementation guide

## Install in a Dart/Flutter project

During development, use a path dependency:

```yaml
dev_dependencies:
  deeplink_setup:
    path: ../deeplink_setup_final
```

For a published package, replace the path with the package version.

Then:

```bash
dart pub get
dart run deeplink_setup:deeplink_setup --help
```

## Initialize a project

```bash
dart run deeplink_setup:deeplink_setup init --domain example.com
```

`init` inspects common Flutter Android/iOS files and writes `deeplink_config.yaml`.

Detection failures are **warnings**, not errors. `init` still writes the YAML (exit 0) so you can fill missing values by hand:

- `keytool` missing from PATH / `JAVA_HOME` → paste `android.sha256`
- debug keystore missing → same
- iOS `DEVELOPMENT_TEAM` missing → paste `ios.team_id`

On Windows the debug keystore is read from `%USERPROFILE%\.android\debug.keystore` (and `HOME` on macOS/Linux). Production/release fingerprints should be set in the YAML explicitly.

Review the generated config before committing it.

## Generate

```bash
dart run deeplink_setup:deeplink_setup generate
```

This writes whichever association files the config can produce:

```text
.well-known/assetlinks.json
.well-known/apple-app-site-association
```

Android-only or iOS-only configs are valid. A platform is skipped until its required values are present.

## Validate

```bash
dart run deeplink_setup:deeplink_setup validate --local
dart run deeplink_setup:deeplink_setup validate --live
```

`--local` fails (exit 1) if config is incomplete or if generated `.well-known` files are missing or out of date.

`--live` fetches `https://<domain>/.well-known/...` (no redirects) and compares that JSON to the output of `generate` from `deeplink_config.yaml`. It does not compare against local files or Apple CDN.

## Apple CDN

```bash
dart run deeplink_setup:deeplink_setup check-cdn
```

This compares the public origin AASA with Apple's observable CDN representation.

The tool does NOT clear Apple CDN cache and does not promise a fixed propagation time.

## Doctor

```bash
dart run deeplink_setup:deeplink_setup doctor
```

Runs local validation, live origin vs config, then origin vs Apple CDN. A CDN mismatch is a warning (cache delay); this CLI cannot clear Apple's cache.

## Development testing

`test-live` validates the origin directly and prints the URLs that should be used for development verification. It does not claim to bypass undocumented Apple CDN behavior.

```bash
dart run deeplink_setup:deeplink_setup test-live
```

## Android / iOS project configuration

```bash
dart run deeplink_setup:deeplink_setup configure
```

This performs conservative, marker-based changes where possible:

- AndroidManifest: inserts an `android:autoVerify="true"` intent-filter on `.MainActivity` (or the launcher activity). It does **not** put the filter on `<application>`.
- iOS: adds `applinks:` to an existing `.entitlements` file, or creates `ios/Runner/Runner.entitlements` and sets `CODE_SIGN_ENTITLEMENTS` in the Xcode project when that is safe.

Backups use the `.deeplink_setup.bak` suffix. Always review the git diff after running it.

## Recommended real-project workflow

```text
1. init
2. review deeplink_config.yaml
3. generate
4. configure
5. validate --local
6. deploy .well-known
7. validate --live
8. check-cdn
9. doctor
```

For CI:

```bash
dart run deeplink_setup:deeplink_setup validate --local
dart run deeplink_setup:deeplink_setup validate --live
```

## Important limitation

Apple's exact CDN invalidation behavior is not a controllable API exposed by this tool. A CDN/origin mismatch is reported as a diagnostic, not as a guaranteed timing prediction.
