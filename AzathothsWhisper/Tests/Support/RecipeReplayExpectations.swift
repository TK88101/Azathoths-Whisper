import Testing

@testable import AzathothsWhisper

/// 「每次播放都換一套」的唯一定義（⑦ simcodex：原本三處各寫一份）：相鄰配對——每個 seed 先組一次，再以 seed+1 避開它組下一次，
/// font、backdrop、enter、exit、fx1、palette 六欄都要換。fx2 不在要求內：`Composer` 不避開上一份的 fx2
func expectReplayChangesEverySlot(_ profile: SongProfile, _ label: String, seeds: Range<UInt64> = 0..<256, sourceLocation: SourceLocation = #_sourceLocation) {
    for seed in seeds {
        guard case .composed(let first) = Composer.compose(profile: profile, seed: seed),
              case .composed(let next) = Composer.compose(profile: profile, seed: seed &+ 1, avoiding: first) else {
            Issue.record("\(label) seed \(seed)：應有組合配方", sourceLocation: sourceLocation)
            continue
        }
        #expect(next.font != first.font && next.backdrop != first.backdrop && next.enter != first.enter, "\(label) seed \(seed)", sourceLocation: sourceLocation)
        #expect(next.exit != first.exit && next.fx1 != first.fx1 && next.palette != first.palette, "\(label) seed \(seed)", sourceLocation: sourceLocation)
    }
}
