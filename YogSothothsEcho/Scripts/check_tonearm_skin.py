"""唱臂皮膚交件檢查（sprint-7-detail.md §4.4，T5；規格＝~/Desktop/YSE-唱機皮膚-唱臂算圖-prompt.md §1、§4、§8）。

manifest v1＝固定幾何：支點與針尖照 App 現行位置（針尖＝支點＋(6, 365) u），只換外觀。規則只定義在這裡；
App 內的載入檢查等 CR-034 真的載入素材時再照搬。

分層規則（CR-034 增補 B §4.2）也只定義在這裡：底座兩層或三層（可選的 base_middle）、composite_order、motion 的宣告，
三者必須一致；匯入器呼叫 `check_layers`，不另寫一套。

用法：python3 -I Scripts/check_tonearm_skin.py <skin_dir>
核心幾何＋（有 motion.json 時）分層規則。全部符合 → 印 OK、退出 0；否則逐條列出不符項目、退出 1。
"""
import json
import math
import pathlib
import struct
import sys

PX_PER_UNIT = 4
ANGLES = list(range(35))
STYLUS_OFFSET_UNITS = (6, 365)
STYLUS_TOLERANCE_PX = 4
EXTENT_BUDGET_UNITS = {"right": 80, "up": 128}
# 交件檔名（CR-034：App `SpriteSkinAssets` 與匯入器都以此為準，`test_skin_file_contract.py` 守跨語言一致）
ARM_PATTERN = "arm_%03d.png"
SHADOW_PATTERN = "arm_shadow_%03d.png"
UNDERLAY, MIDDLE, OVERLAY = "base_underlay.png", "base_middle.png", "base_overlay.png"
# 合成順序（由下而上）：中層可選，有就夾在唱片與唱臂投影之間
TWO_LAYER_ORDER = ["base_underlay", "record", "arm_shadow", "arm", "base_overlay"]
THREE_LAYER_ORDER = ["base_underlay", "record", "base_middle", "arm_shadow", "arm", "base_overlay"]
# 畫布每邊上限（宣稱極大尺寸的 PNG 會讓解碼配置數十 GB；CR-034 安全評審）
MAX_CANVAS_PX = 4096
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
RGBA = 6
COLOR_SPACE_CHUNKS = {b"sRGB", b"iCCP"}


def is_pair(value):
    return isinstance(value, list) and len(value) == 2 and all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in value)


def check_canvas(m, part, problems):
    section = m.get(part)
    if not isinstance(section, dict):
        problems.append(f"{part}：缺少")
        return None
    canvas, pivot = section.get("canvas_px"), section.get("pivot_px")
    if not is_pair(canvas) or min(canvas) <= 0 or max(canvas) > MAX_CANVAS_PX:
        problems.append(f"{part}.canvas_px：必須是兩個正數且每邊 ≤ {MAX_CANVAS_PX}，實際 {canvas!r}")
        return None
    if not is_pair(pivot):
        problems.append(f"{part}.pivot_px：缺少或格式不對，實際 {pivot!r}")
    elif not (0 <= pivot[0] <= canvas[0] and 0 <= pivot[1] <= canvas[1]):
        problems.append(f"{part}.pivot_px：{pivot} 不在畫布 {canvas} 內")
    return tuple(canvas)


def check_manifest(m):
    problems = []
    if m.get("px_per_unit") != PX_PER_UNIT:
        problems.append(f"px_per_unit：必須是 {PX_PER_UNIT}，實際 {m.get('px_per_unit')!r}")
    if m.get("angles_deg") != ANGLES:
        problems.append("angles_deg：必須是 0…34 的連續整數")
    arm = check_canvas(m, "arm", problems)
    base = check_canvas(m, "base", problems)
    arm_section = m.get("arm") if isinstance(m.get("arm"), dict) else {}
    pivot, stylus = arm_section.get("pivot_px"), arm_section.get("stylus_px_at_local")
    if is_pair(pivot) and is_pair(stylus):
        expected = (pivot[0] + STYLUS_OFFSET_UNITS[0] * PX_PER_UNIT, pivot[1] + STYLUS_OFFSET_UNITS[1] * PX_PER_UNIT)
        miss = math.dist(stylus, expected)
        if miss > STYLUS_TOLERANCE_PX:
            problems.append(f"arm.stylus_px_at_local：應為 {list(expected)}（±{STYLUS_TOLERANCE_PX} px），實際 {stylus}，差 {miss:.1f} px")
    elif not is_pair(stylus):
        problems.append(f"arm.stylus_px_at_local：缺少或格式不對，實際 {stylus!r}")
    extent = m.get("extent_units_from_pivot")
    if not isinstance(extent, dict):
        problems.append("extent_units_from_pivot：缺少")
    else:
        for side, limit in EXTENT_BUDGET_UNITS.items():
            value = extent.get(side)
            if not isinstance(value, (int, float)) or value > limit:
                problems.append(f"extent {side}：必須 ≤ {limit} u，實際 {value!r}")
    return problems, arm, base


def png_info(path):
    """(寬, 高, 色彩型態, IDAT 之前是否有色彩空間 chunk)。不是 PNG、任何 chunk 超出檔尾（截斷）、
    沒有 IDAT 或沒有以完整 IEND 結束，都回 None——這種檔 App 解不出來"""
    data = path.read_bytes()
    if len(data) < 26 or not data.startswith(PNG_SIGNATURE) or data[12:16] != b"IHDR":
        return None
    width, height, _, color_type = struct.unpack(">IIBB", data[16:26])
    has_color_space, seen_data, offset = False, False, len(PNG_SIGNATURE)
    while offset + 12 <= len(data):
        length, kind = struct.unpack(">I", data[offset:offset + 4])[0], data[offset + 4:offset + 8]
        end = offset + 12 + length
        if end > len(data):
            return None
        if kind in COLOR_SPACE_CHUNKS and not seen_data:
            has_color_space = True
        seen_data = seen_data or kind == b"IDAT"
        if kind == b"IEND":
            return (width, height, color_type, has_color_space) if seen_data and end == len(data) else None
        offset = end
    return None


def check_files(root, arm, base):
    problems = []
    expected = {ARM_PATTERN % i: arm for i in ANGLES}
    expected.update({SHADOW_PATTERN % i: arm for i in ANGLES})
    expected["base.png"] = base
    for name, size in expected.items():
        path = root / name
        if not path.is_file():
            problems.append(f"{name}：缺檔")
            continue
        info = png_info(path)
        if info is None:
            problems.append(f"{name}：不是 PNG")
            continue
        width, height, color_type, has_color_space = info
        if size is not None and (width, height) != size:
            problems.append(f"{name}：尺寸 {width}×{height}，manifest 是 {size[0]}×{size[1]}")
        if color_type != RGBA:
            problems.append(f"{name}：必須是 RGBA（color type 6），實際 {color_type}")
        if not has_color_space:
            problems.append(f"{name}：缺 sRGB 或 iCCP chunk")
    return problems


def check_still(root, name, canvas):
    """固定底座層：RGBA、尺寸＝畫布、有色彩空間"""
    path = root / name
    info = png_info(path) if path.is_file() and not path.is_symlink() else None
    if info is None:
        return [f"{name}：缺檔或不是 PNG"]
    if (info[0], info[1]) != canvas or info[2] != RGBA or not info[3]:
        return [f"{name}：必須是 RGBA、有 sRGB／iCCP、尺寸＝畫布 {canvas}"]
    return []


def check_layers(root, manifest, motion):
    """底座分層：motion.files 的宣告、base_middle.png 實體、composite_order（manifest／motion 有宣告者都核）三者一致。
    composite_order 兩邊都沒宣告＝舊兩層格式，不得有中層。回傳 (problems, 有沒有中層)"""
    problems = []
    files = motion.get("files") if isinstance(motion.get("files"), dict) else {}
    for key, name in (("base_underlay", UNDERLAY), ("base_overlay", OVERLAY)):
        if files.get(key) != name:
            problems.append(f"files.{key}：必須是 {name}，實際 {files.get(key)!r}")
    declared = "base_middle" in files
    if declared and files["base_middle"] != MIDDLE:
        problems.append(f"files.base_middle：必須是 {MIDDLE}，實際 {files['base_middle']!r}")
    exists = (root / MIDDLE).exists() or (root / MIDDLE).is_symlink()
    orders = {source: data["composite_order"] for source, data in (("manifest", manifest), ("motion", motion))
              if "composite_order" in data}
    if len(orders) == 2 and orders["manifest"] != orders["motion"]:
        problems.append("composite_order：manifest 與 motion 不同")
    in_order = False
    for source, order in orders.items():
        if order not in (TWO_LAYER_ORDER, THREE_LAYER_ORDER):
            problems.append(f"{source}.composite_order：必須是 {TWO_LAYER_ORDER} 或 {THREE_LAYER_ORDER}，實際 {order!r}")
        in_order = in_order or order == THREE_LAYER_ORDER
    if declared != exists:
        problems.append(f"base_middle：motion.files 宣告＝{declared}、{MIDDLE} 存在＝{exists}，必須一致")
    if (declared or exists) != in_order:
        state = "含 base_middle" if in_order else ("沒有宣告（舊兩層格式）" if not orders else "不含 base_middle")
        problems.append(f"composite_order：{state}，與 motion.files／{MIDDLE} 不一致")
    section = manifest.get("arm") if isinstance(manifest.get("arm"), dict) else {}
    canvas = tuple(section["canvas_px"]) if is_pair(section.get("canvas_px")) else None
    if canvas is None:
        problems.append("arm.canvas_px：無法核對底座層尺寸")
    else:
        for name in [UNDERLAY, OVERLAY] + ([MIDDLE] if exists else []):
            problems += check_still(root, name, canvas)
    return problems, not problems and in_order


def read_json_file(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"), parse_constant=reject_constant), None
    except (OSError, ValueError) as error:
        return None, f"{path.name}：讀不到或不是 JSON（{type(error).__name__}）"


def check_package(root):
    """命令列：核心幾何，加上有 motion.json 時的分層規則"""
    problems = check(root)
    if problems or not (root / "motion.json").is_file():
        return problems
    manifest, error = read_json_file(root / "manifest.json")
    motion, error2 = read_json_file(root / "motion.json")
    if error or error2 or not isinstance(motion, dict):
        return [e for e in (error, error2) if e] or ["motion.json：最外層必須是物件"]
    return check_layers(root, manifest, motion)[0]


def reject_constant(name):
    """json 預設接受 NaN／Infinity；任何比較遇到 NaN 都是 False，會讓數值規則全部被放過"""
    raise ValueError(f"不接受 {name}")


def check(root):
    manifest_path = root / "manifest.json"
    try:
        m = json.loads(manifest_path.read_text(encoding="utf-8"), parse_constant=reject_constant)
    except (OSError, ValueError) as error:
        return [f"manifest.json：讀不到或不是 JSON（{type(error).__name__}）"]
    if not isinstance(m, dict):
        return ["manifest.json：最外層必須是物件"]
    problems, arm, base = check_manifest(m)
    return problems + check_files(root, arm, base)


def main(argv):
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    problems = check_package(pathlib.Path(argv[1]))
    for problem in problems:
        print(problem)
    if problems:
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
