#if os(macOS)
import Foundation
import RemoteProtocol

// 離線同定檢查（sprint-4-detail.md §5 T12、D8）：對每張放行專輯，模擬捷徑「以專輯名查找」會撈到的候選
// （歌曲與非歌曲，正規化同名——比 Music 的比對從寬，所以是上界），必須恰好是這張專輯自己的曲目，
// 且首數與依 disc／曲序的順序＝捷徑計畫。夾具版在單元測試；真曲庫版在 Azathoth 宿主以旗標開啟（#4-1 前置）。
// 只回專輯 ID，不回名稱（N-05）。

public enum AdmittedAlbumIdentity {
    /// 違反的放行專輯 ID（排序後）；空＝全部通過
    public static func violations(_ load: CatalogLoad, index: CatalogIndex) -> [String] {
        let byTitle = Dictionary(grouping: load.songs.filter { $0.albumTitle != nil }) { PlayAdmission.normalize($0.albumTitle!) }
        let otherTitles = Set(load.otherAlbumTitles.map { PlayAdmission.normalize($0.title) })
        return index.admission.compactMap { albumID, result -> String? in
            guard case .admitted(let plan) = result else { return nil }
            let key = PlayAdmission.normalize(plan.album)
            let candidates = byTitle[key] ?? []
            let refs = candidates.map { AlbumTrackRef(id: hex($0.trackID), disc: $0.discNumber, number: $0.trackNumber) }
            let identical = !otherTitles.contains(key)
                && candidates.allSatisfy { $0.albumID.map(hex) == albumID }
                && AlbumSuffix.ordered(refs) == plan.order
            return identical ? nil : albumID
        }
        .sorted()
    }

    private static func hex(_ value: UInt64) -> String { CatalogIndexBuilder.hex(value) }
}
#endif
