import CoreVideo
import simd

nonisolated extension GuidancePipeline {
    /// Colours each feature point from the camera picture, then merges it into the map.
    func addFeaturePoints(_ featurePoints: [SIMD3<Float>], from pixelBuffer: CVPixelBuffer, camera: CameraSnapshot, time: Double) {
        let range: Float = torch.isOn ? Self.nearRange + 1 : 30
        let nearby = featurePoints.filter { simd_distance($0, walker.position) < range }
        let sampled = ColorSampler.colors(for: nearby, in: pixelBuffer, camera: camera)
        map.add(sampled.points, colors: sampled.colors, time: time)
    }

    func requestDepth(in pixelBuffer: CVPixelBuffer, prepare: (@Sendable (CVPixelBuffer) -> CVPixelBuffer?)?,
                      camera: CameraSnapshot, featurePoints: [SIMD3<Float>], time: Double) {
        isDepthBusy = true
        lastDepthTime = time
        nonisolated(unsafe) let picture = pixelBuffer
        depthEstimator.estimate(pixelBuffer, prepare: prepare) { [weak self] relativeDepth, milliseconds in
            guard let self else { return }
            queue.async {
                self.handleDepth(relativeDepth, milliseconds: milliseconds, picture: picture, camera: camera, featurePoints: featurePoints, time: time)
            }
        }
    }

    /// Depth Anything V2 is relative: this frame's feature points give it metres, then a pixel grid becomes 3D splats.
    private func handleDepth(_ relativeDepth: [Float]?, milliseconds: Double, picture: CVPixelBuffer, camera: CameraSnapshot, featurePoints: [SIMD3<Float>], time: Double) {
        isDepthBusy = false
        guard let relativeDepth else { return }
        depthMilliseconds = milliseconds
        depthsInWindow += 1
        let modelWidth = DepthEstimator.modelWidth
        let modelHeight = DepthEstimator.modelHeight
        let band = DepthEstimator.croppedBand(for: camera.resolution)
        let sensorWidth = Float(camera.resolution.width)
        let sensorHeight = Float(camera.resolution.height)

        var pairs: [(relative: Float, depth: Float)] = []
        for point in featurePoints {
            let local = camera.inverseTransform * SIMD4<Float>(point.x, point.y, point.z, 1)
            let depth = -local.z
            guard depth > 0.3, depth < 15, let pixel = camera.imagePoint(of: point) else { continue }
            // Sensor pixel to upright normalized coordinates.
            let uprightX = 1 - pixel.y / sensorHeight
            let uprightY = pixel.x / sensorWidth
            let row = Int((uprightY - band.top) / band.height * Float(modelHeight))
            let column = Int(uprightX * Float(modelWidth))
            guard column >= 0, column < modelWidth, row >= 0, row < modelHeight else { continue }
            pairs.append((relativeDepth[row * modelWidth + column], depth))
        }
        depthScale.fit(pairs, time: time)
        guard depthScale.isValid else { return }

        let range: Float = torch.isOn ? Self.nearRange : 8
        let cameraPosition = camera.position
        let cameraForward = -SIMD3<Float>(camera.transform.columns.2.x, camera.transform.columns.2.y, camera.transform.columns.2.z)
        var points: [SIMD3<Float>] = []
        points.reserveCapacity(3500)
        for row in stride(from: 3, to: modelHeight, by: 8) {
            for column in stride(from: 3, to: modelWidth, by: 8) {
                guard let depth = depthScale.metres(fromRelative: relativeDepth[row * modelWidth + column]), depth < range else { continue }
                let uprightX = (Float(column) + 0.5) / Float(modelWidth)
                let uprightY = band.top + (Float(row) + 0.5) / Float(modelHeight) * band.height
                let direction = camera.rayDirection(x: uprightY * sensorWidth, y: (1 - uprightX) * sensorHeight)
                // Depth is measured along the camera axis, not along the ray.
                let along = max(0.05, simd_dot(direction, cameraForward))
                points.append(cameraPosition + direction * (depth / along))
            }
        }
        let sampled = ColorSampler.colors(for: points, in: picture, camera: camera)
        map.add(sampled.points, colors: sampled.colors, time: time)

        // The floor reader reads this picture too.
        feedSteps(relativeDepth, band: DepthBand(y0: band.top, h: band.height), scale: depthScale, picture: picture, camera: camera, time: time)
    }
}
