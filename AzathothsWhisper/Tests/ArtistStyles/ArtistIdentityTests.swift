import Foundation
import Testing

@testable import AzathothsWhisper

// ⑥b 計劃 §4.2（R1-4、R1-5、R2-1、R2-2）：MB 候選與曲庫專輯的身分判定。歌手與專輯名全為自編
@Suite("Artist identity")
struct ArtistIdentityTests {
    private func candidate(_ id: String, _ name: String, aliases: [String] = [], albums: [String]) -> ArtistIdentity.Candidate {
        ArtistIdentity.Candidate(id: id, name: name, aliases: aliases, releaseGroups: albums.enumerated().map { .init(id: "\(id)-rg\($0.offset)", title: $0.element) })
    }

    private func judge(_ artist: String, library: [String], _ candidates: [ArtistIdentity.Candidate]) -> ArtistIdentity.Outcome {
        ArtistIdentity.judge(artist: artist, libraryAlbums: library, candidates: candidates)
    }

    @Test func noCandidateWithTheSameNameIsNotFound() {
        #expect(judge("Velvet Lanterns", library: ["Night Ferry"], [candidate("a", "Velvet Lantern Co", albums: ["Night Ferry"])]) == .unresolved(.notFound))
    }

    @Test func oneCandidateWithTwoMatchingAlbumsIsVerified() {
        let only = candidate("a", "Velvet Lanterns", albums: ["Night Ferry", "Paper Harbour", "Other"])
        #expect(judge("Velvet Lanterns", library: ["Night Ferry", "Paper Harbour"], [only]) == .verified(id: "a", matchedReleaseGroups: ["a-rg0", "a-rg1"]))
    }

    @Test func oneDistinctiveMatchingAlbumIsEnough() {
        let only = candidate("a", "Velvet Lanterns", albums: ["Night Ferry"])
        #expect(judge("Velvet Lanterns", library: ["Night Ferry - Single"], [only]) == .verified(id: "a", matchedReleaseGroups: ["a-rg0"]))
    }

    /// R2-1：唯一同名者也一樣，單張命中是泛用標題不算
    @Test(arguments: ["Greatest Hits", "Live", "Best Of", "The Best", "Demo", "XO", "Velvet Lanterns", "Anthology (Deluxe Edition)"])
    func aSingleGenericAlbumDoesNotVerify(title: String) {
        let only = candidate("a", "Velvet Lanterns", albums: [title])
        #expect(judge("Velvet Lanterns", library: [title], [only]) == .unresolved(.noAlbumMatch))
    }

    @Test func aGenericAlbumPlusADistinctiveOneVerifies() {
        let only = candidate("a", "Velvet Lanterns", albums: ["Live", "Night Ferry"])
        #expect(judge("Velvet Lanterns", library: ["Live", "Night Ferry"], [only]) == .verified(id: "a", matchedReleaseGroups: ["a-rg0", "a-rg1"]))
    }

    @Test func aSameNameCandidateWithoutMatchingAlbumsIsNoAlbumMatch() {
        #expect(judge("Velvet Lanterns", library: ["Night Ferry"], [candidate("a", "Velvet Lanterns", albums: ["Elsewhere"])]) == .unresolved(.noAlbumMatch))
    }

    @Test func theCandidateWhoseAlbumsMatchWinsAmongNamesakes() {
        let other = candidate("a", "Velvet Lanterns", albums: ["Elsewhere"])
        let ours = candidate("b", "Velvet Lanterns", albums: ["Night Ferry"])
        #expect(judge("Velvet Lanterns", library: ["Night Ferry"], [other, ours]) == .verified(id: "b", matchedReleaseGroups: ["b-rg0"]))
    }

    @Test func twoNamesakesThatBothMatchAreAmbiguous() {
        let one = candidate("a", "Velvet Lanterns", albums: ["Night Ferry"])
        let two = candidate("b", "Velvet Lanterns", albums: ["Night Ferry"])
        #expect(judge("Velvet Lanterns", library: ["Night Ferry"], [one, two]) == .unresolved(.ambiguous))
    }

    /// R1-5：不靜默丟掉第 9 個以後的候選
    @Test func moreThanEightNamesakesAreAmbiguous() {
        let many = (0..<9).map { candidate("c\($0)", "Velvet Lanterns", albums: $0 == 0 ? ["Night Ferry"] : []) }
        #expect(judge("Velvet Lanterns", library: ["Night Ferry"], many) == .unresolved(.ambiguous))
        #expect(judge("Velvet Lanterns", library: ["Night Ferry"], Array(many.prefix(8))) == .verified(id: "c0", matchedReleaseGroups: ["c0-rg0"]))
    }

    @Test func anAliasCountsAsTheSameName() {
        let aliased = candidate("a", "The Velvet Lantern Orchestra", aliases: ["Velvet Lanterns"], albums: ["Night Ferry"])
        #expect(judge("Velvet Lanterns", library: ["Night Ferry"], [aliased]) == .verified(id: "a", matchedReleaseGroups: ["a-rg0"]))
    }

    @Test func caseTheAndPunctuationAreFolded() {
        #expect(ArtistIdentity.isSameName("the velvet-lanterns", "Velvet Lanterns"))
        #expect(!ArtistIdentity.isSameName("Velvet Lantern", "Velvet Lanterns"))
    }

    @Test func aNameThatNormalizesToNothingIsNotQueried() {
        #expect(judge("!!!", library: ["Night Ferry"], []) == .unresolved(.emptyName))
        #expect(ArtistIdentity.isQueryable("!!!") == false && ArtistIdentity.isQueryable("Velvet Lanterns"))
    }

    @Test(arguments: [
        ("Night Ferry - Single", "nightferry"), ("Night Ferry - EP", "nightferry"), ("Night Ferry (Deluxe Edition)", "nightferry"),
        ("Night Ferry [2011 Remaster]", "nightferry"), ("Night Ferry (Live)", "nightferry"), ("The Night Ferry", "thenightferry"),
        ("Été Brûlant", "etebrulant"), ("Night Ferry (Part II)", "nightferrypartii"),
    ])
    func albumTitlesAreNormalized(raw: String, expected: String) {
        #expect(ArtistIdentity.albumKey(raw) == expected)
    }

    @Test func emptyAlbumTitlesNeverMatch() {
        let only = candidate("a", "Velvet Lanterns", albums: ["", "Night Ferry"])
        #expect(judge("Velvet Lanterns", library: ["", " - Single"], [only]) == .unresolved(.noAlbumMatch))
    }

    /// 送出前的專輯清單：正規化後去重、去空白、保留第一次出現的原始寫法
    @Test func outgoingAlbumNamesAreDeduplicated() {
        #expect(ArtistIdentity.outgoingAlbums(["Night Ferry", "Night Ferry - Single", "", "Paper Harbour"]) == ["Night Ferry", "Paper Harbour"])
    }
}
