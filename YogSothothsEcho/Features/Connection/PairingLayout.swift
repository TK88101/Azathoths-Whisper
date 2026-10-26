import CoreGraphics
import RemoteTransport

/// 連線頁（CR-033 方向 E Soft Relay；s6-5-pairing-redesign.md §4.2–§4.4）會判斷的部分：純函式，單測
enum PairingLayout {
    static let sideMargin: CGFloat = 48
    static let gap: CGFloat = 48
    static let verticalMargin: CGFloat = 54
    static let minLeftWidth: CGFloat = 360
    static let leftFraction: CGFloat = 0.46
    static let maxViewerWidth: CGFloat = 620
    static let minViewerHeight: CGFloat = 320
    /// 視窗高低於此（iPad mini 橫屏 744）用小一號的品牌名
    static let compactHeight: CGFloat = 800

    struct Metrics: Equatable {
        let leftWidth: CGFloat
        let viewer: CGSize
        let isCompact: Bool
    }

    /// 左欄占可用寬的 46%（至少 360）；取景窗 16:11、最寬 620，放不下高度時改 16:10 並以高反推寬
    static func metrics(for size: CGSize) -> Metrics {
        let usable = size.width - 2 * sideMargin
        let left = max(minLeftWidth, (usable - gap) * leftFraction)
        let right = max(0, usable - gap - left)
        var width = min(maxViewerWidth, right)
        var height = width * 11 / 16
        let maxHeight = size.height - 2 * verticalMargin
        if height > maxHeight {
            width = min(right, maxHeight * 16 / 10)
            height = width * 10 / 16
        }
        return Metrics(leftWidth: left, viewer: CGSize(width: width, height: height), isCompact: size.height < compactHeight)
    }

    // MARK: 各狀態的內容

    /// 抽象底的處理（CR-033 修訂 R1：不用相機畫面）
    enum Tone: Equatable { case normal, dimmed, blurred }

    enum Symbol: Equatable {
        case cameraOff, cameraUnavailable, failed, connected, unreachable, needsRepair

        var systemName: String {
            switch self {
            case .cameraOff: "video.slash"
            case .cameraUnavailable: "camera"
            case .failed: "xmark.circle"
            case .connected: "checkmark.circle"
            case .unreachable: "wifi.exclamationmark"
            case .needsRepair: "exclamationmark.triangle"
            }
        }
    }

    enum Center: Equatable {
        /// 4 碼；nil＝Mac 還沒送來
        case code(String?)
        case symbol(Symbol)
        /// 轉圈；`connecting`＝下方附「Connecting to your Mac…」（只有連線中這一態，與底圖處理無關）
        case progress(connecting: Bool)
    }

    enum Viewer: Equatable {
        case liveCamera(invalid: Bool)
        case abstract(Tone, Center)
    }

    enum Message: Equatable {
        case steps(invalidCode: Bool)
        case cameraDenied, cameraUnavailable, confirmCode
        case failed(PairingFailure)
        case connected(macName: String)
        case retrying(inSeconds: Int)
        case waitingForMac, needsRepair
    }

    enum Action: Equatable { case openSettings, scanAgain, forgetMac, pairAgain }

    struct Content: Equatable {
        let viewer: Viewer
        let text: Message
        let action: Action?
    }

    /// nil＝`suspended`：只畫背景（等同現行空白）
    static func content(for state: ConnectionViewModel.State, suffix: String? = nil) -> Content? {
        switch state {
        case .unpaired(.scanning): Content(viewer: .liveCamera(invalid: false), text: .steps(invalidCode: false), action: nil)
        case .unpaired(.invalidCode): Content(viewer: .liveCamera(invalid: true), text: .steps(invalidCode: true), action: nil)
        case .unpaired(.cameraDenied): Content(viewer: .abstract(.normal, .symbol(.cameraOff)), text: .cameraDenied, action: .openSettings)
        case .unpaired(.cameraUnavailable): Content(viewer: .abstract(.normal, .symbol(.cameraUnavailable)), text: .cameraUnavailable, action: nil)
        case .pairing: Content(viewer: .abstract(.normal, .code(suffix)), text: .confirmCode, action: nil)
        case .pairingFailed(let failure): Content(viewer: .abstract(.dimmed, .symbol(.failed)), text: .failed(failure), action: .scanAgain)
        case .connecting: Content(viewer: .abstract(.blurred, .progress(connecting: true)), text: .steps(invalidCode: false), action: nil)
        case .connected(let name): Content(viewer: .abstract(.normal, .symbol(.connected)), text: .connected(macName: name), action: .forgetMac)
        case .retrying(let seconds): Content(viewer: .abstract(.normal, .symbol(.unreachable)), text: .retrying(inSeconds: seconds), action: nil)
        case .waitingForMac: Content(viewer: .abstract(.normal, .progress(connecting: false)), text: .waitingForMac, action: nil)
        case .needsRepair: Content(viewer: .abstract(.normal, .symbol(.needsRepair)), text: .needsRepair, action: .pairAgain)
        case .suspended: nil
        }
    }

    // MARK: VoiceOver 焦點順序（D4）：rawValue＝accessibilitySortPriority，越大越先

    enum Region: Double { case appearance = 1, action, viewer, body, header }
}
