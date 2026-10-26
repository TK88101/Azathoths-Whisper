"""EchoKit 與 iPad app 的原始碼閘門（docs/plans/2026-10-14-yse/sprint-1-detail.md §4.3 E1–E6；E7 見 sprint-3-detail.md §4.5）。
E11（sprint-7-detail.md 附錄 C T9；N-05）另掃 Mac 中繼的配對畫面 `AzathothsWhisper/App/Remote/`（repo 相對路徑）。

主防線是結構（`tracks` 的 fileprivate 協定、ShortcutRunner 單一啟動點）與單元測試；本閘門是列舉式補助線，
只能證明「列舉的寫法都被擋」，不宣稱全面。比對前去掉 // 與 /* */ 註解（字串內不動）。

用法（在 YogSothothsEcho/ 下）：
  python3 -I Scripts/echo_gate.py                    掃整個樹
  python3 -I Scripts/echo_gate.py --stdin <相對路徑>  把 stdin 當成該路徑的檔案檢查（負對照用）
  python3 -I Scripts/echo_gate.py --e9-stdin <雜湊清單>  stdin 每行「repo 相對路徑<TAB>sha256 或 -」，只跑 E9
E9（sprint-5-detail.md §4.9）：MD Vinyl 素材只放本機，`git ls-files` 不得含素材檔名、本機素材資料夾、ipa，
也不得含內容雜湊在 Scripts/vinyl_asset_hashes.txt 內的圖片（擋改名後誤加）。
任一違規 → stderr 印 `VIOLATION [規則] 路徑: 內容`、退出 1。
"""
import hashlib
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = "Packages/EchoKit/Sources/"
BRIDGE = SOURCES + "MusicRemoteBridge/"
LOOKUP = BRIDGE + "TrackLookup.swift"
RUNNER = BRIDGE + "ShortcutRunner.swift"
READER = BRIDGE + "LibraryReader.swift"
GENIUS = BRIDGE + "GeniusMenu.swift"
APP_DIRS = ("App/", "Features/", "Services/", "UI/")
CORE_DIRS = (SOURCES + "RemoteProtocol/", SOURCES + "RemoteTransport/")
# E11 的範圍：Mac 中繼的配對畫面（repo 相對路徑，在本閘門根目錄之外）與 iPad 連線畫面
MAC_REMOTE = "AzathothsWhisper/App/Remote/"
PAIRING_DIRS = (MAC_REMOTE, "Features/Connection/")

# import 一律容許屬性（@preconcurrency 等）、存取層級（internal 等）與種類（import struct X.Y）前綴，避免以寫法繞過
IMPORT = (r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|internal|private|fileprivate|package|open)\s+)?"
          r"import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?")
E1_IMPORT = re.compile(IMPORT + r"(ScriptingBridge|iTunesLibrary)\b", re.M)
E2_PATTERNS = [
    r"NSAppleScript", r"NSUserAppleScriptTask", r"OSAScript", r"osascript", r"\bAESend\(",
    r"NSAppleEventDescriptor\(eventClass", r"sendEvent\(options:", r"MediaRemote", r"NX_KEYTYPE",
    IMPORT + r"(OSAKit|Carbon|Network)\b",
    r"value\(forKey", r"valueForKey", r"value\(forKeyPath", r"setValue\(", r"mutableArrayValue",
    r"mutableSetValue", r"dictionaryWithValues", r"perform\(", r"NSSelectorFromString", r'Selector\("',
    r"Selector\(\(", r"#selector\(", r"responds\(to:", r"method\(for:", r"objc_msgSend",
    r"class_getMethodImplementation", r"class_getInstanceMethod", r"\bdlopen\b", r"\bdlsym\b",
    r"makeObjectsPerform", r"NSExpression", r"expression\(forKeyPath", r"expressionValue\(with",
    r"NSSortDescriptor\(key", r"NSKeyValueCoding", r"\.(add|insert|remove|replace)(Object)?\(",
]
E2_PREDICATE = re.compile(r"NSPredicate|filtered\(using:")
E3_WORD = re.compile(r"\btracks\b")
E3_PROTO = "AZWMusicRemoteLibraryProto"
E3_PROTO_DECL = re.compile(r"@objc\(AZWMusicRemoteLibraryProto\)\s*fileprivate\s+protocol\b")
E3_CALL = re.compile(r"(?<!func )\btracks\s*[?!]?\s*\(\s*\)")
E3_FILTER_AFTER = re.compile(r"\s*\.filtered\(using:")
E3_ITERATION = [r"\bfor\s", r"\bwhile\s", r"\.map\b", r"\.compactMap\b", r"\.forEach\b", r"\.count\b",
                r"object\(at", r"objectAtIndex", r"\.first\(where", r"\.reduce\b", r"\.filter\s*\{",
                r"\.lazy\b", r"\bArray\("]
E4_LAUNCH = re.compile(
    r"\bProcess\b|\bNSTask\b|executableURL|launchPath|\bposix_spawnp?\b|\bexec(?:v|ve|vp|vpe|l|lp|le)\(|"
    r"\bv?fork\(|(?:\b(?:Darwin|Glibc)\.|(?<![.\w]))system\(|\bpopen\(|\bNSWorkspace\b|\bLSOpen|openApplication|\bNSAppleScript\b|"
    r"\bdlopen\b|\bdlsym\b")
E4_RUNNER_ALLOWED = re.compile(r"^(Process|executableURL)$")
# S4（CR-013(c)、CR-014）：ShortcutRunner 的引數只許三組固定向量的成分；其他 `shortcuts` 子命令與旗標一律擋
E4_SUBCOMMANDS = {"run", "sign", "list", "view", "help"}
E4_ALLOWED_SUBCOMMANDS = {"run", "sign", "list"}
E4_ALLOWED_FLAGS = {"--input-path", "--mode", "--input", "--output", "--show-identifiers"}
# security review LOW-5：執行檔與 sign mode 釘死（#4-0 P1-b 定案）
E4_EXECUTABLE = "/usr/bin/shortcuts"
E4_SIGN_MODE = "people-who-know-me"
E4_SIGN_MODES = {"anyone", "people-who-know-me"}
E4_LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
# E8（CR-014）：EchoKit 不讀「捷徑」的資料庫（app 身分本就讀不到；改為識別碼綁定）
E8_SHORTCUTS_DB = re.compile(IMPORT + r"SQLite3\b|sqlite3_|Library/Shortcuts", re.M)
E5_CORE_IMPORT = re.compile(IMPORT + r"(ScriptingBridge|iTunesLibrary|MusicRemoteBridge|AppKit)\b", re.M)
E5_APP_IMPORT = re.compile(IMPORT + r"MusicRemoteBridge\b", re.M)
# E10（CR-030；s6-61-genius.md §4.2）：輔助使用（AX）只許 GeniusMenu.swift；該檔只許按下（kAXPressAction）
E10_AX = re.compile(r"\b(?:AXUIElement\w*|kAX\w+|AXIsProcessTrusted\w*)|" + IMPORT + r"(?:ApplicationServices|HIServices)\b", re.M)
E10_PERFORM_NAME = re.compile(r"\bAXUIElementPerformAction\b")
E10_PRESS_CALL = re.compile(r"AXUIElementPerformAction\s*\(\s*[A-Za-z_]\w*\s*,\s*kAXPressAction(?:\s+as\s+CFString)?\s*\)")
E10_AX_STRING = re.compile(r'"AX')
E10_TREE = re.compile(r"\bAXMenuTree\b")
E10_TREE_DECL = re.compile(r"\bclass\s+AXMenuTree\b")
E10_TREE_PRIVATE = re.compile(r"\b(?:fileprivate|private)\s+(?:final\s+)?class\s+AXMenuTree\b")
E10_INJECTING_INIT = re.compile(r"\bGeniusMenu\s*\(\s*[^)\s]")
E10_ACTION = re.compile(r"\bkAX\w*Action\b")
E10_FORBIDDEN = re.compile(r"\b(?:AXUIElementSetAttributeValue|AXUIElementPostKeyboardEvent|AXUIElementCreateSystemWide|CGEvent\w*)\b")
E6_QUEUE = re.compile(r"Queue\.dat|History\.dat")
# E7（N-07 曲庫只讀）：iTunesLibrary 只許 LibraryReader.swift；該檔的成員存取只許白名單（框架本身無寫入 API，
# 白名單讓「新用到的 ITLib 成員」必須經過閘門修改與審查）。比對前去掉註解與字串內容
E7_IMPORT = re.compile(IMPORT + r"iTunesLibrary\b", re.M)
E7_MEMBER = re.compile(r"\.([A-Za-z_]\w*)")
E7_STRING = re.compile(r'"(?:[^"\\\n]|\\.)*"')
E7_ALLOWED_MEMBERS = {
    # ITLibrary／ITLibMediaItem／ITLibAlbum／ITLibArtist／ITLibArtwork 的唯讀成員
    "allMediaItems", "reloadData", "mediaKind", "kindSong", "persistentID", "album", "title", "sortTitle",
    "albumArtist", "sortAlbumArtist", "artist", "name", "discNumber", "trackNumber", "modifiedDate",
    "hasArtworkAvailable", "artwork", "imageData",
    # S4 T3：曲目時長（毫秒，唯讀）
    "totalTime",
    # Foundation／Swift／本模組
    "uint64Value", "append", "asUnownedSerialExecutor", "code", "unavailable", "reloadFailedCode", "zeroAlbumID",
}


# E11（N-05／CR-010 ②(h)）：QR 內容與配對秘密不進剪貼簿、不可被選取／拖出／分享，QR 圖不給無障礙讀
E11_CLIPBOARD = re.compile(r"\b(?:NSPasteboard|UIPasteboard|ShareLink)\b|\.textSelection\(\s*\.enabled|\.draggable\(|\.copyable\(")
E11_QR = re.compile(r"QRCodeImage\.make\(")
E11_HIDDEN = re.compile(r"\.accessibilityHidden\(\s*true\s*\)")
E11_QR_WINDOW_LINES = 10


def strip_comments(source):
    """去掉 // 與 /* */ 註解；字串字面量原樣保留（含跳脫）。行數不變。"""
    out, i, n = [], 0, len(source)
    in_string = False
    while i < n:
        c = source[i]
        if in_string:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(source[i + 1])
                i += 2
                continue
            if c == '"':
                in_string = False
            i += 1
        elif c == '"':
            in_string = True
            out.append(c)
            i += 1
        elif source.startswith("//", i):
            while i < n and source[i] != "\n":
                i += 1
        elif source.startswith("/*", i):
            end = source.find("*/", i + 2)
            end = n if end == -1 else end + 2
            out.append("\n" * source.count("\n", i, end))
            i = end
        else:
            out.append(c)
            i += 1
    return "".join(out)


def line_of(text, index):
    return text.count("\n", 0, index) + 1


def check(path, source):
    """回傳 [(規則, 說明)]"""
    text = strip_comments(source)
    found = []

    def hit(rule, match, note=""):
        snippet = match.group(0) if hasattr(match, "group") else str(match)
        where = f"第 {line_of(text, match.start())} 行 " if hasattr(match, "start") else ""
        found.append((rule, f"{where}{snippet!r} {note}".rstrip()))

    in_bridge = path.startswith(BRIDGE)
    in_sources = path.startswith(SOURCES)
    in_app = path.startswith(APP_DIRS)

    # E1
    if not in_bridge:
        for m in E1_IMPORT.finditer(text):
            hit("E1", m, "只許在 MusicRemoteBridge")

    if in_bridge:
        # E2
        for pattern in E2_PATTERNS:
            for m in re.finditer(pattern, text, re.M):
                hit("E2", m)
        if path != LOOKUP:
            for m in E2_PREDICATE.finditer(text):
                hit("E2", m, "述詞只許在 TrackLookup.swift")
        # E3
        if path != LOOKUP:
            for m in E3_WORD.finditer(text):
                hit("E3", m, "tracks 只許在 TrackLookup.swift")
            for m in re.finditer(E3_PROTO, text):
                hit("E3", m, "LibraryProto 只許在 TrackLookup.swift")
        else:
            if E3_PROTO in text and not E3_PROTO_DECL.search(text):
                found.append(("E3", f"{E3_PROTO} 必須宣告為 fileprivate protocol"))
            for pattern in E3_ITERATION:
                for m in re.finditer(pattern, text):
                    hit("E3", m, "TrackLookup 不得列舉")
            for m in E3_CALL.finditer(text):
                if not E3_FILTER_AFTER.match(text, m.end()):
                    hit("E3", m, "tracks 呼叫之後必須緊接 .filtered(using:)")

    # E4
    if in_sources or in_app:
        launches = list(E4_LAUNCH.finditer(text))
        if path != RUNNER:
            for m in launches:
                hit("E4", m, "啟動外部程式只許在 ShortcutRunner.swift")
        else:
            for m in launches:
                if not E4_RUNNER_ALLOWED.match(m.group(0)):
                    hit("E4", m, "ShortcutRunner 只許 Process")
            for m in E4_LITERAL.finditer(text):
                literal = m.group(1)
                if literal in E4_SUBCOMMANDS and literal not in E4_ALLOWED_SUBCOMMANDS:
                    hit("E4", m, "ShortcutRunner 只許 run／sign／list")
                if literal.startswith("-") and literal not in E4_ALLOWED_FLAGS:
                    hit("E4", m, "ShortcutRunner 的旗標不在固定向量內")
                if literal.startswith("/") and literal != E4_EXECUTABLE:
                    hit("E4", m, "ShortcutRunner 只許執行 /usr/bin/shortcuts")
                if literal in E4_SIGN_MODES and literal != E4_SIGN_MODE:
                    hit("E4", m, "sign 只許 people-who-know-me")
            for label, pattern in (("Process()", r"\bProcess\(\)"), (".run(", r"\.run\(")):
                count = len(re.findall(pattern, text))
                if count > 1:
                    found.append(("E4", f"ShortcutRunner 的 {label} 出現 {count} 次（只許 1 個啟動點）"))

    # E8
    if in_sources:
        for m in E8_SHORTCUTS_DB.finditer(text):
            hit("E8", m, "EchoKit 不得讀「捷徑」資料庫（CR-014）")

    # E5
    if path.startswith(CORE_DIRS):
        for m in E5_CORE_IMPORT.finditer(text):
            hit("E5", m)
    if in_app:
        for m in E5_APP_IMPORT.finditer(text):
            hit("E5", m, "iPad app 不得 import MusicRemoteBridge")

    # E7
    if in_bridge and path != READER:
        for m in E7_IMPORT.finditer(text):
            hit("E7", m, "iTunesLibrary 只許 LibraryReader.swift")
    if path == READER:
        scrubbed = E7_STRING.sub('""', text)
        for m in E7_MEMBER.finditer(scrubbed):
            if m.group(1) not in E7_ALLOWED_MEMBERS:
                hit("E7", m, "LibraryReader 只許白名單成員")

    # E10
    if (in_sources or in_app) and path != GENIUS:
        for m in E10_AX.finditer(text):
            hit("E10", m, "輔助使用只許 GeniusMenu.swift（CR-030）")
        for m in E10_TREE.finditer(text):
            hit("E10", m, "AXMenuTree 只許 GeniusMenu.swift")
        for m in E10_INJECTING_INIT.finditer(text):
            hit("E10", m, "正式路徑只許無參數的 GeniusMenu()（PID 只取自驗證過的 locator）")
    if path == GENIUS:
        for m in E10_FORBIDDEN.finditer(text):
            hit("E10", m, "GeniusMenu 不得寫屬性、送鍵盤事件或取系統層元素")
        for m in E10_ACTION.finditer(text):
            if m.group(0) != "kAXPressAction":
                hit("E10", m, "GeniusMenu 只許 kAXPressAction")
        performs = list(E10_PERFORM_NAME.finditer(text))
        for m in performs:
            if not E10_PRESS_CALL.match(text, m.start()):
                hit("E10", m, "AXUIElementPerformAction 只許 (元素, kAXPressAction) 的直接呼叫")
        if len(performs) > 1:
            found.append(("E10", f"AXUIElementPerformAction 出現 {len(performs)} 次（只許 1 個按下點）"))
        for m in E10_AX_STRING.finditer(text):
            hit("E10", m, "GeniusMenu 不得以字串寫 AX 動作或屬性")
        if E10_TREE_DECL.search(text) and not E10_TREE_PRIVATE.search(text):
            found.append(("E10", "AXMenuTree 必須宣告為 fileprivate／private"))

    # E11
    if path.startswith(PAIRING_DIRS):
        for m in E11_CLIPBOARD.finditer(text):
            hit("E11", m, "配對畫面不得用剪貼簿、文字選取、拖出或分享（N-05）")
        for m in E11_QR.finditer(text):
            window = "\n".join(text[m.start():].splitlines()[:E11_QR_WINDOW_LINES + 1])
            if not E11_HIDDEN.search(window):
                hit("E11", m, f"QR 圖之後 {E11_QR_WINDOW_LINES} 行內必須 .accessibilityHidden(true)（N-05）")

    # E6
    if in_sources:
        for m in E6_QUEUE.finditer(text):
            hit("E6", m, "Queue.dat／History.dat 在 EchoKit 內全域禁止（S4 前）")
    return found


E9_NAME = re.compile(r"(^|/)(vinyl_player_[^/]*|ic_vinyl_[^/]*|preview_vinyl_[^/]*|[^/]*\.ipa)$|(^|/)VinylAssets\.local/")
# 資料夾本身要存在才能建置（Xcode folder reference），只追蹤這一個說明檔
E9_KEEP = "YogSothothsEcho/Resources/VinylAssets.local/README.md"
E9_IMAGE = re.compile(r"\.(png|webp|jpe?g)$", re.I)
E9_HASHES = ROOT / "Scripts" / "vinyl_asset_hashes.txt"


def load_hashes(path):
    if not path.is_file():
        return set()
    lines = (line.strip().lower() for line in path.read_text(encoding="utf-8").splitlines())
    return {line for line in lines if line and not line.startswith("#")}


def check_tracked(entries, banned):
    """entries：(repo 相對路徑, sha256 或 None)。回傳 [(路徑, 說明)]"""
    found = []
    for path, digest in entries:
        if path == E9_KEEP:
            continue
        if E9_NAME.search(path):
            found.append((path, "MD Vinyl 素材／ipa 不得進 repo（只放本機）"))
        elif digest and digest.lower() in banned:
            found.append((path, "內容與 MD Vinyl 素材相同（改名後誤加）"))
    return found


def tracked_entries():
    top = pathlib.Path(subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=ROOT, capture_output=True,
                                      text=True, check=True).stdout.strip())
    names = subprocess.run(["git", "ls-files", "-z"], cwd=top, capture_output=True, check=True).stdout
    for name in filter(None, names.decode("utf-8").split("\0")):
        file = top / name
        digest = hashlib.sha256(file.read_bytes()).hexdigest() if E9_IMAGE.search(name) and file.is_file() else None
        yield name, digest


def tree_files():
    """(檔案, 規則用的相對路徑)：本閘門根目錄下的檔案相對 ROOT；Mac 配對畫面相對 repo 根目錄"""
    roots = [(ROOT / SOURCES, ROOT)] + [(ROOT / d, ROOT) for d in APP_DIRS] + [(ROOT.parent / MAC_REMOTE, ROOT.parent)]
    for base, anchor in roots:
        if base.is_dir():
            for file in sorted(base.rglob("*.swift")):
                yield file, file.relative_to(anchor).as_posix()


def main(argv):
    violations = []
    if len(argv) >= 2 and argv[0] == "--stdin":
        violations = [(argv[1], rule, note) for rule, note in check(argv[1], sys.stdin.read())]
    elif len(argv) >= 2 and argv[0] == "--e9-stdin":
        rows = (line.split("\t", 1) for line in sys.stdin.read().splitlines() if line.strip())
        entries = [(row[0], None if len(row) < 2 or row[1] == "-" else row[1]) for row in rows]
        violations = [(path, "E9", note) for path, note in check_tracked(entries, load_hashes(pathlib.Path(argv[1])))]
    else:
        for file, rel in tree_files():
            violations += [(rel, rule, note) for rule, note in check(rel, file.read_text(encoding="utf-8"))]
        violations += [(path, "E9", note) for path, note in check_tracked(tracked_entries(), load_hashes(E9_HASHES))]
    for path, rule, note in violations:
        print(f"VIOLATION [{rule}] {path}: {note}", file=sys.stderr)
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
