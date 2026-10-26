"""echo_gate.py 的測試（sprint-1-detail.md §4.3 E1–E6）。每條規則至少一個負對照被抓、一個正對照通過；
E2–E4 的負對照含 S0 spike 的實際寫法與 Codex 指出的繞過寫法。"""
import pathlib
import subprocess
import sys
import unittest

GATE = pathlib.Path(__file__).with_name("echo_gate.py")
ROOT = GATE.parent.parent
BRIDGE = "Packages/EchoKit/Sources/MusicRemoteBridge/"
LOOKUP = BRIDGE + "TrackLookup.swift"
RUNNER = BRIDGE + "ShortcutRunner.swift"
READER = BRIDGE + "LibraryReader.swift"


def check(path, source):
    result = subprocess.run([sys.executable, "-I", str(GATE), "--stdin", path], input=source,
                            capture_output=True, text=True)
    return result.returncode, result.stderr


class EchoGateTests(unittest.TestCase):
    def assertCaught(self, rule, path, source):
        code, err = check(path, source)
        self.assertEqual(code, 1, f"應被 {rule} 抓到：{path}\n{source}")
        self.assertIn(f"[{rule}]", err)

    def assertPasses(self, path, source):
        code, err = check(path, source)
        self.assertEqual(code, 0, f"不應違規：{path}\n{err}")

    def test_repository_passes_the_gate(self):
        result = subprocess.run([sys.executable, "-I", str(GATE)], capture_output=True, text=True, cwd=ROOT)
        self.assertEqual(result.returncode, 0, result.stderr)

    # E1
    def test_e1_scripting_bridge_outside_bridge_is_caught(self):
        self.assertCaught("E1", "Packages/EchoKit/Sources/RemoteTransport/X.swift", "import ScriptingBridge\n")
        self.assertCaught("E1", "Features/Shell/X.swift", "import iTunesLibrary\n")

    def test_e1_import_with_attributes_or_access_level_is_caught(self):
        for snippet in ["@preconcurrency import ScriptingBridge", "internal import iTunesLibrary",
                        "@_exported import ScriptingBridge", "import class ScriptingBridge.SBApplication",
                        "@preconcurrency public import ScriptingBridge"]:
            self.assertCaught("E1", "Packages/EchoKit/Sources/RemoteTransport/X.swift", snippet + "\n")

    def test_e1_scripting_bridge_inside_bridge_passes(self):
        self.assertPasses(BRIDGE + "Client.swift", "#if os(macOS)\nimport ScriptingBridge\n#endif\n")
        # iTunesLibrary 自 S3 起只許 LibraryReader.swift（E7，負對照見 test_e7_*）
        self.assertPasses(READER, "#if os(macOS)\nimport iTunesLibrary\n#endif\n")

    # E2
    def test_e2_dynamic_dispatch_and_kvc_in_bridge_are_caught(self):
        for snippet in [
            'let x = music.value(forKey: "tracks")',
            'let x = music.value(forKey: ["tr","acks"].joined())',
            'music.perform(NSSelectorFromString("tra" + "cks"))',
            'let s = #selector(getter: X.tracks)',
            'let e = NSExpression(forKeyPath: ["tr","acks"].joined()).expressionValue(with: music, context: nil)',
            'music.setValue(1, forKey: "soundVolume")',
            'let r = music.responds(to: s)',
            'let h = dlsym(nil, "objc_msgSend")',
            'import Network',
            'let s = NSAppleScript(source: "x")',
        ]:
            self.assertCaught("E2", BRIDGE + "Client.swift", snippet + "\n")

    def test_e2_predicate_outside_track_lookup_is_caught(self):
        self.assertCaught("E2", BRIDGE + "Client.swift", 'let p = NSPredicate(format: "persistentID == %@", id)\n')

    def test_e2_static_protocol_call_passes(self):
        self.assertPasses(BRIDGE + "Client.swift", "let state = music.playerState?\nmusic.playpause?()\n")

    def test_e2_comment_is_ignored(self):
        self.assertPasses(BRIDGE + "Client.swift", "// do not use value(forKey:) here\nlet a = 1\n")

    # E3
    def test_e3_spike_style_tracks_call_outside_lookup_is_caught(self):
        for snippet in [
            "let t = music.tracks?().filtered(using: byID(trackID)).first",
            "let t = music\n    .tracks?()\n",
            "let n = music.tracks().count",
        ]:
            self.assertCaught("E3", BRIDGE + "Client.swift", snippet + "\n")

    def test_e3_enumeration_inside_lookup_is_caught(self):
        source = ('@objc(AZWMusicRemoteLibraryProto) fileprivate protocol LibraryProto {\n'
                  '    @objc optional func tracks() -> SBElementArray\n}\n'
                  'func all(_ m: LibraryProto) { for t in m.tracks?() ?? [] { _ = t } }\n')
        self.assertCaught("E3", LOOKUP, source)

    def test_e3_library_protocol_must_be_fileprivate(self):
        source = ('@objc(AZWMusicRemoteLibraryProto) protocol LibraryProto {\n'
                  '    @objc optional func tracks() -> SBElementArray\n}\n')
        self.assertCaught("E3", LOOKUP, source)

    def test_e3_library_protocol_named_elsewhere_is_caught(self):
        self.assertCaught("E3", BRIDGE + "Client.swift", "let n = \"AZWMusicRemoteLibraryProto\"\n")

    def test_e3_tracks_call_without_filter_is_caught(self):
        source = ('@objc(AZWMusicRemoteLibraryProto) fileprivate protocol LibraryProto {\n'
                  '    @objc optional func tracks() -> SBElementArray\n}\n'
                  'func f(_ m: LibraryProto) -> Any? { m.tracks?() }\n')
        self.assertCaught("E3", LOOKUP, source)

    def test_e3_single_filtered_lookup_passes(self):
        source = ('@objc(AZWMusicRemoteLibraryProto) fileprivate protocol LibraryProto {\n'
                  '    @objc optional func tracks() -> SBElementArray\n}\n'
                  'func find(_ m: LibraryProto, _ p: NSPredicate) -> Any? {\n'
                  '    m.tracks?().filtered(using: p).first\n}\n')
        self.assertPasses(LOOKUP, source)

    def test_e3_message_kind_name_outside_bridge_passes(self):
        self.assertPasses("Packages/EchoKit/Sources/RemoteProtocol/MessageKind.swift",
                          'case albumTracks = "album.tracks"\n')

    # E4
    def test_e4_launch_api_outside_runner_is_caught(self):
        for path, snippet in [
            (BRIDGE + "Client.swift", "let p = Process()"),
            (BRIDGE + "Client.swift", 'let u = URL(fileURLWithPath: "/usr" + "/bin/shortcuts")\nlet p = Process()'),
            ("Packages/EchoKit/Sources/RemoteTransport/X.swift", "posix_spawnp(&pid, path, nil, nil, argv, nil)"),
            (BRIDGE + "Client.swift", "execvp(path, argv)"),
            (BRIDGE + "Client.swift", "let pid = fork()"),
            ("Features/Shell/X.swift", "NSWorkspace.shared.open(url)"),
            (BRIDGE + "Client.swift", "LSOpenCFURLRef(url, nil)"),
            (BRIDGE + "Client.swift", 'let h = dlopen("x", 0)'),
            (BRIDGE + "Client.swift", 'system("ls")'),
            (BRIDGE + "Client.swift", 'Darwin.system("ls")'),
            (BRIDGE + "Client.swift", 'Glibc.system("ls")'),
        ]:
            self.assertCaught("E4", path, snippet + "\n")

    def test_e4_second_launch_point_in_runner_is_caught(self):
        source = ("func a() throws { let p = Process(); try p.run() }\n"
                  "func b() throws { let q = Process(); try q.run() }\n")
        self.assertCaught("E4", RUNNER, source)

    def test_e4_other_launch_api_in_runner_is_caught(self):
        self.assertCaught("E4", RUNNER, "let p = Process()\ntry p.run()\nexecvp(path, argv)\n")

    def test_e4_single_launch_point_in_runner_passes(self):
        source = ('let makeProcess: () -> Process = { Process() }\n'
                  'func start() throws { let p = makeProcess(); p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts"); try p.run() }\n')
        self.assertPasses(RUNNER, source)

    def test_e4_swiftui_system_font_is_not_a_launch(self):
        self.assertPasses("Features/Shell/X.swift", "Text(verbatim: \"x\").font(.system(size: 12))\nlet f = Font.system(.body)\n")

    # S4 T7（CR-013(c)、CR-014；sprint-4-detail.md §4.6）：ShortcutRunner 只許 run／sign／list 三個子命令與固定旗標
    def test_e4_runner_other_subcommand_is_caught(self):
        self.assertCaught("E4", RUNNER, 'let p = Process()\np.arguments = ["view", name]\ntry p.run()\n')

    def test_e4_runner_unlisted_flag_is_caught(self):
        self.assertCaught("E4", RUNNER, 'let p = Process()\np.arguments = ["run", id, "--output-type", t]\ntry p.run()\n')

    # security review LOW-5：執行檔與 sign mode 也要釘死
    def test_e4_runner_other_executable_is_caught(self):
        self.assertCaught("E4", RUNNER, 'static let executable = URL(fileURLWithPath: "/bin/sh")\nlet p = Process()\ntry p.run()\n')

    def test_e4_runner_other_sign_mode_is_caught(self):
        self.assertCaught("E4", RUNNER, 'let p = Process()\nlet b = ["sign", "--mode", "anyone", "--input", i, "--output", o]\ntry p.run()\n')

    def test_e4_runner_three_fixed_vectors_pass(self):
        source = ('let p = Process()\n'
                  'let a = ["run", id, "--input-path", f]\n'
                  'let b = ["sign", "--mode", "people-who-know-me", "--input", i, "--output", o]\n'
                  'let c = ["list", "--show-identifiers"]\n'
                  'try p.run()\n')
        self.assertPasses(RUNNER, source)

    # E8（CR-014）：EchoKit 不讀「捷徑」的資料庫
    def test_e8_shortcuts_database_access_is_caught(self):
        self.assertCaught("E8", BRIDGE + "X.swift", "import SQLite3\n")
        self.assertCaught("E8", BRIDGE + "X.swift", 'let p = home + "/Library/Shortcuts/Shortcuts.sqlite"\n')
        self.assertCaught("E8", "Packages/EchoKit/Sources/RemoteTransport/X.swift", "sqlite3_open_v2(path, &db, flags, nil)\n")

    # E5
    def test_e5_forbidden_imports_are_caught(self):
        self.assertCaught("E5", "Packages/EchoKit/Sources/RemoteProtocol/X.swift", "import MusicRemoteBridge\n")
        self.assertCaught("E5", "Packages/EchoKit/Sources/RemoteTransport/X.swift", "import AppKit\n")
        self.assertCaught("E5", "Features/Shell/X.swift", "import MusicRemoteBridge\n")
        self.assertCaught("E5", "Features/Shell/X.swift", "@preconcurrency import MusicRemoteBridge\n")
        self.assertCaught("E5", "Packages/EchoKit/Sources/RemoteProtocol/X.swift", "internal import AppKit\n")
        self.assertCaught("E5", "Features/Shell/X.swift", "import struct MusicRemoteBridge.PlayContext\n")

    def test_e5_allowed_imports_pass(self):
        self.assertPasses("Packages/EchoKit/Sources/RemoteTransport/X.swift", "import Network\nimport RemoteProtocol\n")
        self.assertPasses("Features/Shell/X.swift", "import SwiftUI\nimport RemoteProtocol\n")

    # E6
    def test_e6_queue_files_are_caught(self):
        self.assertCaught("E6", BRIDGE + "Q.swift", 'let p = "Music/Queue.dat"\n')
        self.assertCaught("E6", BRIDGE + "Q.swift", 'let p = base + "History.dat"\n')

    # E7（sprint-3-detail.md §4.5，N-07）：iTunesLibrary 只許 LibraryReader.swift，且該檔只用白名單成員
    def test_e7_itunes_library_elsewhere_in_bridge_is_caught(self):
        self.assertCaught("E7", BRIDGE + "CatalogService.swift", "import iTunesLibrary\n")
        self.assertCaught("E7", BRIDGE + "X.swift", "@preconcurrency import iTunesLibrary\n")

    def test_e7_reader_with_allowed_members_passes(self):
        self.assertPasses(READER, "import iTunesLibrary\nlet a = item.album.persistentID.uint64Value\n"
                                  "let ok = library.reloadData()\nlet d = item.artwork?.imageData\n")

    def test_e7_reader_member_outside_allowlist_is_caught(self):
        self.assertCaught("E7", READER, "import iTunesLibrary\nlibrary.unloadData()\n")
        self.assertCaught("E7", READER, "import iTunesLibrary\nlet p = library.allPlaylists\n")
        self.assertCaught("E7", READER, "import iTunesLibrary\nlet u = item.location\n")

    def test_e7_reader_comment_is_ignored(self):
        self.assertPasses(READER, "import iTunesLibrary\n// library.unloadData()\n")

    # S4 T3（sprint-4-detail.md §4.2）：曲目時長 totalTime 為唯讀成員，加入白名單
    def test_e7_total_time_is_allowed_for_durations(self):
        self.assertPasses(READER, "import iTunesLibrary\nlet ms = item.totalTime\n")


    # E10（CR-030；s6-61-genius.md §4.2）：AX 只許 GeniusMenu.swift，且只許按下
    GENIUS = BRIDGE + "GeniusMenu.swift"
    AX_SNIPPETS = ["let app = AXUIElementCreateApplication(pid)", "let ok = AXIsProcessTrusted()",
                   'let name = kAXMenuBarAttribute', "let opts = AXIsProcessTrustedWithOptions(nil)",
                   "@preconcurrency import ApplicationServices", "import HIServices"]

    # E11（N-05／CR-010 ②(h)；S7 T9 追溯缺口，使用者 2026-10-26 選 A）：配對 QR 與秘密不進剪貼簿、不給無障礙讀
    MAC_REMOTE = "AzathothsWhisper/App/Remote/RelaySettingsView.swift"
    IPAD_CONNECTION = "Features/Connection/PairingScreen.swift"
    QR_HIDDEN = ("if let image = QRCodeImage.make(text: text, scale: 8) {\n    Image(decorative: image, scale: 2)\n"
                 "        .interpolation(.none)\n        .accessibilityHidden(true)\n}\n")

    def test_e11_clipboard_and_text_selection_are_caught(self):
        for path in [self.MAC_REMOTE, "AzathothsWhisper/App/Remote/RelayPresentation.swift", self.IPAD_CONNECTION]:
            for snippet in ["NSPasteboard.general.setString(text, forType: .string)", "UIPasteboard.general.string = text",
                            "Text(text).textSelection(.enabled)", "ShareLink(item: text)", "Image(decorative: i, scale: 2).draggable(text)",
                            "Text(text).copyable([text])"]:
                self.assertCaught("E11", path, snippet + "\n")

    def test_e11_qr_image_without_accessibility_hidden_is_caught(self):
        source = "if let image = QRCodeImage.make(text: text, scale: 8) {\n    Image(decorative: image, scale: 2)\n}\n"
        self.assertCaught("E11", self.MAC_REMOTE, source)
        hidden_far_below = source + "\n" * 12 + "Text(\"x\").accessibilityHidden(true)\n"
        self.assertCaught("E11", self.MAC_REMOTE, hidden_far_below)

    def test_e11_hidden_qr_and_comments_pass(self):
        self.assertPasses(self.MAC_REMOTE, self.QR_HIDDEN)
        self.assertPasses(self.MAC_REMOTE, "// QR 是一次性秘密：不可複製（不用 NSPasteboard）\nlet x = 1\n")

    def test_e11_other_places_may_use_the_clipboard(self):
        self.assertPasses("AzathothsWhisper/Features/Editor/EditorView.swift", "NSPasteboard.general.setString(text, forType: .string)\n")
        self.assertPasses("Features/Library/AlbumDetailView.swift", "Text(title).textSelection(.enabled)\n")

    def test_e10_ax_outside_genius_menu_is_caught(self):
        for path in [BRIDGE + "MusicLane.swift", "Packages/EchoKit/Sources/RemoteTransport/X.swift",
                     "Features/Remote/X.swift", "App/X.swift"]:
            for snippet in self.AX_SNIPPETS:
                self.assertCaught("E10", path, snippet + "\n")

    def test_e10_comment_mentioning_ax_passes(self):
        self.assertPasses(BRIDGE + "MusicLane.swift", "// Genius 走 AXUIElement，只在 GeniusMenu.swift\nlet x = 1\n")

    def test_e10_genius_menu_press_only_passes(self):
        source = ("import ApplicationServices\nlet app = AXUIElementCreateApplication(pid)\n"
                  "AXUIElementSetMessagingTimeout(app, 2)\nlet t = AXIsProcessTrusted()\n"
                  "_ = AXUIElementPerformAction(element, kAXPressAction as CFString)\n")
        self.assertPasses(self.GENIUS, source)

    def test_e10_genius_menu_other_actions_and_writes_are_caught(self):
        for snippet in ["_ = AXUIElementPerformAction(element, kAXShowMenuAction as CFString)",
                        '_ = AXUIElementPerformAction(element, "AXPick" as CFString)',
                        "_ = AXUIElementPerformAction(element, action)",
                        "AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, v)",
                        "AXUIElementPostKeyboardEvent(app, 0, 49, true)",
                        "let e = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)",
                        "let w = AXUIElementCreateSystemWide()",
                        "let a = kAXRaiseAction",
                        '_ = AXUIElementPerformAction(element, ("AXShowMenu" as CFString))',
                        'let action = "AXRaise"',
                        "let perform = AXUIElementPerformAction",
                        "final class AXMenuTree: GeniusMenuTree {}"]:
            self.assertCaught("E10", self.GENIUS, snippet + "\n")

    # simcodex G7 security MEDIUM-2／LOW-1：正式樹只許 fileprivate、可注入的 init 只許本檔與測試用、按下只許一處
    def test_e10_menu_tree_and_injecting_init_stay_inside_genius_menu(self):
        for snippet in ["let t = AXMenuTree(pid: 1)", "let m = GeniusMenu(locator: other)",
                        "let m = GeniusMenu(trusted: { true })"]:
            self.assertCaught("E10", BRIDGE + "RemoteCommandQueue.swift", snippet + "\n")
        self.assertPasses(BRIDGE + "RemoteCommandQueue.swift", "let m = GeniusMenu()\n")

    def test_e10_single_press_site_and_fileprivate_tree_pass(self):
        press = "_ = AXUIElementPerformAction(element, kAXPressAction as CFString)\n"
        self.assertPasses(self.GENIUS, "fileprivate final class AXMenuTree: GeniusMenuTree {}\n" + press)
        self.assertCaught("E10", self.GENIUS, press + press)


class VinylAssetGateTests(unittest.TestCase):
    """E9（sprint-5-detail.md §4.9）：MD Vinyl 素材只放本機，repo 追蹤清單不得含素材（檔名或內容雜湊）"""

    HASH = "ab" * 32

    def run_e9(self, lines, hashes=None):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
            f.write("\n".join(hashes if hashes is not None else [self.HASH]) + "\n")
            hash_file = f.name
        result = subprocess.run([sys.executable, "-I", str(GATE), "--e9-stdin", hash_file],
                                input="\n".join(lines) + "\n", capture_output=True, text=True)
        return result.returncode, result.stderr

    def assertCaught(self, line):
        code, err = self.run_e9([line])
        self.assertEqual(code, 1, line)
        self.assertIn("[E9]", err)

    def test_asset_file_names_are_caught(self):
        self.assertCaught("YogSothothsEcho/Resources/x/vinyl_player_arm_black.png\t" + "00" * 32)
        self.assertCaught("docs/ic_vinyl_handle_white.png\t" + "00" * 32)
        self.assertCaught("docs/preview_vinyl_l.png\t" + "00" * 32)

    def test_local_asset_folder_and_ipa_are_caught(self):
        self.assertCaught("YogSothothsEcho/Resources/VinylAssets.local/base.png\t" + "00" * 32)
        self.assertCaught("dist/YogSothothsEcho-S5.ipa\t-")

    def test_local_asset_folder_readme_is_the_only_allowed_file(self):
        code, err = self.run_e9(["YogSothothsEcho/Resources/VinylAssets.local/README.md\t-"])
        self.assertEqual(code, 0, err)
        self.assertCaught("YogSothothsEcho/Resources/VinylAssets.local/notes/README.md\t-")

    def test_renamed_asset_is_caught_by_content_hash(self):
        self.assertCaught("docs/plans/screens/renamed.png\t" + self.HASH)

    def test_unrelated_images_pass(self):
        code, err = self.run_e9(["docs/plans/screens/ok.png\t" + "00" * 32, "README.md\t-"])
        self.assertEqual(code, 0, err)

    def test_hash_list_ignores_comments_and_case(self):
        code, _ = self.run_e9(["a.png\t" + self.HASH], hashes=["# comment", self.HASH.upper()])
        self.assertEqual(code, 1)


if __name__ == "__main__":
    unittest.main()
