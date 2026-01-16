# -*- mode: python ; coding: utf-8 -*-


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
        'NSAppleEventsUsageDescription': 'Azathoth\'s Whisper needs access to Music to read track info and scribe lyrics.',
        'NSHighResolutionCapable': 'True',
        'CFBundleLocalizations': ['en', 'zh_TW', 'ja'],
        'CFBundleDevelopmentRegion': 'en'
    },
)
