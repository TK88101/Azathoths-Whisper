import Foundation
import Testing

@testable import AzathothsWhisper

// 每批樂團簽字時由原型匯出的對照檔（`Tests/Fixtures/LyricsFX/b2-batch<n>-signed.json`）與共用的比對。
// 只有樂團名、目標值與元件代號

struct SignedBatchFile: Decodable {
    struct Band: Decodable {
        let name: String
        let aliases: [String]
        let tags: [String]
        let axes: [String: Double]
        /// 每槽所有 fit > 0 的元件（原型與 app 可比的那一層）
        let candidates: [String: [String]]

        var profile: SongProfile {
            SongProfile(
                axes: Dictionary(uniqueKeysWithValues: axes.compactMap { key, value in FXAxis(rawValue: key).map { ($0, value) } }),
                tags: Set(tags.compactMap(FXTag.init(rawValue:)))
            )
        }
    }

    /// 連帶團：目標值沒改，但這一批的新元件碰得到它；使用者一起看過、逐團記下決定
    struct Linked: Decodable {
        enum Decision: String, Decodable {
            /// 用這一批的新版
            case new
            /// 留在這一批之前的樣子（不算有差異）
            case current
            /// 退回單色基本型
            case mono
        }

        let name: String
        let decision: Decision
        /// 每槽所有 fit > 0 的元件（原型匯出；`current` 不填）
        let eligible: [String: [String]]?
        /// app 算出的可抽空間（`mono`／`current` 不填）
        let playable: PlayableSpace?
        let signed: String
        let reason: String
    }

    /// 明列不歸任何一團的合作寫法
    struct Unassigned: Decodable {
        let spelling: String
        let reason: String
    }

    let bands: [Band]
    let linked: [Linked]?
    let unassigned: [Unassigned]?

    static func url(batch: Int) throws -> URL {
        try GoldenFixtures.fixturesRoot().appendingPathComponent("LyricsFX/b2-batch\(batch)-signed.json")
    }

    static func load(batch: Int) throws -> SignedBatchFile {
        try JSONDecoder().decode(SignedBatchFile.self, from: Data(contentsOf: url(batch: batch)))
    }

    /// 已簽的各批中列為連帶的團（還沒簽的批次沒有對照檔，不算）
    static func linkedBands(batches: [Int]) throws -> [Linked] {
        try batches.filter { (try? url(batch: $0).checkResourceIsReachable()) == true }.flatMap { try load(batch: $0).linked ?? [] }
    }
}

enum SignedBatchChecks {
    static func everyBandAndAliasResolvesToItsSignedProfile(_ file: SignedBatchFile) {
        for band in file.bands {
            #expect(band.tags.allSatisfy { FXTag(rawValue: $0) != nil }, "\(band.name) 有 app 不認得的標籤")
            for name in [band.name] + band.aliases {
                #expect(SongProfileResolver.resolve(artist: name, genre: nil) == .profile(band.profile), "\(name)")
            }
        }
    }

    static func theAppOffersExactlyTheSignedCandidatesInEverySlot(_ file: SignedBatchFile) {
        for band in file.bands {
            for slot in FXSlot.allCases {
                let app = Set(LyricsFXCatalog.components(in: slot).filter { Composer.fit($0, band.profile) > 0 }.map(\.id))
                let signed = Set(band.candidates[slot.rawValue] ?? [])
                #expect(app == signed, "\(band.name) \(slot)：多 \(app.subtracting(signed)) 少 \(signed.subtracting(app))")
            }
        }
    }
}
