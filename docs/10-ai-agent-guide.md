# Step 10 — AI Agent Guide

Before changing a feature:
1. Read README.
2. Read `docs/02-architecture.md`.
3. Read the feature document.
4. Inspect tests.

Then:
1. update/add tests
2. implement
3. `dart format .`
4. `dart analyze`
5. `dart test`
6. update documentation/progress

Do not silently change public CLI behavior.

Do not invent undocumented Apple CDN guarantees. Typical refresh may be described as a few hours up to 24 hours, rarely several days (TTL). Never present that as an official Apple SLA.
