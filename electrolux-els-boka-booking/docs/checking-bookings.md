# Checking the bookings

## Purpose
Fetch and summarize the current bookings for "Tvättstuga 2 Fristående / Föreningslokal" from the Sjötungan ELS Boka Direkt portal.

## Steps
1. Ensure config.yaml is prepared per the initialization guide.
2. Run the script:

scripts/check_bookings.sh

3. Validate success:
- Look for "Login OK." in stderr; failures print "ERROR: ..." and exit non-zero.
- An empty bookings array is valid (no upcoming slots).

4. Summarize for the user:
- Convert Swedish day labels (e.g., “Torsdag 26 Feb”) into natural English where helpful.
- Mention the next upcoming slot first, then list the rest if multiple exist.
- Always include the booking window (start–end) and location (currently always Tvättstuga 2, but keep wording flexible).

5. Note timestamps:
- `checked_at` is UTC. When comparing with local expectations, convert to Stockholm time if relevant (“Checked just now (09:42 local)”).

## Troubleshooting
- **Login failed:** confirm username/password and that the account is not locked.
- **Terminal selection failed:** the DOM structure may have changed—inspect the portal manually and update `TERMINAL_CTL` in the script if needed.
- **HTML parsing returns nothing:** site markup changes can break the regex scrapes. Dump `RESP2` to a temp file, inspect, and patch the selectors.
