import Foundation
import RemoteProtocol
import RemoteTransport
import SwiftUI
import Testing
@testable import YogSothothsEcho

// S2 T11（sprint-2-detail.md §4.12）→ S6.5 T5（s6-5-pairing-redesign.md）：連線頁在每個可達狀態都能算出畫面。
// 改為整頁 `PairingScreen`，兩種 iPad 尺寸 × 深淺各畫一次（斷言不減：仍逐狀態「畫得出來、不是空的」）。
// 相機區經可注入的掃描器工廠：spy 記錄建立次數（D1：只有兩個掃描態可以掛相機）
@MainActor
struct ConnectionViewRenderTests {
    let connector = FakeConnector()
    let camera = FakeCamera()
    let payload = ConnectionSamples.payload()
    let scanner = ScannerSpy()
    static let sizes = [CGSize(width: 1376, height: 1032), CGSize(width: 1133, height: 744)]

    func model(sleep: @escaping @Sendable (TimeInterval) async -> Void = { _ in await Task.yield() }) -> ConnectionViewModel {
        ConnectionViewModel(connector: connector, camera: camera, deviceName: "iPad", sleep: sleep, jitter: { 1 })
    }

    func expectRenders(_ m: ConnectionViewModel, _ expected: ConnectionViewModel.State) {
        #expect(m.state == expected)
        for size in Self.sizes {
            for scheme in [ColorScheme.light, .dark] {
                let screen = PairingScreen(model: m, appearance: AppearanceViewModel(store: InMemorySettingsStore()),
                                           preset: .silverBlue, scanner: scanner.factory)
                    .frame(width: size.width, height: size.height)
                    .environment(\.colorScheme, scheme)
                let image = ImageRenderer(content: screen).uiImage
                #expect(image != nil && image!.size.width > 0, "\(ConnectionPresentation.stateID(expected)) \(size) \(scheme) 畫不出來")
            }
        }
    }

    /// D1：掃描器只在 unpaired.scanning／invalidCode 建立；其餘狀態一次都不建
    @Test func onlyScanningStatesCreateScanner() async {
        let m = model()
        await m.start()
        expectRenders(m, .unpaired(.scanning))
        let afterScanning = scanner.count
        #expect(afterScanning > 0)
        connector.pairResult = .failed(.rejected)
        await m.scanned(payload.encoded())
        expectRenders(m, .pairingFailed(.rejected))
        #expect(scanner.count == afterScanning, "失敗態不得建立掃描器")
    }

    @Test func scanningStatesRender() async {
        let m = model()
        await m.start()
        expectRenders(m, .unpaired(.scanning))
        await m.scanned("https://example.com")
        expectRenders(m, .unpaired(.invalidCode))
    }

    @Test func pairingAndConnectingDoNotCreateScanner() async {
        connector.holdPair = true
        let m = model()
        await m.start()
        let task = Task { await m.scanned(payload.encoded()) }
        while m.state != .pairing { await Task.yield() }
        let before = scanner.count
        expectRenders(m, .pairing)
        #expect(scanner.count == before, "等 Mac 允許時不得建立掃描器")
        connector.releasePair()
        await task.value
    }

    @Test(arguments: [(CameraAccess.denied, ConnectionViewModel.Scan.cameraDenied), (.unavailable, .cameraUnavailable)])
    func cameraProblemStatesRender(access: CameraAccess, scan: ConnectionViewModel.Scan) async {
        camera.current = access
        let m = model()
        await m.start()
        expectRenders(m, .unpaired(scan))
    }

    @Test func pairingFailedRenders() async {
        connector.pairResult = .failed(.rejected)
        let m = model()
        await m.start()
        await m.scanned(payload.encoded())
        expectRenders(m, .pairingFailed(.rejected))
    }

    @Test func connectedRenders() async {
        connector.paired = true
        connector.connectResults = [.success(FakeSession())]
        let m = model()
        await m.start()
        await settle()
        expectRenders(m, .connected(macName: "Azathoth-ABCD"))
        m.suspend()
        expectRenders(m, .suspended)
    }

    @Test func retryingRenders() async {
        connector.paired = true
        connector.connectResults = [.failure(.network)]
        // 退避等待一直不結束，畫面停在倒數；suspend() 取消它
        let m = model(sleep: { try? await Task.sleep(for: .seconds($0 * 3600)) })
        await m.start()
        await settle()
        expectRenders(m, .retrying(inSeconds: 1))
        m.suspend()
    }

    @Test func waitingForMacRenders() async {
        connector.paired = true
        connector.connectResults = [.failure(.notFound)]
        connector.holdCall = 2
        let m = model()
        await m.start()
        while !connector.isHolding { await settle() }
        expectRenders(m, .waitingForMac)
        m.suspend()
    }

    @Test func needsRepairRenders() async {
        connector.paired = true
        connector.connectResults = Array(repeating: .failure(.rejectedByMac), count: ConnectionViewModel.maxRejectedBeforeRepair)
        let m = model()
        await m.start()
        await settle()
        expectRenders(m, .needsRepair)
    }
}

/// 掃描器工廠的 spy：只計數，不建立相機
@MainActor
final class ScannerSpy {
    private(set) var count = 0
    var factory: PairingScanner {
        PairingScanner { _ in
            self.count += 1
            return AnyView(Color.clear)
        }
    }
}
