#!/usr/bin/env python3
"""Native panel fixtures; permissions and storage remain isolated from Owlet."""
import argparse
import os
from pathlib import Path
import platform
import plistlib
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--live', action='store_true', help='Use DEEPSEEK_API_KEY for model requests')
parser.add_argument('--background', type=Path, help='Optional local backdrop for glass screenshots')
parser.add_argument('--screenshots', type=Path, help='Export panel states and collection toggle screenshots, then exit')
parser.add_argument('--active', action='store_true', help='Render native controls in active appearance for comparison')
args = parser.parse_args()
if args.live and not os.environ.get('DEEPSEEK_API_KEY'):
    parser.error('DEEPSEEK_API_KEY is not set')
root = Path(__file__).resolve().parent.parent
build = root / '.build/panel-preview'
contents = build / 'PanelPreview.app/Contents'
(contents / 'MacOS').mkdir(parents=True, exist_ok=True)
(contents / 'Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'dev.fahchen.owlet.panelpreview',
    'CFBundleName': 'PanelPreview', 'CFBundleExecutable': 'PanelPreview',
    'CFBundlePackageType': 'APPL',
}))
executable = contents / 'MacOS/PanelPreview'
sources = sorted(str(p) for p in (root / 'Owlet').rglob('*.swift') if p.name != 'OwletApp.swift')
subprocess.run([
    'xcrun', 'swiftc', '-swift-version', '6', '-target',
    f'{platform.machine()}-apple-macos26.0', '-module-cache-path', str(build / 'cache'),
    '-o', str(executable), *sources, str(root / 'scripts/PanelPreview.swift'),
], check=True)
# Only the isolated preview child reads this key; no shared test or system configuration changes.
environment = os.environ.copy()
if args.active:
    environment['OWLET_PREVIEW_ACTIVE'] = '1'
if args.screenshots:
    environment['OWLET_PREVIEW_SCREENSHOTS'] = str(args.screenshots.resolve())
if args.background:
    environment['OWLET_PREVIEW_BACKGROUND'] = str(args.background.resolve())
subprocess.run([str(executable), *(['--live'] if args.live else [])], env=environment, check=True)
