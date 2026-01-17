import re

def get_metadata(key):
    with open('lyrics_fetcher.py', 'r', encoding='utf-8') as f:
        content = f.read()
        match = re.search(f'^{key} = ["\']([^"\']+)["\']', content, re.MULTILINE)
        if match:
            return match.group(1)
    return "1.0.0" # Fallback

app_version = get_metadata("APP_VERSION")
app_author = get_metadata("APP_AUTHOR")

a = Analysis(
    ['lyrics_fetcher.py'],
    pathex=[],
    binaries=[],
    datas=[],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='Azathoths_Whisper',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=['MyIcon.icns'],
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='Azathoths_Whisper',
)
app = BUNDLE(
    coll,
    name="Azathoth's Whisper.app",
    icon='MyIcon.icns',
    bundle_identifier='com.ibridgezhao.azathothswhisper',
    info_plist={
        'NSAppleEventsUsageDescription': 'Azathoth\'s Whisper needs access to iTunes to read track info and scribe lyrics.',
        'NSHighResolutionCapable': 'True',
        'CFBundleLocalizations': ['en', 'zh_TW', 'ja'],
        'CFBundleDevelopmentRegion': 'en',
        'CFBundleShortVersionString': app_version,
        'CFBundleVersion': app_version,
        'NSHumanReadableCopyright': f'Copyright © 2026 {app_author}. All rights reserved.'
    },
)
