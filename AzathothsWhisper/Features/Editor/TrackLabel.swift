import Foundation

// 曲目卡片的兩行文字（py:454-468）。
// 原版把 (artist, title) 併成 "artist - title" 送到前端，前端再以首個 " - " 切開：
// artist＝parts[0]，title＝其餘用 " - " 重接。artist 本身含 " - " 時會被切壞——
// 這是原版可觀察行為（ACCEPTANCE B-07），照搬而非「修正」。
enum TrackLabel {
    static func compose(artist: String, title: String) -> String {
        "\(artist) - \(title)"
    }

    static func split(_ label: String) -> (artist: String, title: String) {
        guard label.contains(" - ") else { return (label, "") }
        let parts = label.components(separatedBy: " - ")
        return (parts[0], parts.dropFirst().joined(separator: " - "))
    }

    static func lines(artist: String, title: String) -> (artist: String, title: String) {
        split(compose(artist: artist, title: title))
    }
}
