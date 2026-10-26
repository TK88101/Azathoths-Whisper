import Foundation
import Network

/// Bonjour 瀏覽結果的選擇規則（唯一定義處）：恰好一個服務才自動連；多個＝無法確定是哪台 Mac；
/// 瀏覽器失敗一律優先回報（即使先前找到過服務），不交出可能已失效的端點。
public enum BrowseSelection: Equatable, Sendable {
    case failed(String)
    case none
    case unique(index: Int)
    case ambiguous([String])

    public static func select(names: [String], failure: String?) -> BrowseSelection {
        if let failure { return .failed(failure) }
        switch names.count {
        case 0: return .none
        case 1: return .unique(index: 0)
        default: return .ambiguous(names)
        }
    }
}

/// NWError 的顯示文字：只有類別與代碼，不帶主機名（Mac 端 n5-listen 與 iPad 探針共用）
public func networkErrorText(_ error: NWError) -> String {
    switch error {
    case .posix(let code): "posix(\(code.rawValue))"
    case .dns(let code): "dns(\(code))"
    case .tls(let status): "tls(\(status))"
    default: "NWError"
    }
}
