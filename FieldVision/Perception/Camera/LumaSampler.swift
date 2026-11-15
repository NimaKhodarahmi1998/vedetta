import CoreVideo
import Foundation

/// Brightness and contrast from a cheap grid sample of the luma plane.
nonisolated enum LumaSampler {
    static func stats(of pixelBuffer: CVPixelBuffer) -> LumaStats {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 1,
              let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
            return LumaStats(mean: 120, deviation: 30)
        }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)

        var sum: Float = 0
        var sumOfSquares: Float = 0
        var sampleCount: Float = 0
        for row in 0..<18 {
            let y = (row * 2 + 1) * height / 36
            for column in 0..<24 {
                let x = (column * 2 + 1) * width / 48
                let value = Float(pixels[y * bytesPerRow + x])
                sum += value
                sumOfSquares += value * value
                sampleCount += 1
            }
        }
        let mean = sum / sampleCount
        return LumaStats(mean: mean, deviation: sqrt(max(0, sumOfSquares / sampleCount - mean * mean)))
    }
}
