import Foundation
import Observation
import OSLog

/// 烘焙的抽象（測試注入假烘焙器）
protocol SwirlBaking: Sendable {
    func bake(_ recipe: SwirlRecipe, colors: SwirlColors, side: Int) async throws -> SwirlFace
}

extension SwirlBaker: SwirlBaking {}

extension SwirlFace: Equatable {
    static func == (a: SwirlFace, b: SwirlFace) -> Bool { a.image === b.image }
}

/// SWIRL 盤面的快取（CR-037 §4.4 資料流）：同鍵在途只烘一次；位元組預算 LRU；畫面上正在用的不淘汰；
/// 烘失敗的鍵不重試（鍵改變——換歌、換尺寸、換色——才會再烘）。讀 `state(for:)` 即被觀察，烘好時視圖重繪
@MainActor
@Observable
final class SwirlArtworkStore {
    struct Key: Hashable {
        /// 盤面格式改版就加 1，舊快取自然不命中
        static let currentSchema = 1

        let schema: Int
        let recipe: SwirlRecipe
        /// 已套用 Reduce Transparency 的有效配色（M1 成品圖含顏色與不透明度）
        let colors: SwirlColors
        let side: Int

        init(recipe: SwirlRecipe, colors: SwirlColors, side: Int) {
            schema = Self.currentSchema
            self.recipe = recipe
            self.colors = colors
            self.side = side
        }
    }

    enum State: Equatable {
        case baking
        case ready(SwirlFace)
        case failed

        var isReady: Bool { if case .ready = self { true } else { false } }
    }

    /// 常態預算：M1 1,024 px 一張 4 MiB，G7 轉場舊新兩張同時在畫面＋1 張餘裕
    static let defaultBudgetBytes = 12 << 20
    static let shared = SwirlArtworkStore(baker: try? SwirlBaker(), budgetBytes: defaultBudgetBytes)

    private static let log = Logger(subsystem: "com.ibridgezhao.yogsothothsecho", category: "turntable")

    private var entries: [Key: State] = [:]
    @ObservationIgnored private let baker: (any SwirlBaking)?
    @ObservationIgnored private let budgetBytes: Int
    /// 已就緒的鍵，舊 → 新
    @ObservationIgnored private var recency: [Key] = []
    @ObservationIgnored private var inUse: [Key: Int] = [:]

    init(baker: (any SwirlBaking)?, budgetBytes: Int) {
        self.baker = baker
        self.budgetBytes = budgetBytes
    }

    func state(for key: Key) -> State? { entries[key] }

    var residentBytes: Int {
        entries.values.reduce(0) { total, state in
            if case .ready(let face) = state { total + face.byteCount } else { total }
        }
    }

    func inUseCount(_ key: Key) -> Int { inUse[key, default: 0] }

    func request(_ key: Key) {
        if let existing = entries[key] {
            if existing.isReady { touch(key) }
            return
        }
        guard let baker else {
            entries[key] = .failed
            return
        }
        entries[key] = .baking
        Task {
            let result: State
            do {
                result = .ready(try await baker.bake(key.recipe, colors: key.colors, side: key.side))
            } catch {
                Self.log.error("swirl bake failed: \(String(describing: type(of: error)), privacy: .public)")
                result = .failed
            }
            finish(key, result)
        }
    }

    /// 視圖的作用域：顯示期間登記「使用中」（不被淘汰），任務被取消（視圖消失、鍵改變）時註銷
    func use(_ key: Key) async {
        inUse[key, default: 0] += 1
        request(key)
        while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
        inUse[key] = inUse[key, default: 1] > 1 ? inUse[key, default: 1] - 1 : nil
        evictOverBudget()
    }

    private func finish(_ key: Key, _ state: State) {
        guard entries[key] == .baking else { return }
        entries[key] = state
        if state.isReady {
            touch(key)
            evictOverBudget()
        }
    }

    private func touch(_ key: Key) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    private func evictOverBudget() {
        while residentBytes > budgetBytes, let victim = recency.first(where: { inUse[$0, default: 0] == 0 }) {
            recency.removeAll { $0 == victim }
            entries[victim] = nil
        }
    }
}
