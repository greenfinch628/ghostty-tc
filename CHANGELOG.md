# ghostty-tc - 1.3.1

- 2026-10-29T19:02:51Z — Maintenance: Completed local-project cleanup, retired intermediate backups to Trash, retained baseline and latest rollback packages, and recorded the final package checksum, executable match, signing checks, and 229-test validation. Source checkpoint: project-workspaces-2026-10-29.

- 2026-10-29T18:54:07Z — Changed: Saved projects use Ghostty-TC native recent documents, including Dock access after Quit and direct project-file opening. Cold project launches suppress the extra terminal and recovery windows. Retired the separate Projects launcher and its packaging. Validated project-document opening, native recent registration, the macOS test suite, signing, and installation on Miller. Work assisted by OpenAI Codex.

- 2026-10-29T18:43:42Z — Added: Standalone Ghostty-TC Projects chooser with a default one-window/one-tab option and saved-project launch from a fully quit app. Explicit cold launches skip quit recovery and the extra initial terminal. Packaging and source installation include the companion launcher. Validated the macOS tests and native launcher build, verified both signatures, and installed both apps on Miller. Work assisted by OpenAI Codex.

- 2026-10-29T18:33:16Z — Added: Open Project and saved project shortcuts in the Dock menu, refreshed on each opening. Includes default-folder projects and recently used project files elsewhere without opening an extra terminal first. Passed the macOS test suite, including Dock action restoration, verified signing, and installed on Miller. Work assisted by OpenAI Codex.

- 2026-10-29T18:03:19Z — Added: Explicit local project save/open from the File menu, preserving multiple window frames, tab grouping/order, selected tabs, local folders, custom names, and color modes. Projects open in additional windows and recover placement when a display is disconnected. SSH sessions and split panes are deferred. Validated the macOS build and test suite, including live multiwindow save/reopen and File menu checks; packaged, verified signing, and installed on Miller. Work assisted by OpenAI Codex.

- 2026-10-29T16:55:17Z — Changed: Colored tabs use equally light active fills with dark text and dark inactive fills with white text; selection follows the selected tab even when the app is unfocused. Validated all palette colors in light and dark appearances, passed the macOS build and app tests, verified signing, and installed on Miller with a previous-app backup. Work assisted by OpenAI Codex.

- 2026-10-17T13:42:58Z — Changed: Validated the Miller Xcode build and test action using the documented native archive repair, verified signing, and installed the updated app with a previous-app backup. Documented continued development and dual-host publishing from Miller. Work assisted by OpenAI Codex.
- 2026-10-15T22:21:55Z — Added: Source build-and-install command with optional tests, signature verification, and previous-app backup; documented clean-Mac testing.

- 2026-10-15T22:26:23Z — Changed: Clarified as-is availability, absence of technical support, and discretionary consideration of bug reports and enhancements without implementation commitments.

## 2026-10-30T01:28:12Z

- Appearance: preserve and package the custom black Ghostty-TC icon with its blue ghost and light-gray border; use it for Finder and Dock defaults.

## 2026-10-30T01:40:10Z

- Fixed: pinned Dock tiles use the packaged Ghostty-TC icon even before saved icon preferences load; package the TC Dock plugin with a separate identity.

## 2026-10-30T01:44:10Z

- Fixed: packaged Ghostty-TC uses its native bundled application icon in Finder and Dock without the upstream alternate-icon Dock plugin.

## 2026-10-30T01:46:21Z

- Fixed: recompile packaged TC asset catalogs with the custom application icon, replacing the embedded Tahoe Icon Composer artwork used by the Dock.
