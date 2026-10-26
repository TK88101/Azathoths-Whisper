// swift-tools-version: 6.0
// EchoKit：Azathoth's Whisper（Mac 中繼）與 Yog-Sothoth's Echo（iPad）共用的套件
// （docs/plans/2026-10-14-yse/02-basic-design.md §2、sprint-1-detail.md §4.2）。只有這三個模組。
import PackageDescription

let package = Package(
    name: "EchoKit",
    platforms: [.macOS(.v14), .iOS(.v18)],
    products: [
        .library(name: "RemoteProtocol", targets: ["RemoteProtocol"]),
        .library(name: "RemoteTransport", targets: ["RemoteTransport"]),
        .library(name: "MusicRemoteBridge", targets: ["MusicRemoteBridge"]),
    ],
    targets: [
        .target(name: "RemoteProtocol"),
        .target(name: "RemoteTransport", dependencies: ["RemoteProtocol"]),
        // macOS only：整個模組包在 #if os(macOS) 內
        .target(name: "MusicRemoteBridge", dependencies: ["RemoteProtocol"]),
        .testTarget(name: "RemoteProtocolTests", dependencies: ["RemoteProtocol"]),
        // S3 T13：曲庫變動的端到端 localhost 測試要同時用到 MusicRemoteBridge（只限測試 target；Bridge 本身仍不碰網路）
        .testTarget(name: "RemoteTransportTests", dependencies: ["RemoteTransport", "MusicRemoteBridge"]),
        .testTarget(name: "MusicRemoteBridgeTests", dependencies: ["MusicRemoteBridge"]),
    ]
)
