import SwiftUI

// Material Symbols Outlined 子集（7 glyph，Apache 2.0，隨 app 打包）。
// 原版以 CDN 字型＋連字（ligature）渲染：<span class="material-symbols-outlined">close</span>
// 這裡沿用同一機制——字型名與連字字串都與原版一致，glyph 形狀因此逐一相同。
enum MaterialSymbolName: String, CaseIterable {
    case graphicEq = "graphic_eq"
    case arrowDropDown = "arrow_drop_down"
    case cloudDownload = "cloud_download"
    case saveAlt = "save_alt"
    case saveAs = "save_as"
    case doneAll = "done_all"
    case close = "close"
}

struct MaterialSymbol: View {
    let name: MaterialSymbolName
    let size: CGFloat

    init(_ name: MaterialSymbolName, size: CGFloat) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Text(verbatim: name.rawValue)
            .font(.custom(Theme.Fonts.symbolName, fixedSize: size))
            // 連字替換靠原樣字串比對：父層的 .textCase(.uppercase)／字距會使替換失效，
            // 令圖示退化成 "CLOUD_DOWNLOAD" 這樣的字面文字，故在此強制還原。
            .textCase(nil)
            .tracking(0)
    }
}
