#if os(macOS)
import Foundation
import RemoteProtocol

// 捷徑身分（CR-014；sprint-4-detail.md §4.5 步驟 2、§4.6）：App 身分讀不到「捷徑」的內容（#4-0 附錄 B），
// 改以安裝時綁定的識別碼辨認——識別碼經編輯與改名不變、同名匯入得到新的。
// `shortcuts list --show-identifiers` 的輸出含使用者所有捷徑名稱：只在本檔記憶體內解析，不記錄、不外傳。

public enum ShortcutListing {
    public struct Entry: Sendable, Equatable {
        public let name: String
        public let id: ShortcutIdentifier
    }

    public enum InstallFailure: Error, Sendable, Equatable {
        /// 還沒看到新的同名捷徑（使用者尚未按「加入」）
        case notFound
        /// 已有同名者，新匯入的被改名成「… 2」：請使用者刪掉舊的再裝
        case nameTaken
        /// 新出現的同名者不只一個：不猜
        case ambiguous
    }

    /// 讀取清單的能力（正式＝ShortcutRunner；測試＝替身）
    public protocol Source: Sendable {
        func list(timeout: Double) async -> Data?
    }

    /// 每行「名稱 (UUID)」；名稱本身可含括號，以最後一組括號為識別碼。格式不符的行略過
    public static func parse(_ data: Data) -> [Entry] {
        String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { line in
            guard line.hasSuffix(")"), let open = line.range(of: " (", options: .backwards) else { return nil }
            let idText = line[open.upperBound..<line.index(before: line.endIndex)]
            guard let id = ShortcutIdentifier(String(idText)) else { return nil }
            return Entry(name: String(line[..<open.lowerBound]), id: id)
        }
    }

    /// 安裝前後的清單差：新出現、名稱完全等於 `name` 的恰好一個才算裝好
    public static func installed(name: String, before: [Entry], after: [Entry]) -> Result<ShortcutIdentifier, InstallFailure> {
        let known = Set(before.map(\.id.value))
        let added = after.filter { !known.contains($0.id.value) }
        let exact = added.filter { $0.name == name }
        if exact.count > 1 { return .failure(.ambiguous) }
        if let only = exact.first { return .success(only.id) }
        return added.contains { $0.name.hasPrefix(name + " ") } ? .failure(.nameTaken) : .failure(.notFound)
    }
}

extension ShortcutRunner: ShortcutListing.Source {}

/// 綁定的識別碼存放處（正式＝UserDefaults，非機密；測試＝記憶體）
public protocol ShortcutBindingStore: Sendable {
    func load() -> ShortcutIdentifier?
    func save(_ id: ShortcutIdentifier?)
}

public struct UserDefaultsShortcutBindingStore: ShortcutBindingStore, @unchecked Sendable {
    static let key = "yse.relay.shortcutIdentifier"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> ShortcutIdentifier? { defaults.string(forKey: Self.key).flatMap(ShortcutIdentifier.init) }
    public func save(_ id: ShortcutIdentifier?) { defaults.set(id?.value, forKey: Self.key) }
}

public enum ShortcutBindingStatus: Sendable, Equatable {
    case bound(ShortcutIdentifier)
    case missing
}

public actor ShortcutBinding {
    public static let shortcutName = "YSE Play v1"
    static let cacheSeconds: Double = 60

    private let store: any ShortcutBindingStore
    private let lister: any ShortcutListing.Source
    private let clock: any ControlClock
    private var cached: (status: ShortcutBindingStatus, at: Double)?

    public init(store: any ShortcutBindingStore, lister: any ShortcutListing.Source, clock: any ControlClock = SystemControlClock()) {
        self.store = store
        self.lister = lister
        self.clock = clock
    }

    /// 點歌前：綁定的識別碼還在清單裡＝bound（改名也算）；沒有綁定、不在、清單讀不到或逾時＝missing（fail-closed）
    public func status() async -> ShortcutBindingStatus {
        let now = await clock.now()
        if let cached, now - cached.at < Self.cacheSeconds { return cached.status }
        let status = await freshStatus()
        cached = (status, now)
        return status
    }

    public func invalidate() { cached = nil }

    private func freshStatus() async -> ShortcutBindingStatus {
        guard let id = store.load() else { return .missing }
        guard let data = await lister.list(timeout: PlaybackLimits.bindingTimeout) else { return .missing }
        return ShortcutListing.parse(data).contains { $0.id == id } ? .bound(id) : .missing
    }

    // MARK: 安裝（§4.6 步驟 1、4）

    /// 開啟匯入前的清單快照；讀不到回 nil（安裝失敗）
    public func beginInstall() async -> [ShortcutListing.Entry]? {
        guard let data = await lister.list(timeout: PlaybackLimits.bindingTimeout) else { return nil }
        return ShortcutListing.parse(data)
    }

    /// 使用者按「加入」後：比對快照，恰好一個新的同名者＝綁定並持久化；失敗不動原綁定
    public func checkInstall(_ before: [ShortcutListing.Entry]) async -> Result<ShortcutIdentifier, ShortcutListing.InstallFailure> {
        guard let data = await lister.list(timeout: PlaybackLimits.bindingTimeout) else { return .failure(.notFound) }
        let result = ShortcutListing.installed(name: Self.shortcutName, before: before, after: ShortcutListing.parse(data))
        if case .success(let id) = result {
            store.save(id)
            cached = nil
        }
        return result
    }
}
#endif
