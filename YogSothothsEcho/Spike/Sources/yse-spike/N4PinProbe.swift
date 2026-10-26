import CryptoKit
import Foundation
import Network
import Security
import SpikeCore

// N4 診斷補充：TLS 1.3＋雙向自簽憑證＋指紋釘選，本機迴路（s0-offline-2026-10-15.md T4）。
// 憑證由 run_n4_pin.sh 以 openssl 產生在臨時目錄、跑完即刪；本程式只讀 PKCS#12 並只在記憶體匯入。
// 兩端都以 verify block 自行比對對端葉憑證的 SHA-256 指紋，並記下是否被呼叫、回傳值。
enum N4PinProbe {
    static let password = "yse-test"
    /// 等 verify block 觀察結果到齊的上限
    private static let settleTimeout: TimeInterval = 1
    /// 負例要斷言「伺服端沒收到資料」：這是沒發生的事，verify 到齊後再靜候一段才讀
    private static let quietWindow: TimeInterval = 0.5
    private static let queue = DispatchQueue(label: "yse-spike.n4pin")

    struct Party {
        let identity: sec_identity_t
        let fingerprint: Data
    }

    struct Record: Encodable {
        let experiment = "n4-pin"
        let pinCase: N4PinCase
        let isAsExpected: Bool
    }

    /// directory 內需有 server.p12、client.p12、other.p12（other＝拿來當錯誤指紋）
    static func run(directory: URL) async -> [Record]? {
        guard let server = load(directory.appendingPathComponent("server.p12")),
              let client = load(directory.appendingPathComponent("client.p12")),
              let other = load(directory.appendingPathComponent("other.p12")) else { return nil }
        var records: [Record] = []
        for variant in N4PinVariant.allCases {
            let clientExpects = variant == .clientPinMismatch ? other.fingerprint : server.fingerprint
            let serverExpects = variant == .serverPinMismatch ? other.fingerprint : client.fingerprint
            let pinCase = await trial(variant, server: server, client: client,
                                      clientExpects: clientExpects, serverExpects: serverExpects)
            records.append(Record(pinCase: pinCase, isAsExpected: pinCase.isAsExpected))
        }
        return records
    }

    // MARK: 憑證

    private static func load(_ url: URL) -> Party? {
        guard #available(macOS 15, *), let data = try? Data(contentsOf: url) else { return nil }
        // 勿移除 kSecImportToMemoryOnly：少了它 SecPKCS12Import 會把身分寫進登入鑰匙圈
        let options = [kSecImportExportPassphrase: password, kSecImportToMemoryOnly: true] as [CFString: Any]
        var items: CFArray?
        guard SecPKCS12Import(data as CFData, options as CFDictionary, &items) == errSecSuccess,
              let first = (items as? [[CFString: Any]])?.first,
              let raw = first[kSecImportItemIdentity],
              CFGetTypeID(raw as CFTypeRef) == SecIdentityGetTypeID() else { return nil }
        let identity = raw as! SecIdentity
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate,
              let secIdentity = sec_identity_create(identity) else { return nil }
        return Party(identity: secIdentity, fingerprint: fingerprint(certificate))
    }

    static func fingerprint(_ certificate: SecCertificate) -> Data {
        Data(SHA256.hash(data: SecCertificateCopyData(certificate) as Data))
    }

    /// 回呼（在 queue 上）寫、await 之後讀的單一值
    final class Observed<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Value?
        var value: Value? { lock.withLock { stored } }
        func record(_ value: Value) { lock.withLock { stored = value } }
    }

    private static func parameters(_ local: Party, expecting peer: Data, webSocket: Bool,
                                   verified: Observed<Bool>, requirePeerCertificate: Bool) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv13)
        sec_protocol_options_set_local_identity(options, local.identity)
        if requirePeerCertificate { sec_protocol_options_set_peer_authentication_required(options, true) }
        // 只比葉憑證整張 DER 的指紋（自簽釘選）；空鏈即拒絕
        sec_protocol_options_set_verify_block(options, { _, trust, complete in
            let chain = SecTrustCopyCertificateChain(sec_trust_copy_ref(trust).takeRetainedValue()) as? [SecCertificate]
            let accepted = chain?.first.map { fingerprint($0) == peer } ?? false
            verified.record(accepted)
            complete(accepted)
        }, queue)
        let parameters = NWParameters(tls: tls)
        parameters.requiredInterfaceType = .loopback
        if webSocket { NetProbe.addWebSocket(to: parameters) }
        return parameters
    }

    // MARK: 一次試驗

    private static func trial(_ variant: N4PinVariant, server: Party, client: Party,
                              clientExpects: Data, serverExpects: Data) async -> N4PinCase {
        let webSocket = variant == .positiveWebSocket
        let serverVerified = Observed<Bool>()
        let clientVerified = Observed<Bool>()
        let serverReceived = Observed<Bool>()
        var notes: [String] = []
        let result = { (clientReady: Bool, reply: Data?, version: String?) in
            N4PinCase(variant: variant, clientReady: clientReady, echo: reply == NetProbe.pingPayload,
                      negotiatedVersion: version,
                      clientVerifyAccepted: clientVerified.value, serverVerifyAccepted: serverVerified.value,
                      serverReceivedData: serverReceived.value ?? false, clientReceivedData: reply != nil,
                      error: notes.isEmpty ? nil : notes.joined(separator: "; "))
        }
        let serverParameters = parameters(server, expecting: serverExpects, webSocket: webSocket,
                                          verified: serverVerified, requirePeerCertificate: true)
        guard let listener = try? NWListener(using: serverParameters, on: .any) else {
            notes.append("listener init")
            return result(false, nil, nil)
        }
        defer { listener.cancel() }
        NetProbe.installEcho(on: listener, webSocket: webSocket, queue: queue) { serverReceived.record(true) }
        if let error = await NetProbe.waitReady(listener, queue: queue) {
            notes.append(error)
            return result(false, nil, nil)
        }
        guard let port = listener.port else { return result(false, nil, nil) }

        let connection = NWConnection(to: NetProbe.loopbackEndpoint(port: port, webSocket: webSocket),
                                      using: parameters(client, expecting: clientExpects, webSocket: webSocket,
                                                        verified: clientVerified, requirePeerCertificate: false))
        defer { connection.cancel() }
        if let error = await NetProbe.waitReady(connection, label: "client", queue: queue) {
            notes.append(error)
            return result(false, nil, nil)
        }
        let reply = await NetProbe.echo(over: connection, webSocket: webSocket, queue: queue, notes: &notes)
        // TLS 1.3：client ready 之後 server 才驗 client 憑證；等兩端觀察結果到齊（有上限）
        await settle { clientVerified.value != nil && serverVerified.value != nil }
        if variant == .clientPinMismatch || variant == .serverPinMismatch {
            try? await Task.sleep(for: .seconds(quietWindow))
        }
        return result(true, reply, NetProbe.negotiatedVersion(connection))
    }

    private static func settle(_ done: () -> Bool) async {
        let deadline = Date(timeIntervalSinceNow: settleTimeout)
        while !done(), Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
    }
}
