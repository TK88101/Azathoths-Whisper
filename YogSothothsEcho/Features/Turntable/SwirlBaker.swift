import CoreGraphics
import Foundation
import Metal
import MetalPerformanceShaders

/// 烘好的盤面（M1：底色＋花紋已上色、premultiplied RGBA8）。CGImage 建好後不可變，跨隔離傳遞安全；
/// 相等＝同一張圖（快取狀態比較用）
struct SwirlFace: @unchecked Sendable, Equatable {
    let image: CGImage
    var byteCount: Int { image.byteCost }

    static func == (a: SwirlFace, b: SwirlFace) -> Bool { a.image === b.image }
}

/// SWIRL 系列的盤面烘焙器（CR-037 §4.4；S0 選定 Metal compute）：每首歌烘一次，播放時只旋轉圖片。
/// Metal 物件只在這個 actor 內使用
actor SwirlBaker {
    enum Failure: Error, Equatable {
        case unavailable
        case encodingFailed
    }

    /// 與 SwirlFace.metal 的 FaceParams 欄位順序一致（12 個 float＋4 個 float4）
    private struct Params {
        var seed: Float, type: Float, body: Float, water: Float, opacity: Float, hasGradient: Float, hasAccent: Float, side: Float
        var depthFloor: Float, waterGain: Float, pad0: Float = 0, pad1: Float = 0
        var base: SIMD4<Float>, base2: SIMD4<Float>, ink: SIMD4<Float>, accent: SIMD4<Float>
    }

    /// 小樣烘完再模糊的半徑（以小樣 472 px 盤徑為準，依實際邊長換算）
    static let previewDiameter: Float = 472
    static func blurPixels(_ subtype: SwirlSubtype) -> Float {
        switch subtype {
        case .smokeWater: 0.5
        case .smoke: 0.6
        case .chunk: 0.6
        case .pull, .flake: 0
        }
    }

    /// 煙渦濃淡起伏的最淡倍率：深／淺／強調墨拉高到 0.6 不虛（v0.8 使用者實機回饋）；水感維持小樣定案 0.3
    static func depthFloor(_ subtype: SwirlSubtype) -> Float { subtype == .smoke ? 0.6 : 0.3 }

    /// 水感邊線強度（v0.8 使用者選 A：加強水線）；其他型沒有水線
    static func waterGain(_ subtype: SwirlSubtype) -> Float { subtype == .smokeWater ? 0.7 : 0 }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState

    init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws(Failure) {
        guard let device, let queue = device.makeCommandQueue(),
              let function = (try? device.makeDefaultLibrary(bundle: Bundle(for: SwirlBundleToken.self)))?.makeFunction(name: "swirlFaceKernel"),
              let pipeline = try? device.makeComputePipelineState(function: function) else { throw .unavailable }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
    }

    func bake(_ recipe: SwirlRecipe, colors: SwirlColors, side: Int) throws(Failure) -> SwirlFace {
        var params = Self.params(recipe, colors: colors, side: side)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: side, height: side, mipmapped: false)
        descriptor.usage = [.shaderWrite, .shaderRead]
        guard let face = device.makeTexture(descriptor: descriptor), let command = queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else { throw .encodingFailed }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(face, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
        let group = MTLSize(width: 16, height: 16, depth: 1)
        encoder.dispatchThreadgroups(MTLSize(width: (side + 15) / 16, height: (side + 15) / 16, depth: 1), threadsPerThreadgroup: group)
        encoder.endEncoding()
        var output = face
        let blur = Self.blurPixels(recipe.subtype) * Float(side) / Self.previewDiameter
        if blur > 0 {
            guard let blurred = device.makeTexture(descriptor: descriptor) else { throw .encodingFailed }
            MPSImageGaussianBlur(device: device, sigma: blur).encode(commandBuffer: command, sourceTexture: face, destinationTexture: blurred)
            output = blurred
        }
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed, let image = Self.image(from: output, side: side) else { throw .encodingFailed }
        return SwirlFace(image: image)
    }

    private static func image(from texture: MTLTexture, side: Int) -> CGImage? {
        let bytesPerRow = side * 4
        // 讀回直接寫進 Data（一次配置、一次複製）
        var data = Data(count: bytesPerRow * side)
        data.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            texture.getBytes(base, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0)
        }
        guard let provider = CGDataProvider(data: data as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    private static func params(_ recipe: SwirlRecipe, colors: SwirlColors, side: Int) -> Params {
        func vector(_ c: RGBColor) -> SIMD4<Float> { SIMD4(Float(c.r), Float(c.g), Float(c.b), 1) }
        let type: Float = switch recipe.subtype {
        case .smokeWater, .smoke: 0
        case .pull: 1
        case .flake: 2
        case .chunk: 3
        }
        let (base, base2, hasGradient): (RGBColor, RGBColor, Float) = switch colors.base {
        case .solid(let c): (c, c, 0)
        case .gradient(let a, let b): (a, b, 1)
        }
        return Params(seed: Float(recipe.noiseSeed), type: type, body: Float(recipe.body), water: recipe.subtype == .smokeWater ? 1 : 0,
                      opacity: Float(colors.opacity), hasGradient: hasGradient, hasAccent: colors.accent == nil ? 0 : 1, side: Float(side),
                      depthFloor: Self.depthFloor(recipe.subtype), waterGain: Self.waterGain(recipe.subtype),
                      base: vector(base), base2: vector(base2), ink: vector(colors.ink), accent: vector(colors.accent ?? .black))
    }
}

private final class SwirlBundleToken {}
