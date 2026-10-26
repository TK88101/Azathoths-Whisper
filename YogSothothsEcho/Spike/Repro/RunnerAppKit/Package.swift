// swift-tools-version: 6.0
// 最小重現：swift-testing runner 程序中 AppKit 事件分派與分散式通知的行為與 CLI 不同
// （s0-offline-2026-10-15.md T1 偏離的前提）。不碰 Music、不模擬輸入，只對本程序投遞事件與通知。
// 執行：swift test --package-path YogSothothsEcho/Spike/Repro/RunnerAppKit --scratch-path <~/Documents 之外的目錄>
import PackageDescription

let package = Package(
    name: "RunnerAppKit",
    platforms: [.macOS(.v14)],
    targets: [.testTarget(name: "RunnerAppKitTests")]
)
