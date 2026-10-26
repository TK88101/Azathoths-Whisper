#if os(macOS)
import Foundation
import RemoteProtocol

// 捷徑安裝流程（sprint-4-detail.md §4.6 安裝契約；CR-013(c)、CR-014）。只由使用者在設定頁按「安裝捷徑」觸發：
// 1 匯入前清單快照 → 2 簽署模板 → 3 以「捷徑」App 開啟簽好的檔（呼叫端注入，App/Remote 用 NSWorkspace）
// → 4 每 2 s 比對清單，30 s 內恰好一個新的同名者＝綁定 → 4b 以必停輸入跑一次，觸發「捷徑」App 首次播放的分享確認
// （#4-0 P1-a：要按「常に許可」）。簽好的檔不論成敗都刪除；不猜選、不自動刪除使用者的捷徑。

public protocol ShortcutSigning: Sendable {
    func sign(template: Data, timeout: Double) async -> SignedShortcut?
    func discard(_ signed: SignedShortcut) async
}

extension ShortcutRunner: ShortcutSigning {}

public protocol ShortcutInstallBinding: Sendable {
    func beginInstall() async -> [ShortcutListing.Entry]?
    func checkInstall(_ before: [ShortcutListing.Entry]) async -> Result<ShortcutIdentifier, ShortcutListing.InstallFailure>
}

extension ShortcutBinding: ShortcutInstallBinding {}

public actor ShortcutInstaller {
    public enum Phase: Sendable, Equatable {
        /// 已開啟「捷徑」App，等使用者按「加入」
        case waitingForAdd
        /// 已綁定，正跑一次必停輸入：「捷徑」App 會問是否允許分享，請按「常に許可」
        case confirmingFirstRun
    }

    public enum Outcome: Sendable, Equatable {
        case installed(ShortcutIdentifier)
        case listUnavailable, signFailed, openFailed, notDetected, nameTaken, ambiguous
    }

    static let signTimeout: Double = 30
    static let detectInterval: Double = 2
    static let detectDeadline: Double = 30
    /// 首次確認那次執行：分享確認框一直沒人按時，逾時終止（暫存檔隨之刪除；security review LOW-4）
    static let firstRunDeadline: Double = 60

    private let signer: any ShortcutSigning
    private let binding: any ShortcutInstallBinding
    private let open: @Sendable (SignedShortcut) async -> Bool
    private let starter: any ShortcutStarting
    private let clock: any ControlClock
    private let template: Data

    public init(signer: any ShortcutSigning, binding: any ShortcutInstallBinding, open: @escaping @Sendable (SignedShortcut) async -> Bool,
                starter: any ShortcutStarting, clock: any ControlClock = SystemControlClock()) {
        self.signer = signer
        self.binding = binding
        self.open = open
        self.starter = starter
        self.clock = clock
        template = ShortcutTemplate.data
    }

    public func install(progress: @Sendable (Phase) -> Void) async -> Outcome {
        guard let before = await binding.beginInstall() else { return .listUnavailable }
        guard let signed = await signer.sign(template: template, timeout: Self.signTimeout) else { return .signFailed }
        let outcome = await openAndBind(signed, before: before, progress: progress)
        await signer.discard(signed)
        return outcome
    }

    private func openAndBind(_ signed: SignedShortcut, before: [ShortcutListing.Entry], progress: @Sendable (Phase) -> Void) async -> Outcome {
        guard await open(signed) else { return .openFailed }
        progress(.waitingForAdd)
        let started = await clock.now()
        while await clock.now() - started < Self.detectDeadline {
            try? await clock.sleep(seconds: Self.detectInterval)
            switch await binding.checkInstall(before) {
            case .success(let id):
                progress(.confirmingFirstRun)
                triggerFirstRunPrompt(id)
                return .installed(id)
            case .failure(.notFound): continue
            case .failure(.nameTaken): return .nameTaken
            case .failure(.ambiguous): return .ambiguous
            }
        }
        return .notDetected
    }

    /// 必停輸入（不存在的專輯、首數 1）：捷徑查不到就停、不播；只為了讓「捷徑」App 跳出首次分享確認
    private func triggerFirstRunPrompt(_ id: ShortcutIdentifier) {
        let input = ShortcutInput(album: "yse-first-run-\(UUID().uuidString)", albumArtist: "", artist: "", position: 1, expectedCount: 1)
        guard let running = starter.start(id, input: input) else { return }
        let clock = self.clock
        Task {
            let timer = Task {
                try await clock.sleep(seconds: Self.firstRunDeadline)
                running.terminate()
            }
            _ = await running.wait()
            timer.cancel()
        }
    }
}
#endif
