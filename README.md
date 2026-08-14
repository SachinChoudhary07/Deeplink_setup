# deeplink_setup

A Dart CLI that sets up and checks **Android App Links** and **iOS Universal Links** for Flutter apps.

Deep links fail when the app, the website, and (on iOS) Apple’s cache disagree. This tool generates the website files, edits Android/iOS project settings safely, and tells you what is wrong — including when Apple is still serving an old AASA file (you cannot clear that cache yourself).

## Install

In your Flutter app `pubspec.yaml`:

```yaml
dev_dependencies:
  deeplink_setup:
    git:
      url: https://github.com/SachinChoudhary07/Deeplink_setup.git
      ref: main
```

```bash
flutter pub get
dart run deeplink_setup:deeplink_setup --help
```

## Quick start

Run these from the **root of your Flutter app** (the folder that contains `pubspec.yaml`).

```bash
# 1. Detect package / SHA / bundle ID and create deeplink_config.yaml
dart run deeplink_setup:deeplink_setup init --domain your-domain.com

# 2. Open deeplink_config.yaml and fill any YOUR_TEAM_ID / SHA placeholders
# 3. Write website association files into .well-known/
dart run deeplink_setup:deeplink_setup generate

# 4. Add App Links / Associated Domains to the Android and iOS projects
dart run deeplink_setup:deeplink_setup configure

# 5. Confirm local files match the config
dart run deeplink_setup:deeplink_setup validate --local
```

Then upload `.well-known/assetlinks.json` and `.well-known/apple-app-site-association` to your **website** (backend, CDN, or static host) at:

```text
https://your-domain.com/.well-known/assetlinks.json
https://your-domain.com/.well-known/apple-app-site-association
```

Those URLs must be public HTTPS, return **200**, and **must not redirect**. Then:

```bash
dart run deeplink_setup:deeplink_setup validate --live
dart run deeplink_setup:deeplink_setup check-cdn
dart run deeplink_setup:deeplink_setup doctor
```

## What each command does

| Command | What it does |
| --- | --- |
| `init --domain example.com` | Scans the Flutter project and writes `deeplink_config.yaml`. Missing `keytool` or iOS Team ID is a **warning**; the file is still created. |
| `generate` | Writes `.well-known/assetlinks.json` (Android) and `apple-app-site-association` (iOS). These belong on the **server**, not inside the app binary. |
| `configure` | Edits AndroidManifest (intent-filter on **MainActivity**) and iOS Associated Domains. Creates `*.deeplink_setup.bak` backups. Review the diff. |
| `validate --local` | Checks the YAML and that local `.well-known` files match `generate`. Exit 1 if something is missing or stale. |
| `validate --live` | Fetches the **live website** URLs (no redirects) and compares JSON to what your YAML would generate. |
| `check-cdn` | Compares your live AASA to **Apple’s CDN copy**. A mismatch is a warning (possible cache delay). This CLI cannot flush Apple’s cache. |
| `test-live` | Same live checks as `validate --live`, plus prints the URLs to open in a browser. |
| `doctor` | Runs local + live + CDN in one command. |

Exit codes: `0` success (warnings allowed), `1` error, `64` bad usage.

## `deeplink_config.yaml`

`init` creates this file. Example:

```yaml
domain: example.com

android:
  package: com.example.app
  sha256: "AA:BB:CC:..."

ios:
  bundle_id: com.example.app
  team_id: ABCDE12345

paths:
  - "/*"
```

| Field | Meaning |
| --- | --- |
| `domain` | Website that will host `.well-known` (no `https://`). |
| `android.package` | App `applicationId` from Gradle. |
| `android.sha256` | Signing certificate fingerprint. Debug can be auto-detected; **Play/release SHA should be pasted by you**. |
| `ios.bundle_id` | iOS bundle identifier. |
| `ios.team_id` | 10-character Apple Team ID (Xcode → Signing, or [Apple Developer](https://developer.apple.com/account) → Membership). Required for Universal Links. |
| `paths` | URL paths the app should open. `/*` means all paths. |

Android-only or iOS-only is fine. If `bundle_id` is set, `team_id` must be set too (use a real Team ID for production; `YOUR_TEAM_ID` is only a placeholder).

## Hosting the files

`generate` does **not** upload anything. Copy the two files from `.well-known/` to your web server so they are reachable at the URLs above.

Common mistakes:

- File is only in the Flutter project, not on the domain → `validate --live` returns **404**
- `http://` or a 301 to `www` → App Links / Universal Links fail (no redirects)
- HTML error page instead of JSON

## Apple CDN (iOS)

iOS devices often read AASA from Apple’s CDN, not directly from your server. After you upload a new file, Apple can keep serving the old one for a while.

- `check-cdn` / `doctor` will warn: origin and CDN differ
- That usually means cache delay
- **There is no API to clear Apple’s cache.** Re-check later. This tool will not invent a 24h/48h SLA.

## Backups from `configure`

`configure` copies originals to `AndroidManifest.xml.deeplink_setup.bak` (and similar for iOS). That is only a safety net so you can compare or revert. You can delete `.bak` files after you review the git diff. They are not needed at runtime.

## CI

```bash
dart run deeplink_setup:deeplink_setup validate --local
dart run deeplink_setup:deeplink_setup validate --live
```

CDN mismatch is a warning, so it does not fail CI by itself.

## Troubleshooting

| What you see | What to do |
| --- | --- |
| `TEAM_ID_NOT_FOUND` / `YOUR_TEAM_ID` | Put the real 10-character Team ID in `ios.team_id`. |
| `keytool was not found` | Install a JDK, or paste `android.sha256` into the YAML. |
| `generate` fails: bundle_id and team_id together | Add `team_id`, or remove the whole `ios:` block for Android-only. |
| Live **404** | Upload `.well-known` to the domain in `deeplink_config.yaml`. Open the `Checked:` URL in a browser. |
| Live **redirect** | Serve the file at that exact path with HTTP 200. |
| `APPLE_CDN_ORIGIN_MISMATCH` | New AASA is on your server; Apple may still be caching the old one. Wait and re-run `check-cdn`. |

## More detail

Feature notes live in [`docs/`](docs/).
