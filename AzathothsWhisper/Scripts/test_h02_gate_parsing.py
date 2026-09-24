#!/usr/bin/env python3
"""h02_gate_eval.py 的單元測試：逐行／逐訊息解析（拆自 `test_h02_gate_eval.py`）。

執行：cd AzathothsWhisper/Scripts && /usr/bin/python3 -m unittest discover -s . -p 'test_h02_gate*.py'
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path

import h02_gate_eval as gate
from test_h02_gate_fixtures import load_fixture


class ParsingHelpersTests(unittest.TestCase):
    def test_strip_swift_prefix_removes_file_line_prefix(self):
        text = "CoverFlowUITests.swift:288: SIG{T4.s2|C1-OFFSET|label=T19}"
        self.assertEqual(gate.strip_swift_prefix(text), "SIG{T4.s2|C1-OFFSET|label=T19}")

    def test_strip_swift_prefix_noop_when_absent(self):
        text = "[PROBE-AX] 逾時"
        self.assertEqual(gate.strip_swift_prefix(text), text)

    def test_parse_gate_token_pass(self):
        g = gate.parse_gate_token("GATE{T4.s1|PASS}")
        self.assertEqual((g.step, g.status, g.codes), ("s1", "PASS", ()))

    def test_parse_gate_token_fail_single_code(self):
        g = gate.parse_gate_token("some prefix GATE{T4.s2|FAIL|C1-OFFSET} trailing")
        self.assertEqual((g.step, g.status, g.codes), ("s2", "FAIL", ("C1-OFFSET",)))

    def test_parse_gate_token_fail_multi_code(self):
        g = gate.parse_gate_token("GATE{T4.s2|FAIL|C1-OFFSET,C2-STACK}")
        self.assertEqual(g.codes, ("C1-OFFSET", "C2-STACK"))

    def test_parse_gate_token_fail_mixed_product_and_probe(self):
        g = gate.parse_gate_token("GATE{T2.s1|FAIL|C3-TARGET-MISS,PROBE-OFFCARD}")
        self.assertEqual(g.codes, ("C3-TARGET-MISS", "PROBE-OFFCARD"))

    def test_parse_gate_token_returns_none_when_absent(self):
        self.assertIsNone(gate.parse_gate_token("plain log line, no gate here"))

    def test_parse_failure_message_sig(self):
        f = gate.parse_failure_message(
            "CoverFlowUITests.swift:288: SIG{T4.s2|C1-OFFSET|label=T19|centered=T16|strides=+3}"
        )
        self.assertEqual(f.kind, "SIG")
        self.assertEqual(f.step, "s2")
        self.assertEqual(f.code, "C1-OFFSET")
        self.assertEqual(f.fields, (("label", "T19"), ("centered", "T16"), ("strides", "+3")))
        self.assertEqual(f.sig_key, "C1-OFFSET|label=T19|centered=T16|strides=+3")

    def test_parse_failure_message_probe(self):
        f = gate.parse_failure_message("[PROBE-AX-CULL] 容器缺子項標識")
        self.assertEqual(f.kind, "PROBE")
        self.assertEqual(f.probe_name, "AX-CULL")

    def test_parse_failure_message_untagged(self):
        f = gate.parse_failure_message("CoverFlowUITests.swift:9: XCTAssertTrue failed")
        self.assertEqual(f.kind, "UNTAGGED")


class RealXcresultFormatTests(unittest.TestCase):
    """真實 xcresult 的失敗文字＝`<檔>.swift:<行>: failed - <XCTFail 訊息>`（2026-09-11 cf-m0 實測）。
    舊夾具少了 `failed - ` 包裝，腳本在真實運行上把全部 SIG 判成 UNTAGGED（計劃 §3.12 R2-6 的 dry-run 缺口）。"""

    def test_xctfail_wrapped_sig_is_parsed_as_sig(self):
        f = gate.parse_failure_message(
            "CoverFlowUITests.swift:74: failed - SIG{T4.s2|C1-OFFSET|label=T19|centered=T16|strides=+3}"
        )
        self.assertEqual((f.kind, f.step, f.code), ("SIG", "s2", "C1-OFFSET"))
        self.assertEqual(f.sig_key, "C1-OFFSET|label=T19|centered=T16|strides=+3")

    def test_xctfail_wrapped_probe_is_parsed_as_probe(self):
        f = gate.parse_failure_message("CoverFlowUITests.swift:163: failed - [PROBE-FOREGROUND] T1.s3 state=3")
        self.assertEqual((f.kind, f.probe_name), ("PROBE", "FOREGROUND"))

    def test_framework_failure_is_untagged(self):
        # 真實樣本：spike.xcresult 裡 XCUI 框架自身的失敗（不經 XCTFail）
        f = gate.parse_failure_message(
            "CoverFlowUITests.swift:241: Unable to find hit point for ScrollView, "
            "{{265.0, 131.0}, {680.0, 664.0}}, identifier: 'coverflow-strip'"
        )
        self.assertEqual(f.kind, "UNTAGGED")

    def test_other_assertion_wrapper_stays_untagged(self):
        # 契約只經 XCTFail 發 SIG；其他斷言巨集的包裝不視為訊息通道
        f = gate.parse_failure_message("CoverFlowUITests.swift:200: XCTAssertTrue failed - SIG{T1.s1|C1-OFFSET}")
        self.assertEqual(f.kind, "UNTAGGED")

    def test_real_m0_fixture_two_sigs_same_step(self):
        log_text, xc_json = load_fixture("real_m0_t4")
        table = gate.build_table(log_text, xc_json, expected_iterations=2)
        self.assertEqual(table.errors, [])
        self.assertEqual(table.iteration_count_mismatch, {})
        for info in table.iterations["T4"]:
            self.assertFalse(info.invalid, info.invalid_reasons)
            self.assertEqual(info.cells["s1"].sig_set, frozenset({"C2-STACK|G=T19|over=T18|side=L"}))
            self.assertEqual(
                info.cells["s2"].sig_set,
                frozenset({"C1-OFFSET|label=T19|centered=T16|strides=+3", "C2-STACK|G=T16|over=T17|side=R"}),
            )
        # 夾具只截了 T4：解析本身無誤，但 R4 的 table_valid 要求 T1–T4 全在
        valid, reasons = gate.table_valid(table, 2)
        self.assertFalse(valid)
        self.assertTrue(any("T1" in r for r in reasons), reasons)


class ProductCodeSingleSourceTests(unittest.TestCase):
    """單一源頭紀律：Python 的 PRODUCT_CODES 必須與 Swift 產出端的 `code: "C…"` 字面量集合一致
    （計劃 `docs/plans/2026-09-11-coverflow-h02-uitest-gate.md`）；兩側任一邊新增/刪除產品碼卻忘了
    同步另一邊，這條測試要紅。"""

    CODE_LITERAL_RE = re.compile(r'code: "(C[^"]*)"')

    def test_python_product_codes_match_swift_source(self):
        scripts_dir = Path(__file__).resolve().parent
        swift_paths = [
            scripts_dir / ".." / "App" / "UITestSupport" / "CoverFlowGateLogic.swift",
            scripts_dir / ".." / "UITests" / "CoverFlowUITests.swift",
        ]
        swift_codes = set()
        for path in swift_paths:
            text = path.resolve().read_text(encoding="utf-8")
            swift_codes.update(self.CODE_LITERAL_RE.findall(text))

        self.assertEqual(swift_codes, set(gate.PRODUCT_CODES))


if __name__ == "__main__":
    unittest.main()
