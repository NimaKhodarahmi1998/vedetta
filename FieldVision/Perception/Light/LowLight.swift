import CoreImage
import CoreVideo
import Foundation
import simd

/// Dim light and darkness.
///
/// In dim light the camera picture is dark and noisy, and both models (people/vehicles, depth) lose what they
/// would see in daylight. Here they get a brightened, de-noised copy of the picture instead, with exactly the same
/// geometry, so nothing downstream changes. In daylight they keep getting the raw picture, untouched.
/// The floor reader also gets its own band of the picture from here (the floor, from the horizon down).
///
/// What stays on the raw picture: the map colours, the self-check (TrustMonitor) and the torch.
nonisolated final class LowLight: @unchecked Sendable {
    /// The models get the brightened copy below this picture brightness (luma 0-255), the raw one again above `offAbove`.
    static let onBelow: Float = 70
    static let offAbove: Float = 85
    /// Where the brightened copy is aimed.
    static let target: Float = 110

    private(set) var active = false
    /// 1 = raw picture.
    private(set) var gain: Float = 1

    private let ctx = CIContext(options: [.cacheIntermediates: false])
    private let lock = NSLock()
    private var pools: [String: CVPixelBufferPool] = [:]

    /// Call with the raw picture's mean luma (AR queue).
    func update(lumaMean: Float) {
        if active { if lumaMean > LowLight.offAbove { active = false } }
        else if lumaMean < LowLight.onBelow { active = true }
        gain = active ? max(1, min(6, LowLight.target / max(4, lumaMean))) : 1
    }

    func reset() { active = false; gain = 1 }

    /// The whole picture, brightened, in the camera's own landscape orientation and 4:3 shape (960 x 720):
    /// the models see the same geometry as with the raw picture. nil if it couldn't be made (then use the raw one).
    func brightened(_ pb: CVPixelBuffer, gain: Float) -> CVPixelBuffer? {
        let w = 960, h = 720
        guard let out = buffer(w, h) else { return nil }
        let src = CIImage(cvPixelBuffer: pb)
        let scaled = src.clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: CGFloat(w) / src.extent.width, y: CGFloat(h) / src.extent.height))
            .cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.render(enhance(scaled, gain: gain), to: out, bounds: CGRect(x: 0, y: 0, width: w, height: h),
                   colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return out
    }

    /// The floor reader's band of the upright (portrait) picture: rows y0 ... y0 + h (normalized, from the top),
    /// full width, at the depth model's size (w x h pixels), upright. Brightened if gain > 1.
    func band(_ pb: CVPixelBuffer, band b: DepthBand, gain: Float, w: Int, h: Int) -> CVPixelBuffer? {
        guard let out = buffer(w, h) else { return nil }
        let up = CIImage(cvPixelBuffer: pb).oriented(.right)                    // upright, origin bottom-left
        let E = up.extent
        // upright rows from the top [y0, y0 + h]  ->  Core Image y from the bottom [1 - y0 - h, 1 - y0]
        let crop = CGRect(x: E.minX, y: E.minY + CGFloat(1 - b.y0 - b.h) * E.height,
                          width: E.width, height: CGFloat(b.h) * E.height)
        var img = up.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        let sy = CGFloat(h) / crop.height, sx = CGFloat(w) / crop.width
        img = img.clampedToExtent().applyingFilter("CILanczosScaleTransform",
                                                   parameters: [kCIInputScaleKey: sy, kCIInputAspectRatioKey: sx / sy])
            .cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
        if gain > 1.01 { img = enhance(img, gain: gain) }
        ctx.render(img, to: out, bounds: CGRect(x: 0, y: 0, width: w, height: h), colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return out
    }

    /// Brighter (exposure), shadows lifted a little (gamma), and de-noised when the gain is high.
    /// `gain` is meant on the picture's brightness (luma); exposure works on linear light, about 2 stops per doubling.
    private func enhance(_ img: CIImage, gain: Float) -> CIImage {
        guard gain > 1.01 else { return img }
        var x = img.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 2 * log2(gain)])
        x = x.applyingFilter("CIGammaAdjust", parameters: ["inputPower": 0.85])
        if gain > 2 {
            x = x.applyingFilter("CINoiseReduction", parameters: ["inputNoiseLevel": 0.02 + 0.01 * (gain - 2), "inputSharpness": 0.4])
        }
        return x
    }

    private func buffer(_ w: Int, _ h: Int) -> CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        let key = "\(w)x\(h)"
        if pools[key] == nil {
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: w,
                kCVPixelBufferHeightKey as String: h,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ]
            var pool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, [kCVPixelBufferPoolMinimumBufferCountKey as String: 3] as CFDictionary, attrs as CFDictionary, &pool)
            pools[key] = pool
        }
        guard let pool = pools[key] else { return nil }
        var out: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
        return out
    }
}

/// Reads the raw picture's brightness at sensor pixels: in the dark, only what is lit (by the torch or a street
/// lamp) is trusted. Locks the luma plane from init until close().
nonisolated final class LitSampler: @unchecked Sendable {
    private let pb: CVPixelBuffer
    private let base: UnsafePointer<UInt8>?
    private let w: Int, h: Int, bpr: Int

    /// Mean luma (0-255) a spot needs to count as lit.
    static let litLuma: Float = 22

    init(_ pb: CVPixelBuffer) {
        self.pb = pb
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        if CVPixelBufferGetPlaneCount(pb) >= 1, let b = CVPixelBufferGetBaseAddressOfPlane(pb, 0) {
            base = UnsafePointer(b.assumingMemoryBound(to: UInt8.self))
            w = CVPixelBufferGetWidthOfPlane(pb, 0); h = CVPixelBufferGetHeightOfPlane(pb, 0)
            bpr = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        } else {
            base = nil; w = 0; h = 0; bpr = 0
        }
    }

    func close() { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

    /// Mean luma of a 3 x 3 patch around a sensor pixel (the plane is the sensor picture: x = u, y = v).
    func luma(_ uv: SIMD2<Float>) -> Float {
        guard let p = base else { return 255 }
        let x = min(w - 2, max(1, Int(uv.x))), y = min(h - 2, max(1, Int(uv.y)))
        var s = 0
        for dy in -1...1 { for dx in -1...1 { s += Int(p[(y + dy) * bpr + x + dx]) } }
        return Float(s) / 9
    }

    func lit(_ uv: SIMD2<Float>) -> Bool { luma(uv) >= LitSampler.litLuma }

    /// Mean luma inside a box of the upright picture (Vision coordinates: normalized, origin bottom-left).
    func boxLuma(_ box: CGRect, sensorW sw: Float, sensorH sh: Float) -> Float {
        var s: Float = 0
        var n: Float = 0
        for i in 0..<6 {
            for j in 0..<6 {
                let xu = Float(box.minX) + (Float(i) + 0.5) / 6 * Float(box.width)
                let yuTop = 1 - (Float(box.minY) + (Float(j) + 0.5) / 6 * Float(box.height))
                s += luma(SIMD2(yuTop * sw, (1 - xu) * sh)); n += 1
            }
        }
        return s / max(1, n)
    }
}
