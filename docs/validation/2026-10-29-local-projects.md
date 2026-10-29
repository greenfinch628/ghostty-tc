# Local project workspace checkpoint — 2026-10-29

Verified at 2026-10-29T19:02:51Z on Miller.

- Implementation commit: `fb10093ab2d9acdb357fc7f509a2bddb398f5ffb`. This checkpoint changes documentation only.
- Validation: macOS build and test action succeeded; 229 reported test cases passed.
- Project checks: multiple windows and tabs, frames, selected tabs, folders, custom names, colors, direct document opening, and native recent-document registration.
- Formatting: SwiftLint passed for all changed Swift files.
- Package and installed app: strict signature verification passed; executable hashes match.
- Current package: `dist/Ghostty-TC.zip` (generated, intentionally excluded from Git).
- ZIP SHA-256: `35cd757face670ab5caa3cfd1024e033cfdbc7326da01b316e0f8a6be5310209`.
- Executable SHA-256: `91042219a043a526d6d7f5ff9840adeef16aed6d1219a378204bf6fc205c512b`.

The installed daily-use app is `~/Applications/Ghostty-TC.app`. Existing project
files remain in `~/Library/Application Support/Ghostty-TC/Projects`. Open the
updated app once to register existing projects in macOS recent documents.

The companion Projects launcher, its Dock pin, obsolete ZIP, and generated test
launchers have been removed from active locations. Retired files and intermediate
backups are recoverable in Trash. Retained rollback copies are the original
pre-project app and the latest pre-final-install app under
`~/Library/Application Support/Ghostty-TC/Backups`.

SSH restoration and split-pane project snapshots remain deferred. This is a
source checkpoint, not a newly published binary release. The ZIP is built locally
using the versioned build recipe.
