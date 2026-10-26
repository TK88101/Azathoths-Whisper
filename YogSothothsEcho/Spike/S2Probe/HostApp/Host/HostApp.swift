import SwiftUI

// S2-P2 iOS 宿主：只為了讓測試在有 Keychain 權限的 app 程序內跑。
@main struct S2ProbeHostApp: App {
    var body: some Scene { WindowGroup { Text("S2Probe host") } }
}
