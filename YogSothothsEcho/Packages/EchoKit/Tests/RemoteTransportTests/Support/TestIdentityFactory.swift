import CryptoKit
import Foundation
import Security
@testable import RemoteTransport

/// 測試身分：執行時產生、不入 repo（CLAUDE.md：不 commit 任何憑證；sprint-2-detail.md §4.1）。
/// macOS：CryptoKit 產 P-256 私鑰、/usr/bin/openssl 在暫存目錄簽自簽憑證並打包 p12 → SecPKCS12Import 記憶體匯入 → 目錄即刪，不碰 Keychain。
enum TestIdentityFactory {
    enum Failure: Error { case openssl(Int32), importFailed(OSStatus), noIdentity, noIdentityInItems(String) }

    private static let password = "yse-test-ephemeral"

    #if os(macOS)
    static func make(commonName: String = MiniCert.randomCommonName())
        throws -> DeviceIdentity {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("yse-test-id-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = dir.appendingPathComponent("k.pem").path
        let crt = dir.appendingPathComponent("c.pem").path
        let p12 = dir.appendingPathComponent("i.p12")
        // macOS 的 /usr/bin/openssl 是 LibreSSL 3.3.6：產生或打包 p12 時，首位元組為 0 的 EC 私鑰會被寫成 31 bytes，
        // SecPKCS12Import 對這種 p12 回成功但 0 筆（2026-10-15 實測，sprint-2-detail.md 附錄 C）。
        // 所以只用首位元組非 0 的私鑰——由私鑰的值決定，不是對偶發失敗重試
        var privateKey = P256.Signing.PrivateKey()
        while privateKey.rawRepresentation.first == 0 { privateKey = P256.Signing.PrivateKey() }
        try privateKey.pemRepresentation.write(toFile: key, atomically: true, encoding: .utf8)
        try openssl(["req", "-new", "-x509", "-key", key, "-out", crt, "-days", "2", "-subj", "/CN=\(commonName)"])
        try openssl(["pkcs12", "-export", "-inkey", key, "-in", crt, "-out", p12.path, "-passout", "pass:\(password)",
                     "-keypbe", "PBE-SHA1-3DES", "-certpbe", "PBE-SHA1-3DES", "-macalg", "sha1"])
        guard #available(macOS 15, *) else { throw Failure.noIdentity }
        // 勿移除 kSecImportToMemoryOnly：少了它 SecPKCS12Import 會把身分寫進登入鑰匙圈
        let options = [kSecImportExportPassphrase: password, kSecImportToMemoryOnly: true] as [CFString: Any]
        var items: CFArray?
        let status = SecPKCS12Import(try Data(contentsOf: p12) as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess else { throw Failure.importFailed(status) }
        guard let first = (items as? [[CFString: Any]])?.first, let raw = first[kSecImportItemIdentity],
              CFGetTypeID(raw as CFTypeRef) == SecIdentityGetTypeID() else {
            let list = (items as? [[CFString: Any]]) ?? []
            throw Failure.noIdentityInItems("items=\(list.count) keys=\(list.map { $0.keys.map { $0 as String }.sorted() })")
        }
        return try DeviceIdentity(secIdentity: raw as! SecIdentity)
    }

    private static func openssl(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.openssl(process.terminationStatus) }
    }
    #endif
}
