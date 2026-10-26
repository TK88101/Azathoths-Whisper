import Foundation
import RemoteProtocol

/// 詳情層的會判斷的 View 邏輯（sprint-6-detail.md §4.6）：總長、碟片分組、逐曲歌手、Play 鈕（文字浮現時序見 `DetailRevealSchedule`）
enum AlbumDetailPresentation {

    /// 有時長的才加；全部沒有＝不顯示總長
    static func totalDuration(_ songs: [TrackSummary]) -> Double? {
        let known = songs.compactMap(\.duration)
        return known.isEmpty ? nil : known.reduce(0, +)
    }

    static func ordered(_ songs: [TrackSummary]) -> [TrackSummary] {
        songs.sorted { ($0.disc, $0.number) < ($1.disc, $1.number) }
    }

    static func showsDiscTitles(_ songs: [TrackSummary]) -> Bool { Set(songs.map(\.disc)).count > 1 }

    /// 合輯用：與專輯藝人不同才顯示
    static func showsArtist(_ song: TrackSummary, albumArtist: String) -> Bool {
        !song.artist.isEmpty && song.artist != albumArtist
    }

    static func playEnabled(songCount: Int, phase: AlbumTracksViewModel.Phase, canPlay: Bool) -> Bool {
        songCount > 0 && phase == .ready && canPlay
    }

    /// 「12 首・52 分鐘」：「N 首」英文有單複數變化；總長用系統格式（自動三語）
    static func summary(songCount: Int, total: Double?) -> String {
        let songs = String.localizedStringWithFormat(String(localized: "%lld songs"), songCount)
        guard let total else { return songs }
        let formatter = total >= 3600 ? hoursFormatter : minutesFormatter
        return formatter.string(from: total).map { "\(songs) · \($0)" } ?? songs
    }

    /// 快取：iOS 改系統語言會重啟 App，formatter 跟著啟動時的語系即可
    private static let minutesFormatter = durationFormatter([.minute])
    private static let hoursFormatter = durationFormatter([.hour, .minute])

    private static func durationFormatter(_ units: NSCalendar.Unit) -> DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = units
        formatter.unitsStyle = .short
        return formatter
    }
}
