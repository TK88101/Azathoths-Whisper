import Foundation

extension Duration {
    /// 換成秒（Double）。時鐘外推與量測共用這一份換算
    var inSeconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
