# Ghostty-TC

A macOS customization of [Ghostty](https://ghostty.org), based on **v1.3.1**, for full tab background colors and host color mappings. Developed and tested on an Apple Silicon Mac running macOS Tahoe.

## Features

- Full tab backgrounds using Ghostty's existing color palette, with contrasting labels.
- Right-click tab menu for colors, renaming, and tab actions.
- A visible tab bar with one tab when `window-show-tab-bar = always`.
- Session restoration of tabs, colors, and automatic/manual color mode when `window-save-state = always`.
- A separate **Ghostty-TC** app name and bundle identity; regular Ghostty can remain installed.
- Configurable local host colors and explicit `SSH: hostname` title mappings. Manual selections stay pinned until **Use Automatic Color** is selected.

**Current limits:** this is an experimental macOS fork. Automatic coloring recognizes explicit titles, not SSH connections. An ordinary `ssh hostname` command is not detected unless its tab title supplies the marker. The packaged app uses Ghostty’s Holographic alternate icon. Full backgrounds use Tahoe's private native tab container, falling back to the original color dot if that container is unavailable.

## Installation

Build and package with the instructions in [Ghostty-TC documentation](docs/GHOSTTY-TC.md), then extract `Ghostty-TC.zip` and put **Ghostty-TC.app** in `~/Applications`. Do not replace `/Applications/Ghostty.app`. Locally built bundles are ad-hoc signed, not notarized distribution releases.

## Configuration

Open **Ghostty-TC → Settings** to edit `~/.config/ghostty/config.ghostty`:

```ini
macos-titlebar-style = native
window-show-tab-bar = always
window-save-state = always
right-click-action = copy-or-paste
```

Host mappings go in `~/.config/ghostty/tc-host-colors` (or `$XDG_CONFIG_HOME/ghostty/tc-host-colors`):

```ini
miller=blue
scopuli=orange
```

Use the short local hostname for local tabs. Remote mappings require an exact title such as `SSH: scopuli`, for example in a dedicated launch configuration:

```ini
command = "ssh scopuli"
title = "SSH: scopuli"
```

Choosing any palette color, including **None**, pins a manual choice. **Use Automatic Color** resumes mapping. Quit with tabs open to restore them; restoration starts new terminal processes and does not resume running commands.

See [configuration, build, testing, and limitations](docs/GHOSTTY-TC.md). The original [upstream README](docs/README.upstream.md), [development guide](HACKING.md), and [MIT license](LICENSE) remain available. Ghostty-TC is an independent customization, not an official Ghostty release.
