// swift-tools-version: 6.0
// S2 前置隔離探針（CR-010 ⑪ S2-P1／P2）。不是產品 target，不進 EchoKit。
import PackageDescription

let package = Package(
    name: "S2Probe",
    platforms: [.macOS(.v14), .iOS(.v18)],
    products: [.library(name: "S2ProbeCore", targets: ["S2ProbeCore"])],
    targets: [
        .target(name: "S2ProbeCore"),
        .executableTarget(name: "s2-keyprobe", dependencies: ["S2ProbeCore"]),
        .testTarget(name: "S2ProbeCoreTests", dependencies: ["S2ProbeCore"]),
    ],
    swiftLanguageModes: [.v5]
)
