import RemoteProtocol
import RemoteTransport
import SwiftUI
import Testing
import UIKit
@testable import YogSothothsEcho

// S6.5 T8（s6-5-pairing-redesign.md §5）：連線頁渲染基準圖＋容差比對。
// 玻璃一律走 material 路徑（環境值 forcesMaterialGlass，不用全域旗標）；相機區以固定假影像代替（不碰真相機）。最大字級時左欄改捲動，ImageRenderer 畫不出 ScrollView，
// 所以最大字級不入基準圖，改由 UI 測試 testPairingLayoutFitsLargestTextJapanese 在模擬器實測。
// 無基準圖或比對不過時，把新圖寫到 TEST_RUNNER_PAIRING_SNAPSHOT_DIR（有設時），供人工看與重錄
/// 測試案例表（不隔離：@Test 參數在 actor 外求值）
enum PairingSnapshotCases {
    static let full = CGSize(width: 1376, height: 1032)
    static let mini = CGSize(width: 1133, height: 744)

    struct Case: CustomStringConvertible, Sendable {
        let name: String
        let state: Fixture
        let dark: Bool
        var size = PairingSnapshotCases.full
        var locale = "en"
        var largestText = false
        var reduceTransparency = false
        var description: String { name }
    }

    enum Fixture: Sendable { case scanning, invalid, pairing, failed, cameraDenied, connecting }

    static let all: [Case] = [Fixture.scanning, .invalid, .pairing, .failed, .cameraDenied, .connecting].flatMap { f in
        [Case(name: "\(f)-light", state: f, dark: false), Case(name: "\(f)-dark", state: f, dark: true)]
    } + [
        Case(name: "scanning-dark-mini", state: .scanning, dark: true, size: mini),
        Case(name: "scanning-dark-ja", state: .scanning, dark: true, locale: "ja"),
        Case(name: "scanning-dark-zhHant", state: .scanning, dark: true, locale: "zh-Hant"),
        Case(name: "pairing-dark-reduceTransparency", state: .pairing, dark: true, reduceTransparency: true),
    ]
}

@MainActor
@Suite(.serialized)
struct PairingSnapshotTests {
    typealias Case = PairingSnapshotCases.Case
    typealias Fixture = PairingSnapshotCases.Fixture
    static let scale: CGFloat = 0.5
    static let channelTolerance = 8
    static let minMatchingFraction = 0.995

    @Test(arguments: PairingSnapshotCases.all)
    func matchesBaseline(_ c: Case) async throws {
        let model = await Self.model(for: c.state)
        let screen = PairingScreen(model: model, appearance: AppearanceViewModel(store: InMemorySettingsStore()),
                                   preset: .silverBlue, scanner: Self.fakeCamera,
                                   reduceTransparencyOverride: c.reduceTransparency)
            .frame(width: c.size.width, height: c.size.height)
            .environment(\.colorScheme, c.dark ? .dark : .light)
            .environment(\.locale, Locale(identifier: c.locale))
            .environment(\.dynamicTypeSize, c.largestText ? .accessibility5 : .large)
            .environment(\.forcesMaterialGlass, true)
        let renderer = ImageRenderer(content: screen)
        renderer.scale = Self.scale
        let image = try #require(renderer.uiImage)
        let png = try #require(image.pngData())
        let baselineURL = Bundle(for: SnapshotBundleToken.self).url(forResource: c.name, withExtension: "png")
        guard let baselineURL, let baseline = UIImage(contentsOfFile: baselineURL.path) else {
            Self.write(png, name: c.name)
            Issue.record("沒有基準圖 \(c.name).png；新圖已寫到 TEST_RUNNER_PAIRING_SNAPSHOT_DIR（有設時）")
            return
        }
        let fraction = Self.matchingFraction(image, baseline)
        if fraction < Self.minMatchingFraction { Self.write(png, name: c.name) }
        #expect(fraction >= Self.minMatchingFraction, "\(c.name) 相符像素 \(fraction)")
    }

    // MARK: 狀態佈置（同 ConnectionViewRenderTests 的手法）

    static func model(for fixture: Fixture) async -> ConnectionViewModel {
        let connector = FakeConnector(), camera = FakeCamera()
        let payload = ConnectionSamples.payload()
        if fixture == .cameraDenied { camera.current = .denied }
        if fixture == .connecting { connector.paired = true; connector.holdCall = 1 }
        let m = ConnectionViewModel(connector: connector, camera: camera, deviceName: "iPad",
                                    sleep: { _ in await Task.yield() }, jitter: { 1 })
        switch fixture {
        case .scanning, .cameraDenied:
            await m.start()
        case .invalid:
            await m.start()
            await m.scanned("https://example.com")
        case .pairing:
            connector.pendingSuffix = "0A0B"
            connector.holdPair = true
            await m.start()
            Task { await m.scanned(payload.encoded()) }
            while m.lastPendingSuffix == nil { await Task.yield() }
        case .failed:
            connector.pairResult = .failed(.rejected)
            await m.start()
            await m.scanned(payload.encoded())
        case .connecting:
            Task { await m.start() }
            while !connector.isHolding { await Task.yield() }
        }
        return m
    }

    /// 假相機：固定的暗色漸層＋白色方塊（不是 QR、不含任何秘密）
    static let fakeCamera = PairingScanner { _ in
        AnyView(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
            .overlay(Rectangle().fill(.white).frame(width: 160, height: 160)))
    }

    // MARK: 比對與輸出

    static func rgba(_ image: UIImage) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let cg = image.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? (bytes, w, h) : nil
    }

    static func matchingFraction(_ a: UIImage, _ b: UIImage) -> Double {
        guard let x = rgba(a), let y = rgba(b), x.width == y.width, x.height == y.height else { return 0 }
        var matching = 0
        x.bytes.withUnsafeBufferPointer { p in
            y.bytes.withUnsafeBufferPointer { q in
                for i in stride(from: 0, to: p.count, by: 4) {
                    let diff = max(abs(Int(p[i]) - Int(q[i])), abs(Int(p[i + 1]) - Int(q[i + 1])), abs(Int(p[i + 2]) - Int(q[i + 2])))
                    if diff <= channelTolerance { matching += 1 }
                }
            }
        }
        return Double(matching) / Double(x.width * x.height)
    }

    static func write(_ png: Data, name: String) {
        guard let dir = ProcessInfo.processInfo.environment["PAIRING_SNAPSHOT_DIR"], !dir.isEmpty else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? png.write(to: url)
    }
}

/// 找測試 bundle 用
private final class SnapshotBundleToken {}
