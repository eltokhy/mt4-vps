#!/bin/bash
# Pulls ForexFactory weekly calendar, filters high-impact USD + XAU events,
# writes broker-time (Europe/Athens, IC Markets server tz) windows the
# Guardrail EA reads.
#
# Output format (one event per line, parsed by MT4 FileReadString loop):
#   YYYY.MM.DD HH:MM | IMPACT | CURRENCY | TITLE
# Example:
#   2026.05.02 15:30 | high | USD | Non-Farm Employment Change

set -eu

FEED_URL="${FEED_URL:-https://nfs.faireconomy.media/ff_calendar_thisweek.json}"
OUT_DIR="${OUT_DIR:-/news}"
OUT_FILE="$OUT_DIR/news_calendar.txt"
BROKER_TZ="${BROKER_TZ:-Europe/Athens}"
IMPACT_FILTER="${IMPACT_FILTER:-High}"
CURRENCY_FILTER="${CURRENCY_FILTER:-USD|XAU}"

mkdir -p "$OUT_DIR"
TMP=$(mktemp)
trap "rm -f $TMP" EXIT

echo "[$(date -u '+%FT%TZ')] fetching $FEED_URL" >&2
if ! curl -fsSL --max-time 30 "$FEED_URL" -o "$TMP"; then
    echo "fetch failed; keeping previous calendar" >&2
    exit 0
fi

jq -r --arg impact "$IMPACT_FILTER" --arg ccy "$CURRENCY_FILTER" '
    .[] | select(.impact == $impact) | select(.country | test($ccy; "i")) |
    "\(.date)|\(.time)|\(.impact)|\(.country)|\(.title)"
' "$TMP" | while IFS='|' read -r date time impact country title; do
    # ForexFactory time is US Eastern; convert to broker tz (Europe/Athens).
    # Fields sample: date="2026-05-02", time="8:30am" or "All Day"
    if [ -z "$time" ] || [ "$time" = "All Day" ] || [ "$time" = "Tentative" ]; then
        continue
    fi
    iso=$(TZ=America/New_York date -d "$date $time" -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || continue)
    broker=$(TZ="$BROKER_TZ" date -d "$iso" '+%Y.%m.%d %H:%M' 2>/dev/null || continue)
    printf '%s | %s | %s | %s\n' "$broker" "$impact" "$country" "$title"
done | sort -u > "$OUT_FILE.tmp"

mv "$OUT_FILE.tmp" "$OUT_FILE"
wc -l "$OUT_FILE" >&2
