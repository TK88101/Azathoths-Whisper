import AppKit
import SwiftUI

// About modal（py:296-331）：全 app 唯一圓角區（rounded-2xl / lg / full）
struct AboutModalView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            logo
                .frame(width: 128, height: 128)
                .padding(.bottom, 24)

            Text(verbatim: AppInfo.title)
                .font(Theme.Fonts.display(24, weight: .bold))
                .textCase(.uppercase)
                .tracking(2.4)
                .foregroundStyle(.white)
                .textGlow()
                .padding(.bottom, 4)

            Text(verbatim: AppInfo.aboutVersionLine(version: AppInfo.version, build: AppInfo.build))
                .font(Theme.Fonts.display(10))
                .textCase(.uppercase)
                .tracking(2)
                .foregroundStyle(Theme.Gray.g600)
                .padding(.bottom, 32)

            createdByCard
                .padding(.bottom, 16)

            VStack(spacing: 12) {
                linkRow(label: "Email", value: AppInfo.email, url: URL(string: "mailto:\(AppInfo.email)"))
                linkRow(label: "GitHub", value: AppInfo.repository, url: AppInfo.repositoryURL)
            }

            closeButton
                .padding(.top, 32)
        }
        .padding(32)
        .frame(width: 512)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))          // rounded-2xl
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.Gray.g800, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                MaterialSymbol(.close, size: 24)
                    .foregroundStyle(Theme.Gray.g500)
            }
            .buttonStyle(.plain)
            .padding(16)
        }
    }

    private var logo: some View {
        Group {
            if let image = BundleAssets.aboutLogo {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                HexagonLogo()
            }
        }
    }

    private var createdByCard: some View {
        VStack(spacing: 4) {
            Text(verbatim: "Created By")
                .font(Theme.Fonts.display(10))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Theme.Gray.g600)
            Text(verbatim: AppInfo.author)
                .font(Theme.Fonts.mono(14, weight: .bold))
                .tracking(0.35)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.black.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))           // rounded-lg
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.Gray.g800.opacity(0.5), lineWidth: 1))
    }

    private func linkRow(label: String, value: String, url: URL?) -> some View {
        Button {
            if let url { NSWorkspace.shared.open(url) }
        } label: {
            HStack {
                Text(verbatim: label)
                    .font(Theme.Fonts.display(10))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(Theme.Gray.g600)
                Spacer()
                Text(verbatim: value)
                    .font(Theme.Fonts.mono(14))
                    .foregroundStyle(Theme.link)
            }
            .padding(12)
            .contentShape(Rectangle())
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.Gray.g800.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Text(verbatim: "Close")
                .font(Theme.Fonts.display(12, weight: .bold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(.black)
                .padding(.horizontal, 40)
                .padding(.vertical, 12)
                .background(Color.white)
                .clipShape(Capsule())                          // rounded-full
        }
        .buttonStyle(.plain)
    }
}
