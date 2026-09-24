// queue_spike 自檢的負對照（計劃 §8 S0、AC9 ②）。刻意宣告四種違規，自檢必須全數抓到：
//   playpause（命令）、playOnce:（選擇器名≠命令名）、{ get set } 的隱式 setter、@objc 改名藏起 nextTrack。
// 此協議**不掛到任何 SB 類別**、從不用來送 Apple Event；靜態閘門 spike_gate.sh 只掃 queue_spike.swift，不掃本檔。
import Foundation

@objc(AZWSpikeNegativeControl) protocol SpikeNegativeControl {
    @objc optional func playpause()
    @objc optional func playOnce(_ once: Bool)
    @objc optional var shuffleEnabled: Bool { get set }
    @objc(nextTrack) optional func innocuous()
}

enum SpikeNegativeControlAnchor {
    /// 引用協議以確保它進入 ObjC runtime 的協議表
    static let protocolName: String = NSStringFromProtocol(SpikeNegativeControl.self)
}
