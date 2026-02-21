#!/usr/bin/env bash
# make_regular_bookings.sh — Book a laundry/facility slot at ELS Boka Direkt
#
# Navigates the booking calendar, finds the first free occurrence of the
# requested day + time on the chosen terminal, and books it.
#
# ─────────────────────────────────────────────────────────────────────
# USAGE
# ─────────────────────────────────────────────────────────────────────
#   ./make_regular_bookings.sh
#
# Reads weekly_desired_bookings and credentials from config.yaml.
#
# ─────────────────────────────────────────────────────────────────────
# OUTPUT
# ─────────────────────────────────────────────────────────────────────
#   stdout: JSON  {"status":"ok","booked":"...","remaining_bookings":"..."}
#           or    {"error":"..."}
#   stderr: human-readable progress messages
#   exit 0 on success, 1 on error
#
# ─────────────────────────────────────────────────────────────────────
# CALENDAR GRID REFERENCE
# ─────────────────────────────────────────────────────────────────────
#   Day index is computed relative to today (0 = today).
#   Slot index is derived from the facility’s slots list in config.yaml.
#   Cell ID format: "DAY_IDX,SLOT_IDX,1,"
#
# ─────────────────────────────────────────────────────────────────────
# TERMINAL / PRECHOICE MAPPING
# ─────────────────────────────────────────────────────────────────────
#   Controls are loaded from config.yaml facilities.

set -euo pipefail

# ── Config-driven inputs ─────────────────────────────────────────────
DAY="" ; TIME="" ; TERMINAL=""
USERNAME="" ; PASSWORD="" ; MAX_WEEKS=""

# ── Config ───────────────────────────────────────────────────────────
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFIG_FILE="${SCRIPT_DIR}/../config.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Missing config.yaml at ${CONFIG_FILE}." >&2
  exit 1
fi

read_config_value() {
  local key="$1"
  sed -n "s/^${key}:[[:space:]]*\"\(.*\)\"[[:space:]]*$/\1/p" "$CONFIG_FILE" | head -1
}

get_section_value() {
  local section="$1" key="$2"
  awk -v s="$section" -v k="$key" '
    $0 ~ "^"s":[[:space:]]*$" {in_sec=1; next}
    in_sec && $0 ~ /^[^[:space:]]/ {in_sec=0}
    in_sec && $1 == k":" {
      $1=""; sub(/^ /,"",$0); gsub(/"/,"",$0); print $0; exit
    }
  ' "$CONFIG_FILE"
}

BASE_URL=$(read_config_value "base_url")
CFG_USER=$(read_config_value "user")
CFG_PASS=$(read_config_value "password")

if [ -z "$BASE_URL" ] || [ -z "$CFG_USER" ] || [ -z "$CFG_PASS" ]; then
  echo "ERROR: config.yaml must define quoted 'base_url', 'user', and 'password' values." >&2
  exit 1
fi

[ -z "$USERNAME" ] && USERNAME="$CFG_USER"
[ -z "$PASSWORD" ] && PASSWORD="$CFG_PASS"
[ -z "$MAX_WEEKS" ] && MAX_WEEKS="8"

get_weekly_desired() {
  awk '
    BEGIN{in_sec=0; seen=0}
    /^weekly_desired_bookings:/ {in_sec=1; next}
    in_sec && $0 ~ /^  - / {seen=1}
    in_sec && seen && $0 ~ /^[^[:space:]]/ {exit}
    in_sec && seen {
      if ($0 ~ /facility:/) {gsub(/^ +-[[:space:]]*facility: "/, "", $0); gsub(/^ +facility: "/, "", $0); gsub(/"$/, "", $0); print "facility=" $0}
      if ($0 ~ /time:/) {gsub(/^ +time: "/, "", $0); gsub(/"$/, "", $0); print "time=" $0}
      if ($0 ~ /days:/) {gsub(/^ +days: \[/, "", $0); gsub(/\].*$/, "", $0); gsub(/"/, "", $0); gsub(/,/, " ", $0); print "days=" $0}
    }
  ' "$CONFIG_FILE"
}

while IFS='=' read -r k v; do
  case "$k" in
    facility) [ -z "$TERMINAL" ] && TERMINAL="$v" ;;
    time) [ -z "$TIME" ] && TIME="$v" ;;
    days) if [ -z "$DAY" ]; then for d in $v; do DAY="$d"; break; done; fi ;;
  esac
done < <(get_weekly_desired)

if [[ -z "$DAY" || -z "$TIME" || -z "$TERMINAL" ]]; then
  echo "ERROR: weekly_desired_bookings must include facility, days, and time in config.yaml." >&2
  exit 1
fi

# ── Map day → grid index (0 = today) ─────────────────────────────────
day_to_u() {
  case "$1" in
    mon|mån) echo 1 ;;
    tue|tis) echo 2 ;;
    wed|ons) echo 3 ;;
    thu|tor) echo 4 ;;
    fri|fre) echo 5 ;;
    sat|lör) echo 6 ;;
    sun|sön) echo 7 ;;
    *) echo "" ;;
  esac
}

DAY_KEY=$(echo "$DAY" | tr '[:upper:]' '[:lower:]')
TARGET_U=$(day_to_u "$DAY_KEY")
if [ -z "$TARGET_U" ]; then
  echo "Invalid day: $DAY (use: mon tue wed thu fri sat sun or Swedish: mån tis ons tor fre lör sön)" >&2
  exit 1
fi

TODAY_U=$(date +%u)
DAY_IDX=$(( (TARGET_U - TODAY_U + 7) % 7 ))

normalize_time() {
  local t="$1"
  if [[ "$t" =~ ^[0-9]{1,2}$ ]]; then
    printf "%02d:00" "$t"
  elif [[ "$t" =~ ^[0-9]{1,2}:[0-9]{2}$ ]]; then
    printf "%02d:%02d" "${t%:*}" "${t#*:}"
  else
    echo ""
  fi
}

TIME_NORM=$(normalize_time "$TIME")
if [ -z "$TIME_NORM" ]; then
  echo "Invalid time: $TIME (use: 0 4 7 10 13 16 19 22 or HH:MM)" >&2
  exit 1
fi

FACILITY_NAME="$TERMINAL"

get_facility_field() {
  local name="$1" field="$2"
  awk -v n="$name" -v f="$field" '
    $0 ~ /^  - name: / {
      in_fac=0
      gsub(/^[[:space:]]*- name: "/, "", $0)
      gsub(/"$/, "", $0)
      if ($0 == n) in_fac=1
    }
    in_fac && $0 ~ "^    "f": " {
      gsub(/^    [^:]+: "/, "", $0)
      gsub(/"$/, "", $0)
      print $0
      exit
    }
  ' "$CONFIG_FILE"
}

TERM_CTL=$(get_facility_field "$FACILITY_NAME" "terminal_ctl")
PREC_CTL=$(get_facility_field "$FACILITY_NAME" "prechoice_ctl")
TERM_LABEL="$FACILITY_NAME"

if [ -z "$TERM_CTL" ] || [ -z "$PREC_CTL" ]; then
  echo "Invalid terminal/facility: $TERMINAL (not found in config.yaml facilities)" >&2
  exit 1
fi

SLOTS=$(awk -v n="$FACILITY_NAME" '
  $0 ~ /^  - name: / {
    in_fac=0
    gsub(/^[[:space:]]*- name: "/, "", $0)
    gsub(/"$/, "", $0)
    if ($0 == n) in_fac=1
  }
  in_fac && $0 ~ /^      - / {
    gsub(/^      - "/, "", $0)
    gsub(/"$/, "", $0)
    print $0
  }
' "$CONFIG_FILE")

SLOT_IDX=""
idx=0
while read -r slot; do
  [ -z "$slot" ] && continue
  idx=$((idx + 1))
  if [ "${slot%%-*}" = "$TIME_NORM" ]; then
    SLOT_IDX=$idx
    break
  fi
done <<< "$SLOTS"

if [ -z "$SLOT_IDX" ]; then
  echo "Invalid time for facility '$FACILITY_NAME'. Available slots:" >&2
  echo "$SLOTS" >&2
  exit 1
fi

CELL_ID_FMT="{day},{slot},1,"
BOOKPASS_PREFIX="BookPass"
CELL_ID="${CELL_ID_FMT//\{day\}/$DAY_IDX}"
CELL_ID="${CELL_ID//\{slot\}/$SLOT_IDX}"

# ── URLs ──────────────────────────────────────────────────────────────
LOGIN_URL="${BASE_URL}/Default.aspx"
TERMINAL_URL="${BASE_URL}/Booking/TerminalSelector.aspx"
BOOKING_MAIN="${BASE_URL}/Booking/BookingMain.aspx"
PRECHOICES_URL="${BASE_URL}/Booking/Prechoices.aspx"
CALENDAR_URL="${BASE_URL}/Booking/BookingCalendar.aspx"
COOKIE_JAR=$(mktemp /tmp/els_cookies.XXXXXX)
trap "rm -f '$COOKIE_JAR'" EXIT

# ── Helpers ───────────────────────────────────────────────────────────
extract_tokens() {
  VS=$(echo "$1" | sed -n 's/.*name="__VIEWSTATE".*value="\([^"]*\)".*/\1/p' | head -1)
  VG=$(echo "$1" | sed -n 's/.*name="__VIEWSTATEGENERATOR".*value="\([^"]*\)".*/\1/p' | head -1)
  EV=$(echo "$1" | sed -n 's/.*name="__EVENTVALIDATION".*value="\([^"]*\)".*/\1/p' | head -1)
}

aspnet_post() {
  local url="$1" target="$2" html="$3"; shift 3
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

die() { printf '{"error":"%s"}\n' "$1"; exit 1; }

# ── Step 1: Login ─────────────────────────────────────────────────────
echo "Logging in as ${USERNAME}..." >&2
PAGE=$(curl -s -c "$COOKIE_JAR" "$LOGIN_URL")
RESP=$(aspnet_post "$LOGIN_URL" 'ctl00$ContentPlaceHolder1$btOK' "$PAGE" \
  --data-urlencode "ctl00\$ContentPlaceHolder1\$tbUsername=${USERNAME}" \
  --data-urlencode "ctl00\$ContentPlaceHolder1\$tbPassword=${PASSWORD}")
echo "$RESP" | grep -q 'dgTerminaler' || die "Login failed"
echo "Login OK." >&2

# ── Step 2: Select terminal ──────────────────────────────────────────
echo "Selecting ${TERM_LABEL}..." >&2
RESP2=$(aspnet_post "$TERMINAL_URL" "$TERM_CTL" "$RESP")
echo "$RESP2" | grep -q 'DataGridBookings' || die "Terminal selection failed"

# ── Step 3: Navigate to booking calendar ──────────────────────────────
RESP3=$(aspnet_post "$BOOKING_MAIN" 'ctl00$LinkBooking' "$RESP2")
CAL=$(aspnet_post "$PRECHOICES_URL" "$PREC_CTL" "$RESP3")

# ── Step 4: Find free slot ────────────────────────────────────────────
echo "Looking for free ${DAY} ${TIME}:00 slot at ${TERM_LABEL} (max ${MAX_WEEKS} weeks)..." >&2
FOUND=false
for i in $(seq 1 "$MAX_WEEKS"); do
  SLOT_HTML=$(echo "$CAL" | perl -0777 -ne "while (/<input[^>]*id=\"${CELL_ID}\"[^>]*\/>/g) { print \"$&\n\" }")
  SLOT_TITLE=$(echo "$SLOT_HTML" | sed -n 's/.*title="\([^"]*\)".*/\1/p')

  if echo "$SLOT_HTML" | grep -q 'onclick'; then
    echo "Found free slot (week +${i}): ${SLOT_TITLE}" >&2
    FOUND=true
    break
  fi
  echo "Week +${i}: ${SLOT_TITLE:-slot not on page} — skipping" >&2
  CAL=$(aspnet_post "$CALENDAR_URL" \
    'ctl00$ContentPlaceHolder1$btCalendarNext' "$CAL")
done

$FOUND || die "No free slot found within ${MAX_WEEKS} weeks"

# ── Step 5: Book ──────────────────────────────────────────────────────
echo "Booking..." >&2
extract_tokens "$CAL"
BOOK_RESP=$(curl -s -L -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  --data-urlencode "__EVENTTARGET=${BOOKPASS_PREFIX}${CELL_ID}" \
  --data-urlencode "__EVENTARGUMENT=${CELL_ID}" \
  --data-urlencode "__VIEWSTATE=${VS}" \
  --data-urlencode "__VIEWSTATEGENERATOR=${VG}" \
  --data-urlencode "__EVENTVALIDATION=${EV}" \
  --data-urlencode "ctl00\$MessageType=ERROR" \
  "$CALENDAR_URL")

# ── Step 6: Parse confirmation ────────────────────────────────────────
CONFIRMATION=$(echo "$BOOK_RESP" | sed 's/<[^>]*>//g; s/&nbsp;/ /g' | tr -s '[:space:]' ' ')

if echo "$CONFIRMATION" | grep -q 'Bokning OK'; then
  BOOKED_INFO=$(echo "$CONFIRMATION" | perl -ne 'if (/Du har bokat\s+(.*?)(?=\s*Du har \d)/) { print $1 }' | sed 's/ *$//')
  REMAINING=$(echo "$CONFIRMATION" | perl -ne 'if (/(\d+ bokningar kvar)/) { print $1 }')
  [ -z "$BOOKED_INFO" ] && BOOKED_INFO="unknown"
  [ -z "$REMAINING" ] && REMAINING="unknown"

  printf '{"status":"ok","booked":"%s","remaining_bookings":"%s","checked_at":"%s"}\n' \
    "$BOOKED_INFO" "$REMAINING" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
elif echo "$CONFIRMATION" | grep -q 'Inga fler bokningar'; then
  die "Booking limit reached (Inga fler bokningar möjliga)"
else
  ERROR_MSG=$(echo "$CONFIRMATION" | perl -ne 'if (/(Bokning|Fel|Error|Inga)[^.]*\./) { print $& }' | head -1)
  die "${ERROR_MSG:-Booking failed (unknown error)}"
fi
