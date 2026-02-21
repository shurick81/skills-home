---
name: washing-bookings
description: Query current Sjötungan laundry bookings (Tvättstuga 2) via the check_bookings.sh CLI and config.yaml. The agent must ensure config.yaml contains login arguments: user and password (in quotes). Use whenever Aleks or Nat asks “when is our next washing time?” or needs a summary of existing bookings pulled directly from ELS Boka Direkt.
---

# Washing Bookings

## Documents
- [docs/initialization.md](docs/initialization.md) — Set up config.yaml, verify credentials, and populate facilities with slot metadata.
- [docs/checking-bookings.md](docs/checking-bookings.md) — Fetch current bookings and summarize results.
- [docs/regular-bookings.md](docs/regular-bookings.md) — Book recurring weekly slots based on weekly_desired_bookings in config.yaml.
