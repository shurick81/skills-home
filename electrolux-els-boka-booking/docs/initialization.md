# Initialization

## Purpose
Prepare config.yaml with the correct login credentials for the specific user.

## Steps
1. If config.yaml does not exist, create it in the skill root.
2. Set quoted values for `base_url`, `user`, and `password`.
3. Run the credential check script to confirm the login works:

scripts/check_credentials.sh

4. Run the initialization script to list available facilities and store them in config.yaml:

scripts/init_terminals.sh

5. Ask the user for their preferred facility, booking weekdays, and time, then store it in config.yaml under `weekly_desired_bookings`.

Example:

base_url: "https://example.portal/M5WebBokning"
user: "example-user"
password: "example-password"

weekly_desired_bookings:
	- facility: "Tvättstuga 2 Fristående"
		days: ["thu"]
		time: "10:00"

## Requirements
- config.yaml must exist in the skill root.
- config.yaml must contain `base_url`, `user`, and `password` keys.
- Values must be quoted.
- The initialization script must be run to populate the `facilities` list in config.yaml, including slot titles per facility.
- The preferred booking settings must be stored under `weekly_desired_bookings`.

## Rerun behavior
- You can rerun the credential check and facility initialization at any time.
- Re-running the facility initialization replaces the existing `facilities` list in config.yaml.
