import Foundation
import Testing

@testable import AzathothsWhisper

// ACCEPTANCE D-03…D-09 的邏輯層
@MainActor
@Suite("SettingsViewModel")
struct SettingsViewModelTests {
    private struct StubValidator: TokenValidating {
        let result: TokenValidation
        func validate(token: String) async -> TokenValidation { result }
    }

    private final class Recorder {
        var savedToken: String?
        var savedLanguage: AppLanguage?
        var closeCount = 0
    }

    private func makeModel(
        validation: TokenValidation = .valid,
        recorder: Recorder = Recorder()
    ) -> (SettingsViewModel, Recorder) {
        let model = SettingsViewModel(
            validator: StubValidator(result: validation),
            clock: ImmediateClock(),
            onTokenSaved: { recorder.savedToken = $0 },
            onLanguageSaved: { recorder.savedLanguage = $0 },
            onClose: { recorder.closeCount += 1 }
        )
        return (model, recorder)
    }

    // D-03：標題繞過 i18n，固定英文
    @Test func titleOverridesLocalizationPerGroup() {
        let (model, _) = makeModel()
        model.open(.token, token: "", language: .system)
        #expect(model.title == "Token Settings")

        model.open(.language, token: "", language: .system)
        #expect(model.title == "Language Settings")
    }

    @Test func openPrefillsFieldsAndClearsStatus() async {
        let (model, _) = makeModel(validation: .invalid("nope"))
        model.tokenInput = ""
        await model.saveToken()
        #expect(model.tokenStatus != .none)

        model.open(.token, token: "existing", language: .ja)
        #expect(model.tokenInput == "existing")
        #expect(model.language == .ja)
        #expect(model.tokenStatus == .none)
    }

    // D-04
    @Test func emptyTokenIsRejectedWithoutCallingValidator() async {
        let (model, recorder) = makeModel()
        model.tokenInput = "   "

        await model.saveToken()

        #expect(model.tokenStatus == .failure(StatusText.tokenCannotBeEmpty))
        #expect(recorder.savedToken == nil)
    }

    // D-05 / D-06
    @Test func validTokenIsSavedThenModalCloses() async {
        let (model, recorder) = makeModel(validation: .valid)
        model.tokenInput = "  fake-token  "

        await model.saveToken()

        #expect(recorder.savedToken == "fake-token", "保存前去除前後空白")
        #expect(model.tokenStatus == .success(StatusText.tokenValidAndSaved))
        #expect(recorder.closeCount == 1, "成功後延時關閉 modal")
    }

    // D-07
    @Test func invalidTokenShowsPrefixedMessageAndKeepsModalOpen() async {
        let (model, recorder) = makeModel(validation: .invalid("HTTP 401 from Genius account API"))
        model.tokenInput = "fake-bad"

        await model.saveToken()

        #expect(model.tokenStatus == .failure("Invalid Token: HTTP 401 from Genius account API"))
        #expect(recorder.savedToken == nil)
        #expect(recorder.closeCount == 0)
    }

    // D-09
    @Test func savingLanguageStoresValueAndAsksForRestart() {
        let (model, recorder) = makeModel()
        model.open(.language, token: "", language: .system)
        model.language = .zhTW

        model.saveLanguage()

        #expect(recorder.savedLanguage == .zhTW)
        #expect(model.languageAlert == StatusText.languageSaved)

        model.dismissLanguageAlert()
        #expect(model.languageAlert == nil)
        #expect(recorder.closeCount == 1)
    }
}
