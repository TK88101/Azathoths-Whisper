import CoreGraphics; import Foundation; import ImageIO; import UniformTypeIdentifiers
// 底座鋁質化（CR-034 增補 B；Codex 2026-10-28 配方 A 分層亮度重映射／B 局部對比／C 支點同心車削紋／E 去色偏）：
// 只改 RGB、alpha 逐位元不動（中層點擊遮罩依 alpha 算，不受影響）。Technics r6 採 mid（使用者 2026-10-28 選）。
// 只用在交件包的整張畫布（支點 480,528）；處理後的三層放進衍生交件包、更新 delivery.json，再走 import_tonearm_skin.py。
// 編譯：swiftc -O Scripts/aluminize_skin_base.swift -o <暫存>/aluminize
// 用法：aluminize <交件包> <輸出資料夾> <參數組名 mid|strong>
let args = CommandLine.arguments
let root = args[1], out = args[2], preset = args[3]
let pivot = (480.0, 528.0)

struct Img { var w: Int; var h: Int; var r: [Float]; var g: [Float]; var b: [Float]; var a: [UInt8]; var space: CGColorSpace }
func load(_ path: String) -> Img {
  let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!; let im = CGImageSourceCreateImageAtIndex(s, 0, nil)!
  let w = im.width, h = im.height, space = CGColorSpace(name: CGColorSpace.sRGB)!
  let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.draw(im, in: CGRect(x: 0, y: 0, width: w, height: h))
  let p = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
  var img = Img(w: w, h: h, r: .init(repeating: 0, count: w*h), g: .init(repeating: 0, count: w*h), b: .init(repeating: 0, count: w*h), a: .init(repeating: 0, count: w*h), space: space)
  for i in 0..<(w*h) { let a = p[i*4+3]; img.a[i] = a; guard a > 0 else { continue }; let k = 1 / Float(a)
    img.r[i] = Float(p[i*4]) * k; img.g[i] = Float(p[i*4+1]) * k; img.b[i] = Float(p[i*4+2]) * k }
  return img
}
func save(_ img: Img, _ path: String) {
  let ctx = CGContext(data: nil, width: img.w, height: img.h, bitsPerComponent: 8, bytesPerRow: img.w * 4, space: img.space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  let p = ctx.data!.bindMemory(to: UInt8.self, capacity: img.w * img.h * 4)
  for i in 0..<(img.w*img.h) { let a = Float(img.a[i]); p[i*4+3] = img.a[i]
    p[i*4] = UInt8(min(255, max(0, img.r[i] * a + 0.5))); p[i*4+1] = UInt8(min(255, max(0, img.g[i] * a + 0.5))); p[i*4+2] = UInt8(min(255, max(0, img.b[i] * a + 0.5))) }
  let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(d, ctx.makeImage()!, nil); CGImageDestinationFinalize(d)
}
func lin(_ c: Float) -> Float { c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4) }
func srgb(_ l: Float) -> Float { let v = max(0, min(1, l)); return v <= 0.0031308 ? v * 12.92 : 1.055 * powf(v, 1 / 2.4) - 0.055 }
func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float { let t = max(0, min(1, (x - e0) / (e1 - e0))); return t * t * (3 - 2 * t) }

/// alpha 加權的高斯近似（三次 box blur）
func blur(_ v: [Float], _ wt: [Float], _ w: Int, _ h: Int, sigma: Float) -> [Float] {
  let box = Int((sqrtf(12 * sigma * sigma / 3 + 1) - 1) / 2)
  func pass(_ src: [Float]) -> [Float] {
    var tmp = src, dst = src
    for y in 0..<h { var acc: Float = 0; let row = y * w
      for x in -box...box { acc += src[row + min(max(x, 0), w - 1)] }
      for x in 0..<w { tmp[row + x] = acc / Float(2 * box + 1); acc += src[row + min(x + box + 1, w - 1)] - src[row + max(x - box, 0)] } }
    for x in 0..<w { var acc: Float = 0
      for y in -box...box { acc += tmp[min(max(y, 0), h - 1) * w + x] }
      for y in 0..<h { dst[y * w + x] = acc / Float(2 * box + 1); acc += tmp[min(y + box + 1, h - 1) * w + x] - tmp[max(y - box, 0) * w + x] } }
    return dst
  }
  var num = zip(v, wt).map(*), den = wt
  for _ in 0..<3 { num = pass(num); den = pass(den) }
  return zip(num, den).map { $1 > 1e-4 ? $0 / $1 : 0 }
}

struct Params { let anchors: [Float]; let k8: Float; let k24: Float; let hair: Float; let lambda: Float; let sat: Float }
let presets: [String: [String: Params]] = [
  "mid": ["base_middle": Params(anchors: [115, 158, 184, 210, 234], k8: 0.38, k24: 0.16, hair: 0.009, lambda: 2.2, sat: 0.3),
          "base_underlay": Params(anchors: [95, 135, 165, 195, 225], k8: 0.16, k24: 0.08, hair: 0.007, lambda: 2.2, sat: 0.3),
          "base_overlay": Params(anchors: [95, 145, 187, 220, 240], k8: 0.25, k24: 0.12, hair: 0, lambda: 2.2, sat: 0.3)],
  "strong": ["base_middle": Params(anchors: [105, 150, 176, 204, 232], k8: 0.45, k24: 0.20, hair: 0.012, lambda: 2.0, sat: 0.25),
             "base_underlay": Params(anchors: [85, 125, 155, 188, 220], k8: 0.22, k24: 0.12, hair: 0.010, lambda: 2.0, sat: 0.25),
             "base_overlay": Params(anchors: [88, 138, 182, 216, 238], k8: 0.32, k24: 0.16, hair: 0, lambda: 2.0, sat: 0.25)],
]
let middleAlpha = load("\(root)/base_middle.png").a

/// 以支點為圓心的切向同心紋：沿半徑的帶限雜訊（固定種子），RMS 正規化為 1
func concentric(maxR: Int, lambda: Float) -> [Float] {
  var seed: UInt64 = 0x1200_2026_1028
  func rnd() -> Float { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Float(seed >> 40) / Float(1 << 24) - 0.5 }
  let steps = maxR * 4 + 8
  var n = (0..<steps).map { _ in rnd() }
  let k = max(1, Int(lambda * 4 / 2))
  for _ in 0..<3 { n = n.indices.map { i in var s: Float = 0; for d in -k...k { s += n[min(max(i + d, 0), steps - 1)] }; return s / Float(2 * k + 1) } }
  let rms = sqrtf(n.map { $0 * $0 }.reduce(0, +) / Float(n.count))
  return n.map { $0 / rms }
}

for name in ["base_middle", "base_underlay", "base_overlay"] {
  let prm = presets[preset]![name]!
  var img = load("\(root)/\(name).png")
  let w = img.w, h = img.h, n = w * h
  var rl = img.r.map(lin), gl = img.g.map(lin), bl = img.b.map(lin)
  let y = (0..<n).map { 0.2126 * rl[$0] + 0.7152 * gl[$0] + 0.0722 * bl[$0] }
  // 統計只看看得見的不透明像素（下層：被中層蓋住的不算）
  var vis: [Float] = []
  for i in 0..<n where img.a[i] >= 250 && (name != "base_underlay" || middleAlpha[i] < 250) { vis.append(y[i]) }
  vis.sort()
  func q(_ f: Float) -> Float { vis[Int(Float(vis.count - 1) * f)] }
  let src = [q(0), q(0.05), q(0.25), q(0.5), q(0.75), q(0.95), q(1)]
  let t = prm.anchors.map { lin($0 / 255) }
  let dst = [min(src[0], t[0] * 0.5)] + t + [lin(min(250, prm.anchors[4] + 10) / 255)]
  func remap(_ v: Float) -> Float {
    if v <= src[0] { return v * (dst[0] / max(src[0], 1e-6)) }
    for s in 1..<src.count where v <= src[s] { let f = (v - src[s-1]) / max(src[s] - src[s-1], 1e-6); return dst[s-1] + f * (dst[s] - dst[s-1]) }
    return dst.last!
  }
  let y1 = y.map(remap)
  for i in 0..<n { let k = y1[i] / max(y[i], 0.001); rl[i] = min(1, rl[i] * k); gl[i] = min(1, gl[i] * k); bl[i] = min(1, bl[i] * k) }
  // 保護遮罩：原圖 8-bit 亮度的 5×5 局部標準差與 Sobel（字、刻度、邊緣不加對比與紋理）
  let y8 = y.map { srgb($0) * 255 }
  var m = [Float](repeating: 0, count: n)
  for yy in 2..<(h - 2) { for xx in 2..<(w - 2) { let i = yy * w + xx; guard img.a[i] >= 250 else { continue }
    var s: Float = 0, s2: Float = 0
    for dy in -2...2 { for dx in -2...2 { let v = y8[i + dy * w + dx]; s += v; s2 += v * v } }
    let sd = sqrtf(max(0, s2 / 25 - (s / 25) * (s / 25)))
    let gx = y8[i - w + 1] + 2 * y8[i + 1] + y8[i + w + 1] - y8[i - w - 1] - 2 * y8[i - 1] - y8[i + w - 1]
    let gy = y8[i + w - 1] + 2 * y8[i + w] + y8[i + w + 1] - y8[i - w - 1] - 2 * y8[i - w] - y8[i - w + 1]
    m[i] = (1 - smooth(4, 10, sd)) * (1 - smooth(6, 18, hypotf(gx, gy) / 4)) } }
  let wt = img.a.map { Float($0) / 255 }
  let b8 = blur(y1, wt, w, h, sigma: 6.5), b24 = blur(y1, wt, w, h, sigma: 20)
  let tex = prm.hair > 0 ? concentric(maxR: Int(hypot(Double(w), Double(h))), lambda: prm.lambda) : []
  for i in 0..<n where img.a[i] > 0 {
    var y2 = y1[i] + m[i] * (prm.k8 * (y1[i] - b8[i]) + prm.k24 * (y1[i] - b24[i]))
    if prm.hair > 0 {
      let r = Float(hypot(Double(i % w) - pivot.0, Double(i / w) - pivot.1)) * 4
      let i0 = min(Int(r), tex.count - 2), f = r - Float(i0)
      y2 += m[i] * prm.hair * (tex[i0] * (1 - f) + tex[i0 + 1] * f)
    }
    y2 = max(0, min(1, y2))
    let gray = y1[i]
    img.r[i] = srgb(y2 + prm.sat * (rl[i] - gray)); img.g[i] = srgb(y2 + prm.sat * (gl[i] - gray)); img.b[i] = srgb(y2 + prm.sat * (bl[i] - gray))
  }
  save(img, "\(out)/\(name).png")
}
