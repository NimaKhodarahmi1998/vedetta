import CoreML
import CoreVideo
import Foundation
import QuartzCore
import Vision

/// Depth Anything V2 Small (Apple's Core ML build, Apache-2.0): depth for every pixel, plain walls included.
/// Its output is relative; ARKit's feature points in the same frame give it a metric scale (see DepthScale).
nonisolated final class DepthEstimator: @unchecked Sendable {
    static let modelWidth = 518
    static let modelHeight = 392

    let loadError: String?
    private let request: VNCoreMLRequest?
    private let queue = DispatchQueue(label: "fv.depth", qos: .userInitiated)

    var isAvailable: Bool { request != nil }

    init() {
        guard let url = Bundle.main.url(forResource: "DepthAnythingV2SmallF16P6", withExtension: "mlmodelc") else {
            request = nil
            loadError = "depth model missing from the app bundle"
            return
        }
        do {
            let configuration = MLModelConfiguration()
            // The GPU is busy drawing the camera and the map: in a live camera app .all is no faster, only jitterier.
            configuration.computeUnits = .cpuAndNeuralEngine
            let model = try MLModel(contentsOf: url, configuration: configuration)
            let visionModel = try VNCoreMLModel(for: model)
            let request = VNCoreMLRequest(model: visionModel)
            // Upright picture, central band: see croppedBand(for:)
            request.imageCropAndScaleOption = .centerCrop
            self.request = request
            loadError = nil
        } catch {
            request = nil
            loadError = error.localizedDescription
        }
    }

    /// The model sees the upright picture cropped to its 518:392 shape: full width, a central band of the height.
    /// Returns that band in normalized upright coordinates.
    static func croppedBand(for resolution: CGSize) -> (top: Float, height: Float) {
        let uprightAspect = Float(resolution.height / resolution.width)
        let height = min(1, uprightAspect / (Float(modelWidth) / Float(modelHeight)))
        return ((1 - height) / 2, height)
    }

    /// Relative inverse depth (bigger is closer), row-major modelWidth by modelHeight, and the time taken in milliseconds.
    /// `prepare` (dim light) swaps in a brightened copy of the same picture, made on the depth queue.
    func estimate(_ pixelBuffer: CVPixelBuffer, prepare: (@Sendable (CVPixelBuffer) -> CVPixelBuffer?)? = nil,
                  completion: @escaping @Sendable ([Float]?, Double) -> Void) {
        guard request != nil else {
            completion(nil, 0)
            return
        }
        nonisolated(unsafe) let pixelBuffer = pixelBuffer
        queue.async {
            let input = prepare?(pixelBuffer) ?? pixelBuffer
            let result = self.runEstimation(on: input, orientation: .right)
            completion(result.depths, result.milliseconds)
        }
    }

    /// Same, on a picture already cut and scaled to the model's size, upright (the floor reader's band).
    /// `make` runs on the depth queue.
    func estimate(prepared make: @escaping @Sendable () -> CVPixelBuffer?, completion: @escaping @Sendable ([Float]?, Double) -> Void) {
        guard request != nil else {
            completion(nil, 0)
            return
        }
        queue.async {
            guard let input = make() else {
                completion(nil, 0)
                return
            }
            let result = self.runEstimation(on: input, orientation: .up)
            completion(result.depths, result.milliseconds)
        }
    }

    private func runEstimation(on pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> (depths: [Float]?, milliseconds: Double) {
        guard let request else { return (nil, 0) }
        let startTime = CACurrentMediaTime()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return (nil, 0)
        }
        guard let observation = request.results?.first as? VNPixelBufferObservation else { return (nil, 0) }
        return (Self.relativeDepths(from: observation.pixelBuffer), (CACurrentMediaTime() - startTime) * 1000)
    }

    private static func relativeDepths(from pixelBuffer: CVPixelBuffer) -> [Float]? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width == modelWidth, height == modelHeight, let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        var depths = [Float](repeating: 0, count: width * height)
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
            case kCVPixelFormatType_OneComponent16Half:
                for y in 0..<height {
                    let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float16.self)
                    for x in 0..<width { depths[y * width + x] = Float(row[x]) }
                }
            case kCVPixelFormatType_OneComponent32Float:
                for y in 0..<height {
                    let row = baseAddress.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float.self)
                    for x in 0..<width { depths[y * width + x] = row[x] }
                }
            default:
                return nil
        }
        return depths
    }
}
