#!/bin/sh
# Altools plugin example; the contract is in PLUGINS.md.
now=$(date +%H:%M)
if [ "$ALTOOLS_EVENT" = "action:greet" ]; then greeting="Hi again"; else greeting="Hello"; fi
if [ "$ALTOOLS_LANG" = "zh" ]; then title="你好"; else title="Hello"; fi
cat <<JSON
{
  "ears": { "symbol": "clock", "text": "$now" },
  "home": { "title": "$title", "rows": [
    { "title": "$greeting", "symbol": "hand.wave", "action": { "run": "greet" } },
    { "title": "Altools on GitHub", "symbol": "link", "action": { "open": "https://github.com/matyle/altools" } }
  ] },
  "tab": { "title": "$title", "sections": [
    { "title": "Actions", "rows": [
      { "title": "$greeting", "subtitle": "run: runs this script again", "symbol": "hand.wave", "action": { "run": "greet" } },
      { "title": "Open the plugin guide", "subtitle": "open: a URL", "symbol": "book", "action": { "open": "https://github.com/matyle/altools/blob/main/PLUGINS.md" } },
      { "title": "Copy the time", "subtitle": "copy: text to the clipboard", "symbol": "doc.on.doc", "value": "$now", "action": { "copy": "$now" } }
    ] }
  ] },
  "alerts": [ { "id": "hello-$(date +%Y-%m-%d)", "title": "Hello from a plugin", "body": "Shown once a day. Edit run.sh to change me." } ]
}
JSON
