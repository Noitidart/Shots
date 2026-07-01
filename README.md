# Shots

A macOS menu bar app that renames screenshots the moment you take them — and copies the path to your clipboard, ready to paste.

## Use Cases

**Screenshot filenames are useless.** macOS names them `Screenshot 2024-06-28 at 3.42.17 PM.png`. Shots renames the file the instant it's captured — type a name, press Enter, done.

**Working with a coding agent that can't read images?** If your model isn't multi-modal, an MCP tool that can read images needs a **file path** — not an attachment. Pasting a raw path into the chat causes the agent to auto-attach the image instead of passing the string to the MCP. Shots copies the path wrapped in backticks so agents like [OpenCode](https://opencode.ai) treat it as text, not a file reference.

**Ever been asked "how did this look before we fixed it?"** Screenshots build up as a visual history. Having one from when you first noticed the issue saves you from reverting locally just to take a picture.

**Tired of a cluttered screenshot folder?** Trash old screenshots by age — but only actual screenshots (identified via Spotlight metadata), leaving your other files untouched.

## Install

1. Download **Shots.dmg** from [GitHub Releases](../../releases)
2. Open the .dmg and drag **Shots** to your **Applications** folder
3. Launch Shots — it lives in your menu bar (no Dock icon)
4. Enable **Launch at Login** from the menu if you want it always running

## How it works

When you take a screenshot (⌘⇧3 or ⌘⇧4), the rename panel appears instantly with the filename selected. Type a new name, press **Enter**, and the file is renamed with its new path copied to your clipboard. Press **⌘⌫** to trash the file. Press **Esc** to cancel and return to what you were doing.

If multiple screenshots are taken back-to-back, the first one stays open for renaming. The rest appear in the menu's recent list, where you can pick them in order.

## Rename Panel Shortcuts

| Shortcut | Action |
|---|---|
| **Enter** | Rename and copy path (default format) |
| **⌘Enter** | Rename and copy path (CLI Friendly) |
| **⌃Enter** | Rename and copy path (Markdown Code) |
| **⌘⌫** | Move the file to Trash |
| **Esc** | Cancel |

## Copied Path Format

Three formats are available when you press Enter. The default is Markdown Code (changeable from the menu), or override per-paste using modifier keys:

| Key | Format | Use when |
|---|---|---|
| **Enter** | Markdown Code | Agents like OpenCode — prevents auto-attach |
| **⌘Enter** | CLI Friendly | Terminal / shell commands |
| **⌃Enter** | No Quotes | Finder (⌘⇧G) and apps that don't understand quotes |

**No Quotes** copies the raw path. **CLI Friendly** single-quotes only when the path contains spaces. **Markdown Code** wraps the path in backticks so agents treat it as inline code instead of attaching the image — this preserves the path string for MCP tools that need it.

## Global Hotkeys

These work from any application — you don't need to switch to Shots first.

| Shortcut | Action |
|---|---|
| **⌘⌥.** | Open the Shots menu |
| **⌘⌥1–9** | Preview the 1st–9th most recent screenshot (rename and copy optional) |

Every rename panel shows a preview of the screenshot.

## Menu Shortcuts

Available when the menu is open:

| Shortcut | Action |
|---|---|
| **⌘O** | Open the screenshots folder |
| **⌘T** | Trash screenshots older than 14 days |
| **⌘Q** | Quit Shots |

## Screenshot Destination

Where screenshots are saved is controlled by macOS, not Shots. Use **⌘⇧5 → Options** to change the destination. When the destination is set to Clipboard or another non-folder mode, Shots pauses rename, trash, and folder actions — the menu shows the current target and how to switch back.

## Help

All of the above is also available inside the app: click the menu bar icon → **Help**.
