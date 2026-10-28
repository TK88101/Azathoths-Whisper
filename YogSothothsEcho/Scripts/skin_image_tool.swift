// 唱臂皮膚匯入的影像部分（yse-1.0.1-skins.md §4.2）：只做需要解碼的兩件事，規則與檢查在 import_tonearm_skin.py。
// 由 import_tonearm_skin.py 以 swiftc -O 編譯後呼叫（ImageIO＋CoreGraphics，不需額外套件）。
//   analyze <file>...                  所有檔 alpha>0 的聯集：印 JSON {"bbox":[x0,y0,x1,y1]|null,"rows":[[min,max]|null…]}
//   crop <x> <y> <w> <h> <in> <out>    原像素裁切（不重繪：保留色彩空間與 straight alpha）寫成 PNG
//   runs <file> <alpha>                逐像素列 alpha≥門檻的不重疊半開區間：印 JSON [[[x0,x1],…],…]（中層點擊遮罩，增補 B §4.2）
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ToolError: Error, CustomStringConvertible {
    let description: String
}

func load(_ path: String) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ToolError(description: "\(path)：解不開") }
    return image
}

/// 整張圖的 alpha（逐列、每像素一個位元組）
func alphaPlane(_ image: CGImage) throws -> [[UInt8]] {
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drawn else { throw ToolError(description: "建立點陣失敗") }
    return (0..<height).map { y in (0..<width).map { x in pixels[(y * width + x) * 4 + 3] } }
}

/// 每列 alpha>0 的最左／最右 x（沒有則 nil）
func alphaRows(_ image: CGImage) throws -> [(Int, Int)?] {
    try alphaPlane(image).map { row in
        guard let lo = row.firstIndex(where: { $0 > 0 }), let hi = row.lastIndex(where: { $0 > 0 }) else { return nil }
        return (lo, hi)
    }
}

/// 每列 alpha ≥ threshold 的連續區段（半開 [x0, x1)）
func runs(_ path: String, threshold: UInt8) throws -> String {
    let rows: [[[Int]]] = try alphaPlane(load(path)).map { row in
        var result: [[Int]] = [], start: Int?
        for (x, alpha) in row.enumerated() {
            if alpha >= threshold, start == nil { start = x }
            if alpha < threshold, let begin = start { result.append([begin, x]); start = nil }
        }
        if let begin = start { result.append([begin, row.count]) }
        return result
    }
    return String(decoding: try JSONSerialization.data(withJSONObject: rows), as: UTF8.self)
}

func analyze(_ paths: [String]) throws -> String {
    guard !paths.isEmpty else { throw ToolError(description: "analyze：沒有檔案") }
    var size: (Int, Int)?
    var union: [(Int, Int)?] = []
    for path in paths {
        let image = try load(path)
        if let size, size != (image.width, image.height) { throw ToolError(description: "\(path)：尺寸與同層其他檔不同") }
        size = (image.width, image.height)
        let rows = try alphaRows(image)
        union = union.isEmpty ? rows : zip(union, rows).map { a, b in
            switch (a, b) {
            case let (a?, b?): (min(a.0, b.0), max(a.1, b.1))
            case let (a?, nil): a
            case let (nil, b): b
            }
        }
    }
    let filled = union.enumerated().compactMap { y, row in row.map { (y, $0) } }
    let bbox: Any = filled.isEmpty ? NSNull() : [filled.map { $0.1.0 }.min()!, filled.first!.0, filled.map { $0.1.1 }.max()!, filled.last!.0]
    let rows: [Any] = union.map { row -> Any in
        guard let row else { return NSNull() }
        return [row.0, row.1]
    }
    let object: [String: Any] = ["bbox": bbox, "rows": rows]
    return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}

func crop(_ rect: CGRect, from input: String, to output: String) throws {
    guard let cropped = try load(input).cropping(to: rect), cropped.width == Int(rect.width), cropped.height == Int(rect.height) else {
        throw ToolError(description: "\(input)：裁切框 \(rect) 超出畫布")
    }
    guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw ToolError(description: "\(output)：無法建立")
    }
    CGImageDestinationAddImage(destination, cropped, nil)
    guard CGImageDestinationFinalize(destination) else { throw ToolError(description: "\(output)：寫入失敗") }
}

func main(_ args: [String]) throws {
    switch args.first {
    case "analyze":
        print(try analyze(Array(args.dropFirst())))
    case "crop" where args.count == 7:
        let n = try args[1...4].map { value -> Int in
            guard let number = Int(value), number >= 0 else { throw ToolError(description: "crop：\(value) 不是非負整數") }
            return number
        }
        try crop(CGRect(x: n[0], y: n[1], width: n[2], height: n[3]), from: args[5], to: args[6])
    case "runs" where args.count == 3:
        guard let threshold = UInt8(args[2]), threshold > 0 else { throw ToolError(description: "runs：門檻必須是 1…255") }
        print(try runs(args[1], threshold: threshold))
    default:
        throw ToolError(description: "用法：analyze <file>… | crop <x> <y> <w> <h> <in> <out> | runs <file> <alpha>")
    }
}

do {
    try main(Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
