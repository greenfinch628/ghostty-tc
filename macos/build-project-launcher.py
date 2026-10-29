#!/usr/bin/env python3
"""Package the standalone Ghostty-TC project chooser; optionally install the ZIP."""
import argparse
from datetime import datetime, timezone
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
NAME = 'Ghostty-TC Projects'
IDENTITY = 'local.miller.ghosttytc.projects'
LSREGISTER = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'


def run(*command):
    subprocess.run([str(part) for part in command], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--install-only', action='store_true')
    parser.add_argument('--install-dir', type=Path, default=Path.home() / 'Applications')
    args = parser.parse_args()
    archive = ROOT / 'dist/Ghostty-TC-Projects.zip'
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not args.install_only:
        with tempfile.TemporaryDirectory(prefix='ghostty-project-launcher-') as temporary:
            app = Path(temporary) / (NAME + '.app')
            contents = app / 'Contents'
            (contents / 'MacOS').mkdir(parents=True)
            (contents / 'Resources').mkdir()
            run('xcrun', 'swiftc', '-O', '-target', 'arm64-apple-macos13.0',
                ROOT / 'macos/ProjectLauncher/main.swift', '-o', contents / 'MacOS/ProjectLauncher',
                '-framework', 'AppKit', '-framework', 'UniformTypeIdentifiers')
            info = dict(CFBundleName=NAME, CFBundleDisplayName=NAME, CFBundleExecutable='ProjectLauncher',
                        CFBundleIdentifier=IDENTITY, CFBundlePackageType='APPL',
                        CFBundleShortVersionString='1.0', CFBundleVersion='1',
                        LSMinimumSystemVersion='13.0', NSHighResolutionCapable=True, CFBundleIconFile='Projects')
            (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
            shutil.copyfile('/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericFolderIcon.icns',
                         contents / 'Resources/Projects.icns')
            run('xattr', '-cr', app)
            run('codesign', '--force', '--sign', '-', '--identifier', IDENTITY, app)
            run('codesign', '--verify', '--deep', '--strict', app)
            run('ditto', '-c', '-k', '--norsrc', '--noextattr', '--keepParent', app, archive)
        print(archive)
        return
    destination = args.install_dir.expanduser().resolve() / (NAME + '.app')
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_symlink():
        parser.error('Refusing to replace a symbolic link: ' + str(destination))
    if destination.exists():
        info = plistlib.loads((destination / 'Contents/Info.plist').read_bytes())
        if info.get('CFBundleIdentifier') != IDENTITY:
            parser.error('An unrelated application already exists: ' + str(destination))
        processes = subprocess.check_output(['ps', '-axo', 'command='], text=True)
        if any(line.lstrip().startswith(str(destination / 'Contents/MacOS') + '/') for line in processes.splitlines()):
            parser.error('Quit the project launcher before installing.')
        backups = Path.home() / 'Library/Application Support/Ghostty-TC/Backups'
        backups.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        run('ditto', '-c', '-k', '--norsrc', '--noextattr', '--keepParent', destination,
            backups / ('Projects-launcher-' + stamp + '.zip'))
    with tempfile.TemporaryDirectory(prefix='.ghostty-project-install-', dir=destination.parent) as temporary:
        temporary = Path(temporary)
        run('ditto', '-x', '-k', archive, temporary)
        candidate = temporary / (NAME + '.app')
        run('codesign', '--verify', '--deep', '--strict', candidate)
        previous = temporary / 'previous.app'
        if destination.exists():
            run(LSREGISTER, '-u', destination)
            destination.rename(previous)
        try:
            candidate.rename(destination)
        except OSError:
            if previous.exists():
                previous.rename(destination)
            raise
    run(LSREGISTER, '-f', destination)
    print('Installed:', destination)


if __name__ == '__main__':
    main()
