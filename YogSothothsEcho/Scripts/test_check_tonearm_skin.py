"""check_tonearm_skin.py 的測試（sprint-7-detail.md §4.4，T5）：以程式產生的小 PNG 與 manifest 當交件 fixture。"""
import json
import pathlib
import re
import runpy
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

TOOL = pathlib.Path(__file__).with_name("check_tonearm_skin.py")
ARM = (40, 1500)
BASE = (30, 40)
ARM_PIVOT = (10, 20)


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def png(size, color_type=6, srgb=True):
    width, height = size
    channels = {6: 4, 2: 3}[color_type]
    raw = b"".join(b"\x00" + b"\x00" * (width * channels) for _ in range(height))
    parts = [b"\x89PNG\r\n\x1a\n", chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0))]
    if srgb:
        parts.append(chunk(b"sRGB", b"\x00"))
    parts += [chunk(b"IDAT", zlib.compress(raw)), chunk(b"IEND", b"")]
    return b"".join(parts)


def manifest(**overrides):
    m = {
        "skin_id": "test-arm",
        "px_per_unit": 4,
        "angles_deg": list(range(35)),
        "arm": {"canvas_px": list(ARM), "pivot_px": list(ARM_PIVOT),
                "stylus_px_at_local": [ARM_PIVOT[0] + 24, ARM_PIVOT[1] + 1460]},
        "base": {"canvas_px": list(BASE), "pivot_px": [10, 20]},
        "extent_units_from_pivot": {"right": 40, "up": 60, "left": 120, "down": 380},
    }
    m.update(overrides)
    return m


class CheckTonearmSkinTests(unittest.TestCase):
    def run_tool(self, m=None, skip=(), replace=None):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            (root / "manifest.json").write_text(json.dumps(manifest() if m is None else m), encoding="utf-8")
            files = {f"arm_{i:03d}.png": ARM for i in range(35)}
            files.update({f"arm_shadow_{i:03d}.png": ARM for i in range(35)})
            files["base.png"] = BASE
            for name, size in files.items():
                if name in skip:
                    continue
                data = replace[name] if replace and name in replace else png(size)
                (root / name).write_bytes(data)
            result = subprocess.run([sys.executable, "-I", str(TOOL), str(root)], capture_output=True, text=True)
            return result.returncode, result.stdout + result.stderr

    def assertRejected(self, needle, **kwargs):
        code, out = self.run_tool(**kwargs)
        self.assertEqual(code, 1, out)
        self.assertIn(needle, out)

    def test_valid_delivery_passes(self):
        code, out = self.run_tool()
        self.assertEqual(code, 0, out)

    def test_canvas_has_an_upper_bound(self):
        self.assertRejected("canvas_px", m=manifest(base={"canvas_px": [4097, 40], "pivot_px": [10, 20]}))

    def test_px_per_unit_must_be_the_contract_value(self):
        self.assertRejected("px_per_unit", m=manifest(px_per_unit=3))

    def test_angles_must_be_0_to_34(self):
        self.assertRejected("angles_deg", m=manifest(angles_deg=list(range(34))))
        self.assertRejected("angles_deg", m=manifest(angles_deg=[0, 1, 2, "...", 34]))

    def test_stylus_must_sit_at_the_app_offset(self):
        m = manifest()
        m["arm"]["stylus_px_at_local"] = [ARM_PIVOT[0] + 24, ARM_PIVOT[1] + 1466]
        self.assertRejected("stylus_px_at_local", m=m)

    def test_stylus_within_tolerance_passes(self):
        m = manifest()
        m["arm"]["stylus_px_at_local"] = [ARM_PIVOT[0] + 26, ARM_PIVOT[1] + 1463]
        code, out = self.run_tool(m=m)
        self.assertEqual(code, 0, out)

    def test_extent_budget(self):
        self.assertRejected("extent right", m=manifest(extent_units_from_pivot={"right": 81, "up": 60, "left": 1, "down": 1}))
        self.assertRejected("extent up", m=manifest(extent_units_from_pivot={"right": 1, "up": 129, "left": 1, "down": 1}))

    def test_base_pivot_is_required_and_inside_its_canvas(self):
        m = manifest()
        del m["base"]["pivot_px"]
        self.assertRejected("base.pivot_px", m=m)
        m = manifest()
        m["base"]["pivot_px"] = [10, 41]
        self.assertRejected("base.pivot_px", m=m)

    def test_arm_pivot_inside_its_canvas(self):
        m = manifest()
        m["arm"]["pivot_px"] = [41, 20]
        m["arm"]["stylus_px_at_local"] = [65, 1480]
        self.assertRejected("arm.pivot_px", m=m)

    def test_canvas_must_be_positive(self):
        m = manifest()
        m["base"]["canvas_px"] = [0, 40]
        self.assertRejected("base.canvas_px", m=m)

    def test_missing_file(self):
        self.assertRejected("arm_shadow_007.png", skip={"arm_shadow_007.png"})

    def test_size_mismatch(self):
        self.assertRejected("arm_012.png", replace={"arm_012.png": png((41, 1500))})

    def test_must_be_rgba(self):
        self.assertRejected("base.png", replace={"base.png": png(BASE, color_type=2)})

    def test_needs_a_color_space_chunk(self):
        self.assertRejected("arm_000.png", replace={"arm_000.png": png(ARM, srgb=False)})

    def test_not_a_png(self):
        self.assertRejected("arm_001.png", replace={"arm_001.png": b"GIF89a"})

    def test_truncated_png_is_reported_not_crashed(self):
        self.assertRejected("arm_002.png", replace={"arm_002.png": png(ARM)[:20]})

    def test_png_cut_inside_idat_is_rejected(self):
        whole = png(ARM)
        self.assertRejected("arm_003.png", replace={"arm_003.png": whole[:len(whole) - 20]})

    def test_png_without_iend_is_rejected(self):
        whole = png(ARM)
        self.assertRejected("arm_004.png", replace={"arm_004.png": whole[:len(whole) - 12]})

    def test_nan_in_manifest_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            text = json.dumps(manifest()).replace('"right": 40', '"right": NaN')
            (pathlib.Path(tmp) / "manifest.json").write_text(text, encoding="utf-8")
            result = subprocess.run([sys.executable, "-I", str(TOOL), tmp], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn("manifest.json", result.stdout + result.stderr)

    def test_stylus_offset_matches_the_app_classic_skin(self):
        """針尖位移在 Swift（TurntableSkin.classic）與本腳本各寫一次：兩處必須一致"""
        swift = (TOOL.parent.parent / "Features" / "Turntable" / "TurntableSkin.swift").read_text(encoding="utf-8")
        match = re.search(r"stylusAtRest: CGVector\(dx: (-?\d+(?:\.\d+)?), dy: (-?\d+(?:\.\d+)?)\)", swift)
        self.assertIsNotNone(match)
        spec = runpy.run_path(str(TOOL))
        self.assertEqual((float(match.group(1)), float(match.group(2))), tuple(map(float, spec["STYLUS_OFFSET_UNITS"])))

    def test_unreadable_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            (pathlib.Path(tmp) / "manifest.json").write_text("{", encoding="utf-8")
            result = subprocess.run([sys.executable, "-I", str(TOOL), tmp], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn("manifest.json", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
