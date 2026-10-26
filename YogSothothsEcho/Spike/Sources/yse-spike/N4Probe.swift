import Foundation
import Network
import Security
import SpikeCore

// N4：Network.framework 的 TLS 1.3 PSK 能否在本機迴路建立 WebSocket 連線（sprint-0-detail.md §4.3 n4）。
// PSK 每次隨機產生、只在記憶體，不輸出。
enum N4Probe {
    private static let identity = Data("yse-s0-probe".utf8)
    private static let queue = DispatchQueue(label: "yse-spike.n4")

    /// 判定用的是 `.tls13`（§4.3 n4 的定義）；其餘變體只作診斷紀錄，不改判定
    enum Variant: String, CaseIterable, Sendable {
        case tls13 = "tls13-aes128gcm"
        case tls13Default = "tls13-default-suites"
        case tls12PSK = "tls12-psk-aes128gcm"
        case tls12ECDHEPSK = "tls12-ecdhe-psk-aes128cbc"
        /// 不疊 WebSocket：把 TLS 握手與 WebSocket 升級兩層分開看
        case tls13Raw = "tls13-aes128gcm-raw"
        case tls12PSKRaw = "tls12-psk-aes128gcm-raw"
        case tls12ECDHEPSKRaw = "tls12-ecdhe-psk-aes128cbc-raw"

        var version: tls_protocol_version_t {
            switch self {
            case .tls13, .tls13Default, .tls13Raw: .TLSv13
            case .tls12PSK, .tls12ECDHEPSK, .tls12PSKRaw, .tls12ECDHEPSKRaw: .TLSv12
            }
        }

        /// IANA 編號：0x1301 TLS_AES_128_GCM_SHA256、0x00A8 TLS_PSK_WITH_AES_128_GCM_SHA256、
        /// 0xC037 TLS_ECDHE_PSK_WITH_AES_128_CBC_SHA256
        var suite: UInt16? {
            switch self {
            case .tls13, .tls13Raw: 0x1301
            case .tls13Default: nil
            case .tls12PSK, .tls12PSKRaw: 0x00A8
            case .tls12ECDHEPSK, .tls12ECDHEPSKRaw: 0xC037
            }
        }

        var webSocket: Bool {
            switch self {
            case .tls13Raw, .tls12PSKRaw, .tls12ECDHEPSKRaw: false
            default: true
            }
        }
    }

    static func run(_ variant: Variant) async -> (N4Result, [String]) {
        var notes: [String] = []
        let serverKey = randomKey()
        guard let (listener, port) = await startEchoListener(psk: serverKey, variant: variant, notes: &notes) else {
            return (N4Result(positiveHandshake: false, positiveEcho: false, negativeHandshake: false,
                             negotiatedVersion: nil), notes)
        }
        defer { listener.cancel() }

        let positive = await connect(port: port, psk: serverKey, variant: variant, label: "positive", notes: &notes)
        var echoed = false
        if let connection = positive.connection {
            echoed = await NetProbe.echo(over: connection, webSocket: variant.webSocket, queue: queue, notes: &notes)
                == NetProbe.pingPayload
            connection.cancel()
        }

        let negative = await connect(port: port, psk: randomKey(), variant: variant, label: "negative", notes: &notes)
        negative.connection?.cancel()

        let result = N4Result(positiveHandshake: positive.connection != nil, positiveEcho: echoed,
                              negativeHandshake: negative.connection != nil, negotiatedVersion: positive.version)
        return (result, notes)
    }

    // MARK: 參數

    static func parameters(psk: Data, variant: Variant) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, variant.version)
        sec_protocol_options_set_max_tls_protocol_version(options, variant.version)
        let key = psk.withUnsafeBytes { DispatchData(bytes: $0) }
        let id = identity.withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(options, key as __DispatchData, id as __DispatchData)
        if let raw = variant.suite, let suite = tls_ciphersuite_t(rawValue: raw) {
            sec_protocol_options_append_tls_ciphersuite(options, suite)
        }

        let parameters = NWParameters(tls: tls)
        // 只在本機迴路監聽／連線，不對區網開放
        parameters.requiredInterfaceType = .loopback
        if variant.webSocket { NetProbe.addWebSocket(to: parameters) }
        return parameters
    }

    private static func randomKey() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    // MARK: 伺服端

    private static func startEchoListener(psk: Data, variant: Variant, notes: inout [String]) async -> (NWListener, NWEndpoint.Port)? {
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters(psk: psk, variant: variant), on: .any)
        } catch {
            notes.append("listener init failed: \(error)")
            return nil
        }
        NetProbe.installEcho(on: listener, webSocket: variant.webSocket, queue: queue)
        let failure = await NetProbe.waitReady(listener, queue: queue)
        if let failure { notes.append(failure) }
        guard failure == nil, let port = listener.port else {
            listener.cancel()
            return nil
        }
        return (listener, port)
    }

    // MARK: 用戶端

    private static func connect(port: NWEndpoint.Port, psk: Data, variant: Variant, label: String,
                                notes: inout [String]) async -> (connection: NWConnection?, version: String?) {
        let connection = NWConnection(to: NetProbe.loopbackEndpoint(port: port, webSocket: variant.webSocket),
                                      using: parameters(psk: psk, variant: variant))
        let failure = await NetProbe.waitReady(connection, label: label, queue: queue)
        if let failure {
            notes.append(failure)
            connection.cancel()
            return (nil, nil)
        }
        if let suite = NetProbe.negotiatedSuite(connection) { notes.append("\(label) negotiated suite 0x\(String(suite, radix: 16))") }
        return (connection, NetProbe.negotiatedVersion(connection))
    }
}
