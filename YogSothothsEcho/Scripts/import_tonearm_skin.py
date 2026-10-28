"""唱臂皮膚匯入（yse-1.0.1-skins.md §4.2、T1）：交件包 → App bundle 用的裁切素材＋skin.json。

用法（需要 Mac：影像裁切由 skin_image_tool.swift 經 swiftc 編譯執行）：
  python3 -I Scripts/import_tonearm_skin.py <交件包> <輸出資料夾>   檢查 → 裁切 → 寫 skin.json／IMPORT.md → 自動跑 --verify
  python3 -I Scripts/import_tonearm_skin.py --verify <輸出資料夾>   只驗輸出

輸入檢查：check_tonearm_skin.py 全部規則（含分層 `check_layers`）；雜湊表（checksums.json 或 delivery.json）吻合；
manifest.json 與 motion.json 一致（skin_id、source build SHA、px_per_unit／canvas／pivot／stylus 逐值、manifest 的角度＋
檔名樣式展開後與 motion 的檔名陣列逐項依序）。任一不符：逐條列出、退出 1、不留下輸出。
每層（arm、arm_shadow、base＝underlay、可選的 base_middle、base_overlay）取該層所有幀 alpha 外接框的聯集為裁切框（必要時擴到含支點）；
轉動層（arm、arm_shadow）另記「可見輪廓」＝該層所有幀 alpha 聯集每 4 u 一列的最左／最右（裁切框內 u）：
App 以它算旋轉後的可見外接框（不出框檢查），唱臂點擊外形＝輪廓外擴 hit_margin_u。起止角不寫：一律由 App 的求解器算。
中層另記 hit_runs_px＝裁切後每一像素列 alpha ≥ 128 的半開區間（唱片上被中層蓋住處的點擊遮罩，增補 B §4.5）；--verify 重算比對。
"""
import datetime
import hashlib
import collections
import json
import os
import pathlib
import re
import runpy
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
CHECKER = runpy.run_path(str(HERE / "check_tonearm_skin.py"))
IMAGE_TOOL_SOURCE = HERE / "skin_image_tool.swift"
PX_PER_UNIT = CHECKER["PX_PER_UNIT"]
ANGLES = CHECKER["ANGLES"]
RGBA = CHECKER["RGBA"]
png_info = CHECKER["png_info"]
# 檔名一律是程式常數（定義在 checker）：交件包與 skin.json 的檔名欄位只核對、不拿來組路徑或當格式字串（安全評審 M-1／M-2）
ARM_PATTERN = CHECKER["ARM_PATTERN"]
SHADOW_PATTERN = CHECKER["SHADOW_PATTERN"]
UNDERLAY, MIDDLE, OVERLAY = CHECKER["UNDERLAY"], CHECKER["MIDDLE"], CHECKER["OVERLAY"]
ARM_FILES = [ARM_PATTERN % a for a in ANGLES]
SHADOW_FILES = [SHADOW_PATTERN % a for a in ANGLES]
# 輸出層：輸入檔名、skin.json 的檔名欄位、是否轉動層（＝要記可見輪廓）、是否可選（交件有宣告才輸出）
Layer = collections.namedtuple("Layer", "names file_field rotates optional", defaults=(False,))
LAYERS = {
    "arm": Layer(ARM_FILES, {"file_pattern": ARM_PATTERN}, True),
    "arm_shadow": Layer(SHADOW_FILES, {"file_pattern": SHADOW_PATTERN}, True),
    "base": Layer([UNDERLAY], {"file": UNDERLAY}, False),
    "base_middle": Layer([MIDDLE], {"file": MIDDLE}, False, True),
    "base_overlay": Layer([OVERLAY], {"file": OVERLAY}, False),
}
# 中層點擊遮罩的 alpha 門檻：刻度環投在唱片上的淡影（< 128）不攔唱片點擊
HIT_ALPHA = 128
SHA256 = re.compile(r"[0-9a-f]{64}")
HASH_TABLES = ("checksums.json", "delivery.json")
# skin_id 也是 App 端的皮膚 id 與 bundle 子資料夾名；classic 保留給內建皮膚
SKIN_ID = re.compile(r"[a-z0-9-]{1,32}")
RESERVED_SKIN_IDS = {"classic"}
OUTLINE_BAND_UNITS = 4
HIT_MARGIN_UNITS = 4
SKIN_SCHEMA = 1


class ImportFailed(Exception):
    def __init__(self, problems):
        super().__init__("\n".join(problems))
        self.problems = problems


def read_json(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"), parse_constant=CHECKER["reject_constant"])
    except (OSError, ValueError) as error:
        raise ImportFailed([f"{path.name}：讀不到或不是 JSON（{type(error).__name__}）"])


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_identity(manifest):
    """skin_id 白名單、檔名樣式＝常數（畫布上限在 checker）"""
    problems = []
    skin_id = manifest.get("skin_id")
    if not isinstance(skin_id, str) or not SKIN_ID.fullmatch(skin_id) or skin_id in RESERVED_SKIN_IDS:
        problems.append(f"skin_id：必須符合 {SKIN_ID.pattern} 且不是 {sorted(RESERVED_SKIN_IDS)}，實際 {skin_id!r}")
    if manifest["arm"].get("file_pattern", ARM_PATTERN) != ARM_PATTERN:
        problems.append(f"arm.file_pattern：必須是 {ARM_PATTERN}，實際 {manifest['arm'].get('file_pattern')!r}")
    return problems


def check_consistency(manifest, motion):
    problems = []
    coords = motion.get("coordinate_system") if isinstance(motion.get("coordinate_system"), dict) else {}
    files = motion.get("files") if isinstance(motion.get("files"), dict) else {}
    if manifest.get("skin_id") != motion.get("skin_id"):
        problems.append(f"skin_id：manifest {manifest.get('skin_id')!r} ≠ motion {motion.get('skin_id')!r}")
    if manifest.get("build_source_sha256") != motion.get("source_build_sha256"):
        problems.append("source build SHA：manifest.build_source_sha256 ≠ motion.source_build_sha256")
    pairs = {"px_per_unit": manifest.get("px_per_unit"), "canvas_px": manifest["arm"].get("canvas_px"),
             "pivot_px": manifest["arm"].get("pivot_px"), "stylus_px_at_local": manifest["arm"].get("stylus_px_at_local")}
    for key, value in pairs.items():
        if coords.get(key) != value:
            problems.append(f"{key}：manifest {value!r} ≠ motion.coordinate_system {coords.get(key)!r}")
    if files.get("arm") != ARM_FILES:
        problems.append("files.arm：motion 的檔名陣列與 manifest 的角度＋檔名樣式展開不一致（逐項依序比對）")
    if files.get("shadow") != SHADOW_FILES:
        problems.append("files.shadow：motion 的檔名陣列與 manifest 的角度展開不一致（逐項依序比對）")
    return problems


def read_hash_tables(root):
    """交件的雜湊表正規化成 {來源檔名: {檔名: (sha256, bytes 或 None)}}：checksums.json＝平面 {檔名: sha256}；
    delivery.json＝files.<檔名>.{sha256, bytes}（Codex Desktop r6 起的格式）。格式不對逐條列出"""
    tables, problems = {}, []
    for source in HASH_TABLES:
        path = root / source
        if not path.exists() and not path.is_symlink():
            continue
        if path.is_symlink():
            problems.append(f"{source}：不接受符號連結")
            continue
        data = read_json(path)
        entries = data.get("files") if source == "delivery.json" and isinstance(data, dict) else data
        if not isinstance(entries, dict):
            problems.append(f"{source}：檔案清單必須是物件")
            continue
        table = {}
        for name, value in entries.items():
            sha, size = (value.get("sha256"), value.get("bytes")) if isinstance(value, dict) else (value, None)
            if source == "checksums.json" and isinstance(value, dict):
                sha = None
            table[name] = (sha, size)
        tables[source] = table
    return tables, problems


def check_hashes(root, names):
    """每個必需檔都要在每張雜湊表上列出且吻合（兩張都有＝兩張都核）；sha256 為 64 位小寫十六進位、bytes 有寫就要等於檔案大小"""
    tables, problems = read_hash_tables(root)
    if not tables and not problems:
        return ["雜湊表：需要 checksums.json 或 delivery.json"]
    for name in names:
        path = root / name
        if path.is_symlink():
            problems.append(f"{name}：不接受符號連結")
            continue
        actual = sha256(path) if path.is_file() else None
        for source, table in tables.items():
            if name not in table:
                problems.append(f"{name}：{source} 沒有列出")
                continue
            sha, size = table[name]
            if not isinstance(sha, str) or not SHA256.fullmatch(sha):
                problems.append(f"{name}：{source} 的 sha256 必須是 64 位小寫十六進位")
            elif actual is not None and sha != actual:
                problems.append(f"{name}：{source} 的 sha256 不符（checksum mismatch）")
            if size is not None and (not isinstance(size, int) or isinstance(size, bool) or size != path.stat().st_size):
                problems.append(f"{name}：{source} 的 bytes 與檔案大小不符")
    return problems


def check_input(root):
    problems = CHECKER["check"](root)
    if problems:
        raise ImportFailed(problems)
    manifest, motion = read_json(root / "manifest.json"), read_json(root / "motion.json")
    problems = check_identity(manifest)
    if problems:
        raise ImportFailed(problems)
    layer_problems, has_middle = CHECKER["check_layers"](root, manifest, motion)
    problems = check_consistency(manifest, motion) + layer_problems
    if problems:
        raise ImportFailed(problems)
    required = ARM_FILES + SHADOW_FILES + [UNDERLAY, OVERLAY, "manifest.json", "motion.json"] + ([MIDDLE] if has_middle else [])
    problems = check_hashes(root, required)
    if problems:
        raise ImportFailed(problems)
    return manifest, motion, has_middle


def image_tool(work):
    """每次都 swiftc -O 編進本次的私有暫存目錄（不跨次快取：預先放在共用暫存區的同名檔不會被執行，安全評審 M-3）"""
    binary = work / "skin_image_tool"
    subprocess.run(["swiftc", "-O", str(IMAGE_TOOL_SOURCE), "-o", str(binary)], check=True, capture_output=True)
    return binary


def run_tool(binary, *args):
    result = subprocess.run([str(binary), *map(str, args)], capture_output=True, text=True)
    if result.returncode != 0:
        raise ImportFailed([f"skin_image_tool：{result.stderr.strip()}"])
    return result.stdout


# 可以整層透明的層：上層底座（例如 Rega r4 起沒有蓋在唱臂上的零件）。App 要求上層必在，輸出支點上 1×1 的透明像素
MAY_BE_EMPTY = {"base_overlay"}


def crop_box(analysis, pivot, name):
    if analysis["bbox"] is None:
        if name in MAY_BE_EMPTY:
            return pivot[0], pivot[1], 1, 1
        raise ImportFailed([f"{name}：整層都是透明"])
    x0, y0, x1, y1 = analysis["bbox"]
    x0, y0 = min(x0, pivot[0]), min(y0, pivot[1])
    x1, y1 = max(x1, pivot[0] - 1), max(y1, pivot[1] - 1)
    return x0, y0, x1 - x0 + 1, y1 - y0 + 1


def outline(analysis, box):
    """裁切框內 u：每 OUTLINE_BAND_UNITS 一列的最左／最右（該層所有幀的聯集；整列透明＝None）"""
    x0, y0, _, height = box
    band = OUTLINE_BAND_UNITS * PX_PER_UNIT
    spans = []
    for top in range(y0, y0 + height, band):
        rows = [r for r in analysis["rows"][top:min(top + band, y0 + height)] if r is not None]
        if not rows:
            spans.append(None)
            continue
        spans.append([(min(r[0] for r in rows) - x0) / PX_PER_UNIT, (max(r[1] for r in rows) + 1 - x0) / PX_PER_UNIT])
    return spans


def hit_runs(binary, path):
    return json.loads(run_tool(binary, "runs", path, HIT_ALPHA))


def import_package(root, out):
    manifest, motion, has_middle = check_input(root)
    pivot = manifest["arm"]["pivot_px"]
    stylus = manifest["arm"]["stylus_px_at_local"]
    with tempfile.TemporaryDirectory() as tmp:
        work = pathlib.Path(tmp)
        binary = image_tool(work)
        staging = work / "out"
        staging.mkdir()
        layers = {}
        for layer, spec in LAYERS.items():
            if spec.optional and not has_middle:
                continue
            analysis = json.loads(run_tool(binary, "analyze", *[root / n for n in spec.names]))
            box = crop_box(analysis, pivot, layer)
            for name in spec.names:
                run_tool(binary, "crop", *box, root / name, staging / name)
            entry = {"size_px": [box[2], box[3]], "pivot_px": [pivot[0] - box[0], pivot[1] - box[1]], **spec.file_field}
            if spec.rotates:
                entry["outline_u"] = outline(analysis, box)
            if layer == "base_middle":
                entry["hit_runs_px"] = hit_runs(binary, staging / MIDDLE)
            layers[layer] = entry
        skin = {
            "schema": SKIN_SCHEMA, "skin_id": manifest["skin_id"], "px_per_unit": PX_PER_UNIT, "frame_count": len(ANGLES),
            "layers": layers,
            "kinematics": {"stylus_at_rest_u": [(stylus[0] - pivot[0]) / PX_PER_UNIT, (stylus[1] - pivot[1]) / PX_PER_UNIT],
                           "rest_degrees": 0},
            "outline_band_u": OUTLINE_BAND_UNITS, "hit_margin_u": HIT_MARGIN_UNITS,
        }
        (staging / "skin.json").write_text(json.dumps(skin, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        (staging / "IMPORT.md").write_text(import_record(root, staging, manifest, motion), encoding="utf-8")
        problems = verify(staging, binary)
        if problems:
            raise ImportFailed(problems)
        replace_output(staging, out)


def import_record(root, staging, manifest, motion):
    files = sorted(p for p in staging.iterdir() if p.suffix == ".png")
    total = sum(p.stat().st_size for p in files)
    lines = [f"# {manifest['skin_id']} 匯入紀錄", "",
             f"- 日期：{datetime.date.today().isoformat()}",
             f"- 工具：`Scripts/import_tonearm_skin.py`（yse-1.0.1-skins.md §4.2）",
             *[f"- 來源雜湊表：{source} sha256 `{sha256(root / source)}`" for source in HASH_TABLES if (root / source).is_file()],
             f"- manifest revision：{manifest.get('revision')!r}；motion revision：{motion.get('revision')!r}",
             f"- source build SHA：`{manifest.get('build_source_sha256')}`",
             f"- 輸出 PNG：{len(files)} 檔、{total} bytes", "", "| 檔案 | sha256 |", "|---|---|"]
    lines += [f"| {p.name} | `{sha256(p)}` |" for p in files]
    return "\n".join(lines) + "\n"


def is_previous_import(out):
    try:
        return read_json(out / "skin.json").get("schema") == SKIN_SCHEMA
    except (ImportFailed, AttributeError):
        return False


def replace_output(staging, out):
    """輸出資料夾只能不存在、或是先前的匯入結果（skin.json 可解析且 schema 相符）；其他內容一律不覆蓋。
    在原資料夾內逐檔替換（同資料夾寫暫存名再單檔改名），再刪掉新結果沒有的舊檔。
    不對調整個資料夾：repo 在 iCloud 同步的 ~/Documents 下，2026-10-26 實測資料夾改名對調後整個輸出資料夾被同步弄掉
    （只留一個空的「 2」副本），檔案靠 git 還原"""
    if out.exists() and (out.is_symlink() or not out.is_dir() or not is_previous_import(out)):
        raise ImportFailed([f"{out}：已存在且不是先前的匯入結果，不覆蓋"])
    out.mkdir(parents=True, exist_ok=True)
    incoming = sorted(p for p in staging.iterdir() if p.is_file())
    for source in incoming:
        partial = out / f".{source.name}.importing"
        shutil.copyfile(source, partial)
        os.replace(partial, out / source.name)
    keep = {p.name for p in incoming}
    for stale in out.iterdir():
        if stale.is_file() and stale.name not in keep:
            stale.unlink()


def runs_problems(runs, size):
    """逐像素列、每段 [x0, x1) 整數、0 ≤ x0 < x1 ≤ 寬、同列遞增不重疊"""
    width, height = size
    if not isinstance(runs, list) or len(runs) != height:
        return [f"layers.base_middle.hit_runs_px：必須逐像素列共 {height} 列"]
    for y, row in enumerate(runs):
        previous = 0
        for run in row if isinstance(row, list) else [None]:
            ok = (isinstance(run, list) and len(run) == 2 and all(isinstance(v, int) and not isinstance(v, bool) for v in run)
                  and previous <= run[0] < run[1] <= width)
            if not ok:
                return [f"layers.base_middle.hit_runs_px：第 {y} 列的區段無效（須整數、遞增、不重疊、在框內）"]
            previous = run[1]
    return []


def verify(out, binary=None):
    try:
        skin = read_json(out / "skin.json")
    except ImportFailed as failed:
        return failed.problems
    problems = []
    count = skin.get("frame_count")
    if skin.get("schema") != SKIN_SCHEMA or skin.get("px_per_unit") != PX_PER_UNIT or count != len(ANGLES):
        problems.append("skin.json：schema／px_per_unit／frame_count 與契約不符")
    layers = skin.get("layers") or {}
    for layer, spec in LAYERS.items():
        entry = layers.get(layer)
        if spec.optional and entry is None:
            stray = [n for n in spec.names if (out / n).exists()]
            problems += [f"{n}：有檔但 skin.json 沒有 layers.{layer}" for n in stray]
            continue
        if not isinstance(entry, dict):
            problems.append(f"skin.json：缺 layers.{layer}")
            continue
        size, pivot = entry.get("size_px"), entry.get("pivot_px")
        if not (CHECKER["is_pair"](size) and CHECKER["is_pair"](pivot) and min(size) > 0
                and 0 <= pivot[0] <= size[0] and 0 <= pivot[1] <= size[1]):
            problems.append(f"layers.{layer}：size_px／pivot_px 無效或支點不在框內")
            continue
        if {k: entry.get(k) for k in spec.file_field} != spec.file_field:
            problems.append(f"layers.{layer}：檔名欄位必須是 {spec.file_field}")
            continue
        names = spec.names
        for name in names:
            info = png_info(out / name) if (out / name).is_file() else None
            if info is None:
                problems.append(f"{name}：缺檔或不是 PNG")
            elif (info[0], info[1]) != tuple(size) or info[2] != RGBA or not info[3]:
                problems.append(f"{name}：必須是 RGBA、有 sRGB／iCCP、尺寸＝skin.json {size}，實際 {info[0]}×{info[1]}")
    if skin.get("outline_band_u") != OUTLINE_BAND_UNITS or skin.get("hit_margin_u") != HIT_MARGIN_UNITS:
        problems.append("skin.json：outline_band_u／hit_margin_u 與契約不符")
    for layer in (name for name, spec in LAYERS.items() if spec.rotates):
        entry = layers.get(layer) or {}
        spans, size = entry.get("outline_u"), entry.get("size_px") or [0, 0]
        width_u, rows = size[0] / PX_PER_UNIT, -(-size[1] // (OUTLINE_BAND_UNITS * PX_PER_UNIT))
        if not isinstance(spans, list) or len(spans) != rows or not any(spans) or any(
                s is not None and not (0 <= s[0] <= s[1] <= width_u) for s in spans):
            problems.append(f"layers.{layer}.outline_u：必須每 {OUTLINE_BAND_UNITS} u 一列、非空、上下界不顛倒、在框內")
    middle = layers.get("base_middle")
    if isinstance(middle, dict) and CHECKER["is_pair"](middle.get("size_px")) and not problems:
        problems += middle_runs_problems(out, middle, binary)
    return problems


def middle_runs_problems(out, middle, binary):
    """格式之外再重解碼輸出的 base_middle.png 逐列重算，必須與 skin.json 完全相同（抓位移、漏列、全空白）"""
    problems = runs_problems(middle.get("hit_runs_px"), middle["size_px"])
    if problems:
        return problems
    if binary is None:
        with tempfile.TemporaryDirectory() as tmp:
            return middle_runs_problems(out, middle, image_tool(pathlib.Path(tmp)))
    if hit_runs(binary, out / MIDDLE) != middle["hit_runs_px"]:
        return ["layers.base_middle.hit_runs_px：與 base_middle.png 重算的結果不同"]
    return []


def main(argv):
    try:
        if len(argv) == 3 and argv[1] == "--verify":
            problems = verify(pathlib.Path(argv[2]))
            if problems:
                raise ImportFailed(problems)
        elif len(argv) == 3:
            import_package(pathlib.Path(argv[1]), pathlib.Path(argv[2]))
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except ImportFailed as failed:
        for problem in failed.problems:
            print(problem)
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
