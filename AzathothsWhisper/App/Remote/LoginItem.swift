import Foundation
import Observation
import OSLog
import ServiceManagement

/// 登入時啟動的系統狀態（sprint-6-detail.md §4.10）：`.notFound` 與其他未知值都歸 unavailable
enum LoginItemStatus: Equatable, Sendable { case enabled, disabled, requiresApproval, unavailable }

/// 外部邊界（CLAUDE.md 慣例：protocol＋Live＋替身）。`import ServiceManagement` 只在本檔
protocol LoginItemControlling: Sendable {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

/// F-R-06：`SMAppService.mainApp`（設計 §5.1）。狀態以系統為準、App 不另存（CR-021）
struct LiveLoginItem: LoginItemControlling {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// 不碰系統的替身（單元／UI 測試與 `RelayHost.inert()`）：永遠 unavailable、操作無效果
struct InertLoginItem: LoginItemControlling {
    var status: LoginItemStatus { .unavailable }
    func register() throws {}
    func unregister() throws {}
    func openSystemSettings() {}
}

/// 設定 modal 那一列會判斷的部分（純函式）
enum LoginItemPresentation {
    static func isOn(_ status: LoginItemStatus) -> Bool { status == .enabled }

    static func noteKey(_ status: LoginItemStatus) -> String? {
        switch status {
        case .enabled, .disabled: nil
        case .requiresApproval: "login_item_requires_approval"
        case .unavailable: "login_item_unavailable"
        }
    }

    static func showsSettingsButton(_ status: LoginItemStatus) -> Bool { status == .requiresApproval }
}

/// 一次只允許一個 register／unregister 在途（在途期間開關停用）；每次操作與每次重讀帶遞增序號，只採用最新的；
/// 操作完成（成功或失敗）後一律重讀系統狀態作為顯示值。同步 API 放到背景執行，不阻塞主執行緒（§4.10 並發）
@MainActor
@Observable
final class LoginItemController {
    private(set) var status: LoginItemStatus
    private(set) var isBusy = false
    /// 最近一次失敗的錯誤種類（domain＋code，不記內容；SMAppService 丟的是 NSError，型別名一律是 NSError、看不出原因）
    private(set) var failure: String?

    @ObservationIgnored private let control: any LoginItemControlling
    @ObservationIgnored private var sequence = 0
    private static let log = Logger(subsystem: "com.ibridgezhao.azathothswhisper", category: "loginItem")

    init(control: any LoginItemControlling) {
        self.control = control
        status = control.status
    }

    /// modal 出現與 App 回到前景時
    func refresh() {
        sequence += 1
        status = control.status
    }

    func setEnabled(_ on: Bool) async {
        guard !isBusy else { return }
        isBusy = true
        sequence += 1
        let mine = sequence, control = control
        let error: Error? = await Task.detached {
            do {
                try on ? control.register() : control.unregister()
                return nil
            } catch {
                return error
            }
        }.value
        isBusy = false
        defer { status = control.status }   // 完成後一律重讀系統（期間有更新的重讀也一樣，系統才是最新）
        guard mine == sequence else { return }   // 期間有更新的重讀：舊操作的成敗不再顯示
        if let error {
            let ns = error as NSError
            let kind = "\(ns.domain) \(ns.code)"
            failure = kind
            Self.log.error("login item \(on ? "register" : "unregister", privacy: .public) failed: \(kind, privacy: .public)")
        } else {
            failure = nil
        }
    }

    func openSystemSettings() { control.openSystemSettings() }
}
