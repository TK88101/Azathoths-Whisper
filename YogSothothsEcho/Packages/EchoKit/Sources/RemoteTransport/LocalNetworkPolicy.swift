import Darwin
import Foundation
import Network

/// IP 位址的原始位元組（IPv4 4 bytes／IPv6 16 bytes）
public struct IPAddressBytes: Hashable, Sendable {
    public let bytes: Data
    /// IPv6 scope 介面名（link-local 用來判定是哪張介面進來的）；無則 nil
    public let scope: String?

    public init?(_ text: String, scope: String? = nil) {
        if let v4 = IPv4Address(text) {
            bytes = v4.rawValue
        } else if let v6 = IPv6Address(text) {
            bytes = v6.rawValue
        } else {
            return nil
        }
        self.scope = scope
    }

    init?(raw: Data) {
        guard raw.count == 4 || raw.count == 16 else { return nil }
        bytes = raw
        scope = nil
    }

    /// IPv4-mapped IPv6（::ffff:a.b.c.d）一律化為 IPv4
    var normalized: Data {
        let mappedPrefix = Data(repeating: 0, count: 10) + Data([0xFF, 0xFF])
        if bytes.count == 16, bytes.prefix(12) == mappedPrefix { return bytes.suffix(4) }
        return bytes
    }

    public init?(host: NWEndpoint.Host) {
        switch host {
        case .ipv4(let address):
            bytes = address.rawValue
            scope = nil
        case .ipv6(let address):
            bytes = address.rawValue
            scope = address.interface?.name
        case .name: return nil
        @unknown default: return nil
        }
    }
}

public struct NetworkInterface: Equatable, Sendable {
    /// feth＝ZeroTier 等 overlay（security review S2 M-3）
    static let tunnelPrefixes = ["utun", "ipsec", "ppp", "tun", "tap", "gif", "stf", "feth"]

    public let name: String
    public let address: IPAddressBytes
    public let prefixLength: Int

    public init(name: String, address: IPAddressBytes, prefixLength: Int) {
        self.name = name
        self.address = address
        self.prefixLength = prefixLength
    }

    public var isTunnel: Bool { Self.tunnelPrefixes.contains { name.hasPrefix($0) } }

    /// 上線中介面的位址快照（`getifaddrs`）
    public static func current() -> [NetworkInterface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var result: [NetworkInterface] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard entry.ifa_flags & UInt32(IFF_UP) != 0, let address = entry.ifa_addr, let mask = entry.ifa_netmask,
                  let ip = rawAddress(address), let maskBytes = rawAddress(mask), maskBytes.count == ip.count,
                  let bytes = IPAddressBytes(raw: ip) else { continue }
            let prefix = maskBytes.reduce(0) { $0 + $1.nonzeroBitCount }
            result.append(NetworkInterface(name: String(cString: entry.ifa_name), address: bytes, prefixLength: prefix))
        }
        return result
    }

    private static func rawAddress(_ pointer: UnsafeMutablePointer<sockaddr>) -> Data? {
        switch Int32(pointer.pointee.sa_family) {
        case AF_INET:
            return pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { withUnsafeBytes(of: $0.pointee.sin_addr) { Data($0) } }
        case AF_INET6:
            return pointer.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { withUnsafeBytes(of: $0.pointee.sin6_addr) { Data($0) } }
        default:
            return nil
        }
    }
}

/// N-04「只在區網」（sprint-2-detail.md §4.7）：對端位址落在本機某個非隧道介面的子網內（IPv4 netmask／IPv6 prefix，
/// 含全域 IPv6 前綴與 IPv4 169.254/16）、或為 scope 屬非隧道介面的 IPv6 link-local、或為 loopback（測試用）才放行；
/// 無法判定＝拒絕（IPv6 link-local 的 fe80::/64 每張介面都有，只能靠 scope 分辨；security review S2 M-3）。
/// 限制：這是「同一子網」判定，不防同子網內的攻擊者（那由配對與釘選防）。
public enum LocalNetworkPolicy {
    public static func isOnLink(_ remote: IPAddressBytes, interfaces: [NetworkInterface], allowLoopback: Bool = true) -> Bool {
        let address = remote.normalized
        if isLoopback(address) { return allowLoopback }
        if isIPv6LinkLocal(address) {
            guard let scope = remote.scope else { return false }
            return interfaces.contains { $0.name == scope && !$0.isTunnel }
        }
        return interfaces.contains { interface in
            let local = interface.address.normalized
            return !interface.isTunnel && local.count == address.count && !isLoopback(local)
                && samePrefix(local, address, bits: interface.prefixLength)
        }
    }

    static func isLoopback(_ bytes: Data) -> Bool {
        bytes.count == 4 ? bytes.first == 127 : bytes == Data(repeating: 0, count: 15) + Data([1])
    }

    /// fe80::/10（IPv4 的 169.254/16 走一般子網比對）
    static func isIPv6LinkLocal(_ bytes: Data) -> Bool {
        bytes.count == 16 && bytes[bytes.startIndex] == 0xFE && (bytes[bytes.startIndex + 1] & 0xC0) == 0x80
    }

    static func samePrefix(_ a: Data, _ b: Data, bits: Int) -> Bool {
        guard bits > 0, bits <= a.count * 8 else { return false }
        let x = [UInt8](a), y = [UInt8](b)
        let whole = bits / 8, rest = bits % 8
        guard x[0..<whole] == y[0..<whole] else { return false }
        guard rest > 0 else { return true }
        let mask = UInt8(0xFF) << (8 - rest)
        return x[whole] & mask == y[whole] & mask
    }
}
