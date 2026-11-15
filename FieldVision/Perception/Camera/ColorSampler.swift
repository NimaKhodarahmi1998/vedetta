import CoreVideo
import simd

/// Keeps only the points that land inside the picture, each with its colour.
nonisolated enum ColorSampler {
    static func colors(
        for points: [SIMD3<Float>],
        in pixelBuffer: CVPixelBuffer,
        camera: CameraSnapshot
    ) -> (points: [SIMD3<Float>], colors: [SIMD3<Float>]) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 2,
              let lumaBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let chromaBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
            return ([], [])
        }
        let lumaWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let lumaHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let lumaBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let chromaWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let chromaHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        let chromaBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        let lumaPixels = lumaBase.assumingMemoryBound(to: UInt8.self)
        let chromaPixels = chromaBase.assumingMemoryBound(to: UInt8.self)

        var visiblePoints: [SIMD3<Float>] = []
        var colors: [SIMD3<Float>] = []
        visiblePoints.reserveCapacity(points.count)
        colors.reserveCapacity(points.count)
        for point in points {
            guard let pixel = camera.imagePoint(of: point) else { continue }
            let x = Int(pixel.x)
            let y = Int(pixel.y)
            guard x >= 0, y >= 0, x < lumaWidth, y < lumaHeight else { continue }
            let chromaX = min(x / 2, chromaWidth - 1)
            let chromaY = min(y / 2, chromaHeight - 1)
            let chromaOffset = chromaY * chromaBytesPerRow + chromaX * 2
            let luma = Float(lumaPixels[y * lumaBytesPerRow + x])
            let blueDifference = Float(chromaPixels[chromaOffset]) - 128
            let redDifference = Float(chromaPixels[chromaOffset + 1]) - 128
            let red = (luma + 1.402 * redDifference) / 255
            let green = (luma - 0.344136 * blueDifference - 0.714136 * redDifference) / 255
            let blue = (luma + 1.772 * blueDifference) / 255
            visiblePoints.append(point)
            colors.append(SIMD3(red.clamped(to: 0...1), green.clamped(to: 0...1), blue.clamped(to: 0...1)))
        }
        return (visiblePoints, colors)
    }
}
