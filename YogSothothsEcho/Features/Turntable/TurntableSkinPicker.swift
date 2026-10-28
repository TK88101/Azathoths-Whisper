import SwiftUI

/// 唱機外觀選擇器（CR-034 增補 A §4.4）：設定頁（push 進來）與唱機浮層（popover，唱機在背後即時換）共用這一個。
/// 縮圖網格（直放）；名稱與順序來自註冊表、預覽由各皮膚圖層合成；點了立即套用；唱機轉場中格子停用並說明
struct TurntableSkinPicker: View {
    let model: TurntableViewModel

    static let artSize = CGSize(width: 96, height: 150)
    static let tileMinimumWidth: CGFloat = 120
    static let spacing: CGFloat = 14
    /// 三格一列的寬度（popover 用）
    static let threeColumnWidth = tileMinimumWidth * 3 + spacing * 2

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 說明只講「轉場中」；可不可點另看 canSelectSkin（只剩一款時也不可點，但不是因為轉場）
            let blocked = model.skinApplyBlock != nil
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tileMinimumWidth), spacing: Self.spacing)], spacing: Self.spacing) {
                ForEach(model.availableSkins, id: \.spec.id) { tile($0, blocked: blocked) }
            }
            if blocked { Text(blockedNote).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    /// 格子停用時的說明（畫面與 VoiceOver 提示共用）
    private var blockedNote: LocalizedStringKey { "Skins can be changed once the turntable settles." }

    private func tile(_ skin: ResolvedTurntableSkin, blocked: Bool) -> some View {
        let selected = model.skin == skin
        return Button {
            model.selectSkin(skin.spec.id)
        } label: {
            VStack(spacing: 6) {
                SkinPreviewImage(previews: model.previews, skin: skin, crop: .wholeArm, size: Self.artSize)
                SkinTitle(skin: skin).font(.subheadline).lineLimit(1)
            }
            // 停用時只淡內容，選中框照留（m-7）
            .opacity(blocked ? 0.4 : 1)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(SkinTileBackground())
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
            .overlay(alignment: .topTrailing) {
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor).padding(6) }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!model.canSelectSkin)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(blocked ? Text(blockedNote) : Text(verbatim: ""))
        .accessibilityIdentifier(AccessibilityID.turntableSkin(skin.spec.id))
    }
}

/// 格子底：三款同一個中性底（比面板亮一階）＋1 px 淡邊，不為單款加亮（m-5）。深色下夠亮，黑色唱臂也看得清
struct SkinTileBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(colorScheme == .dark ? Color(white: 0.34) : Color.white)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

/// 一張預覽：依畫面像素向共用 renderer 要圖；換尺寸時先用舊的一張；預覽失敗＝中性符號（皮膚仍可選，r1-3）
struct SkinPreviewImage: View {
    let previews: SkinPreviewRenderer
    let skin: ResolvedTurntableSkin
    let crop: SkinPreviewCrop
    let size: CGSize
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let pixels = CGSize(width: (size.width * displayScale).rounded(), height: (size.height * displayScale).rounded())
        Group {
            if let image = previews.image(for: skin, crop: crop, pixelSize: pixels) {
                Image(decorative: image, scale: displayScale).resizable().scaledToFit()
            } else if previews.isUnavailable(skin.spec.id) {
                Image(systemName: "circle.circle").font(.title).foregroundStyle(.secondary)
            } else {
                Color.clear
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: SkinPreviewRenderer.Key(skin, crop, pixels)) {
            await previews.load(skin, crop: crop, pixelSize: pixels)
        }
    }
}

/// 皮膚名稱（註冊表）；不在表上的皮膚顯示 id 原文
struct SkinTitle: View {
    let skin: ResolvedTurntableSkin

    var body: some View {
        if let title = skin.title { Text(title) } else { Text(verbatim: skin.spec.id) }
    }
}
