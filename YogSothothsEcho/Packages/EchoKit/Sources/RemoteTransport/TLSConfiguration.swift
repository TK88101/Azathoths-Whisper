import Foundation
import Network
import RemoteProtocol
import Security

public enum TLSRole: Sendable {
    case server, client
}

/// TLS 1.3＋雙向自簽憑證＋指紋釘選＋WebSocket（CR-007、CR-010；sprint-2-detail.md §4.7）
public enum TLSConfiguration {
    public static let exporterLabel = "EXPORTER-yse-pair-v1"
    public static let exporterLength = 32
    /// 兩端都關 tickets 與 resumption（CR-010 ②(i)）；寫成常數供設定值測試斷言
    public static let ticketsEnabled = false
    public static let resumptionEnabled = false

    /// verify 只取 leaf DER SHA-256 交給 `verify`，空鏈即拒，不做系統信任評估
    public static func parameters(identity: DeviceIdentity, role: TLSRole, verifyQueue: DispatchQueue,
                                  verify: @escaping @Sendable (Fingerprint?) -> Bool) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv13)
        if let local = sec_identity_create(identity.secIdentity) {
            sec_protocol_options_set_local_identity(options, local)
        }
        if role == .server { sec_protocol_options_set_peer_authentication_required(options, true) }
        sec_protocol_options_set_tls_tickets_enabled(options, ticketsEnabled)
        sec_protocol_options_set_tls_resumption_enabled(options, resumptionEnabled)
        sec_protocol_options_set_verify_block(options, { _, trust, complete in
            let chain = SecTrustCopyCertificateChain(sec_trust_copy_ref(trust).takeRetainedValue()) as? [SecCertificate]
            let leaf = chain?.first.map { Fingerprint(der: SecCertificateCopyData($0) as Data) }
            complete(verify(leaf))
        }, verifyQueue)
        let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
        parameters.includePeerToPeer = false
        parameters.prohibitedInterfaceTypes = [.cellular]
        let webSocket = NWProtocolWebSocket.Options()
        webSocket.autoReplyPing = false
        webSocket.maximumMessageSize = TransportLimits.maxMessageBytes
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
        return parameters
    }

    static func metadata(_ connection: NWConnection) -> sec_protocol_metadata_t? {
        (connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata)?.securityProtocolMetadata
    }

    /// 對端 leaf 指紋（ready 之後取）
    public static func peerFingerprint(_ connection: NWConnection) -> Fingerprint? {
        guard let metadata = metadata(connection) else { return nil }
        let leaf = Locked<Fingerprint?>(nil)
        _ = sec_protocol_metadata_access_peer_certificate_chain(metadata) { certificate in
            let der = SecCertificateCopyData(sec_certificate_copy_ref(certificate).takeRetainedValue()) as Data
            leaf.withLock { if $0 == nil { $0 = Fingerprint(der: der) } }
        }
        return leaf.withLock { $0 }
    }

    /// RFC 5705／8446 exporter（S2-P1：兩端一致、每連線不同）
    public static func exporter(_ connection: NWConnection) -> Data? {
        guard let metadata = metadata(connection) else { return nil }
        let data: DispatchData? = exporterLabel.withCString { label in
            sec_protocol_metadata_create_secret(metadata, exporterLabel.utf8.count, label, exporterLength) as DispatchData?
        }
        return data.map { Data($0) }
    }
}
