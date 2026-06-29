# Shots

A macOS menu bar app that renames screenshots the moment you take them — and copies the path to your clipboard, ready to paste.

Built for developers who take screenshots to share with AI coding agents like [OpenCode](https://opencode.ai). The path lands on your clipboard in the format your tool needs, so you can paste it straight into a command or an MCP tool without the agent auto-attaching the image.

## Install

1. Download `Shots.dmg` from [GitHub Releases](../../releases)
2. Open the .dmg and drag **Shots** to your **Applications** folder
3. Launch Shots — it lives in your menu bar (no Dock icon)
4. Enable **Launch at Login** from the menu if you want it always running

## How it works

When you take a screenshot (⌘⇧3 or ⌘⇧4), the rename panel appears instantly with the filename selected. Type a new name, press **Enter**, and the file is renamed with its new path copied to your clipboard. Press **Esc** to cancel and return to what you were doing.

If multiple screenshots are taken back-to-back, the first one stays open for renaming. The rest appear in the menu's recent list, where you can pick them in order.

## Copied Path Format

Three formats are available when you press Enter. Pick a default from the menu, or override per-paste using modifier keys:

| Key | Format | Use when |
|---|---|---|
| **Enter** | Default format (set in menu) | Your most common paste destination |
| **⌘Enter** | No Quotes | Finder (⌘⇧G) and apps that don't understand quotes |
| **⌃Enter** | Markdown Code | Coding agents — prevents auto-attach |

**No Quotes** copies the raw path. **CLI Friendly** single-quotes only when the path contains spaces. **Markdown Code (Anti Coding Agent Auto-Attach)** wraps the path in backticks so coding agents like OpenCode treat it as inline code instead of attaching the image — this preserves the path string for MCP tools that need it.

The default is **Markdown Code** since the app's primary use case is pasting into AI coding agents.

## Global Hotkeys

These work from any application — you don't need to switch to Shots first.

| Shortcut | Action |
|---|---|
| **⌘⌥.** | Open the Shots menu |
| **⌘⌥1–9** | Rename the 1st–9th most recent screenshot |

Panels opened via hotkey show a preview thumbnail. Panels opened automatically from a new capture skip the preview to stay fast.

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
