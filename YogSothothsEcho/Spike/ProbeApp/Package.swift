// swift-tools-version: 6.0
// 只給 macOS 跑 ProbeApp 純邏輯測試用（iOS 模擬器 runtime 未安裝）。App 本體由 project.yml（XcodeGen）建置，
// 同一份 Shared/ 以原始檔身分編進 YSEProbe。用法：swift test --scratch-path <放在 ~/Documents 之外的目錄>
import PackageDescription

let package = Package(
    name: "ProbeShared",
    platforms: [.macOS(.v14)],
    // yse-spike（上層 Spike 套件）也依賴 ProbeShared：N5 訊息格式與 OneShot 只有一份
    products: [.library(name: "ProbeShared", targets: ["ProbeShared"])],
    targets: [
        .target(name: "ProbeShared", path: "Shared"),
        .testTarget(name: "ProbeSharedTests", dependencies: ["ProbeShared"], path: "Tests"),
    ]
)
