# Ghostty-TC development and operation

## Supported baseline

Base: Ghostty v1.3.1 (`332b2ae`). Verified development environment: Apple Silicon, macOS Tahoe 26.7.1, Swift 6.3.3, Zig 0.15.2 (`zig@0.15`), Xcode, and Nushell. Other macOS versions and Intel builds have not been verified.

## Build and package

Install Xcode and its command-line tools. Install the Metal toolchain if Xcode requests it. Homebrew dependencies:

```sh
brew install zig@0.15 nushell swiftlint
```

From the repository root:

```sh
python3 macos/build-tc.py --test
```

The helper builds the native GhosttyKit framework, builds the Debug macOS application with `macos/build.nu`, runs the macOS unit suite when requested, and produces `dist/Ghostty-TC.zip`. It does not install, launch, or replace any application. The default native-only output is for the machine's architecture, not a universal release. Debug builds may display an upstream debug warning.

On the tested Zig/Xcode combination, Xcode's archive tool omitted misaligned object members from Zig static archives. If linking fails with the corresponding warnings or missing symbols, use:

```sh
python3 macos/build-tc.py --repair-archives --test
```

This opt-in workaround extracts the native cached archive objects and re-archives them with Apple's tool before the Swift build. It is specific to the native framework; do not use it to package a cross-architecture framework.

For Swift-only edits after the framework exists:

```sh
nu macos/build.nu
nu macos/build.nu --action test
swiftlint lint --no-cache --config macos/.swiftlint.yml
```

The test build may register development apps with macOS app search. Use the packaged Ghostty-TC application for daily work; build products can be moved out of app search after packaging. The helper keeps its own staging bundle in a temporary directory and removes it on completion.

## Identity and installation

Packaged name: **Ghostty-TC**. Bundle identifier: `local.miller.ghosttytc.singletab`. The historical suffix is intentional: keeping the existing identity preserves its preferences and saved sessions. Upstream's identifier is `com.mitchellh.ghostty`.

The helper packages Ghostty’s Holographic alternate icon, disables upstream automatic updates for the fork, removes test plug-ins, and ad-hoc signs the package. Icon preferences use the packaged app’s own bundle identity. The unchanged source Xcode target retains its development identity; use the packaging helper to create the daily-use app.

Extract the ZIP, then move Ghostty-TC.app into `~/Applications`. Back up any existing experimental build before replacing it. Never replace the Homebrew installation at `/Applications/Ghostty.app`.

## Main configuration

On macOS, Ghostty-TC loads only `~/.config/ghostty-tc/config.ghostty` by default, including Finder, Dock, and AppleScript launches. Settings / Open Configuration opens that same file. `XDG_CONFIG_HOME`, legacy `config` files, and Application Support configuration files do not change this default. Explicit `--config-file` arguments and `config-file` includes remain supported. Regular Ghostty is independent. The Zig core uses the packaged TC bundle identifier for its macOS Application Support and cache directories.

```ini
theme = "Aardvark Blue"
font-family = "CaskaydiaCove Nerd Font Mono"
font-size = 18
macos-titlebar-style = native
window-show-tab-bar = always
window-save-state = always
right-click-action = copy-or-paste
```

Middle-click opens Ghostty’s existing native context menu without forwarding a middle-button paste to the terminal core. Right-click continues to honor `right-click-action = copy-or-paste`. Other auxiliary mouse buttons retain their existing behavior.

The macOS customization honors `window-show-tab-bar = always`. It preserves native behavior for `auto` and `never`; `never` is not newly implemented on macOS. Restart after changing tab-bar behavior.

## Local projects (Step 1)

Arrange local terminal windows and tabs, then choose **File > Save Project…**.
Name the `.ghostty-project` file; the default folder is
`~/Library/Application Support/Ghostty-TC/Projects`. **File > Open Project…**
opens the saved layout in additional windows without closing existing work.
Saving to the same file explicitly replaces that snapshot after the save panel's
normal overwrite confirmation; closing windows never updates a saved project.

Snapshots include window positions and sizes, tab grouping and order, selected
tabs, custom tab names, colors and automatic-color mode, and local working folders.
Windows are constrained to connected screens if a saved monitor is unavailable.
Each tab starts a fresh shell using the current configuration. Running programs,
scrollback, SSH connections, remote directories, split panes, fullscreen state,
and Spaces are not captured. Known `SSH: ` tabs and split panes are rejected;
unmarked SSH tabs cannot be identified reliably and must be excluded by closing
them before saving. This first step is for local sessions only. Missing folders
or invalid project data are reported before any project windows are opened.
Right-click Ghostty-TC's Dock icon to open native recent projects, including after
Quit. While running, its custom **Open Project…** command also browses all saved
project files. Project management remains a later step.

Automatic quit restoration
and the normal launch configuration remain independent of explicit project files.

### Native Dock recents

Saved and opened projects are registered with macOS as recent documents for
Ghostty-TC itself. After Quit, right-click the Ghostty-TC Dock icon to choose a
recent project, just as with Xcode. macOS controls the number of visible recents
and their display. Existing project files are registered on the first launch of
this update. A selected project opens its layout without the extra initial
terminal or automatic recovery windows. If Ghostty-TC is already active, existing
windows remain open. Double-clicking a `.ghostty-project` file also opens it as a
project. The separate Projects launcher is retired; only Ghostty-TC is packaged.

## Host mappings and manual priority

Create `~/.config/ghostty/tc-host-colors`, or `$XDG_CONFIG_HOME/ghostty/tc-host-colors` if that variable is set:

```ini
# hostname=color
miller=blue
scopuli=orange
```

Supported names: `none`, `blue`, `purple`, `pink`, `red`, `orange`, `yellow`, `green`, `teal`, `graphite`. Names are case-insensitive; whitespace and comments beginning with `#` are allowed. Invalid entries are ignored. Later duplicate hosts replace earlier ones. These entries are not supported directly in Ghostty's main configuration.

For titles beginning exactly with `SSH: `, the remainder is matched as a hostname. Otherwise the short local hostname is used (for example, `miller.local` maps to `miller`). An explicit unmapped remote title receives no automatic color. Mapping changes are read on title changes or by selecting Use Automatic Color again.

New tabs use automatic colors. Any palette selection, including None, pins the tab and prevents automatic overrides. Use Automatic Color clears that pin and immediately reevaluates the mapping. This mode is saved with the session and preserved by undo; older saved tabs without a mode are restored as manual to preserve their existing color.

A dedicated SSH launcher can use:

```ini
command = "ssh scopuli"
title = "SSH: scopuli"
```

Launch the packaged executable with `--config-file=/absolute/path/to/ssh-config`. A static SSH title persists for the life of that tab; it is not a connection-status signal. Ordinary SSH commands without explicit titles, nested SSH, renamed tabs, remote commands, and disconnect detection require additional integration. A remote session without the marker can retain the local fallback color. This implementation does not inspect SSH processes or network connections.

## Restoration and checks

Use `window-save-state = always`, leave tabs open, and quit normally using Command+Q or Dock Quit. Closed tabs are not part of the saved session. Restored terminals start new shells or configured commands; running processes and SSH connections are not resumed. Changing the application bundle identity creates a separate restoration namespace.

Validation performed during development: full macOS unit suite; host parsing, exact matching, local fallback, and manual priority; SwiftLint; native lifecycle harnesses for startup with one tab, opening a second, and closing to one; live menu and full red/blue backgrounds; live normal quit/reopen and user-confirmed Dock Quit restoration. The first SSH-title mapping build was tested without initiating a network connection. Fullscreen and all native tab layouts have not received exhaustive live testing.

## Maintenance

Tab fill attaches under Tahoe's `_tabButtonContainerView` via the tab accessory. It is decorative and rejects hit testing. If the private container is absent, the existing dot remains. Contrast resolves the assigned system color in the current appearance before selecting black or white text.

Keep the fork small, preserve upstream attribution and licensing, and validate tab reordering, single-tab visibility, menus, manual priority, and restoration after rebasing onto a new Ghostty release.
