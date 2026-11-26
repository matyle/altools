# Altools plugins

**English** · [简体中文](PLUGINS.zh-CN.md)

A plugin puts your own information in the Altools notch: a count beside the notch, a card on Home,
a page under the Plugins tab, and alert cards that drop down. A plugin is a folder with a
`plugin.json` and a program in any language. Altools runs the program on a schedule; the program
prints JSON saying what to show. That is the whole API.

You can write one by hand, ask Claude Code or any other coding agent to write it from this page, or
use **Settings › Notch › Plugins › Make a plugin** and describe what you want.

## Folder

```
~/Library/Application Support/Altools/Plugins/
  ticktick/            ← folder name = plugin id
    plugin.json
    run.py             ← any executable: shell, Python, Node, a compiled binary…
```

Plugins found in the folder start **switched off**: they are programs that run as you, so switch
them on in Settings only if you trust them. Changes to the folder are picked up automatically.

## plugin.json

```json
{
  "id": "ticktick",
  "name": "TickTick",
  "version": "1.0.0",
  "author": "you",
  "description": "Tasks due today",
  "api": 1,
  "icon": "checklist",
  "tint": "#E5C07B",
  "run": "run.py",
  "interval": 300,
  "timeout": 20,
  "slots": ["ears", "home", "tab", "alerts"],
  "settings": [
    { "key": "token", "title": "API token", "type": "secret" },
    { "key": "region", "title": "Region", "type": "choice", "options": ["ticktick.com", "dida365.com"], "default": "dida365.com" }
  ]
}
```

| Field | Meaning |
|---|---|
| `id` | Lowercase letters, digits and dashes. Must equal the folder name. |
| `name`, `version`, `author`, `description` | Shown in Settings. |
| `api` | Plugin API version the plugin was written for. This page describes `1`. |
| `icon` | An [SF Symbol](https://developer.apple.com/sf-symbols/) name. |
| `tint` | `#RRGGBB` accent colour. |
| `run` | Path of the program, relative to the folder. It's made executable if it isn't. |
| `interval` | Seconds between runs, at least 10. Default 300. |
| `timeout` | Seconds a run may take before it's stopped, 1 to 120. Default 20. |
| `slots` | Where output may appear: `ears`, `home`, `tab`, `alerts`. Default all. |
| `settings` | Fields the user fills in under Settings: `type` is `text`, `secret` (kept in the Keychain), `toggle` (`"1"`/`"0"`) or `choice` (with `options`). |

## How a run works

Altools starts the program with the plugin folder as its working directory. Its environment has the
user's PATH (including Homebrew) and proxy, plus:

| Variable | Value |
|---|---|
| `ALTOOLS_API` | `1` |
| `ALTOOLS_EVENT` | `refresh` for a scheduled run, `action:<id>` when the user clicked a `run` action |
| `ALTOOLS_PLUGIN_ID` | The plugin id |
| `ALTOOLS_PLUGIN_DIR` | The plugin folder |
| `ALTOOLS_DATA_DIR` | A writable folder for caches and state, kept across runs |
| `ALTOOLS_LANG` | `en` or `zh` |
| `ALTOOLS_SETTING_<KEY>` | Each setting's value, e.g. `ALTOOLS_SETTING_TOKEN` |

The program prints **one JSON object** on stdout and exits with status 0. Anything printed before
the last line that starts with `{` is ignored, so logging to stdout is harmless; stderr goes to the
plugin's log in Settings. A non-zero exit, invalid JSON or a timeout shows the error in Settings and
on the plugin's card; the notch keeps working.

## Output

Every part is optional, and parts for slots not listed in `slots` are ignored.

```json
{
  "ears": { "symbol": "checklist", "text": "3", "tint": "#E5C07B" },
  "home": {
    "title": "Due today",
    "rows": [ { "title": "Send the invoice", "value": "15:00", "action": { "open": "https://ticktick.com" } } ]
  },
  "tab": {
    "title": "TickTick",
    "sections": [
      { "title": "Work", "rows": [
        { "title": "Send the invoice", "subtitle": "Today 15:00", "symbol": "circle", "action": { "run": "complete:abc123" } }
      ] }
    ]
  },
  "alerts": [
    { "id": "due-abc123", "title": "Send the invoice", "body": "Due in 10 minutes", "action": { "open": "ticktick://" } }
  ],
  "next": 60
}
```

| Part | Shown |
|---|---|
| `ears` | Beside the notch while nothing more important (a meeting, music, an agent) is live. `text` is cut to 24 characters. |
| `home` | A card on Home; the first three rows. The user adds it under Settings › Notch › Home layout. |
| `tab` | A page under the notch's **Plugins** tab. `sections` with optional titles; plain `rows` also works. |
| `alerts` | Cards that drop from the notch. Each `id` is shown once, ever, so repeat it freely. |
| `next` | Seconds until the next run, overriding `interval` once (at least 10). |

A **row** is `{ "title", "subtitle"?, "symbol"?, "tint"?, "value"?, "action"? }`; `value` is short
text on the right such as a time or a count.

An **action** is one of:

- `{ "open": "<url>" }` opens a web page, an app's URL scheme or a `file://` path.
- `{ "run": "<id>" }` runs the program again with `ALTOOLS_EVENT=action:<id>`; the output of that run
  replaces what's shown. Use it for "mark done", "refresh now", "snooze".
- `{ "copy": "<text>" }` copies text to the clipboard.

## A minimal plugin

`plugin.json`:

```json
{ "id": "hello", "name": "Hello", "icon": "hand.wave.fill", "run": "run.sh", "interval": 60 }
```

`run.sh`:

```sh
#!/bin/sh
if [ "$ALTOOLS_EVENT" = "action:greet" ]; then greeting="Hi again"; else greeting="Hello"; fi
cat <<EOF
{ "ears": { "text": "$(date +%H:%M)" },
  "tab": { "rows": [
    { "title": "$greeting", "symbol": "hand.wave", "action": { "run": "greet" } },
    { "title": "Copy the time", "value": "$(date +%H:%M)", "action": { "copy": "$(date)" } }
  ] } }
EOF
```

More examples are in [`examples/plugins`](examples/plugins): `hello` and a TickTick / 滴答清单 task list.

## Writing one with an AI agent

Give your agent this page and a sentence, for example:

> Using PLUGINS.md, write an Altools plugin in `~/Library/Application Support/Altools/Plugins/hn/`
> that shows the top 5 Hacker News stories in the Plugins tab and the top score in the ears.
> Run it once with `ALTOOLS_EVENT=refresh` and check it prints valid JSON.

Then switch it on in Settings › Notch › Plugins.

## Share and publish

**A file.** Settings › Notch › Plugins › **Export…** saves a plugin as `<id>.altoolsplugin` (the
folder, zipped). Anyone with Altools double-clicks it, drags it onto Altools, or uses **Import…**;
Altools shows the name, author and where it appears, and installs only after they confirm.

**A link.** Put the plugin in a GitHub repository, then share:

```
altools://install-plugin?repo=you/your-plugin
altools://install-plugin?repo=you/plugins&path=weather&ref=v1.2
```

`path` points at a plugin in a subfolder, `ref` at a branch or tag (default: the default branch). A
`url=https://…` form installs any zip that holds a plugin. Pasting `you/your-plugin` or a GitHub
link into **Install from GitHub** in Settings does the same.

**The store.** Settings › Notch › Plugins › **Plugin store** lists:

- every public GitHub repository with the topic **`altools-plugin`** and a `plugin.json` at its root.
  To publish, push your plugin and add the topic (repository › About › ⚙ › Topics). Stars sort
  the list. Update by pushing; users see **Update** when `version` changes.
- **Featured** plugins from [`plugins/registry.json`](plugins/registry.json) in this repository. To be
  featured, open a pull request adding `{ "repo": "you/your-plugin" }` (with `"path"` for a
  subfolder and `"ref"` to pin a branch or tag) after checking it against this page.

Store listings read `plugin.json` straight from GitHub, so keep `name`, `description`, `author`,
`icon` and `version` filled in. A plugin from the store is still a program that runs as the user:
keep it readable and don't fetch code to run at runtime.

## Tips

- Keep runs short; cache slow API calls in `$ALTOOLS_DATA_DIR`.
- Never print secrets; read them from `ALTOOLS_SETTING_*`.
- Prefer tools that ship with macOS (`sh`, `curl`, `osascript`). `python3` needs Apple's
  Command Line Tools, which most developers have.
- Escape strings properly when you build JSON by hand; a JSON library is safer.
