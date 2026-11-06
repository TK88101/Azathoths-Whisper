import XCTest

// ⑨ 計劃 §6.6、T9：Settings ▸ iCloud Sync Settings...（A-07 英文、D-03 標題英文）；打開開關後，測試指定的臨時同步資料夾
// 出現這台的四個檔。不碰使用者的 iCloud；刻意不截圖（設定 modal 同一視窗另有 token 欄，見 memory）
final class CloudSyncSettingsUITests: AppUITestCase {
    private typealias Scenario = LyricsFlowUITestScenario
    private typealias ID = AccessibilityID

    private var syncRoot: URL!

    override func setUp() {
        super.setUp()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("azw-uitest-sync-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        syncRoot = base.appendingPathComponent("Azathoth's Whisper")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: syncRoot.deletingLastPathComponent())
        super.tearDown()
    }

    func testTurningSyncOnWritesThisMacsFolder() {
        var environment = Scenario.environment(.notPlaying, resetDefaults: true)
        environment[Scenario.cloudSyncRootVariable] = syncRoot.path
        launch(environment: environment)
        waitForMainUI()

        app.activate()
        app.menuBarItems["Settings"].click()
        let item = app.menuItems["iCloud Sync Settings..."]
        XCTAssertTrue(item.waitForExistence(timeout: 2), "A-07：選單寫死英文")
        item.click()
        XCTAssertTrue(app.staticTexts["ICLOUD SYNC SETTINGS"].waitForExistence(timeout: 5), "D-03：標題英文")

        let toggle = element(ID.cloudSyncToggle)
        XCTAssertTrue(waitUntilHittable(toggle))
        toggle.click()

        let deadline = Date().addingTimeInterval(15)
        var names: [String] = []
        while Date() < deadline {
            let sync = syncRoot.appendingPathComponent("Sync")
            if let writer = (try? FileManager.default.contentsOfDirectory(atPath: sync.path))?.first {
                names = ((try? FileManager.default.contentsOfDirectory(atPath: sync.appendingPathComponent(writer).path)) ?? []).sorted()
                if names.count >= 2 { break }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        // UI 測試組裝沒有 MB 與時間軸存檔，只有決定與標記兩類
        XCTAssertEqual(names, ["decisions.json", "nolyrics.json"])
    }
}
