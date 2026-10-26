// Bonjour 服務識別（基本設計 §4.1）；連線與配對從 S2 起實作（CR-007）
public enum EchoService {
    public static let type = "_yse._tcp"
    public static let domain = "local."

    /// Bonjour 實例名＝"Azathoth-"＋本機指紋末 4 碼；QR 的 instanceName 與廣播名必須同源（只作尋址提示，不作身分）
    public static func instanceName(for fingerprint: Fingerprint) -> String { "Azathoth-" + fingerprint.suffix }
}
