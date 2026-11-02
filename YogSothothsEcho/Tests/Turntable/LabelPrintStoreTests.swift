import CoreGraphics
import Foundation
import Testing

@testable import YogSothothsEcho

/// 假 renderer：記錄每次畫的 key；可設定失敗
@MainActor
private final class FakeLabelPrintRenderer: LabelPrintRendering {
    private(set) var rendered: [LabelPrintKey] = []
    var failing = false

    func render(_ key: LabelPrintKey) -> CGImage? {
        rendered.append(key)
        guard !failing else { return nil }
        let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()
    }
}

// CR-039 §11 S2（yse-g7-hitch-fix.md v0.9 B1-S2／B2-S2）：key 公式與內容版次、lookup 純讀、只畫一次、failed 不重試、
// 非使用中最多 2 張、使用中可暫時超額、G7 中不畫（pending、end 後畫）、logical miss 與 end note 格式
@MainActor
struct LabelPrintStoreTests {
    private static let digits = "12345678901"   // 自編 11 碼（檢查碼由程式算）

    private static func key(_ side: CGFloat, scale: CGFloat = 2) -> LabelPrintKey {
        LabelPrintKey.make(recordSide: side, displayScale: scale, digits: nil)
    }

    private static func settle(until done: () -> Bool) async {
        for _ in 0..<200 where !done() { await Task.yield(); try? await Task.sleep(for: .milliseconds(5)) }
    }

    // MARK: Key

    @Test func keyAppliesLabelDiameterFormulaAndScale() {
        let key = LabelPrintKey.make(recordSide: 700, displayScale: 2, digits: nil)
        #expect(key.diameterCenti == Int((214.0 * 700 / 474 * 100).rounded()))
        #expect(key.scaleCenti == 200)
        #expect(abs(key.diameter - 214.0 * 700 / 474) < 0.01)
        #expect(key.scale == 2)
        #expect(key.schema == LabelPrintKey.currentSchema)
    }

    @Test func keyChangesWithSideAndScale() {
        #expect(Self.key(700) != Self.key(701))
        #expect(Self.key(700, scale: 2) != Self.key(700, scale: 3))
        #expect(Self.key(700) == Self.key(700))
    }

    /// 條碼三態：合法＝模組序列；沒有＝nil；不合法＝與沒有相同（兩者都不畫條碼）
    @Test func barcodeFingerprintHasThreeStates() {
        let valid = LabelPrintKey.make(recordSide: 700, displayScale: 2, digits: Self.digits)
        let none = LabelPrintKey.make(recordSide: 700, displayScale: 2, digits: nil)
        let invalid = LabelPrintKey.make(recordSide: 700, displayScale: 2, digits: "123")
        #expect(valid.barcode == UPCABarcode.modules(Self.digits))
        #expect(valid != none)
        #expect(none.barcode == nil)
        #expect(invalid == none)
    }

    /// 印字常數改了而 schema 沒加＝紅：每個 schema 登記一份內容簽章
    @Test func contentSignatureIsRegisteredForCurrentSchema() {
        let registered: [Int: String] = [
            1: "ring=DESIGNED BY YOG-SOTHOTH'S ECHO IN FUKUOKA · MADE IN JAPAN|wordmark=YOG-SOTHOTH'S ECHO|ringRadius=0.437|ringFont=0.026|"
                + "ringStep=0.0915|rim=0.95|wordmarkTop=0.16|wordmarkFont=0.03|wordmarkTracking=0.004|barcodeTop=0.205|"
                + "barcodeHeight=0.106|barcodeWidth=0.32|guard=1.12|opacity=rim0.25,ring0.8,bar1,wordmark1",
        ]
        #expect(registered[LabelPrintKey.currentSchema] == LabelPrintKey.contentSignature)
    }

    // MARK: Store

    @Test func requestRendersOnceAndLookupIsPureRead() {
        let renderer = FakeLabelPrintRenderer()
        let store = LabelPrintStore(renderer: renderer)
        let key = Self.key(700)
        #expect(store.lookup(key) == .fallback(.absent))
        store.request(key)
        store.request(key)
        for _ in 0..<5 { _ = store.lookup(key) }
        #expect(renderer.rendered == [key])
        #expect(store.renderCount == 1)
        guard case .ready = store.lookup(key) else { Issue.record("not ready"); return }
        #expect(store.transitionEnded() == "misses=0 reasons=absent:0,pending:0,rendering:0,failed:0")
    }

    @Test func failureIsNotRetried() {
        let renderer = FakeLabelPrintRenderer()
        renderer.failing = true
        let store = LabelPrintStore(renderer: renderer)
        let key = Self.key(700)
        store.request(key)
        store.request(key)
        #expect(store.lookup(key) == .fallback(.failed))
        #expect(renderer.rendered.count == 1)
    }

    @Test func idleEntriesAreCappedAtTwoOldestFirst() {
        let renderer = FakeLabelPrintRenderer()
        let store = LabelPrintStore(renderer: renderer)
        let keys = [Self.key(600), Self.key(650), Self.key(700), Self.key(750)]
        keys.forEach(store.request)
        #expect(store.lookup(keys[0]) == .fallback(.absent))
        #expect(store.lookup(keys[1]) == .fallback(.absent))
        guard case .ready = store.lookup(keys[2]), case .ready = store.lookup(keys[3]) else { Issue.record("newest evicted"); return }
    }

    /// 使用中的不淘汰：三個同時使用＝暫時超額；取消後回收到 2 張
    @Test func inUseEntriesMayExceedCapacityTemporarily() async {
        let renderer = FakeLabelPrintRenderer()
        let store = LabelPrintStore(renderer: renderer)
        let keys = [Self.key(600), Self.key(650), Self.key(700)]
        let tasks = keys.map { key in Task { await store.use(key) } }
        await Self.settle { store.inUseCount == 3 }
        #expect(keys.allSatisfy { if case .ready = store.lookup($0) { true } else { false } })
        tasks.forEach { $0.cancel() }
        await Self.settle { store.inUseCount == 0 }
        #expect(store.readyCount == 2)
    }

    /// G7 中不畫：request 新 key 只標 pending、renderer 0 次；end 後恰畫 1 次
    @Test func doesNotRenderDuringTransition() {
        let renderer = FakeLabelPrintRenderer()
        let store = LabelPrintStore(renderer: renderer)
        let key = Self.key(700)
        store.transitionBegan()
        store.request(key)
        #expect(renderer.rendered.isEmpty)
        #expect(store.lookup(key) == .fallback(.pending))
        _ = store.transitionEnded()
        #expect(renderer.rendered == [key])
        guard case .ready = store.lookup(key) else { Issue.record("not rendered after end"); return }
    }

    /// logical miss：G7 開始時使用中但未就緒記一筆；G7 中改成新 key 記一筆；同轉場同 key 只記一次；G7 外不記
    @Test func logicalMissesAreRecordedOncePerKeyPerTransition() async {
        let renderer = FakeLabelPrintRenderer()
        renderer.failing = true
        let store = LabelPrintStore(renderer: renderer)
        let failedKey = Self.key(700)
        let task = Task { await store.use(failedKey) }
        await Self.settle { store.inUseCount == 1 }
        #expect(store.lookup(failedKey) == .fallback(.failed))
        store.transitionBegan()
        let newKey = Self.key(720)
        store.request(newKey)
        store.request(newKey)
        #expect(store.transitionEnded() == "misses=2 reasons=absent:0,pending:1,rendering:0,failed:1")
        #expect(store.transitionEnded() == "misses=0 reasons=absent:0,pending:0,rendering:0,failed:0")
        task.cancel()
    }

    // MARK: S1（保留）

    @Test func labelRingEqualityComparesDiameterAndTint() {
        #expect(LabelRing(diameter: 100, tint: .white) == LabelRing(diameter: 100, tint: .white))
        #expect(LabelRing(diameter: 100, tint: .white) != LabelRing(diameter: 100, tint: .black))
        #expect(LabelRing(diameter: 100, tint: .white) != LabelRing(diameter: 101, tint: .white))
    }
}
