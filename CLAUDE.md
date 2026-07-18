# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概况

代号 Bjork，实际产品为 **Azathoth's Whisper**：一个 macOS 应用，监听 iTunes/Music 当前播放曲目，从多个歌词源抓取歌词并写入音频文件的 lyrics metadata。Python 编写，pywebview 做主 UI（内嵌 HTML），Tkinter 做批处理弹窗，appscript 做 iTunes 自动化，PyInstaller 打包成 .app + DMG 发布。

仅支持 macOS（依赖 appscript / Apple Events）。

## 常用命令

```bash
# 本地运行（必须用 run.sh：它设置 aeosa 的 PYTHONPATH，appscript 依赖此路径）
./run.sh
# 等价于：
# PYTHONPATH=$(pwd)/.venv/lib/python3.14/site-packages/aeosa ./.venv/bin/python3 lyrics_fetcher.py

# 打包 .app（完整流程见 README.md「Build from Source」第 5 步）
rm -rf build/ dist/
pyinstaller Azathoths_Whisper.spec --clean
# 打包后必须补建 en.lproj / zh_TW.lproj / ja.lproj 空 Localizable.strings，
# 否则 macOS 系统语言检测失效（命令见 README.md）

# DMG 版式（挂载 DMG 后跑，设置背景图与图标位置）
osascript setup_dmg.applescript
```

没有测试套件，也没有 lint 配置。依赖清单见 `requirements.txt`（版本锁定，2026-07-18 由 venv 实测生成）。开发环境另需 Homebrew 的 `python-tk@3.14`（venv 的 tkinter 依赖它，brew 升级 python 后容易缺失）。

## 架构

几乎全部逻辑集中在单文件 `lyrics_fetcher.py`（约 2250 行），按行号区段划分：

- **~58–900**：`HTML_CONTENT` — 内嵌的 pywebview 前端（HTML/CSS/JS 单页），UI 改动都在这段字符串里
- **~912–931**：`.env` 加载（三级 fallback：脚本目录 → PyInstaller bundle 目录 → `~/Documents/Bjork/.env`）
- **~944**：`APP_VERSION` 等元数据常量 — 改版本号时需与 `Azathoths_Whisper.spec` 里的 `version` / `CFBundleShortVersionString` 同步
- **~950**：`TRANSLATIONS` — en / zh_TW / ja 三语 i18n 字典，新增 UI 文案必须三语都加
- `MusicController`（1103）— appscript 控制 iTunes/Music，读当前曲目、写歌词回音频文件
- `LyricsFetcher`（1198）— 多源歌词抓取，按序 fallback：Genius（需 API token）→ Metal Archives → DarkLyrics → Musixmatch
- `DirectoryScanner`（1435）— 批量扫描本地音乐目录
- `ConfigManager`（1561）— 用户配置持久化到 `~/.azathoths_whisper_config`（JSON，含旧格式迁移）
- `BatchProcessingWindow`（1646）— Tkinter Toplevel 批处理窗口（与 pywebview 主窗口并存）
- `LyricsApp`（1841）— 主应用；自身作为 `js_api` 传给 `webview.create_window`，Python 方法即 JS 桥接口

其他文件：`splash.py`（启动画面 HTML）；`make_icns.py` / `process_icon.py` / `update_icon_in_code.py`（图标生成链：源图 → iconset/icns → base64 内嵌进代码）；`debug_id.py`（调试用）。

## 注意事项

- 打包（frozen）状态下 stdout/stderr 重定向到 `~/Documents/Bjork/app_debug.log`，排查打包后崩溃先看此文件
- UI 版本号由 `load_main_content` 把 HTML 里的 `__APP_VERSION__` 占位符替换为 `APP_VERSION`——改版本只动 `APP_VERSION` 与 `.spec`，勿在 HTML 里写死
- 打包后补 lproj 会破坏签名 seal，必须 `codesign --force --deep -s -` ad-hoc 重签再 strict 校验
- 打包/DMG 工作区放 iCloud 同步树（~/Documents）之外；DMG 版式复用历史 `.DS_Store` + 背景图 `chflags hidden`（详见 learned skill dmg-icon-and-layout-standards）
- 退出逻辑：`setup_macos_hotkey` 用包装 NSApp delegate 的方式让 `terminate:` 生效；红色关闭钮＝隐藏（`on_closing` 返回 False），勿改回拦截 terminate 的写法
- `.env` 存放 Genius token 等，已 gitignore，不要提交
- venv 为 Python 3.14，路径硬编码在 `run.sh` 与 `.spec` 的 `pathex` 中，升级 Python 版本时两处都要改
- 应用未做 Apple 签名，DMG 分发依赖用户手动 `xattr -d com.apple.quarantine`
