#!/usr/bin/env bash

# check_credentials.sh — Verify that config.yaml user/password can log in

set -euo pipefail

LOGIN_PATH="/Default.aspx"

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

BASE_URL=$(read_config_value "base_url")
USERNAME=$(read_config_value "user")
PASSWORD=$(read_config_value "password")

if [ -z "$BASE_URL" ] || [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
  echo "ERROR: config.yaml must define quoted 'base_url', 'user', and 'password' values." >&2
  exit 1
fi

LOGIN_URL="${BASE_URL}${LOGIN_PATH}"

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
  echo "ERROR: Login failed. Check credentials." >&2
  exit 1
fi

echo "Login OK." >&2
