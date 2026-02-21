# Regular bookings

## Purpose
Book a recurring weekly slot using the preferences defined in config.yaml.

## Prerequisites
- config.yaml must include `weekly_desired_bookings` with `facility`, `days`, and `time`.
- `facilities` must be populated by running the initialization script.

## Steps
1. Review weekly_desired_bookings in config.yaml and update as needed.
2. Run the booking script (no arguments required; it reads config.yaml):

scripts/make_regular_bookings.sh

## Notes
- The script uses the first entry in weekly_desired_bookings.
- Day index is computed relative to today (0 = today).
- If the portal returns a booking limit error, no booking is made.
