import CoreGraphics
import RemoteTransport
import Testing
@testable import YogSothothsEcho

// S6.5 T2／T3（s6-5-pairing-redesign.md §4.2、§4.3）：連線頁版面的純函式
struct PairingLayoutMetricsTests {
    static let sizes: [(name: String, size: CGSize)] = [
        ("13 吋", CGSize(width: 1376, height: 1032)),
        ("11 吋", CGSize(width: 1210, height: 834)),
        ("mini", CGSize(width: 1133, height: 744)),
    ]

    @Test(arguments: sizes.map(\.size))
    func columnsFitWidth(size: CGSize) {
        let m = PairingLayout.metrics(for: size)
        #expect(2 * PairingLayout.sideMargin + m.leftWidth + PairingLayout.gap + m.viewer.width <= size.width + 0.5)
        #expect(m.leftWidth >= PairingLayout.minLeftWidth)
    }

    @Test(arguments: sizes.map(\.size))
    func viewerFitsHeightAndKeepsRatio(size: CGSize) {
        let m = PairingLayout.metrics(for: size)
        #expect(m.viewer.height <= size.height - 2 * PairingLayout.verticalMargin + 0.5)
        #expect(m.viewer.height >= PairingLayout.minViewerHeight)
        #expect(m.viewer.width <= PairingLayout.maxViewerWidth)
        let ratio = m.viewer.width / m.viewer.height
        #expect(abs(ratio - 16.0 / 11) < 0.01 || abs(ratio - 16.0 / 10) < 0.01)
    }

    @Test func largestIPadUsesMaximumViewer() {
        let m = PairingLayout.metrics(for: CGSize(width: 1376, height: 1032))
        #expect(m.viewer == CGSize(width: 620, height: 620.0 * 11 / 16))
        #expect(!m.isCompact)
    }

    @Test func miniIsCompact() {
        #expect(PairingLayout.metrics(for: CGSize(width: 1133, height: 744)).isCompact)
    }

    /// 矮視窗：16:11 放不下時改 16:10、以高反推寬
    @Test func shortWindowSwitchesToSixteenByTen() {
        let m = PairingLayout.metrics(for: CGSize(width: 1376, height: 480))
        #expect(abs(m.viewer.width / m.viewer.height - 1.6) < 0.01)
        #expect(m.viewer.height <= 480 - 2 * PairingLayout.verticalMargin + 0.5)
    }
}

struct PairingLayoutContentTests {
    typealias S = ConnectionViewModel.State

    func content(_ state: S, suffix: String? = nil) throws -> PairingLayout.Content {
        try #require(PairingLayout.content(for: state, suffix: suffix))
    }

    @Test func scanningShowsLiveCameraAndSteps() throws {
        let c = try content(.unpaired(.scanning))
        #expect(c.viewer == .liveCamera(invalid: false))
        #expect(c.text == .steps(invalidCode: false))
        #expect(c.action == nil)
    }

    @Test func invalidCodeMarksCameraAndSteps() throws {
        let c = try content(.unpaired(.invalidCode))
        #expect(c.viewer == .liveCamera(invalid: true))
        #expect(c.text == .steps(invalidCode: true))
    }

    @Test func cameraDeniedOffersSettings() throws {
        let c = try content(.unpaired(.cameraDenied))
        #expect(c.viewer == .abstract(.normal, .symbol(.cameraOff)))
        #expect(c.text == .cameraDenied)
        #expect(c.action == .openSettings)
    }

    @Test func cameraUnavailableHasNoAction() throws {
        let c = try content(.unpaired(.cameraUnavailable))
        #expect(c.viewer == .abstract(.normal, .symbol(.cameraUnavailable)))
        #expect(c.text == .cameraUnavailable)
        #expect(c.action == nil)
    }

    @Test func pairingShowsCodeOnAbstractBackground() throws {
        #expect(try content(.pairing, suffix: "0A0B").viewer == .abstract(.normal, .code("0A0B")))
        #expect(try content(.pairing, suffix: nil).viewer == .abstract(.normal, .code(nil)))
        #expect(try content(.pairing).text == .confirmCode)
    }

    @Test(arguments: [PairingFailure.rejected, .expired, .cancelled, .unavailable, .invalid, .macPinMismatch,
                      .notOnLink, .network, .timeout, .notFound])
    func everyFailureDimsAndOffersScanAgain(failure: PairingFailure) throws {
        let c = try content(.pairingFailed(failure))
        #expect(c.viewer == .abstract(.dimmed, .symbol(.failed)))
        #expect(c.text == .failed(failure))
        #expect(c.action == .scanAgain)
    }

    /// 「Connecting…」文字屬於連線中狀態本身（不是由底圖模糊與否推斷）
    @Test func connectingBlursAndLabelsProgress() throws {
        let c = try content(.connecting)
        #expect(c.viewer == .abstract(.blurred, .progress(connecting: true)))
        #expect(c.text == .steps(invalidCode: false))
    }

    @Test func connectedOffersForget() throws {
        let c = try content(.connected(macName: "Mac"))
        #expect(c.viewer == .abstract(.normal, .symbol(.connected)))
        #expect(c.text == .connected(macName: "Mac"))
        #expect(c.action == .forgetMac)
    }

    @Test func retryingShowsSeconds() throws {
        let c = try content(.retrying(inSeconds: 7))
        #expect(c.viewer == .abstract(.normal, .symbol(.unreachable)))
        #expect(c.text == .retrying(inSeconds: 7))
    }

    @Test func waitingForMacShowsUnlabelledProgress() throws {
        let c = try content(.waitingForMac)
        #expect(c.viewer == .abstract(.normal, .progress(connecting: false)))
        #expect(c.text == .waitingForMac)
    }

    @Test func needsRepairOffersPairAgain() throws {
        let c = try content(.needsRepair)
        #expect(c.viewer == .abstract(.normal, .symbol(.needsRepair)))
        #expect(c.text == .needsRepair)
        #expect(c.action == .pairAgain)
    }

    @Test func suspendedDrawsNothing() {
        #expect(PairingLayout.content(for: .suspended) == nil)
    }

    /// D1（CR-033 修訂 R1）：只有兩個掃描態掛相機
    @Test func onlyScanningStatesUseCamera() {
        let all: [S] = [.unpaired(.scanning), .unpaired(.invalidCode), .unpaired(.cameraDenied), .unpaired(.cameraUnavailable),
                        .pairing, .pairingFailed(.rejected), .connecting, .connected(macName: "M"), .retrying(inSeconds: 1),
                        .waitingForMac, .needsRepair, .suspended]
        let camera = all.filter {
            if case .liveCamera = PairingLayout.content(for: $0)?.viewer { return true }
            return false
        }
        #expect(camera == [.unpaired(.scanning), .unpaired(.invalidCode)])
    }

    /// D4：VoiceOver 焦點順序＝標題 → 說明 → 取景區 → 主要按鈕 → 外觀（sortPriority 越大越先）
    @Test func focusOrderIsHeaderBodyViewerActionAppearance() {
        let priorities = [PairingLayout.Region.header, .body, .viewer, .action, .appearance].map(\.rawValue)
        #expect(priorities == priorities.sorted(by: >) && Set(priorities).count == priorities.count)
    }
}
