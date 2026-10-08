#!/usr/bin/env python3
import json
import pathlib
import plistlib
import sys

root = pathlib.Path(sys.argv[1])
metadata = json.loads(pathlib.Path('dist/build-info.json').read_text())
for bundle, executable, identifier, package in [
    ('Countdown.saver', 'Countdown', 'com.zfdang.CountdownScreenSaver', 'BNDL'),
    ('Countdown Preview.app', 'CountdownPreview', 'com.zfdang.CountdownPreview', 'APPL'),
]:
    info = {
        'CFBundleDevelopmentRegion': 'en', 'CFBundleLocalizations': ['en', 'zh-Hans'],
        'CFBundleExecutable': executable, 'CFBundleIdentifier': identifier,
        'CFBundleInfoDictionaryVersion': '6.0', 'CFBundleName': 'Countdown',
        'CFBundlePackageType': package, 'CFBundleShortVersionString': metadata['bundleVersion'],
        'CountdownReleaseVersion': metadata['version'], 'CFBundleIconFile': 'Countdown.icns',
        'CFBundleVersion': metadata['build'], 'LSMinimumSystemVersion': '13.0',
        'CountdownGitCommit': metadata['commit'], 'NSHighResolutionCapable': True,
    }
    if package == 'BNDL':
        info['NSPrincipalClass'] = 'CountdownScreenSaverView'
    else:
        info['NSPrincipalClass'] = 'NSApplication'
    path = root / bundle / 'Contents'
    (path / 'Info.plist').write_bytes(plistlib.dumps(info))
    resources = path / 'Resources'
    resources.mkdir(exist_ok=True)
    for name in ['README.md', 'LICENSE']:
        (resources / name).write_bytes(pathlib.Path(name).read_bytes())

    (resources / 'Countdown.icns').write_bytes(pathlib.Path('Assets/Countdown.icns').read_bytes())
