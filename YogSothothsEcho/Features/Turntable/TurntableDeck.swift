import UIKit

/// 唱機畫面的一組展示資料（sprint-5-detail.md §4.4 v1.3「展示快照」）：甩動轉場期間凍結，Mac 回覆或事件先到也不換圖、換色、換字。
/// 只由 TurntableViewModel 同步組出；封面與取色只取屬於同一 albumID 的
struct TurntableDeck: Equatable {
    let trackID: String?
    let albumID: String?
    let label: TurntableViewModel.Label
    let style: RecordStyle
    let splash: SplashStyle
    let cover: UIImage?
    let colors: AlbumColors
    /// SWIRL 系列的花紋配方（CR-037）：組 deck 時已套用煙渦設定，轉場快照一併凍結；其他樣式＝nil
    var swirl: SwirlRecipe? = nil

    /// 同一張專輯的封面到了（spine→原圖）：只換圖與取色（花紋配方不變）
    func withArtwork(_ image: UIImage?, colors: AlbumColors) -> TurntableDeck {
        TurntableDeck(trackID: trackID, albumID: albumID, label: label, style: style, splash: splash, cover: image, colors: colors, swirl: swirl)
    }
}
