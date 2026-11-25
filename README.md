# Altools

A native macOS menu-bar toolkit: launcher, clipboard history, AI via Claude Code / Codex CLI,
text-selection actions, screenshots with annotation / pin / OCR, and a notch panel.

## Build & run

```sh
scripts/build-app.sh            # → build/Altools.app (release)
open build/Altools.app
swift test                      # core logic tests
```

Set `ALTOOLS_SIGN_IDENTITY` to a code-signing identity to keep macOS permissions across
rebuilds; the default ad-hoc signature makes macOS treat every build as a new app.

## Shortcuts

| Keys | Action |
|---|---|
| ⌥ Space | Launcher (apps, commands, math, clipboard; ⇥ asks AI) |
| ⌥⇧ Space | Ask AI |
| ⌥⇧ V | Clipboard history (↩ paste, ⌘↩ copy, ⌘⌫ delete) |
| ⌥⇧ A | Capture area → annotate (↩ copy, ⌘S save, Pin, Text) |
| ⌥⇧ O | Capture area → copy recognized text |
| ⌥⇧ S | Actions on selected text (also appears after selecting with the mouse) |

Hover the notch for now playing, battery, quick actions and a file shelf.

## Permissions

- **Accessibility**: read selected text, paste results back.
- **Screen Recording**: capture other apps' windows.
- **Automation** (Music / Spotify): now playing in the notch.

## AI

Settings › AI picks Claude Code or Codex, the model, the agent's tool access
(none / read-only / edit files / full) and an optional proxy. Text actions always run
in a lightweight mode (no tools, hooks, plugins or saved session).

## UI previews (debug builds)

```sh
scripts/build-app.sh debug
ALTOOLS_RENDER_DIR=/tmp/altools-render build/Altools.app/Contents/MacOS/Altools
```

Renders every surface with demo data to PNGs off-screen, then quits.

## Self-test (debug builds)

```sh
ALTOOLS_SELFTEST=1 build/Altools.app/Contents/MacOS/Altools        # add ALTOOLS_SELFTEST_AI=0 to skip CLI calls
```

Exercises the real integrations without opening windows: hotkey registration, app search,
calculator, clipboard capture / skip / restore (your clipboard is put back), Vision OCR,
annotation export, proxy detection, Claude quick + agent mode with tools and session resume,
read-only enforcement, and Codex error reporting.
