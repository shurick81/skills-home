---
name: washing-bookings
description: Manage Sjötungan ELS Boka Direkt laundry bookings using config.yaml. The agent must ensure config.yaml contains quoted login values (base_url, user, password), a populated facilities list, and weekly_desired_bookings. Use to initialize credentials, check bookings, and schedule recurring weekly slots as configured.
---

# Washing Bookings

## Documents
- [docs/initialization.md](docs/initialization.md) — Set up config.yaml, verify credentials, and populate facilities with slot metadata.
- [docs/checking-bookings.md](docs/checking-bookings.md) — Fetch current bookings and summarize results.
- [docs/regular-bookings.md](docs/regular-bookings.md) — Book recurring weekly slots based on weekly_desired_bookings in config.yaml.
