# -*- mode: python ; coding: utf-8 -*-


a = Analysis(
    ['lyrics_fetcher.py'],
    pathex=['/Users/ibridgezhao/Documents/Bjork/.venv/lib/python3.14/site-packages/aeosa'],
    binaries=[],
    datas=[('MyIcon.iconset/icon_128x128@2x.png', '.')],
    hiddenimports=['appscript', 'aeosa'],
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
    version='1.2.3',
    info_plist={
        'CFBundleShortVersionString': '1.2.3',
        'CFBundleVersion': '1.2.3',
        'NSHighResolutionCapable': 'True',
        'NSAppleEventsUsageDescription': 'Azathoths Whisper needs access to Music to detect the currently playing song.',
    },
)
