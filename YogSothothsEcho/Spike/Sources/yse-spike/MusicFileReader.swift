import CryptoKit
import Foundation
import SpikeCore

// yse-spike 唯一讀 Music 佇列檔的地方（spike_gate.sh 限定）。只用 Data(contentsOf:)，不寫、不移動、不刪除（N-07）。
// 只回傳 persistentID 序列與雜湊，不保存原檔內容。
enum MusicFileReader {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Music/Music/Music Library.musiclibrary/Preferences")

    struct QueueRead: Sendable {
        let ids: [String]?
        let hash: String?
    }

    static func queue() -> QueueRead {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("Queue.dat")) else {
            return QueueRead(ids: nil, hash: nil)
        }
        let digest = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
        return QueueRead(ids: QueueIDs.parse(data), hash: digest)
    }
}
