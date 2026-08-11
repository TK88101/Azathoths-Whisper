// M1 AE spike（Plan §5 M1／評審 H3）：驗證 ScriptingBridge 對 Music.app 的五項關鍵操作。
// 1) 讀 playerState＋當前曲（name/artist/album/persistentID/disc/track）
// 2) 讀當前曲 lyrics
// 3) by-persistentID 定位並寫 lyrics（原值回寫＝零數據變更）
// 4) 讀 artwork raw data
// 5) album＋artist 雙條件過濾整張專輯
// 編譯：swiftc -O music_spike.swift -framework ScriptingBridge -o music_spike
import Foundation
import ScriptingBridge

@objc protocol MusicArtworkProto {
    @objc optional var rawData: NSData { get }
}

@objc protocol MusicTrackProto {
    @objc optional var name: String { get }
    @objc optional var artist: String { get }
    @objc optional var album: String { get }
    @objc optional var persistentID: String { get }
    @objc optional var lyrics: String { get }
    @objc optional var discNumber: Int { get }
    @objc optional var trackNumber: Int { get }
    @objc optional func setLyrics(_ value: String)
    @objc optional func artworks() -> SBElementArray
}

@objc protocol MusicAppProto {
    @objc optional var playerState: UInt32 { get }
    @objc optional var currentTrack: SBObject { get }
    @objc optional func tracks() -> SBElementArray
}

extension SBApplication: MusicAppProto {}
extension SBObject: MusicTrackProto, MusicArtworkProto {}

func fourCC(_ v: UInt32) -> String {
    let chars = [24, 16, 8, 0].map { Character(UnicodeScalar((v >> $0) & 0xFF)!) }
    return String(chars)
}

guard let app = SBApplication(bundleIdentifier: "com.apple.Music") else {
    print("SPIKE FAIL: SBApplication init nil"); exit(1)
}
guard app.isRunning else {
    print("SPIKE FAIL: Music not running"); exit(1)
}

// --- 1. playerState + current track ---
let state = (app as MusicAppProto).playerState ?? 0
print("1a playerState raw=\(state) fourcc=\(fourCC(state))")  // kPSP=playing kPSp=paused kPSS=stopped

guard let track = (app as MusicAppProto).currentTrack else {
    print("SPIKE PARTIAL: no currentTrack (Music stopped?) — 請在 Music 播放/暫停一首本地曲目後重跑")
    exit(2)
}
let t = track as MusicTrackProto
let name = t.name ?? "(nil)"
let artist = t.artist ?? "(nil)"
let album = t.album ?? "(nil)"
let pid = t.persistentID ?? "(nil)"
print("1b current: artist=\(artist) name=\(name) album=\(album) pid=\(pid) disc=\(t.discNumber ?? -1) trk=\(t.trackNumber ?? -1)")
if pid == "(nil)" { print("SPIKE FAIL: persistentID nil"); exit(1) }

// --- 2. read lyrics ---
let originalLyrics = t.lyrics ?? ""
print("2 lyrics length=\(originalLyrics.count) head=\(String(originalLyrics.prefix(40)).replacingOccurrences(of: "\n", with: "\\n"))")

// --- 5 (先查後寫). album+artist 雙條件過濾 ---
guard let allTracks = (app as MusicAppProto).tracks?() else {
    print("SPIKE FAIL: tracks() nil"); exit(1)
}
let pred = NSPredicate(format: "album == %@ AND artist == %@", album, artist)
let albumTracks = allTracks.filtered(using: pred)
print("5 album filter count=\(albumTracks.count)")
for (i, obj) in albumTracks.prefix(5).enumerated() {
    let tt = obj as! SBObject as MusicTrackProto
    print("   [\(i)] d\(tt.discNumber ?? -1)-t\(tt.trackNumber ?? -1) \(tt.name ?? "?") lyrics=\((tt.lyrics ?? "").isEmpty ? "no" : "yes")")
}

// --- 3. by-persistentID 定位＋原值回寫 ---
let byID = allTracks.filtered(using: NSPredicate(format: "persistentID == %@", pid))
if byID.count == 0 { print("SPIKE FAIL: persistentID filter found 0"); exit(1) }
let target = byID.first as! SBObject as MusicTrackProto
target.setLyrics?(originalLyrics)  // 原值回寫：驗證寫通道，零變更
let after = target.lyrics ?? ""
print("3 write-by-id ok=\(after == originalLyrics) (verbatim rewrite)")

// --- 4. artwork raw data ---
if let arts = t.artworks?(), arts.count > 0 {
    let artObj = arts.object(at: 0) as! SBObject
    let rawRef = artObj.value(forKey: "rawData")
    let evaluated = (rawRef as? SBObject)?.get() ?? rawRef
    if let desc = evaluated as? NSAppleEventDescriptor {
        let d = desc.data
        print("4 artwork count=\(arts.count) descType=\(fourCC(desc.descriptorType)) bytes=\(d.count) magic=\(d.prefix(4).map { String(format: "%02x", $0) }.joined())")
    } else if let nsdata = evaluated as? NSData {
        print("4 artwork count=\(arts.count) rawData bytes=\(nsdata.length)")
    } else {
        print("4 artwork: unexpected type=\(String(describing: evaluated.map { type(of: $0) }))")
    }
} else {
    print("4 artwork: none on current track（非致命——換帶封面曲目可複驗）")
}

print("SPIKE DONE")
