#!/usr/bin/env bash

# check_bookings.sh — Log into ELS Boka Direkt and display current bookings
# Always selects "Tvättstuga 2 Fristående / Föreningslokal" terminal.
#
# Usage: ./check_bookings.sh
# Reads credentials from ../config.yaml

set -euo pipefail

LOGIN_PATH="/Default.aspx"
TERMINAL_PATH="/Booking/TerminalSelector.aspx"
TERMINAL_CTL='ctl00$ContentPlaceHolder1$dgTerminaler$ctl04$ctl00'

COOKIE_JAR=$(mktemp /tmp/els_cookies.XXXXXX)
trap "rm -f '$COOKIE_JAR'" EXIT

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFIG_FILE="${SCRIPT_DIR}/../config.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Missing config.yaml at ${CONFIG_FILE}" >&2
  exit 1
fi

read_config_value() {
  local key="$1"
  sed -n "s/^${key}:[[:space:]]*\"\(.*\)\"[[:space:]]*$/\1/p" "$CONFIG_FILE" | head -1
}

BASE_URL=$(read_config_value "base_url")
USERNAME=$(read_config_value "user")
PASSWORD=$(read_config_value "password")

if [ -z "$BASE_URL" ] || [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
  echo "ERROR: config.yaml must define quoted 'base_url', 'user', and 'password' values." >&2
  exit 1
fi

LOGIN_URL="${BASE_URL}${LOGIN_PATH}"
TERMINAL_URL="${BASE_URL}${TERMINAL_PATH}"

extract_tokens() {
  VS=$(echo "$1" | sed -n 's/.*name="__VIEWSTATE".*value="\([^"]*\)".*/\1/p' | head -1)
  VG=$(echo "$1" | sed -n 's/.*name="__VIEWSTATEGENERATOR".*value="\([^"]*\)".*/\1/p' | head -1)
  EV=$(echo "$1" | sed -n 's/.*name="__EVENTVALIDATION".*value="\([^"]*\)".*/\1/p' | head -1)
}

aspnet_post() {
  local url="$1" target="$2" html="$3"
  shift 3
  extract_tokens "$html"
  curl -s -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    --data-urlencode "__EVENTTARGET=${target}" \
    --data-urlencode "__EVENTARGUMENT=" \
    --data-urlencode "__VIEWSTATE=${VS}" \
    --data-urlencode "__VIEWSTATEGENERATOR=${VG}" \
    --data-urlencode "__EVENTVALIDATION=${EV}" \
    --data-urlencode "ctl00\$MessageType=ERROR" \
    "$@" "$url"
}

# --- Step 1: Login ---
echo "Logging in as ${USERNAME}..." >&2
PAGE=$(curl -s -c "$COOKIE_JAR" "$LOGIN_URL")
RESP=$(aspnet_post "$LOGIN_URL" 'ctl00$ContentPlaceHolder1$btOK' "$PAGE" \
  --data-urlencode "ctl00\$ContentPlaceHolder1\$tbUsername=${USERNAME}" \
  --data-urlencode "ctl00\$ContentPlaceHolder1\$tbPassword=${PASSWORD}")

if ! echo "$RESP" | grep -q 'dgTerminaler'; then
  echo "ERROR: Login failed. Check credentials." >&2
  exit 1
fi

echo "Login OK." >&2

# --- Step 2: Select Tvättstuga 2 ---
RESP2=$(aspnet_post "$TERMINAL_URL" "$TERMINAL_CTL" "$RESP")
if ! echo "$RESP2" | grep -q 'DataGridBookings'; then
  echo "ERROR: Terminal selection failed." >&2
  exit 1
fi

# --- Step 3: Parse bookings as JSON ---
BOOKINGS_HTML=$(echo "$RESP2" | perl -0777 -ne 'if (/<table[^>]*DataGridBookings.*?<\/table>/s) { print $& }')

ITEMS=""
if [ -n "$BOOKINGS_HTML" ] && echo "$BOOKINGS_HTML" | grep -q '<td'; then
  ITEMS=$(echo "$BOOKINGS_HTML" | perl -0777 -ne '
    while (/<tr[^>]*>.*?<\/tr>/sg) {
      my $row = $&;
      my @t = $row =~ /<td[^>]*>(.*?)<\/td>/sg;
      @t = map {
        my $x = $_;
        $x =~ s/<[^>]+>//g;
        $x =~ s/&nbsp;/ /g;
        $x =~ s/\s+/ /g;
        $x =~ s/^\s+|\s+$//g;
        $x;
      } @t;
      next if @t < 4;
      print join("\t", @t[0..3]), "\n";
    }
  ' | while IFS=$'\t' read -r date location start end; do
    [ -z "$date" ] && continue
    printf '{"date":"%s","location":"%s","start":"%s","end":"%s"}\n' \
      "$date" "$location" "$start" "$end"
  done | paste -sd ',' -)
fi

printf '{"checked_at":"%s","user":"%s","bookings":[%s]}\n' \
  "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$USERNAME" "$ITEMS"
