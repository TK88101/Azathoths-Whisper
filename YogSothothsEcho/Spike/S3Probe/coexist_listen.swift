import Foundation
import os

// #3-1 (f) 共存觀測：只旁聽 Music 的換歌通知並寫一筆 OSLog（不記曲名、不送任何指令給 Music）
let log = Logger(subsystem: "yse.coexist", category: "music")
DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main) { _ in
    log.notice("music-notify")
}
RunLoop.main.run()
