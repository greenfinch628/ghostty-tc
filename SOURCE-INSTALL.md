# Build and install Ghostty-TC from source

## Prerequisites

Apple Silicon Mac, macOS Tahoe (the tested baseline), full Xcode with the macOS SDK and Metal toolchain, Python 3, and Homebrew. Install the project-specific tools with `brew install zig@0.15 nushell swiftlint`. This checkout requires Zig 0.15.2; the installer checks that version before building.

Open Xcode once and complete its first-launch setup. Command Line Tools alone
are not sufficient. Check `xcodebuild -version`; if it points to the wrong tools,
select your Xcode installation (for the usual location):

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

No paid Apple Developer account is needed. The resulting app is locally
ad-hoc signed for this Mac, rather than a notarized download for distribution.
Internet access is required to clone and resolve build dependencies.

## Clone, build, and install

Clone from either host, then run the same installer:

```sh
git clone https://github.com/greenfinch628/ghostty-tc.git
cd ghostty-tc
python3 scripts/build-and-install.py --test
```

Or replace the clone command with Gitea (requires access to Scopuli and a
configured SSH key):

```sh
git clone ssh://git@scopuli:2224/scopuli/ghostty-tc.git
```

The installer builds from this checkout, runs the existing app tests when
`--test` is supplied, verifies the local signature, and installs
`~/Applications/Ghostty-TC.app`. Open that app in Finder. It does not launch the app
automatically or change preferences, recovery data, or configuration files.
Tests may exercise app preferences; use a separate macOS test account when
checking a clean installation.

Quit the installed app before upgrading. An existing app with the expected
bundle identity is retained as a timestamped `.app.backup` beside the new app.
An unrelated app or symbolic link is never replaced. The installer stages the
new app before replacing the old one and restores the backup if replacement
fails. The backup can be restored manually while the app is closed.

To build without installing:

```sh
python3 scripts/build-and-install.py --build-only --test
```

For a different install folder, add `--install-dir /absolute/path`. The default
per-user location needs no administrator privileges. Omit `--test` to skip the
existing tests, for example after the same checkout has already been validated.

## Update and rebuild

From your existing clone, after quitting the app:

```sh
git pull --ff-only
python3 scripts/build-and-install.py --test
```

Use a clean checkout or commit your own changes before updating. Keep only one
daily-use app copy to avoid selecting an older build from app search.

## Test directly on a Mac

Use a separate macOS test account to avoid existing preferences and recovery
masking first-run problems. Starting with the prerequisites above, clone into
a new folder, build with `--test`, open the installed app, and verify editing or
terminal input, tab colors, closing/reopening, and saved-session restoration.
Then rebuild to check that the prior app is backed up and settings are retained.

The installer has been checked for syntax, command-line behavior, platform
rejection, and staged installation/backup behavior on Linux. Actual Xcode builds,
macOS tests, signing, and launching still need to be verified directly on the Mac.

## Ghostty-TC specifics

This wraps the existing `macos/build-tc.py` helper and installs its packaged
Ghostty-TC bundle; regular Ghostty keeps its own identity and installation.
The native-only build is not a universal Apple Silicon/Intel app. The existing
helper uses a Debug application with an optimized native core; an upstream Debug
warning may appear. Build details remain in [docs/GHOSTTY-TC.md](docs/GHOSTTY-TC.md).

If Xcode reports the known misaligned archive/missing-symbol link failure, retry:

```sh
python3 scripts/build-and-install.py --repair-archives --test
```

This workaround is opt-in and specific to the native Apple Silicon framework.
Ghostty-TC uses Metal, so the physical Mac is the final graphics test target.
