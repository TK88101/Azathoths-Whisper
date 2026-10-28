"""import_tonearm_skin.py 的測試（yse-1.0.1-skins.md §4.2、T1）：以程式產生的小交件包跑匯入與輸出驗收。
需要 Mac（裁切由 skin_image_tool.swift 經 swiftc 編譯執行）。"""
import hashlib
import json
import pathlib
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

TOOL = pathlib.Path(__file__).with_name("import_tonearm_skin.py")
CANVAS = (40, 1500)
PIVOT = (10, 20)
# 不透明區（x0, y0, x1, y1，含端點）：arm 每 4 幀往右多 1 px，聯集＝(8, 4)…(19+8, 1490)
ARM_RECT = (8, 4, 19, 1490)
SHADOW_RECT = (10, 10, 24, 1495)
UNDER_RECT = (2, 6, 30, 50)
OVER_RECT = (6, 15, 14, 26)


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def png(size, rect):
    return png_regions(size, [(*rect, 255)])


def png_regions(size, regions):
    """regions：(x0, y0, x1, y1, alpha)（含端點）；後面的蓋前面的"""
    width, height = size
    pixels = [[b"\x00\x00\x00\x00"] * width for _ in range(height)]
    for x0, y0, x1, y1, alpha in regions:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                pixels[y][x] = b"\x80\x80\x80" + bytes([alpha])
    rows = [b"\x00" + b"".join(row) for row in pixels]
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return b"".join([b"\x89PNG\r\n\x1a\n", chunk(b"IHDR", ihdr), chunk(b"sRGB", b"\x00"),
                     chunk(b"IDAT", zlib.compress(b"".join(rows))), chunk(b"IEND", b"")])


def arm_rect(i):
    x0, y0, x1, y1 = ARM_RECT
    return (x0, y0, x1 + i // 4, y1)


TWO_LAYER_ORDER = ["base_underlay", "record", "arm_shadow", "arm", "base_overlay"]
THREE_LAYER_ORDER = ["base_underlay", "record", "base_middle", "arm_shadow", "arm", "base_overlay"]
# 中層：同列兩塊（y 30–40）、alpha 127 的一列（y 42，不算點擊）、alpha 128 的一列（y 44，算）
MIDDLE_REGIONS = [(4, 30, 9, 40, 255), (14, 30, 18, 40, 255), (4, 42, 9, 42, 127), (4, 44, 9, 44, 128)]
DEFAULT = object()


def build_package(root, manifest_patch=None, motion_patch=None, skip=(), corrupt=(), middle=None,
                  middle_declared=DEFAULT, orders=DEFAULT, hashes="checksums", hash_patch=None, regions=None):
    """middle：中層 regions（None＝兩層交件）；orders：{"manifest": [...]|None, "motion": [...]|None}
    （預設：兩層＝都不宣告的舊格式，三層＝兩邊都宣告三層順序）；hashes：checksums／delivery／both／none"""
    if middle_declared is DEFAULT:
        middle_declared = middle is not None
    if orders is DEFAULT:
        orders = {"manifest": None, "motion": None} if middle is None else \
            {"manifest": THREE_LAYER_ORDER, "motion": THREE_LAYER_ORDER}
    stylus = [PIVOT[0] + 24, PIVOT[1] + 1460]
    manifest = {
        "skin_id": "test-arm", "px_per_unit": 4, "angles_deg": list(range(35)),
        "build_source_sha256": "a" * 64, "revision": "r2",
        "arm": {"canvas_px": list(CANVAS), "pivot_px": list(PIVOT), "stylus_px_at_local": stylus, "file_pattern": "arm_%03d.png"},
        "base": {"canvas_px": list(CANVAS), "pivot_px": list(PIVOT), "file": "base.png"},
        "extent_units_from_pivot": {"right": 40, "up": 60, "left": 120, "down": 380},
    }
    motion = {
        "schema_version": 1, "skin_id": "test-arm", "revision": "r3", "source_build_sha256": "a" * 64,
        "coordinate_system": {"canvas_px": list(CANVAS), "px_per_unit": 4, "pivot_px": list(PIVOT), "stylus_px_at_local": stylus},
        "files": {"arm": [f"arm_{i:03d}.png" for i in range(35)], "shadow": [f"arm_shadow_{i:03d}.png" for i in range(35)],
                  "base_underlay": "base_underlay.png", "base_overlay": "base_overlay.png"},
    }
    if middle_declared:
        motion["files"]["base_middle"] = "base_middle.png"
    for target, key in ((manifest, "manifest"), (motion, "motion")):
        if orders.get(key) is not None:
            target["composite_order"] = orders[key]
    for target, patch in ((manifest, manifest_patch), (motion, motion_patch)):
        if patch:
            patch(target)
    images = {f"arm_{i:03d}.png": arm_rect(i) for i in range(35)}
    images.update({f"arm_shadow_{i:03d}.png": SHADOW_RECT for i in range(35)})
    images.update({"base.png": UNDER_RECT, "base_underlay.png": UNDER_RECT, "base_overlay.png": OVER_RECT})
    (root / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    (root / "motion.json").write_text(json.dumps(motion), encoding="utf-8")
    for name, rect in images.items():
        if name in skip:
            continue
        custom = (regions or {}).get(name)
        (root / name).write_bytes(png(CANVAS, rect) if custom is None else png_regions(CANVAS, custom))
    if middle is not None and "base_middle.png" not in skip:
        (root / "base_middle.png").write_bytes(png_regions(CANVAS, middle))
    listed = sorted(p for p in root.iterdir() if p.suffix in (".png", ".json"))
    sums = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in listed}
    delivery = {"skin_id": "test-arm", "revision": "r6",
                "files": {p.name: {"sha256": sums[p.name], "bytes": p.stat().st_size} for p in listed}}
    for name in corrupt:
        (root / name).write_bytes(png(CANVAS, (0, 0, 1, 1)))
    if hash_patch:
        hash_patch(sums, delivery)
    if hashes in ("checksums", "both"):
        (root / "checksums.json").write_text(json.dumps(sums), encoding="utf-8")
    if hashes in ("delivery", "both"):
        (root / "delivery.json").write_text(json.dumps(delivery), encoding="utf-8")


def run(*args):
    result = subprocess.run([sys.executable, "-I", str(TOOL), *map(str, args)], capture_output=True, text=True)
    return result.returncode, result.stdout + result.stderr


class PackageFixture(unittest.TestCase):
    def setUp(self):
        self.tmp = pathlib.Path(tempfile.mkdtemp())
        self.pkg, self.out = self.tmp / "pkg", self.tmp / "out"
        self.pkg.mkdir()

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def import_package(self, **kwargs):
        build_package(self.pkg, **kwargs)
        return run(self.pkg, self.out)

    def assertRejected(self, needle, **kwargs):
        code, out = self.import_package(**kwargs)
        self.assertNotEqual(code, 0, out)
        self.assertIn(needle, out)
        self.assertFalse((self.out / "skin.json").exists(), "失敗時不得留下 skin.json")


class ImportTonearmSkinTests(PackageFixture):
    def test_valid_package_imports_cropped_layers(self):
        code, out = self.import_package()
        self.assertEqual(code, 0, out)
        skin = json.loads((self.out / "skin.json").read_text(encoding="utf-8"))
        self.assertEqual(skin["skin_id"], "test-arm")
        self.assertEqual(skin["px_per_unit"], 4)
        self.assertEqual(skin["frame_count"], 35)
        layers = skin["layers"]
        # 聯集外框 → 裁切框；本地支點＝原支點 − 裁切左上
        self.assertEqual(layers["arm"]["size_px"], [27 - 8 + 1, 1490 - 4 + 1])
        self.assertEqual(layers["arm"]["pivot_px"], [PIVOT[0] - 8, PIVOT[1] - 4])
        self.assertEqual(layers["arm_shadow"]["size_px"], [15, 1486])
        self.assertEqual(layers["arm_shadow"]["pivot_px"], [0, 10])
        self.assertEqual(layers["base"]["file"], "base_underlay.png")
        self.assertEqual(layers["base"]["pivot_px"], [8, 14])
        self.assertEqual(layers["base_overlay"]["size_px"], [9, 12])
        self.assertEqual(skin["kinematics"]["stylus_at_rest_u"], [6, 365])
        for i in (0, 34):
            self.assertTrue((self.out / f"arm_{i:03d}.png").is_file())
            self.assertTrue((self.out / f"arm_shadow_{i:03d}.png").is_file())
        self.assertFalse((self.out / "base.png").exists())
        self.assertIn("來源雜湊表：checksums.json", (self.out / "IMPORT.md").read_text(encoding="utf-8"))
        self.assertNotIn("base_middle", layers)
        self.assertFalse((self.out / "base_middle.png").exists())

    def test_rotating_layers_record_their_visible_outline(self):
        self.import_package()
        skin = json.loads((self.out / "skin.json").read_text(encoding="utf-8"))
        self.assertEqual((skin["outline_band_u"], skin["hit_margin_u"]), (4, 4))
        # arm：裁切框寬 20 px＝5 u、高 1487 px → 每 16 px 一列＝93 列；每列都是聯集最左 0、最右 5 u（不外擴）
        arm = skin["layers"]["arm"]["outline_u"]
        self.assertEqual(len(arm), 93)
        self.assertTrue(all(row == [0, 5] for row in arm))
        # 前幾幀較窄：第 0 幀最右在 x 19 → 若只取 rest 幀會是 12/4＝3 u；聯集取到 27 → 5 u
        shadow = skin["layers"]["arm_shadow"]["outline_u"]
        self.assertEqual(len(shadow), 93)
        self.assertTrue(all(row == [0, 15 / 4] for row in shadow))
        self.assertNotIn("outline_u", skin["layers"]["base"])

    def test_verify_rejects_an_outline_outside_the_frame(self):
        self.import_package()
        path = self.out / "skin.json"
        skin = json.loads(path.read_text(encoding="utf-8"))
        skin["layers"]["arm"]["outline_u"][3] = [0, 99]
        path.write_text(json.dumps(skin), encoding="utf-8")
        code, out = run("--verify", self.out)
        self.assertNotEqual(code, 0, out)
        self.assertIn("layers.arm.outline_u", out)

    def test_verify_mode_accepts_the_import(self):
        self.import_package()
        code, out = run("--verify", self.out)
        self.assertEqual(code, 0, out)

    def test_verify_rejects_a_png_that_does_not_match_skin_json(self):
        self.import_package()
        (self.out / "arm_007.png").write_bytes(png((5, 5), (0, 0, 1, 1)))
        code, out = run("--verify", self.out)
        self.assertNotEqual(code, 0, out)
        self.assertIn("arm_007.png", out)

    def test_verify_rejects_a_missing_shadow_frame(self):
        self.import_package()
        (self.out / "arm_shadow_012.png").unlink()
        code, out = run("--verify", self.out)
        self.assertNotEqual(code, 0, out)
        self.assertIn("arm_shadow_012.png", out)

    def test_checker_failure_stops_the_import(self):
        self.assertRejected("px_per_unit", manifest_patch=lambda m: m.update(px_per_unit=3))

    def test_skin_id_must_match(self):
        self.assertRejected("skin_id", motion_patch=lambda m: m.update(skin_id="other"))

    def test_source_build_sha_must_match(self):
        self.assertRejected("source", motion_patch=lambda m: m.update(source_build_sha256="b" * 64))

    def test_geometry_must_match(self):
        for key, value in (("pivot_px", [11, 20]), ("canvas_px", [41, 1500]), ("stylus_px_at_local", [35, 1480])):
            with self.subTest(key=key):
                self.assertRejected(key, motion_patch=lambda m, k=key, v=value: m["coordinate_system"].update({k: v}))
                shutil.rmtree(self.out, ignore_errors=True)

    def test_motion_frame_list_must_match_the_manifest_pattern(self):
        self.assertRejected("files.arm", motion_patch=lambda m: m["files"]["arm"].pop())
        self.assertRejected("files.shadow", motion_patch=lambda m: m["files"]["shadow"].reverse())

    def test_checksum_mismatch_stops_the_import(self):
        self.assertRejected("checksum", corrupt=("arm_010.png",))

    # 安全評審 M-1／M-2／LOW：檔名不拿資料組、skin_id 白名單、不跟隨符號連結、不覆蓋非匯入結果的資料夾
    def test_arm_file_pattern_must_be_the_contract_constant(self):
        self.assertRejected("arm.file_pattern", manifest_patch=lambda m: m["arm"].update(file_pattern="arm_%s.png"))
        self.assertRejected("arm.file_pattern", manifest_patch=lambda m: m["arm"].update(file_pattern="/private/tmp/x_%03d.png"))

    def test_skin_id_must_be_a_safe_non_reserved_slug(self):
        for bad in ("classic", "../evil", "Has Space", "x" * 33):
            with self.subTest(skin_id=bad):
                self.assertRejected("skin_id", manifest_patch=lambda m, b=bad: m.update(skin_id=b),
                                    motion_patch=lambda m, b=bad: m.update(skin_id=b))
                shutil.rmtree(self.out, ignore_errors=True)
                shutil.rmtree(self.pkg)
                self.pkg.mkdir()

    def test_symlinked_input_is_rejected(self):
        build_package(self.pkg)
        target = self.tmp / "elsewhere.png"
        (self.pkg / "arm_005.png").rename(target)
        (self.pkg / "arm_005.png").symlink_to(target)
        code, out = run(self.pkg, self.out)
        self.assertNotEqual(code, 0, out)
        self.assertIn("符號連結", out)

    def test_existing_folder_that_is_not_an_import_is_not_overwritten(self):
        self.out.mkdir()
        (self.out / "keep.txt").write_text("mine", encoding="utf-8")
        (self.out / "skin.json").write_text("{}", encoding="utf-8")
        code, out = self.import_package()
        self.assertNotEqual(code, 0, out)
        self.assertEqual((self.out / "keep.txt").read_text(encoding="utf-8"), "mine")

    def test_reimport_replaces_the_previous_output(self):
        self.import_package()
        (self.out / "stale.png").write_bytes(b"old")
        code, out = run(self.pkg, self.out)
        self.assertEqual(code, 0, out)
        self.assertFalse((self.out / "stale.png").exists())
        self.assertEqual([p.name for p in self.out.iterdir() if p.name.startswith(".")], [], "暫存檔要清掉")
        self.assertEqual(sorted(p.name for p in self.tmp.iterdir()), ["out", "pkg"], "不在輸出資料夾外留任何東西")

    def test_verify_rejects_a_tampered_file_pattern(self):
        self.import_package()
        path = self.out / "skin.json"
        skin = json.loads(path.read_text(encoding="utf-8"))
        skin["layers"]["arm"]["file_pattern"] = "arm_%s.png"
        path.write_text(json.dumps(skin), encoding="utf-8")
        code, out = run("--verify", self.out)
        self.assertNotEqual(code, 0, out)
        self.assertIn("layers.arm", out)

    def test_missing_underlay_stops_the_import(self):
        self.assertRejected("base_underlay.png", skip=("base_underlay.png",))



class MiddleLayerTests(PackageFixture):
    """CR-034 增補 B §4.2：可選的第三層底座 base_middle＋雜湊表兩種格式"""

    def skin(self):
        return json.loads((self.out / "skin.json").read_text(encoding="utf-8"))

    def rejected_again(self, needle, **kwargs):
        shutil.rmtree(self.out, ignore_errors=True)
        shutil.rmtree(self.pkg)
        self.pkg.mkdir()
        self.assertRejected(needle, **kwargs)

    def test_middle_layer_is_cropped_and_records_pixel_runs(self):
        code, out = self.import_package(middle=MIDDLE_REGIONS)
        self.assertEqual(code, 0, out)
        entry = self.skin()["layers"]["base_middle"]
        # alpha>0 外接框 (4,30)…(18,44) 擴到含支點 (10,20) → 框 (4,20) 15×25；本地支點 (6,0)
        self.assertEqual(entry["file"], "base_middle.png")
        self.assertEqual(entry["size_px"], [15, 25])
        self.assertEqual(entry["pivot_px"], [6, 0])
        runs = entry["hit_runs_px"]
        self.assertEqual(len(runs), 25, "逐像素列")
        self.assertEqual(runs[0], [])
        self.assertEqual(runs[10], [[0, 6], [10, 15]], "同列兩塊＝兩段（半開區間）")
        self.assertEqual(runs[22], [], "alpha 127 不算")
        self.assertEqual(runs[24], [[0, 6]], "alpha 128 算")
        self.assertTrue((self.out / "base_middle.png").is_file())
        code, out = run("--verify", self.out)
        self.assertEqual(code, 0, out)

    def test_declared_middle_without_its_file_is_rejected(self):
        self.assertRejected("base_middle", middle=MIDDLE_REGIONS, skip=("base_middle.png",))

    def test_middle_file_must_be_declared_in_motion(self):
        self.assertRejected("base_middle", middle=MIDDLE_REGIONS, middle_declared=False)

    def test_order_with_middle_needs_the_layer(self):
        self.assertRejected("composite_order", orders={"manifest": THREE_LAYER_ORDER, "motion": THREE_LAYER_ORDER})

    def test_order_without_middle_rejects_a_declared_middle(self):
        self.assertRejected("composite_order", middle=MIDDLE_REGIONS,
                            orders={"manifest": TWO_LAYER_ORDER, "motion": TWO_LAYER_ORDER})

    def test_old_format_without_order_cannot_carry_a_middle(self):
        self.assertRejected("composite_order", middle=MIDDLE_REGIONS, orders={"manifest": None, "motion": None})

    def test_order_must_be_the_contract_sequence(self):
        bad = (["base_underlay", "record", "arm_shadow", "base_middle", "arm", "base_overlay"],
               THREE_LAYER_ORDER + ["base_middle"], ["base_underlay", "record", "glow", "arm_shadow", "arm", "base_overlay"])
        for order in bad:
            with self.subTest(order=order):
                self.rejected_again("composite_order", middle=MIDDLE_REGIONS, orders={"manifest": order, "motion": order})

    def test_manifest_and_motion_orders_must_agree(self):
        self.assertRejected("composite_order", middle=MIDDLE_REGIONS,
                            orders={"manifest": THREE_LAYER_ORDER, "motion": TWO_LAYER_ORDER})

    def test_two_layer_order_declared_on_one_side_is_accepted(self):
        code, out = self.import_package(orders={"manifest": None, "motion": TWO_LAYER_ORDER})
        self.assertEqual(code, 0, out)

    def test_delivery_json_alone_is_accepted(self):
        code, out = self.import_package(middle=MIDDLE_REGIONS, hashes="delivery")
        self.assertEqual(code, 0, out)
        self.assertIn("來源雜湊表：delivery.json", (self.out / "IMPORT.md").read_text(encoding="utf-8"))

    def test_both_hash_tables_must_agree(self):
        def disagree(sums, delivery):
            sums["arm_003.png"] = "0" * 64
        self.assertRejected("arm_003.png", hashes="both", hash_patch=disagree)

    def test_a_hash_table_is_required(self):
        self.assertRejected("雜湊表", hashes="none")

    def test_delivery_sha_must_be_lowercase_hex(self):
        def upper(sums, delivery):
            delivery["files"]["arm_000.png"]["sha256"] = delivery["files"]["arm_000.png"]["sha256"].upper()
        self.assertRejected("arm_000.png", hashes="delivery", hash_patch=upper)

    def test_delivery_bytes_must_match_the_file(self):
        def wrong_size(sums, delivery):
            delivery["files"]["base_overlay.png"]["bytes"] += 1
        self.assertRejected("base_overlay.png", hashes="delivery", hash_patch=wrong_size)

    def test_every_required_file_must_be_listed(self):
        def drop(sums, delivery):
            del delivery["files"]["base_middle.png"]
        self.assertRejected("base_middle.png", middle=MIDDLE_REGIONS, hashes="delivery", hash_patch=drop)

    def test_verify_recomputes_the_runs_from_the_png(self):
        self.import_package(middle=MIDDLE_REGIONS)
        path = self.out / "skin.json"
        skin = json.loads(path.read_text(encoding="utf-8"))
        skin["layers"]["base_middle"]["hit_runs_px"][10] = [[1, 7], [10, 15]]
        path.write_text(json.dumps(skin), encoding="utf-8")
        code, out = run("--verify", self.out)
        self.assertNotEqual(code, 0, out)
        self.assertIn("hit_runs_px", out)

    def test_verify_rejects_malformed_runs(self):
        for bad in ([[6, 0]], [[0, 6], [5, 9]], [[0, 99]]):
            with self.subTest(runs=bad):
                shutil.rmtree(self.out, ignore_errors=True)
                self.import_package(middle=MIDDLE_REGIONS)
                path = self.out / "skin.json"
                skin = json.loads(path.read_text(encoding="utf-8"))
                skin["layers"]["base_middle"]["hit_runs_px"][10] = bad
                path.write_text(json.dumps(skin), encoding="utf-8")
                code, out = run("--verify", self.out)
                self.assertNotEqual(code, 0, out)
                self.assertIn("hit_runs_px", out)

    def test_fully_transparent_overlay_becomes_a_one_pixel_layer_at_the_pivot(self):
        """Rega r4 起：上層沒有零件、交全透明 PNG。App 的格式要求上層必在 → 裁成支點上的 1×1 透明像素"""
        code, out = self.import_package(middle=MIDDLE_REGIONS, regions={"base_overlay.png": []})
        self.assertEqual(code, 0, out)
        overlay = self.skin()["layers"]["base_overlay"]
        self.assertEqual((overlay["size_px"], overlay["pivot_px"]), ([1, 1], [0, 0]))
        code, out = run("--verify", self.out)
        self.assertEqual(code, 0, out)

    def test_fully_transparent_underlay_or_middle_is_still_rejected(self):
        self.assertRejected("整層都是透明", regions={"base_underlay.png": []})
        self.rejected_again("整層都是透明", middle=[])

    def test_verify_rejects_a_middle_png_without_its_layer(self):
        self.import_package()
        (self.out / "base_middle.png").write_bytes(png((5, 5), (0, 0, 1, 1)))
        code, out = run("--verify", self.out)
        self.assertNotEqual(code, 0, out)
        self.assertIn("base_middle.png", out)


if __name__ == "__main__":
    unittest.main()
