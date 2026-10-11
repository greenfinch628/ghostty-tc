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

The helper retains the upstream icon artwork, disables upstream automatic updates for the fork, removes test plug-ins, and ad-hoc signs the package. A distinctive TC icon is still pending. The unchanged source Xcode target retains its development identity; use the packaging helper to create the daily-use app.

Extract the ZIP, then move Ghostty-TC.app into `~/Applications`. Back up any existing experimental build before replacing it. Never replace the Homebrew installation at `/Applications/Ghostty.app`.

## Main configuration

Ghostty-TC and regular Ghostty share the normal Ghostty configuration paths. Ghostty 1.3.1 loads the legacy `config` first and the newer `config.ghostty` afterward. Prefer one `~/.config/ghostty/config.ghostty` file; Settings opens the preferred configuration. Normal Ghostty settings in this file affect both applications.

```ini
theme = "Aardvark Blue"
font-family = "MesloLGLDZ Nerd Font Mono"
font-size = 16
macos-titlebar-style = native
window-show-tab-bar = always
window-save-state = always
right-click-action = copy-or-paste
```

The macOS customization honors `window-show-tab-bar = always`. It preserves native behavior for `auto` and `never`; `never` is not newly implemented on macOS. Restart after changing tab-bar behavior.

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
