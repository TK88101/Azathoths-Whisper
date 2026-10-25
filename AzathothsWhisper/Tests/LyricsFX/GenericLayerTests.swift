import Testing

@testable import AzathothsWhisper

// ⑦ 通用零件（docs/plans/2026-10-25-lyrics-fx-generic-parts.md §4.1、§4.3–4.5）：通用層排在 Apple 曲風之後，
// 只接住現在會素面的曲；通用列是手定的政策列，只帶自己的私有標籤
@Suite("Generic layer")
struct GenericLayerTests {
    private func resolve(_ genre: String?, mb: ArtistGenres = .unknown, artist: String = "Velvet Lanterns", japanese: Bool = false) -> ProfileResolution {
        SongProfileResolver.resolve(artist: artist, genre: genre, lyrics: .text(isJapanese: japanese), artistGenres: mb)
    }

    private func tags(_ resolution: ProfileResolution) -> Set<FXTag>? {
        if case .genericRow(let profile) = resolution { return profile.tags }
        return nil
    }

    // MARK: 落層

    @Test func anAppleIndustrialGenreFallsToTheGenericLayer() {
        #expect(tags(resolve("Industrial")) == [.genIndustrial])
    }

    @Test func anMBIndustrialGenreFallsToTheGenericLayer() {
        #expect(tags(resolve("Electronic", mb: .verified(["industrial", "ebm"]))) == [.genIndustrial])
    }

    @Test func anExistingAppleRowStillWinsOverAGenericMBGenre() {
        let resolution = resolve("Alternative Rock", mb: .verified(["industrial"]))
        #expect(resolution.source == .genreRow, "MB 碰不到既有列時，Apple 的既有列照舊優先")
    }

    @Test func japaneseLyricsStayJPop() {
        #expect(resolve("ポップ", mb: .verified(["industrial"]), japanese: true) == .jpop)
    }

    @Test func signedBandsAreUntouched() {
        #expect(resolve("Industrial", artist: "Rammstein").source == .signedBand)
    }

    @Test func noGenericHitIsStillPlain() {
        #expect(resolve("Reggae", mb: .verified(["roots reggae"])) == .noMatch)
    }

    @Test func theGenericSourceDoesNotDependOnLyrics() {
        #expect(resolve("Industrial").source == .generic)
        #expect(!ProfileSource.generic.dependsOnLyrics)
    }

    @Test(arguments: ["industrial", "EBM", "Neue Deutsche Härte", "インダストリアル"])
    func industrialKeywordsMatch(genre: String) {
        #expect(tags(resolve(genre)) == [.genIndustrial])
    }

    @Test(arguments: [
        ("experimental", FXTag.genExperimental), ("Avant-Garde", .genExperimental), ("noise rock", .genExperimental),
        ("Electronica", .genElectronic), ("trip-hop", .genElectronic), ("Downtempo", .genElectronic), ("jungle", .genElectronic), ("dub", .genElectronic),
        ("エレクトロニック", .genElectronic), ("Dance", .genElectronic),
        ("ポップ", .genPop), ("art pop", .genPop), ("J-Pop", .genPop),
        ("Singer/Songwriter", .genFolk), ("neofolk", .genFolk), ("Americana", .genFolk), ("country gospel", .genFolk), ("フォーク", .genFolk),
        ("new age", .genAmbient), ("drone", .genAmbient),
        ("madrigal", .genSacred), ("Gregorian Chant", .genSacred),
        ("dark wave", .genDarkwave), ("ダークウェーブ", .genDarkwave),
        ("Hip-Hop/Rap", .genHipHop), ("ヒップホップ", .genHipHop), ("alternative hip hop", .genHipHop),
    ])
    func eachFamilyKeywordMatches(genre: String, family: FXTag) {
        #expect(tags(resolve(genre))?.contains(family) == true, "\(genre)")
    }

    @Test(arguments: ["singer", "trap", "Reggae", "Soundtrack Jazz Lounge"])
    func lookalikesDoNotMatchAFamily(genre: String) {
        #expect(tags(resolve(genre)).map { $0.isDisjoint(with: [.genFolk, .genHipHop]) } ?? true, "\(genre)")
    }

    /// 片假名ダークウェーブ不譯成 darkwave：譯了會在 Apple 層命中既有 gothic 列（⑦ 計劃 R1-13）
    @Test func appleDarkwaveInKatakanaDoesNotHitTheGothicRow() {
        let resolution = resolve("ダークウェーブ")
        #expect(resolution.source == .generic)
        #expect(tags(resolution) == [.genDarkwave])
    }

    @Test func mbGenresWinOverAppleInTheGenericLayer() {
        #expect(tags(resolve("ポップ", mb: .verified(["industrial"]))) == [.genIndustrial])
    }

    /// §4.2：曲庫實際出現的通用家族組合（T0，§9-1 選 a：14 種＋工業單獨），再補上每一族單獨——各自組得出、每次播放每槽都換
    static let libraryCombinations: [[String]] = [
        ["pop"], ["electronic", "experimental", "pop"], ["experimental", "industrial"], ["folk"], ["electronic", "pop"],
        ["experimental", "pop"], ["ambient", "electronic"], ["hiphop"], ["folk", "pop"], ["folk", "sacred"],
        ["darkwave", "folk", "sacred"], ["electronic", "industrial"], ["electronic"], ["darkwave"], ["industrial"],
    ]
    static let combinationsToCheck: [[String]] = SongProfileResolver.genericRows.map { [$0.id] }
        .reduce(into: libraryCombinations) { all, single in if !all.contains(single) { all.append(single) } }

    @Test(arguments: combinationsToCheck)
    func everyCombinationComposesAndChangesEverySlot(ids: [String]) throws {
        let rows = SongProfileResolver.genericRows.filter { ids.contains($0.id) }
        try #require(rows.count == ids.count, "\(ids)：有家族不存在")
        let profile = try #require(SongProfileResolver.compose(rows: rows))
        #expect(Composer.isComposable(profile), "\(ids)")
        expectReplayChangesEverySlot(profile, ids.joined(separator: "+"))
    }

    // MARK: 通用列

    @Test func eachGenericRowCarriesExactlyOneGenericTagAndNoRepresentatives() {
        for row in SongProfileResolver.genericRows {
            #expect(row.tags.count == 1 && row.tags.isSubset(of: FXTag.genericFamily), "\(row.id)")
            #expect(row.representatives.isEmpty, "\(row.id)：政策列不借代表團")
            #expect(!row.isGeneric, "\(row.id)")
        }
    }

}
