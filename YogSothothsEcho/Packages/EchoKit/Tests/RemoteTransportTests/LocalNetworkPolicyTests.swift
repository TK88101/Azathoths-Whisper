import Foundation
import Testing
@testable import RemoteTransport

// S2 T6a（sprint-2-detail.md §4.7「只在區網」）：對端是否落在本機非隧道介面的子網內

private func v4(_ text: String) -> IPAddressBytes { IPAddressBytes(text)! }

struct LocalNetworkPolicyTests {
    let wifi = NetworkInterface(name: "en0", address: v4("192.168.1.20"), prefixLength: 24)
    let wifi6 = NetworkInterface(name: "en0", address: IPAddressBytes("2001:db8:1:2::20")!, prefixLength: 64)
    let vpn = NetworkInterface(name: "utun3", address: v4("10.8.0.2"), prefixLength: 24)

    @Test func sameIPv4SubnetIsOnLink() {
        #expect(LocalNetworkPolicy.isOnLink(v4("192.168.1.77"), interfaces: [wifi]))
        #expect(!LocalNetworkPolicy.isOnLink(v4("192.168.2.77"), interfaces: [wifi]))
    }

    @Test func globalIPv6PrefixIsOnLink() {
        #expect(LocalNetworkPolicy.isOnLink(IPAddressBytes("2001:db8:1:2::99")!, interfaces: [wifi6]))
        #expect(!LocalNetworkPolicy.isOnLink(IPAddressBytes("2001:db8:1:3::99")!, interfaces: [wifi6]))
    }

    @Test func loopbackIsOnLink() {
        #expect(LocalNetworkPolicy.isOnLink(v4("127.0.0.1"), interfaces: []))
        #expect(LocalNetworkPolicy.isOnLink(IPAddressBytes("::1")!, interfaces: []))
    }

    /// security review S2 M-3：IPv6 link-local 要看 scope 介面——非隧道才放行；不帶 scope＝無法判定＝拒絕
    @Test func ipv6LinkLocalRequiresNonTunnelScope() {
        let ll = NetworkInterface(name: "en0", address: IPAddressBytes("fe80::20")!, prefixLength: 64)
        let vpnLL = NetworkInterface(name: "utun3", address: IPAddressBytes("fe80::30")!, prefixLength: 64)
        #expect(LocalNetworkPolicy.isOnLink(IPAddressBytes("fe80::1", scope: "en0")!, interfaces: [ll, vpnLL]))
        #expect(!LocalNetworkPolicy.isOnLink(IPAddressBytes("fe80::1", scope: "utun3")!, interfaces: [ll, vpnLL]))
        #expect(!LocalNetworkPolicy.isOnLink(IPAddressBytes("fe80::1", scope: "en9")!, interfaces: [ll, vpnLL]))
        #expect(!LocalNetworkPolicy.isOnLink(IPAddressBytes("fe80::1")!, interfaces: [ll, vpnLL]))
    }

    /// IPv4 link-local 與其他位址一樣，要落在本機非隧道介面的 169.254/16 子網內
    @Test func ipv4LinkLocalMustMatchAnInterfaceSubnet() {
        #expect(!LocalNetworkPolicy.isOnLink(v4("169.254.3.4"), interfaces: []))
        #expect(!LocalNetworkPolicy.isOnLink(v4("169.254.3.4"),
                                             interfaces: [NetworkInterface(name: "utun1", address: v4("169.254.9.9"), prefixLength: 16)]))
        #expect(LocalNetworkPolicy.isOnLink(v4("169.254.3.4"),
                                            interfaces: [NetworkInterface(name: "en0", address: v4("169.254.9.9"), prefixLength: 16)]))
    }

    @Test func tunnelInterfaceSubnetIsRejected() {
        #expect(!LocalNetworkPolicy.isOnLink(v4("10.8.0.9"), interfaces: [vpn]))
        for name in ["utun0", "ipsec1", "ppp0", "tun2", "tap0", "gif0", "stf0", "feth1234"] {
            #expect(NetworkInterface(name: name, address: v4("10.0.0.1"), prefixLength: 8).isTunnel, "\(name)")
        }
        #expect(!wifi.isTunnel)
    }

    @Test func publicAddressIsRejected() {
        #expect(!LocalNetworkPolicy.isOnLink(v4("8.8.8.8"), interfaces: [wifi, wifi6]))
    }

    @Test func ipv4MappedIPv6IsTreatedAsIPv4() {
        #expect(LocalNetworkPolicy.isOnLink(IPAddressBytes("::ffff:192.168.1.5")!, interfaces: [wifi]))
    }

    @Test func loopbackCanBeDeclaredOffLinkForTests() {
        #expect(!LocalNetworkPolicy.isOnLink(v4("127.0.0.1"), interfaces: [], allowLoopback: false))
    }

    @Test func unparsableAddressIsRejected() {
        #expect(IPAddressBytes("not-an-ip") == nil)
    }

    @Test func currentInterfacesIncludeLoopback() {
        #expect(NetworkInterface.current().contains { $0.name.hasPrefix("lo") })
    }
}

struct PairingGateTests {
    let a = Fingerprint(bytes: Data(repeating: 1, count: 32))!

    @Test func onlyNewerSnapshotsArePublished() {
        let gate = PairingGate()
        gate.publish(PairingGate.Snapshot(version: 2, trusted: [a], pairingOpen: true))
        gate.publish(PairingGate.Snapshot(version: 1, trusted: [], pairingOpen: false))   // 晚到的舊快照
        #expect(gate.current.version == 2)
        #expect(gate.current.trusted == [a] && gate.current.pairingOpen)
    }

    @Test func admitsTrustedOrUnknownWhilePairingOpen() {
        let gate = PairingGate()
        let unknown = Fingerprint(bytes: Data(repeating: 9, count: 32))!
        #expect(gate.admits(a) == .reject)
        gate.publish(PairingGate.Snapshot(version: 1, trusted: [a], pairingOpen: false))
        #expect(gate.admits(a) == .trusted)
        #expect(gate.admits(unknown) == .reject)
        gate.publish(PairingGate.Snapshot(version: 2, trusted: [a], pairingOpen: true))
        #expect(gate.admits(unknown) == .pairingCandidate)
    }
}
