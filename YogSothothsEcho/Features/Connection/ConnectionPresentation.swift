import RemoteTransport
import SwiftUI

/// 畫面會判斷的部分（純函式，單測）
enum ConnectionPresentation {
    static func failureMessage(_ failure: PairingFailure) -> LocalizedStringKey {
        switch failure {
        case .rejected: "Your Mac rejected the pairing."
        case .expired, .unavailable: "That code is no longer valid. Generate a new one on your Mac."
        case .cancelled: "Pairing was cancelled on your Mac."
        case .invalid: "The pairing code was not accepted. Generate a new one on your Mac."
        case .macPinMismatch: "The Mac that answered isn't the one that showed this code."
        case .notFound: "Couldn't find your Mac on this network."
        case .notOnLink, .network, .timeout: "Couldn't reach your Mac. Check that both are on the same Wi-Fi."
        }
    }

    /// UI 測試讀的狀態代號（非顯示文字）
    static func stateID(_ state: ConnectionViewModel.State) -> String {
        switch state {
        case .unpaired(let scan): "unpaired.\(scan)"
        case .pairing: "pairing"
        case .pairingFailed(let failure): "pairingFailed.\(failure)"
        case .connecting: "connecting"
        case .connected: "connected"
        case .retrying: "retrying"
        case .waitingForMac: "waitingForMac"
        case .needsRepair: "needsRepair"
        case .suspended: "suspended"
        }
    }
}
