#!/usr/bin/env python3
"""Build from this checkout and install a local, ad-hoc-signed macOS app."""
import argparse
from datetime import datetime, timezone
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
APP_NAME = 'Ghostty-TC'
BUNDLE_ID = 'local.miller.ghosttytc.singletab'


def run(*command):
    subprocess.run([str(part) for part in command], cwd=ROOT, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--test', action='store_true', help='Run the existing app tests before installation')
    parser.add_argument('--build-only', action='store_true', help='Build without installing')
    parser.add_argument('--install-dir', type=Path, default=Path.home() / 'Applications')
    parser.add_argument('--repair-archives', action='store_true', help='Use the existing native archive workaround if linking fails')
    args = parser.parse_args()
    if platform.system() != 'Darwin':
        parser.error('Run this script on macOS with full Xcode installed.')
    for tool in ['xcodebuild', 'xcrun', 'ditto', 'codesign']:
        if not shutil.which(tool):
            parser.error(f'Missing {tool}; install and select full Xcode first.')
    run('xcodebuild', '-version')
    destination = args.install_dir.expanduser().resolve() / (APP_NAME + '.app')
    if not args.build_only:
        if destination.is_symlink():
            parser.error(f'Refusing to replace a symbolic link: {destination}')
        if destination.exists():
            try:
                identity = plistlib.loads((destination / 'Contents/Info.plist').read_bytes()).get('CFBundleIdentifier')
            except (OSError, plistlib.InvalidFileException):
                parser.error(f'Cannot identify the existing app: {destination}')
            if identity != BUNDLE_ID:
                parser.error(f'The app at {destination} has a different identity; choose another --install-dir.')
            processes = subprocess.check_output(['ps', '-axo', 'command='], text=True)
            if any(line.lstrip().startswith(str(destination / 'Contents/MacOS') + '/') for line in processes.splitlines()):
                parser.error(f'Quit {APP_NAME} before replacing it.')
    if platform.machine() != 'arm64':
        parser.error('The Ghostty-TC installation helper currently targets Apple Silicon Macs.')
    for tool in ['brew', 'nu', 'swiftlint']:
        if not shutil.which(tool):
            parser.error(f'Missing {tool}; see SOURCE-INSTALL.md for prerequisites.')
    zig_prefix = subprocess.check_output(['brew', '--prefix', 'zig@0.15'], text=True).strip()
    zig = Path(zig_prefix) / 'bin/zig'
    version = subprocess.check_output([str(zig), 'version'], text=True).strip()
    if version != '0.15.2':
        parser.error(f'This checkout requires Zig 0.15.2, found {version}.')
    command = ['python3', ROOT / 'macos/build-tc.py']
    if args.test:
        command.append('--test')
    if args.repair_archives:
        command.append('--repair-archives')
    run(*command)
    # Extract the helper's identity-preserving, signed daily-use bundle.
    unpacked = ROOT / 'dist/source-install'
    unpacked.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='ghostty-tc-unpack-') as temporary:
        run('ditto', '-x', '-k', ROOT / 'dist/Ghostty-TC.zip', temporary)
        app = unpacked / 'Ghostty-TC.app'
        if app.exists():
            shutil.rmtree(app)
        run('ditto', Path(temporary) / 'Ghostty-TC.app', app)
    run('codesign', '--verify', '--deep', '--strict', app)
    print(f'Built: {app}', flush=True)
    if args.build_only:
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Stage on the destination filesystem, then keep the old app as a backup.
    with tempfile.TemporaryDirectory(prefix=f'.{APP_NAME}-install-', dir=destination.parent) as staging:
        candidate = Path(staging) / destination.name
        run('ditto', app, candidate)
        run('codesign', '--verify', '--deep', '--strict', candidate)
        backup = None
        if destination.exists():
            stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
            backup = destination.with_name(f'{APP_NAME}-{stamp}.app.backup')
            destination.rename(backup)
        try:
            candidate.rename(destination)
        except OSError:
            if backup is not None:
                backup.rename(destination)
            raise
    print(f'Installed: {destination}')
    if backup is not None:
        print(f'Previous app retained at: {backup}')
    print('Open Ghostty-TC from Finder. Existing settings and recovery are retained.')


if __name__ == '__main__':
    main()
