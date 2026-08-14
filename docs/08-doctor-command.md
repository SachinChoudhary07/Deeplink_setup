# Step 08 — Doctor

`doctor` runs:

1. local validation
2. live origin vs generated config
3. Apple CDN vs origin (or `CDN_SKIPPED` when iOS config is incomplete)

CDN cache mismatch is a warning and does not fail the command by itself. Local/live errors still fail (exit 1).

The result is designed for humans first and CI second.
