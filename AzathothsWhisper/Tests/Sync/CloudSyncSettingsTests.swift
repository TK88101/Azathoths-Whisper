import Foundation
import Testing

@testable import AzathothsWhisper

// ⑨ 計劃 §6.6、T9：Settings 的 iCloud 同步群組——英文標題（D-03）、開關切換即存、重設要確認、狀態列的純函式
@MainActor
@Suite("Cloud sync settings")
struct CloudSyncSettingsTests {
    private struct StubValidator: TokenValidating {
        func validate(token: String) async -> TokenValidation { .valid }
    }

    private final class Recorder {
        var toggles: [Bool] = []
        var resets = 0
    }

    private func makeModel(_ recorder: Recorder) -> SettingsViewModel {
        SettingsViewModel(
            validator: StubValidator(), onTokenSaved: { _ in }, onLanguageSaved: { _ in },
            onCloudSyncToggled: { recorder.toggles.append($0) },
            onCloudSyncReset: { recorder.resets += 1 },
            onClose: {}
        )
    }

    @Test func theGroupHasAnEnglishTitle() {
        let model = makeModel(Recorder())
        model.open(.cloudSync, token: "", language: .system)
        #expect(model.title == "iCloud Sync Settings")
    }

    @Test func togglingSavesImmediately() {
        let recorder = Recorder()
        let model = makeModel(recorder)
        model.open(.cloudSync, token: "", language: .system, cloudSync: CloudSyncDisplay(enabled: false))
        model.setCloudSyncEnabled(true)
        #expect(recorder.toggles == [true])
        #expect(model.cloudSync.enabled)
    }

    @Test func resettingAsksFirstAndOnlyRunsWhenConfirmed() async {
        let recorder = Recorder()
        let model = makeModel(recorder)
        model.open(.cloudSync, token: "", language: .system, cloudSync: CloudSyncDisplay(enabled: true))
        model.requestCloudSyncReset()
        #expect(model.isConfirmingCloudSyncReset)
        #expect(recorder.resets == 0)
        model.cancelCloudSyncReset()
        #expect(model.isConfirmingCloudSyncReset == false)
        model.requestCloudSyncReset()
        await model.confirmCloudSyncReset()
        #expect(recorder.resets == 1)
        #expect(model.isConfirmingCloudSyncReset == false)
    }

    @Test func statusIsUpdatedWhileTheModalIsOpen() {
        let model = makeModel(Recorder())
        model.open(.cloudSync, token: "", language: .system, cloudSync: CloudSyncDisplay(enabled: true))
        let status = CloudSyncCoordinator.Status(lastExport: Date(timeIntervalSince1970: 1_790_000_000), otherWriters: ["000000000000000b": .now])
        model.updateCloudSync(CloudSyncDisplay(enabled: true, status: status))
        #expect(model.cloudSync.otherMacs == 1)
    }

    // MARK: 狀態列（純函式）

    @Test func aNeverSyncedStateShowsNothingButTheHint() {
        #expect(CloudSyncDisplay(enabled: false).statusLines.isEmpty)
    }

    @Test func statusLinesListWhatHappened() {
        let status = CloudSyncCoordinator.Status(
            lastExport: Date(timeIntervalSince1970: 1_790_000_000), lastImport: Date(timeIntervalSince1970: 1_790_000_060),
            otherWriters: ["000000000000000b": .now, "000000000000000c": .now], skipped: 2, pendingDownloads: 1, lastError: "exportFailed"
        )
        let kinds = CloudSyncDisplay(enabled: true, status: status).statusLines.map(\.kind)
        #expect(kinds == [.lastExport, .lastImport, .otherMacs(2), .skipped(2), .pendingDownloads(1), .error("exportFailed")])
    }

    @Test func anUnavailableIdentityIsShownInsteadOfStatus() {
        let display = CloudSyncDisplay(enabled: false, unavailable: true)
        #expect(display.statusLines.map(\.kind) == [.unavailable])
    }
}
