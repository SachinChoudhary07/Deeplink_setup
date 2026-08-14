# Implementation Progress

- [x] CLI scaffold
- [x] config parser
- [x] generation
- [x] local validation
- [x] live validation
- [x] Apple CDN comparison
- [x] doctor
- [x] init/project detection
- [x] Android applicationId detection
- [x] debug SHA-256 detection
- [x] iOS bundle ID detection
- [x] safe AndroidManifest configuration with backup
- [x] safe iOS entitlements configuration with backup
- [x] test-live origin verification
- [x] feature documentation
- [x] initial tests

## Hardening

- [x] Slice 1: platform-optional generate + SHA-256 normalization
- [x] Slice 2: Windows SHA / project detect
- [x] Slice 3: safe configure (activity-level App Links + iOS entitlements)
- [x] Slice 4: local validation
- [x] Slice 5: live validation with origin vs generated compare (no redirects)
- [x] Slice 6: CDN diagnostics + doctor

## Known engineering boundary

Automatic signing-certificate discovery is environment-dependent. The detector looks up the Android debug keystore under the project, `HOME`, and Windows `USERPROFILE`. If `keytool` is missing it reports `KEYTOOL_NOT_FOUND` as a warning and still writes `deeplink_config.yaml`. Production/release fingerprints should normally be supplied explicitly in that file.
