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
parser.add_argument('--transition', type=Path,
                    help='Record the real panel going from 翻译中 to the result as a .mov, then exit')
parser.add_argument('--panel', action='store_true', help='Open the real floating panel through PanelController')
parser.add_argument('--main', action='store_true', help='Open the main window pages with fixture data')
parser.add_argument('--no-voice', action='store_true', help='Stand in for a Mac without a system voice')
parser.add_argument('--target', choices=['en', 'ja', 'zh-Hans'], help='Result language for --panel')
parser.add_argument('--appearance', choices=['dark', 'contrast', 'darkContrast'], help='Appearance for --panel')
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
if args.transition:
    environment['OWLET_PREVIEW_TRANSITION'] = str(args.transition.resolve())
if args.no_voice:
    environment['OWLET_PREVIEW_NO_VOICE'] = '1'
if args.target:
    environment['OWLET_PREVIEW_TARGET'] = args.target
if args.appearance:
    environment['OWLET_PREVIEW_APPEARANCE'] = args.appearance
if args.background:
    environment['OWLET_PREVIEW_BACKGROUND'] = str(args.background.resolve())
flags = [*(['--live'] if args.live else []), *(['--panel'] if args.panel else []), *(['--main'] if args.main else [])]
subprocess.run([str(executable), *flags], env=environment, check=True)
