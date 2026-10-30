#!/usr/bin/env python3
"""Build and package the native Ghostty-TC app without installing it."""
import argparse
import json
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
                SUEnableAutomaticChecks=False, GhosttyTCDefaultIcon='custom',
                CFBundleIconFile='GhosttyTC')
    info['CFBundleURLTypes'] = [dict(CFBundleURLName='Ghostty-TC Project Requests',
                                   CFBundleURLSchemes=['ghostty-tc-project'])]
    project_type = 'local.miller.ghosttytc.project'
    info.setdefault('CFBundleDocumentTypes', []).append(dict(
        CFBundleTypeName='Ghostty-TC Project', CFBundleTypeRole='Editor',
        LSHandlerRank='Owner', LSItemContentTypes=[project_type],
        CFBundleTypeExtensions=['ghostty-project'], CFBundleTypeIconFile='GhosttyTC'))
    info['UTExportedTypeDeclarations'] = [dict(
        UTTypeIdentifier=project_type, UTTypeDescription='Ghostty-TC Project',
        UTTypeConformsTo=['public.json'],
        UTTypeTagSpecification={'public.filename-extension': ['ghostty-project']})]
    info.pop('CFBundleIconName', None)
    info_path.write_bytes(plistlib.dumps(info))
    # Use the preserved TC icon; never regenerate it from an upstream alternate.
    shutil.copy2(root / 'macos/Icons/GhosttyTC.icns', app / 'Contents/Resources/GhosttyTC.icns')
    # Use the same native bundle icon in Finder and the pinned/running Dock.
    # The upstream icon override plugin can retain a stale alternate icon.
    shutil.rmtree(app / 'Contents/PlugIns/DockTilePlugin.plugin', ignore_errors=True)
    info.pop('NSDockTilePlugIn', None)
    info_path.write_bytes(plistlib.dumps(info))
    # Tahoe can resolve its Dock artwork from Assets.car rather than ICNS.
    # Recompile the full catalog with a TC appiconset, omitting Ghostty.icon.
    catalog = temporary / 'TCIcons.xcassets'
    iconset = catalog / 'Ghostty.appiconset'
    iconset.mkdir(parents=True)
    images = []
    for size in [16, 32, 128, 256, 512]:
        for scale in [1, 2]:
            name = f'icon_{size}x{size}' + ('@2x' if scale == 2 else '') + '.png'
            shutil.copy2(root / 'macos/Icons/GhosttyTC.iconset' / name, iconset / name)
            images.append(dict(idiom='mac', size=f'{size}x{size}',
                               scale=f'{scale}x', filename=name))
    (iconset / 'Contents.json').write_text(json.dumps(dict(
        images=images, info=dict(author='xcode', version=1))))
    run('xcrun', 'actool', root / 'macos/Assets.xcassets', catalog,
        '--compile', app / 'Contents/Resources', '--platform', 'macosx',
        '--minimum-deployment-target', '13.0', '--app-icon', 'Ghostty',
        '--output-partial-info-plist', temporary / 'TCIconInfo.plist',
        '--target-device', 'mac', '--development-region', 'en')
    info['CFBundleIconName'] = 'Ghostty'
    info_path.write_bytes(plistlib.dumps(info))
    run('xattr', '-cr', app)
    run('codesign', '--force', '--sign', '-', '--entitlements',
        root / 'macos/GhosttyDebug.entitlements', '--identifier',
        'local.miller.ghosttytc.singletab', app)
    run('codesign', '--verify', '--deep', '--strict', app)
    run('ditto', '-c', '-k', '--norsrc', '--noextattr', '--keepParent',
        app, out / 'Ghostty-TC.zip')
print(out / 'Ghostty-TC.zip')
