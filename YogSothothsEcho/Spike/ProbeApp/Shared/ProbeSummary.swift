import Foundation

/// 畫面上每張卡片的顯示狀態。刻意只含狀態文字：不放主機名、不放任何憑證或測試值。
public enum ProbeDisplay: Equatable, Sendable {
    case idle
    case running
    case passed(headline: String, lines: [String])
    case failed(headline: String, lines: [String])
}

/// 每個測試的逾時秒數（按鈕①②③共用）
public let probeTimeoutSeconds: TimeInterval = 10

public enum ConnectResult: Equatable, Sendable {
    case received(String)
    case invalidMessage
    case noEndpoint
    case timedOut
    case failed(String)
}

public enum StepOutcome: Equatable, Sendable {
    case ok
    case failed(String)
    case skipped
}

public struct KeychainStep: Equatable, Sendable {
    public let label: String
    public let outcome: StepOutcome
}

/// Keychain 三步（寫入、讀回比對、刪除）的原始結果。status 為 nil＝該步沒執行（前一步失敗）。
public struct KeychainReport: Equatable, Sendable {
    public let expected: String
    public let writeStatus: Int32?
    public let readStatus: Int32?
    public let readValue: String?
    public let deleteStatus: Int32?

    public init(expected: String, writeStatus: Int32?, readStatus: Int32?, readValue: String?, deleteStatus: Int32?) {
        self.expected = expected
        self.writeStatus = writeStatus
        self.readStatus = readStatus
        self.readValue = readValue
        self.deleteStatus = deleteStatus
    }

    public var steps: [KeychainStep] {
        [
            KeychainStep(label: "寫入", outcome: Self.outcome(of: writeStatus)),
            KeychainStep(label: "讀回比對", outcome: readOutcome),
            KeychainStep(label: "刪除", outcome: Self.outcome(of: deleteStatus)),
        ]
    }

    public var passed: Bool { steps.allSatisfy { $0.outcome == .ok } }

    private var readOutcome: StepOutcome {
        guard let readStatus else { return .skipped }
        guard readStatus == 0 else { return .failed("OSStatus \(readStatus)") }
        return readValue == expected ? .ok : .failed("讀回的值與寫入不一致")
    }

    private static func outcome(of status: Int32?) -> StepOutcome {
        guard let status else { return .skipped }
        return status == 0 ? .ok : .failed("OSStatus \(status)")
    }
}

public enum ProbeSummary {
    public static func browse(serviceNames: [String], failure: String?) -> ProbeDisplay {
        let type = N5Message.serviceType
        switch BrowseSelection.select(names: serviceNames, failure: failure) {
        case .failed(let failure):
            return .failed(headline: "瀏覽失敗", lines: [failure, "若是 NoAuth，請到 設定 > 隱私權 > 區域網路 允許本 app。"])
        case .none:
            return .failed(headline: "未找到 \(type) 服務", lines: [
                "確認 Mac 已執行 n5-listen、兩台在同一個 Wi-Fi，且已允許本 app 的「區域網路」。",
            ])
        case .ambiguous(let names):
            // 同網段可能有別人廣播；不判通過、不自動連
            return .failed(headline: "找到 \(names.count) 個 \(type) 服務，無法確定是哪台 Mac", lines: names)
        case .unique:
            return .passed(headline: "找到 1 個 \(type) 服務", lines: serviceNames)
        }
    }

    public static func connect(_ result: ConnectResult) -> ProbeDisplay {
        switch result {
        case .received(let challenge):
            return .passed(headline: challenge, lines: ["請與 Mac 終端機顯示的 6 位數比對，一致才算成功。"])
        case .invalidMessage:
            return .failed(headline: "收到的訊息格式不符", lines: ["不是 YSE-N5 訊息，視為失敗。"])
        case .noEndpoint:
            return .failed(headline: "尚無可連的服務", lines: ["先按①找到服務。"])
        case .timedOut:
            return .failed(headline: "\(Int(probeTimeoutSeconds)) 秒內沒有收到訊息", lines: [])
        case .failed(let error):
            return .failed(headline: "連線失敗", lines: [error])
        }
    }

    /// nil＝整組逾時（Keychain 呼叫卡住）
    public static func keychain(_ report: KeychainReport?) -> ProbeDisplay {
        guard let report else {
            return .failed(headline: "\(Int(probeTimeoutSeconds)) 秒內 Keychain 沒有回應", lines: [])
        }
        let lines = report.steps.map { step in
            switch step.outcome {
            case .ok: "\(step.label)：成功"
            case .failed(let reason): "\(step.label)：失敗（\(reason)）"
            case .skipped: "\(step.label)：略過"
            }
        }
        return report.passed
            ? .passed(headline: "Keychain 寫讀刪成功", lines: lines)
            : .failed(headline: "Keychain 測試失敗", lines: lines)
    }
}
