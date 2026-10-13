#!/usr/bin/env python3
"""Build and package the native Ghostty-TC app without installing it."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
parser.add_argument('--test', action='store_true')
parser.add_argument('--repair-archives', action='store_true')
args = parser.parse_args()
root = args.source.resolve()
out = root / 'dist'
out.mkdir(parents=True, exist_ok=True)

def run(*command, cwd=root):
    subprocess.run([str(c) for c in command], cwd=cwd, check=True)

brew = shutil.which('brew') or '/opt/homebrew/bin/brew'
zig_prefix = subprocess.check_output([brew, '--prefix', 'zig@0.15'], text=True).strip()
run(Path(zig_prefix) / 'bin/zig', 'build', '-Demit-macos-app=false',
    '-Demit-xcframework=true', '-Dxcframework-target=native', '-Doptimize=ReleaseFast',
    '-Dversion-string=1.3.1')
# Xcode 26.6 libtool can drop misaligned members in Zig 0.15.2 archives.
# Extracting the original objects and archiving them directly preserves them.
with tempfile.TemporaryDirectory(prefix='ghostty-tc-') as temporary:
    temporary = Path(temporary)
    if args.repair_archives:
        manifest_candidates = []
        for path in (root / '.zig-cache/h').glob('*.txt'):
            try:
                text = path.read_text()
            except (UnicodeError, OSError):
                continue
            if '/libghostty.a' in text and '/libfreetype.a' in text:
                manifest_candidates.append(path)
        if not manifest_candidates:
            raise RuntimeError('Could not locate the native combined-library cache manifest')
        manifest = max(manifest_candidates, key=lambda p: p.stat().st_mtime)
        objects = []
        for index, line in enumerate(manifest.read_text().splitlines()):
            if not line.endswith('.a'):
                continue
            archive = root / line.split(maxsplit=6)[-1]
            folder = temporary / str(index)
            folder.mkdir()
            run('/usr/bin/ar', '-x', archive, cwd=folder)
            for obj in folder.glob('*.o'):
                obj.chmod(0o644)
                objects.append(obj)
        library = temporary / 'libghostty-fat.a'
        run('/usr/bin/libtool', '-static', '-o', library, *objects)
        shutil.copy2(library, root / 'macos/GhosttyKit.xcframework/macos-arm64/libghostty-fat.a')
    nu = shutil.which('nu') or '/opt/homebrew/bin/nu'
    run(nu, 'macos/build.nu', '--configuration', 'Debug')
    if args.test:
        run(nu, 'macos/build.nu', '--action', 'test')
    app = temporary / 'Ghostty-TC.app'
    run('ditto', root / 'macos/build/Debug/Ghostty.app', app)
    shutil.rmtree(app / 'Contents/PlugIns/GhosttyTests.xctest', ignore_errors=True)
    info_path = app / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info.update(CFBundleName='Ghostty-TC', CFBundleDisplayName='Ghostty-TC',
                CFBundleIdentifier='local.miller.ghosttytc.singletab',
                CFBundleShortVersionString='1.3.1', CFBundleVersion='131',
                SUEnableAutomaticChecks=False, GhosttyTCDefaultIcon='holographic',
                CFBundleIconFile='GhosttyTC')
    info.pop('CFBundleIconName', None)
    info_path.write_bytes(plistlib.dumps(info))
    iconset = temporary / 'GhosttyTC.iconset'
    iconset.mkdir()
    icon_source = root / 'macos/Assets.xcassets/Alternate Icons/HolographicImage.imageset/macOS-AppIcon-1024px.png'
    for size in [16, 32, 128, 256, 512]:
        for scale in [1, 2]:
            name = f'icon_{size}x{size}' + ('@2x' if scale == 2 else '') + '.png'
            run('sips', '-z', size * scale, size * scale, icon_source, '--out', iconset / name)
    run('iconutil', '-c', 'icns', iconset, '-o', app / 'Contents/Resources/GhosttyTC.icns')
    run('xattr', '-cr', app)
    run('codesign', '--force', '--sign', '-', '--entitlements',
        root / 'macos/GhosttyDebug.entitlements', '--identifier',
        'local.miller.ghosttytc.singletab', app)
    run('codesign', '--verify', '--deep', '--strict', app)
    run('ditto', '-c', '-k', '--norsrc', '--noextattr', '--keepParent',
        app, out / 'Ghostty-TC.zip')
print(out / 'Ghostty-TC.zip')
