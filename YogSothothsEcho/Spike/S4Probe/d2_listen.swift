import AppKit
import os

// #4-1 D2 被動旁聽：每次滑鼠左鍵按下寫一筆 OSLog（subsystem yse.d2），時間取 OSLog 自帶的單調時間戳，
// 媒體鍵另記 key-down。由 Scripts/d2_pair.py 與 Azathoth 的 relay-measure 回條到達紀錄配對。只聽、不送任何指令給 Music、不記座標與視窗內容。
// 需要「輔助使用」或「輸入監控」權限（給執行它的終端機）；沒有權限時 macOS 不會送事件，啟動時會提示。
// 必須建 NSApplication 並跑它的事件迴圈，只推 RunLoop 收不到全域事件（S0 B4 的教訓）。
// 建置：swiftc -O d2_listen.swift -o <scratchpad>/d2-listen
let log = Logger(subsystem: "yse.d2", category: "mouse")
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
if !AXIsProcessTrusted() {
    FileHandle.standardError.write(Data("沒有輔助使用權限：請到 系統設定 › 隱私權與安全性 › 輔助使用 允許這個終端機，再重新執行\n".utf8))
}
let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
    let musicFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Music"
    log.notice("mouse-down music-front=\(musicFront, privacy: .public)")
}
// 媒體鍵（#4-1 實測：使用者以 F8 播放／暫停、F9 下一首操作）：systemDefined 子類型 8，data1 高 16 位＝鍵碼、按下＝0xA
let mediaKeys: [Int: String] = [16: "play", 17: "next", 18: "previous", 19: "next", 20: "previous"]
let keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { event in
    guard event.subtype.rawValue == 8 else { return }
    let code = (event.data1 & 0xFFFF0000) >> 16, down = ((event.data1 & 0xFF00) >> 8) == 0xA
    guard down, let name = mediaKeys[code] else { return }
    let musicFront = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Music"
    log.notice("key-down key=\(name, privacy: .public) music-front=\(musicFront, privacy: .public)")
}
FileHandle.standardError.write(Data("d2-listen 執行中：每次左鍵按下、媒體鍵（播放／下一首／上一首）按下記一筆；Ctrl-C 結束\n".utf8))
withExtendedLifetime((monitor, keyMonitor)) { app.run() }
