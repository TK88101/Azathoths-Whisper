import SwiftUI

struct ContentView: View {
    @State private var model = ProbeModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("YSE N5 探針").font(.largeTitle.bold())
            Text("依序按 1、2、3。結果只顯示狀態，不含任何憑證。")
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                ProbeCard(title: "1  找 Mac（Bonjour）", buttonLabel: "瀏覽 \(N5Message.serviceType)",
                          display: model.browse, bigHeadline: false) { await model.runBrowse() }
                ProbeCard(title: "2  連線收訊息（明文 TCP）", buttonLabel: "連第一個服務",
                          display: model.connect, bigHeadline: true) { await model.runConnect() }
                ProbeCard(title: "3  Keychain 寫讀刪", buttonLabel: "執行 Keychain 測試",
                          display: model.keychain, bigHeadline: false) { await model.runKeychain() }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ProbeCard: View {
    let title: String
    let buttonLabel: String
    let display: ProbeDisplay
    let bigHeadline: Bool
    let action: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Button(buttonLabel) { Task { await action() } }
                .buttonStyle(.borderedProminent)
                .disabled(display == .running)
            result
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var result: some View {
        switch display {
        case .idle:
            Text("尚未執行").foregroundStyle(.secondary)
        case .running:
            HStack { ProgressView(); Text("執行中（最長 10 秒）") }
        case .passed(let headline, let lines):
            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(bigHeadline ? .system(size: 56, weight: .bold, design: .monospaced) : .title3.bold())
                    .foregroundStyle(.green)
                ForEach(lines, id: \.self) { Text($0) }
            }
        case .failed(let headline, let lines):
            VStack(alignment: .leading, spacing: 6) {
                Text(headline).font(.title3.bold()).foregroundStyle(.red)
                ForEach(lines, id: \.self) { Text($0) }
            }
        }
    }
}
