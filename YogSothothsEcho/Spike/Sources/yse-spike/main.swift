import Foundation
import SpikeCore

// yse-spike <實驗>：S0 量測工具入口（docs/plans/2026-10-14-yse/sprint-0-detail.md §4.3）。
// 不碰 Music：selfcheck、logcheck、pumpcheck、mousecheck、n4、n4-pin、n5-listen。讀曲庫（可能跳授權框）：n3、sample-ids。
// 其餘都會操控 Music：一律經 Experiments.run（同意 YSE_CONSENT=yes、無待還原、快照落盤、結束還原）。

struct N4Record: Encodable {
    let experiment = "n4"
    let variant: String
    /// 只有 tls13-aes128gcm 一列是判定依據（§4.3 n4）；其餘列是診斷
    let isVerdictRow: Bool
    let result: N4Result
    let feasible: Bool
    let notes: [String]
}

func emit<Record: Encodable>(_ name: String, _ records: [Record]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    for record in records { print(String(decoding: try encoder.encode(record), as: UTF8.self)) }
    if ResultWriter.directory != nil {
        print("written:", try ResultWriter.save(experiment: name, records: records).path)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? ""
/// §4.5 的間隔組只有 0.5 s 與 1 s；其他值（0、負數、極大值）一律拒絕
let intervalArgument = arguments.dropFirst().first.flatMap(Double.init) ?? 0.5
guard [0.5, 1.0].contains(intervalArgument) else {
    fputs("interval 只接受 0.5 或 1\n", stderr)
    exit(64)
}
let interval = intervalArgument

Session.installInterruptHandler()

var succeeded = true
switch command {
case "selfcheck":
    // 只讀本程式的 ObjC 執行期資料，不連 Music
    for (name, audit) in MusicBridge.selfCheck().sorted(by: { $0.key < $1.key }) {
        succeeded = succeeded && audit.isExact
        print(name, audit.isExact ? "ok" : "MISMATCH missing=\(audit.missing.sorted()) extra=\(audit.extra.sorted())")
    }
case "logcheck":
    let record = try await LogCheck.run()
    succeeded = record.usable
    try emit("logcheck", [record])
case "n4":
    var records: [N4Record] = []
    for variant in N4Probe.Variant.allCases {
        let (result, notes) = await N4Probe.run(variant)
        records.append(N4Record(variant: variant.rawValue, isVerdictRow: variant == .tls13, result: result,
                                feasible: result.isFeasible, notes: notes))
    }
    try emit("n4", records)
case "n4-pin":
    // N4 診斷補充（本機迴路、不碰 Music）；由 run_n4_pin.sh 產生並清除測試憑證
    guard let directory = ProcessInfo.processInfo.environment["YSE_PIN_DIR"],
          let records = await N4PinProbe.run(directory: URL(fileURLWithPath: directory)) else {
        print("讀不到測試憑證（請用 run_n4_pin.sh 執行；需要 macOS 15 以上）")
        exit(2)
    }
    succeeded = N4PinCase.isFeasible(records.map(\.pinCase))
    try emit("n4-pin", records)
    print("此組合在本機迴路", succeeded ? "可行" : "不可行（見各列）")
case "n5-listen":
    // 不碰 Music。--self-test：只走迴路、不廣播；否則綁所有介面並廣播 Bonjour（#0-2 現場用）
    succeeded = arguments.contains("--self-test") ? await N5Listen.selfTest() : await N5Listen.run()
case "context-check":
    // 唯讀：不送任何控制指令，只確認 oracle 脈絡是否合格（§4.3.2、§6 #0-1 第 2 項）
    guard let bridge = MusicBridge.connect() else {
        print("Music 未開或自檢不過")
        exit(1)
    }
    let modes = bridge.shuffleAndRepeat().value
    let ids = MusicFileReader.queue().ids
    let current = bridge.currentTrackID().value
    let unique = ids.map { Set($0).count == $0.count } ?? false
    print("佇列 \(ids.map { "\($0.count) 首" } ?? "讀不到／非順序")；整份不重複 \(unique)；"
          + "目前曲在佇列中 \(current.map { ids?.contains($0) ?? false } ?? false)；"
          + "隨機 \(modes.shuffle.map(String.init) ?? "?")；重複關 \(modes.repeatMode == Experiments.repeatOff)")
    succeeded = (ids?.count ?? 0) >= 22 && unique && current.map { ids?.contains($0) ?? false } == true
        && modes.shuffle == false && modes.repeatMode == Experiments.repeatOff
    print(succeeded ? "合格" : "不合格")
case "pumpcheck":
    // 不碰 Music：EventPump 分派語意自檢（test_pumpcheck.py 驅動）
    succeeded = PumpCheck.run()
case "mousecheck":
    // 不碰 Music：全域左鍵監聽現場驗收，需明示同意旗標
    succeeded = MouseCheck.run(arguments: arguments)
case "n3":
    try emit("n3", [N3Probe.run()])
case "sample-ids":
    try emit("sample", [try Experiments.sampleIDs()])
case "relay-load":
    // 只該由 Experiments.run 以子程序啟動（同意與配額都由父程序處理）；單獨執行時同樣要求同意
    guard ProcessInfo.processInfo.environment["YSE_CONSENT"] == "yes" else {
        print("未取得使用者同意；不送任何指令")
        exit(1)
    }
    let maxSeeks = min(arguments.dropFirst(2).first.flatMap(Int.init) ?? 0, RelayLoad.seekQuota)
    await RelayLoad.run(interval: interval, maxSeeks: maxSeeks)
case "recover":
    guard let snapshot = Recovery.pendingSnapshot(), let bridge = MusicBridge.connect() else {
        print("沒有待還原的快照，或 Music 未開")
        break
    }
    let check = await Session(bridge: bridge, experiment: .restore, restoring: snapshot).restore()
    succeeded = check?.unrestored.isEmpty == true
    print("還原：", check.map { "未還原 \($0.unrestored)" } ?? "失敗")
case "b1", "b5-play":
    guard let ids: [String] = Recovery.latestRecord(prefix: "sample-"), !ids.isEmpty else {
        print("先執行 sample-ids")
        exit(2)
    }
    succeeded = command == "b1" ? await Experiments.b1(ids: ids) : await Experiments.b5Play(ids: ids, interval: interval)
case "b2": succeeded = await Experiments.b2()
case "b3": succeeded = await Experiments.b3()
case "b4": succeeded = await Experiments.b4(interval: interval, useMouse: !arguments.contains("--enter"))
case "b5": succeeded = await Experiments.b5(interval: interval)
case "b6-baseline": succeeded = await Experiments.b6(interval: nil)
case "b6": succeeded = await Experiments.b6(interval: interval)
case "n1": succeeded = await Experiments.n1()
case "n1-library": succeeded = await Experiments.n1Library()
case "fp01-catalog":
    // 唯讀（ITLibrary）：樣本母體的數量與分層，只印數字
    let catalog = try Experiments.albumCatalog()
    let plan = Experiments.fp01Samples(catalog.albums, count: FP01Verdict.requiredSamples)
    print("可用專輯 \(catalog.albums.count)、排除 \(catalog.excluded.sorted { $0.key < $1.key })、多 disc \(catalog.albums.filter(\.multiDisc).count)、"
          + "閘門拒絕 \(Experiments.refusalCounts(catalog.albums).sorted { $0.key < $1.key })、資料庫清單 \(catalog.libraryID == nil ? "無" : "有")")
    print("樣本 \(plan.count) 張（皆閘門放行）：多 disc \(plan.filter(\.album.multiDisc).count)")
case "fp01-preflight", "fp01":
    // 捷徑名稱由使用者在場建立後提供；不帶就不跑
    guard let name = arguments.dropFirst().first, !name.isEmpty else {
        fputs("需要捷徑名稱：yse-spike \(command) <捷徑名稱>\n", stderr)
        exit(64)
    }
    succeeded = command == "fp01" ? await Experiments.fp01(shortcut: name) : await Experiments.fp01Preflight(shortcut: name)
case "n2": succeeded = await Experiments.n2()
default:
    fputs("usage: yse-spike selfcheck|logcheck|pumpcheck|mousecheck --consent-click-monitor|n3|n4|n4-pin|n5-listen [--self-test]|sample-ids|recover|b1|b2|b3|b4 <s> [--enter]|b5 <s>|b5-play <s>|b6-baseline|b6 <s>|n1|n1-library|n2|fp01-catalog|fp01-preflight <捷徑>|fp01 <捷徑>\n", stderr)
    exit(64)
}
exit(succeeded ? 0 : 1)
