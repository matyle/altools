#!/bin/sh
# Altools stream plugin: runs until Altools stops it. Each line printed is applied at once;
# this one only ever prints alerts, so it has no UI. Contract: PLUGINS.md › Stream plugins.
url="${ALTOOLS_SETTING_URL:-https://github.com}"
every="${ALTOOLS_SETTING_EVERY:-30}"
last=""
while true; do
  code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$url")
  if [ "$code" -ge 200 ] 2>/dev/null && [ "$code" -lt 400 ]; then state=up; else state=down; fi
  if [ -n "$last" ] && [ "$state" != "$last" ]; then
    if [ "$state" = down ]; then
      printf '{"alerts": [{"id": "down-%s", "title": "%s is down", "body": "HTTP %s", "symbol": "exclamationmark.triangle.fill", "tint": "#E06C75", "action": {"open": "%s"}}]}\n' \
        "$(date +%s)" "$url" "$code" "$url"
    else
      printf '{"alerts": [{"id": "up-%s", "title": "%s is back", "body": "HTTP %s", "symbol": "checkmark.circle.fill", "tint": "#98C379", "action": {"open": "%s"}}]}\n' \
        "$(date +%s)" "$url" "$code" "$url"
    fi
  fi
  last=$state
  sleep "$every"
done
