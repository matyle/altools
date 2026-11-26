# Altools plugins

**English** · [简体中文](PLUGINS.zh-CN.md)

A plugin extends Altools anywhere: in the notch (text beside it, a widget on Home, its own tab, alert
cards), in the menu bar, in the launcher (commands with hotkeys, and search), and on selected text.
It can also have no UI at all and only pop alerts when something happens. A plugin is a folder with a
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
| `mode` | `interval` (default): run every `interval` seconds. `stream`: started once and kept running; see [Stream plugins](#stream-plugins). |
| `interval` | Seconds between runs, at least 10. Default 300. |
| `timeout` | Seconds a run may take before it's stopped, 1 to 120. Default 20. |
| `slots` | Where output may appear: `ears`, `home`, `tab`, `alerts`, `menubar`. Default all. |
| `commands` | Launcher commands, each `{ "id", "title", "subtitle"?, "icon"?, "keywords"?, "hotkey"? }`; see [Beyond the notch](#beyond-the-notch). |
| `selection` | Selected-text actions, each `{ "id", "title", "icon"? }`. |
| `search` | `{ "keyword", "placeholder"? }`: launcher queries starting with the keyword go to the plugin. |
| `settings` | Fields the user fills in under Settings: `type` is `text`, `secret` (kept in the Keychain), `toggle` (`"1"`/`"0"`) or `choice` (with `options`). |

## How a run works

Altools starts the program with the plugin folder as its working directory. Its environment has the
user's PATH (including Homebrew) and proxy, plus:

| Variable | Value |
|---|---|
| `ALTOOLS_API` | `1` |
| `ALTOOLS_EVENT` | `refresh` for a scheduled run, `action:<id>` when the user clicked a `run` action, `trigger:<name>` for a [trigger link](#trigger-links), `command:<id>`, `selection:<id>` or `search` (see [Beyond the notch](#beyond-the-notch)) |
| `ALTOOLS_INPUT` | The selected text (`selection:<id>`) or the search query (`search`); absent otherwise |
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
| `ears` | Beside the notch while nothing more important (a meeting, music, an agent) is live. Simple form: `symbol` on the left, `text` (up to 24 characters) on the right; each side grows with the text. Or `left` and `right` as [views](#views-your-own-layout) with an optional `width` per side (30–140, default 64), e.g. a coin icon left and price over change right. |
| `home` | A widget on Home: your own `view`, or `title` + the first three `rows`. The user places it under Settings › Notch › Home layout; it shares the row's width. |
| `tab` | The plugin's own tab in the notch's tab row (its `icon`; its `title` when open): a `view`, or `sections` / `rows`. |
| `alerts` | Cards that drop from the notch. Each `id` is shown once, ever, so repeat it freely. |
| `next` | Seconds until the next run, overriding `interval` once (at least 10). |

A **row** is `{ "title", "subtitle"?, "symbol"?, "tint"?, "value"?, "action"? }`; `value` is short
text on the right such as a time or a count.

`home` and `tab` take either simple `rows` or a [`view`](#views-your-own-layout) you lay out yourself.

An **action** is one of:

- `{ "open": "<url>" }` opens a web page, an app's URL scheme or a `file://` path.
- `{ "run": "<id>" }` runs the program again with `ALTOOLS_EVENT=action:<id>`; the output of that run
  replaces what's shown. Use it for "mark done", "refresh now", "snooze".
- `{ "copy": "<text>" }` copies text to the clipboard.

## Views: your own layout

Like a widget, a plugin can lay out its own UI. Put a node tree in `home.view` or `tab.view`; Altools
draws it natively in the notch's style. Any node can carry an `action`, which makes it clickable.

```json
{ "tab": { "title": "Markets", "view":
  { "type": "grid", "columns": 2, "children": [
    { "type": "card", "action": { "open": "https://finance.yahoo.com/quote/AAPL" }, "children": [
      { "type": "hstack", "children": [
        { "type": "badge", "text": "US" },
        { "type": "text", "text": "AAPL", "weight": "bold" },
        { "type": "spacer" },
        { "type": "text", "text": "231.47", "mono": true } ] },
      { "type": "text", "text": "+0.86%", "size": 10, "color": "green" },
      { "type": "sparkline", "values": [228, 230, 229, 231.5], "color": "green" } ] } ] } } }
```

| type | properties |
|---|---|
| `vstack`, `hstack` | `children`, `spacing`, `align` (`leading`/`center`/`trailing`, or `top`/`center`/`bottom` for hstack) |
| `grid` | `children`, `columns` (1–6), `spacing` |
| `card` | `children` (stacked), `padding`, `color` (background tint) |
| `text` | `text`, `size` (9–28), `weight` (`regular`/`medium`/`semibold`/`bold`), `color`, `mono` (even-width digits), `lines` |
| `symbol` | `name` (SF Symbol), `size`, `color` |
| `image` | `url`: `https://…` or a file inside the plugin folder; `width`, `height`, `radius` |
| `badge` | `text`, `color` |
| `progress` | `value` 0–1, `color` |
| `sparkline` | `values` (numbers), `color`, `height` |
| `spacer`, `divider` | — |

Every node also takes `width`, `height`, `flex` (`true` fills the width), `opacity` and `action`.
Colours are `#RRGGBB` or `primary`, `secondary`, `tertiary`, `green`, `red`, `orange`, `yellow`,
`blue`, `purple`, `cyan`. Trees are limited to 12 levels and 400 nodes; unknown types are skipped.

## Beyond the notch

**Menu bar.** With `menubar` in `slots`, output `"menubar": { "symbol"?, "text"?, "tint"? }` (text up
to 20 characters) to get a menu-bar item; clicking it opens a panel with the plugin's `tab` page.

**Launcher commands.** Each entry in `commands` appears in the ⌥ Space launcher (matched on its title,
`keywords` and the plugin's name). Running one starts the plugin with `ALTOOLS_EVENT=command:<id>`.
A `hotkey` such as `"⌥⇧T"` or `"ctrl+option+u"` runs it from anywhere; a combination another app
already owns is skipped. If the output has a `result`, it's copied and shown:

```json
{ "result": { "text": "5747fb34-ee34-4438-82c4-0a240b0fc22f", "title": "UUID" } }
```

**Selected text.** Each entry in `selection` appears in the selection bar's ⋯ menu. The plugin runs
with `ALTOOLS_EVENT=selection:<id>` and the text in `ALTOOLS_INPUT`; its `result` shows in the result
panel with **Copy**, and with **Replace** when `"replace": true`.

**Launcher search.** With `"search": { "keyword": "b64" }`, typing `b64 hello` runs the plugin with
`ALTOOLS_EVENT=search` and `ALTOOLS_INPUT=hello`; its `"results"` (rows) replace the launcher's list,
and ↩ performs the row's action (or copies its title). Queries wait a quarter second after typing.

Commands, selected-text actions and searches always start a separate run, in either `mode`, and any
other parts of that output (ears, home, …) update what's shown. A plugin can use only these and list
no notch slots: see [`examples/plugins/text-tools`](examples/plugins/text-tools).

## Stream plugins

For plugins that react to events rather than a schedule, set `"mode": "stream"`. Altools starts the
program once and keeps it running:

- **Each line it prints** on stdout is an output object, applied straight away. Parts a line leaves
  out keep what's shown, so a line with only `alerts` just pops a card, and a plugin whose `slots`
  are only `["alerts"]` has no UI at all.
- **Events arrive on stdin** as lines: `action:<id>` when the user clicks a `run` action,
  `trigger:<name>` for a trigger link.
- If it exits, it's restarted after 5 s, doubling up to 5 minutes; it's stopped when switched off.

See [`examples/plugins/site-monitor`](examples/plugins/site-monitor): an alert only when a website
goes down or comes back.

## Trigger links

Any program can run a plugin: hooks, cron, Shortcuts, a CI script.

```sh
open -g "altools://plugin/deploys/run?event=finished"
```

An interval plugin runs once with `ALTOOLS_EVENT=trigger:finished`; a stream plugin receives
`trigger:finished` on stdin.

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

More examples are in [`examples/plugins`](examples/plugins): `hello` (rows and a view), `ticktick` (TickTick /
滴答清单: read and add tasks from the notch, launcher and selected text, with OAuth sign-in), `site-monitor` (a stream plugin with no UI) and `text-tools` (selected text, a
command with a hotkey, launcher search). The built-in Markets plugin
([`Resources/BuiltinPlugins/markets`](Resources/BuiltinPlugins/markets)) is a full example of views.

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
