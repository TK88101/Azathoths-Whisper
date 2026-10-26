import Foundation
import Testing

@testable import YogSothothsEcho

// F-V-01（S7 T9 追溯缺口）：只橫屏。XCUITest 只驗轉直時畫面不轉；這裡核 Info.plist 的宣告本身（project.yml 為真源）
struct OrientationTests {
    private let info = Bundle.main.infoDictionary ?? [:]

    @Test func iPadDeclaresOnlyTheTwoLandscapeOrientations() {
        let orientations = info["UISupportedInterfaceOrientations~ipad"] as? [String]
        #expect(Set(orientations ?? []) == ["UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"])
    }

    /// 全螢幕：不參與分割畫面與 Slide Over（否則系統可要求直式尺寸）
    @Test func requiresFullScreen() {
        #expect(info["UIRequiresFullScreen"] as? Bool == true)
    }
}
