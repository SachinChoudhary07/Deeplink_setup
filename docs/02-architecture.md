# Step 02 — Architecture

```text
CLI → services → generators / validators / detectors / HTTP
```

Keep business logic out of the executable entry point.

Network clients and process runners (`keytool`) are injectable where tests need them.

Platform mutations are conservative, create backups before editing, and insert Android App Links on an activity (`.MainActivity` / launcher), not on `<application>`.
