// swift-tools-version: 6.0
// S0 可行性實測工具（docs/plans/2026-10-14-yse/sprint-0-detail.md）。不是產品 target。
import PackageDescription

let package = Package(
    name: "YSESpike",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "ProbeApp")],
    targets: [
        .target(name: "SpikeCore"),
        .executableTarget(name: "yse-spike",
                         dependencies: ["SpikeCore", .product(name: "ProbeShared", package: "ProbeApp")]),
        .testTarget(name: "SpikeCoreTests", dependencies: ["SpikeCore"]),
        // 執行檔薄殼中可離線驗證的部分（AppKit 事件分派等）；不碰 Music
        .testTarget(name: "YSESpikeTests", dependencies: ["yse-spike"]),
    ]
)
