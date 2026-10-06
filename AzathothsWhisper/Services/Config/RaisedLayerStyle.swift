import Foundation

/// 升起層畫什麼（母計劃 §2.1；A2 計劃 §3.1）。與升降（`LyricsSurface`）正交，不進 reducer
enum RaisedLayerStyle: String, Sendable, CaseIterable {
    case coverFlow
    case lyricsFX
}
