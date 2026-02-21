#!/usr/bin/env bash

# init_terminals.sh — Fetch available terminals and store them in config.yaml
# Requires valid user/password in config.yaml

set -euo pipefail

LOGIN_PATH="/Default.aspx"
TERMINAL_PATH="/Booking/TerminalSelector.aspx"
BOOKING_MAIN_PATH="/Booking/BookingMain.aspx"
PRECHOICES_PATH="/Booking/Prechoices.aspx"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFIG_FILE="${SCRIPT_DIR}/../config.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Missing config.yaml at ${CONFIG_FILE}. Create it first." >&2
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
BOOKING_MAIN_URL="${BASE_URL}${BOOKING_MAIN_PATH}"
PRECHOICES_URL="${BASE_URL}${PRECHOICES_PATH}"

COOKIE_JAR=$(mktemp /tmp/els_cookies.XXXXXX)
trap "rm -f '$COOKIE_JAR'" EXIT

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
  echo "ERROR: Login failed or terminal list missing." >&2
  exit 1
fi

echo "Login OK. Extracting terminals..." >&2

TERMINAL_ITEMS=()
FACILITY_ITEMS=()
while read -r item; do
  [ -z "$item" ] && continue
  name=${item%%|*}
  ctl=${item#*|}
  if [ -n "$ctl" ] && [ -n "$name" ]; then
    TERMINAL_ITEMS+=("$name|$ctl")
  fi
done < <(echo "$RESP" | perl -0777 -ne '
  while (/__doPostBack\(&#39;([^&]*dgTerminaler[^&]*)&#39;[^>]*>.*?<font[^>]*>([^<]+)<\/font>/sg) {
    print "$2|$1\n";
  }
  while (/__doPostBack\(\x27([^\x27]*dgTerminaler[^\x27]*)\x27[^>]*>.*?<font[^>]*>([^<]+)<\/font>/sg) {
    print "$2|$1\n";
  }
')

if [ ${#TERMINAL_ITEMS[@]} -eq 0 ]; then
  echo "ERROR: No terminals parsed. The portal markup may have changed." >&2
  exit 1
fi

# For each terminal, open booking page and parse facilities (prechoices).
for item in "${TERMINAL_ITEMS[@]}"; do
  term_name=${item%%|*}
  term_ctl=${item#*|}

  RESP_T=$(aspnet_post "$TERMINAL_URL" "$term_ctl" "$RESP")
  RESP_B=$(aspnet_post "$BOOKING_MAIN_URL" 'ctl00$LinkBooking' "$RESP_T")

  while read -r entry; do
    [ -z "$entry" ] && continue
    fac_name=${entry%%|*}
    fac_ctl=${entry#*|}
    FACILITY_ITEMS+=("$fac_name|$term_ctl|$fac_ctl")
  done < <(echo "$RESP_B" | perl -0777 -ne '
    while (/__doPostBack\(&#39;([^&]*dgForval[^&]*)&#39;[^>]*>.*?<font[^>]*>([^<]+)<\/font>/sg) {
      print "$2|$1\n";
    }
    while (/__doPostBack\(\x27([^\x27]*dgForval[^\x27]*)\x27[^>]*>.*?<font[^>]*>([^<]+)<\/font>/sg) {
      print "$2|$1\n";
    }
  ')
done

# Remove existing terminals/facilities blocks if present, then append updated list.
TMP_FILE=$(mktemp)
awk '
  BEGIN{skip=0}
  /^terminals:[[:space:]]*$/ {skip=1; next}
  /^facilities:[[:space:]]*$/ {skip=1; next}
  skip==1 {
    if ($0 ~ /^[^[:space:]]/) {skip=0}
    else {next}
  }
  skip==0 {print}
' "$CONFIG_FILE" > "$TMP_FILE"

if [ ${#FACILITY_ITEMS[@]} -gt 0 ]; then
  echo "facilities:" >> "$TMP_FILE"
  printf "%s\n" "${FACILITY_ITEMS[@]}" | awk -F'|' '!seen[$1]++' | while read -r item; do
    fac_name=${item%%|*}
    rest=${item#*|}
    term_ctl=${rest%%|*}
    fac_ctl=${rest#*|}
    fac_name=${fac_name//"/\\"}
    term_ctl=${term_ctl//"/\\"}
    fac_ctl=${fac_ctl//"/\\"}

    # Fetch calendar to extract day names and slot times for this facility.
    RESP_T=$(aspnet_post "$TERMINAL_URL" "$term_ctl" "$RESP")
    RESP_B=$(aspnet_post "$BOOKING_MAIN_URL" 'ctl00$LinkBooking' "$RESP_T")
    CAL=$(aspnet_post "$PRECHOICES_URL" "$fac_ctl" "$RESP_B")

    SLOTS=$(echo "$CAL" | tr -d '\r\n' | perl -ne 'while (/id="0,\d+,1,"[^>]*title="([^"]*)"/g) { print "$1\n" }')

    printf '  - name: "%s"\n' "$fac_name" >> "$TMP_FILE"
    printf '    terminal_ctl: "%s"\n' "$term_ctl" >> "$TMP_FILE"
    printf '    prechoice_ctl: "%s"\n' "$fac_ctl" >> "$TMP_FILE"
    if [ -z "$SLOTS" ]; then
      printf '    slots: []\n' >> "$TMP_FILE"
    else
      printf '    slots:\n' >> "$TMP_FILE"
      while read -r s; do
        [ -n "$s" ] && printf '      - "%s"\n' "$s" >> "$TMP_FILE"
      done <<< "$SLOTS"
    fi
    echo "" >> "$TMP_FILE"
  done
fi

mv "$TMP_FILE" "$CONFIG_FILE"

echo "Updated config.yaml with ${#FACILITY_ITEMS[@]} facilities." >&2
