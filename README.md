# mac-spaces-switcher

A tiny headless macOS LaunchAgent that switches Spaces (virtual desktops)
**instantly, with no slide animation**. Keep the muscle memory of the native
`⌃←` / `⌃→` and `⌃1`…`⌃9` — but without waiting for the animation, and have the
switch follow the app you `⌘-Tab` to across multiple monitors.

## What it is

A background process with no window, no Dock icon, and no menu-bar item. It
registers global hotkeys and, on each press, switches the focused display to the
target Space. It does **not** require disabling SIP.

## How it works

macOS has no public API to switch Spaces without the animation, so this works
the same way a trackpad does:

1. **Global hotkeys** are registered with Carbon (`RegisterEventHotKey`), so
   presses are caught system-wide.
2. On a press, it reads the live Space layout via the private SkyLight API
   (`CGSCopyManagedDisplaySpaces`) and computes the target Space on the
   **focused display** — the one whose menu bar is active, i.e. where the
   frontmost app lives. That tracks `⌘-Tab`, not the mouse.
3. It then **synthesizes the trackpad "Dock swipe" gesture** the OS itself uses
   to change Spaces, but with the swipe *progress* pinned to the smallest
   possible value — which makes the switch **instant** (no slide). The event's
   location is stamped onto the focused display, so the correct monitor switches
   **without moving your cursor**.

Because it drives the *real* WindowServer path (rather than just rewriting Space
metadata), the outgoing Space is properly replaced — no ghosting or overlapping
windows. Jumps (`⌃1`…`⌃9`) are performed as N adjacent instant swipes toward the
target desktop.

> The instant-swipe technique is borrowed from
> [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher) and
> [FasterSwiper](https://github.com/mgbowen/FasterSwiper).

## Features

- **Instant** Space switching — no animation, regardless of monitor refresh rate.
- **No ghosting** — the previous Space's windows are cleanly replaced.
- **Relative** moves (`⌃←` / `⌃→`) and **absolute** jumps (`⌃1`…`⌃9`).
- **Move the active window** one Space left/right (`⌃⇧←` / `⌃⇧→`) and follow it
  there.
- **Multi-monitor, keyboard-only** — switches the display with the frontmost app
  (follows `⌘-Tab`) and never moves your cursor.
- **Clamps** at the first/last Space — no wrap-around; out-of-range jumps are
  safe no-ops.
- **Configurable** hotkeys via a small JSON file.
- **No SIP changes** — runs as an unprivileged LaunchAgent.
- Tiny: one Swift binary, no third-party dependencies.

## Requirements

- macOS 13 or newer (developed and tested on macOS 26).
- A Swift toolchain to build (Xcode or the Command Line Tools).
- "Displays have separate Spaces" enabled (the macOS default) for per-monitor
  switching — *System Settings → Desktop & Dock → Mission Control*.

## Install

```bash
./scripts/install.sh
```

This will:

- build a release binary and install it to `~/.local/bin/mac-spaces-switcher`,
- ad-hoc code-sign it (a stable identity for the permission grant),
- install a default config to `~/.config/mac-spaces-switcher/config.json` (only
  if one isn't already there),
- install and start the LaunchAgent `com.oltv00.mac-spaces-switcher`.

### Then — two one-time setup steps (both required)

**1. Grant Accessibility permission.** Posting the switch gesture needs it.

- Open **System Settings → Privacy & Security → Accessibility**.
- Enable **mac-spaces-switcher** in the list. If it isn't there, click **+**,
  press `⌘⇧G`, enter `~/.local/bin`, and choose `mac-spaces-switcher`.
- Reload the agent so it picks up the grant:
  ```bash
  launchctl kickstart -k "gui/$(id -u)/com.oltv00.mac-spaces-switcher"
  ```

**2. Disable the native Mission Control shortcuts** so they don't double-fire or
animate.

- Open **System Settings → Keyboard → Keyboard Shortcuts → Mission Control**.
- Untick **Move left a space**, **Move right a space**, and **Switch to Desktop
  1**…**9**.

A hotkey still claimed by the system can't be registered; the agent logs a
warning to its stderr when that happens.

## Configuration

Edit `~/.config/mac-spaces-switcher/config.json`:

```json
{
  "shortcuts": {
    "left": "ctrl+left",
    "right": "ctrl+right",
    "move-left": "ctrl+shift+left",
    "move-right": "ctrl+shift+right",
    "1": "ctrl+1",
    "9": "ctrl+9"
  }
}
```

- **Action keys:** `left`, `right`, `move-left`, `move-right`, `1`…`9`.
- **Hotkey strings:** `modifier+…+key`. Modifiers: `ctrl`, `alt`, `cmd`,
  `shift`. Keys: `left`, `right`, `up`, `down`, `0`…`9`.
- **`move-left` / `move-right`** move the frontmost window to the neighboring
  Space and follow it. They default to `ctrl+shift+←/→` — not native macOS
  shortcuts, so there's nothing extra to disable — and reuse the Accessibility
  permission the agent already needs. Moving onto a fullscreen-app Space or past
  the first/last desktop is a safe no-op.
- Missing or invalid entries are simply skipped.

The config is read **once at launch**. After editing, reload the agent:

```bash
launchctl kickstart -k "gui/$(id -u)/com.oltv00.mac-spaces-switcher"
```

## Uninstall

```bash
launchctl bootout "gui/$(id -u)/com.oltv00.mac-spaces-switcher"
rm ~/Library/LaunchAgents/com.oltv00.mac-spaces-switcher.plist
rm ~/.local/bin/mac-spaces-switcher
rm -rf ~/.config/mac-spaces-switcher        # optional: also remove the config
```

Optionally, remove the **mac-spaces-switcher** entry from *System Settings →
Privacy & Security → Accessibility*, and re-enable the native Mission Control
shortcuts if you want them back.

## Troubleshooting & debugging

Inspect the parsed display/space layout without registering hotkeys:

```bash
mac-spaces-switcher --dump
```

Run in the foreground with verbose logging (stop the agent first, or it will own
the hotkeys instead of this instance):

```bash
launchctl bootout "gui/$(id -u)/com.oltv00.mac-spaces-switcher"
MSS_DEBUG=1 ~/.local/bin/mac-spaces-switcher
```

With `MSS_DEBUG=1`, each press logs the target Space, the three display signals
(menu-bar / cursor / `NSScreen.main`), and a before/after snapshot of the active
Space and on-screen windows — useful for diagnosing multi-monitor or detection
issues.

Common issues:

- **Nothing happens on a keypress** — the hotkey is probably still claimed by
  macOS. Disable the matching native shortcut (see setup).
- **Switching ghosts/overlaps, or nothing moves** — Accessibility permission is
  missing or stale. Re-grant it (toggling the entry off then on forces a
  refresh), then `kickstart` the agent.
- **The wrong monitor switches** — confirm "Displays have separate Spaces" is
  enabled (*System Settings → Desktop & Dock → Mission Control*).

## Notes

- This relies on **private** SkyLight / CoreGraphics behavior:
  `CGSCopyManagedDisplaySpaces`, `CGSCopyActiveMenuBarDisplayIdentifier`, and
  synthetic Dock-swipe `CGEvent`s built from private event fields. It's all
  isolated in `Sources/CSkyLight/` and
  `Sources/MacSpacesSwitcher/SpaceController.swift`. A major macOS update could
  change these — if switching breaks, that's the first place to look.
- Re-running `install.sh` replaces the binary, which can reset its Accessibility
  grant. If switching stops after a reinstall, just re-enable the entry in
  System Settings.
