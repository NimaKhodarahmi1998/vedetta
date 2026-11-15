import CoreGraphics
import simd

/// Camera maths only, so no ARFrame is kept alive.
nonisolated struct CameraSnapshot {
    var transform: simd_float4x4
    var inverseTransform: simd_float4x4
    var intrinsics: simd_float3x3
    var resolution: CGSize

    init(
        transform: simd_float4x4 = matrix_identity_float4x4,
        intrinsics: simd_float3x3 = matrix_identity_float3x3,
        resolution: CGSize = CGSize(width: 1920, height: 1440)
    ) {
        self.transform = transform
        inverseTransform = transform.inverse
        self.intrinsics = intrinsics
        self.resolution = resolution
    }

    var position: SIMD3<Float> {
        SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }

    /// Pixel in the landscape sensor image, or nil behind the camera.
    func imagePoint(of point: SIMD3<Float>) -> SIMD2<Float>? {
        let cameraPoint = inverseTransform * SIMD4<Float>(point.x, point.y, point.z, 1)
        if cameraPoint.z > -0.15 { return nil }
        let x = cameraPoint.x / -cameraPoint.z
        let y = -cameraPoint.y / -cameraPoint.z
        return SIMD2(intrinsics[0][0] * x + intrinsics[2][0], intrinsics[1][1] * y + intrinsics[2][1])
    }

    /// World ray through a pixel of the landscape sensor image.
    func rayDirection(x: Float, y: Float) -> SIMD3<Float> {
        let cameraX = (x - intrinsics[2][0]) / intrinsics[0][0]
        let cameraY = (y - intrinsics[2][1]) / intrinsics[1][1]
        let direction = transform * SIMD4<Float>(cameraX, -cameraY, -1, 0)
        return simd_normalize(SIMD3(direction.x, direction.y, direction.z))
    }

    /// Inside the picture and away from its edges.
    func isInView(_ point: SIMD3<Float>, margin: Float = 0.06) -> Bool {
        guard let pixel = imagePoint(of: point) else { return false }
        let width = Float(resolution.width)
        let height = Float(resolution.height)
        return pixel.x > width * margin && pixel.x < width * (1 - margin)
            && pixel.y > height * margin && pixel.y < height * (1 - margin)
    }
}
