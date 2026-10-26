import SwiftUI
import Testing
import UIKit
@testable import YogSothothsEcho

// S6.5 T1（s6-5-pairing-redesign.md §5）：Space Grotesk 隨 App 打包並已註冊；未註冊時 SwiftUI 會靜默退回系統字
@MainActor
struct PairingStyleTests {
    @Test func spaceGroteskIsRegistered() {
        #expect(UIFont(name: "SpaceGrotesk-Light", size: 12) != nil)
        #expect(UIFont.familyNames.contains("Space Grotesk"))
    }
}

// S6.5 T4（§4.2 對比）：左欄文字疊在漸層上；7 組背景 × 深淺 × 兩種尺寸，左欄每個取樣點都要達 WCAG AA
@MainActor
struct PairingContrastTests {
    static let sizes = [CGSize(width: 1376, height: 1032), CGSize(width: 1133, height: 744)]

    @Test(arguments: BackgroundPreset.allCases, [false, true])
    func leftColumnTextMeetsAA(preset: BackgroundPreset, dark: Bool) {
        let scheme: ColorScheme = dark ? .dark : .light
        for size in Self.sizes {
            for reduceTransparency in [false, true] {
                let treatment = PairingStyle.computeTreatment(preset: preset, scheme: scheme, size: size, reduceTransparency: reduceTransparency)
                #expect(treatment.scrim < PairingStyle.maxScrim, "\(preset) \(scheme) RT=\(reduceTransparency) 遮罩到上限仍不夠")
                let palette = PairingStyle.palette(treatment.ink)
                let failing = PairingStyle.leftColumnSamples(size: size).filter { point in
                    !PairingStyle.passes(palette, on: PairingStyle.backdrop(preset: preset, scheme: scheme, at: point, size: size,
                                                                            reduceTransparency: reduceTransparency, treatment: treatment))
                }
                #expect(failing.isEmpty, "\(preset) \(scheme) RT=\(reduceTransparency) \(size) 未達標 \(failing.count) 點")
            }
        }
    }

    /// 深色主題的漸層夠暗：白字不需遮罩
    @Test(arguments: BackgroundPreset.allCases)
    func darkSchemeNeedsNoScrim(preset: BackgroundPreset) {
        let t = PairingStyle.computeTreatment(preset: preset, scheme: .dark, size: CGSize(width: 1376, height: 1032), reduceTransparency: false)
        #expect(t == PairingStyle.Treatment(ink: .white, scrim: 0))
    }

    @Test func ctaWhiteTextMeetsAA() {
        #expect(AlbumPalette.contrast(.white, PairingStyle.cta) >= 4.5)
    }

    /// body 每次重算都會呼叫：同一組輸入只算一次（尺寸差不到 1 pt 也命中）
    @Test func treatmentIsMemoized() {
        let size = CGSize(width: 1234, height: 777)
        let before = PairingStyle.computeCount
        let first = PairingStyle.treatment(preset: .aurora, scheme: .light, size: size, reduceTransparency: false)
        let again = PairingStyle.treatment(preset: .aurora, scheme: .light, size: CGSize(width: 1234.2, height: 776.9), reduceTransparency: false)
        #expect(again == first)
        #expect(PairingStyle.computeCount == before + 1)
        _ = PairingStyle.treatment(preset: .aurora, scheme: .light, size: size, reduceTransparency: true)
        #expect(PairingStyle.computeCount == before + 2, "減少透明度是另一組輸入")
    }
}
