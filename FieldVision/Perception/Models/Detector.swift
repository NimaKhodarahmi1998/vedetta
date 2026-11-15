import CoreML
import CoreVideo
import Foundation
import QuartzCore
import Vision

/// YOLO11n on the Neural Engine, through Vision. One frame at a time; frames that arrive while it's busy are skipped.
nonisolated final class Detector: @unchecked Sendable {
    let loadError: String?
    private let request: VNCoreMLRequest?
    private let queue = DispatchQueue(label: "fv.detector", qos: .userInitiated)
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private var lastPoseTime = 0.0
    private var lastJoints: [CGPoint] = []

    init() {
        guard let url = Bundle.main.url(forResource: "yolo11n", withExtension: "mlmodelc") else {
            request = nil
            loadError = "yolo11n.mlmodelc missing from the app bundle"
            return
        }
        do {
            let configuration = MLModelConfiguration()
            // The GPU is busy drawing the camera and the map: in a live camera app .all is no faster, only jitterier.
            configuration.computeUnits = .cpuAndNeuralEngine
            let model = try MLModel(contentsOf: url, configuration: configuration)
            let visionModel = try VNCoreMLModel(for: model)
            visionModel.featureProvider = DetectorThresholds(iou: 0.45, confidence: 0.3)
            let request = VNCoreMLRequest(model: visionModel)
            request.imageCropAndScaleOption = .scaleFit
            self.request = request
            loadError = nil
        } catch {
            request = nil
            loadError = error.localizedDescription
        }
    }

    /// The phone is held upright, so the landscape camera buffer is rotated before detection.
    /// `prepare` (dim light) swaps in a brightened copy of the same picture, made on the detector's queue.
    func detect(_ pixelBuffer: CVPixelBuffer, prepare: (@Sendable (CVPixelBuffer) -> CVPixelBuffer?)? = nil,
                completion: @escaping @Sendable ([ImageDetection], Double) -> Void) {
        guard request != nil else {
            completion([], 0)
            return
        }
        nonisolated(unsafe) let pixelBuffer = pixelBuffer
        queue.async {
            let input = prepare?(pixelBuffer) ?? pixelBuffer
            let result = self.runDetection(on: input)
            completion(result.detections, result.milliseconds)
        }
    }

    private func runDetection(on pixelBuffer: CVPixelBuffer) -> (detections: [ImageDetection], milliseconds: Double) {
        guard let request else { return ([], 0) }
        let startTime = CACurrentMediaTime()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ([], 0)
        }
        let observations = (request.results as? [VNRecognizedObjectObservation]) ?? []
        let detections = observations.compactMap { observation -> ImageDetection? in
            guard let label = observation.labels.first else { return nil }
            return ImageDetection(label: label.identifier, confidence: label.confidence, box: observation.boundingBox)
        }
        return (verifyPeople(detections, in: pixelBuffer), (CACurrentMediaTime() - startTime) * 1000)
    }

    /// A big "person" box (a quarter of the picture or more, so within a few metres) must hold a body: at least three
    /// joints from Apple's body-pose request, any of them (head, shoulders, hips, knees, feet). A towel on a rack, a
    /// coat or a bag has none. At most about 6 times a second; in between, the last joints are reused.
    private func verifyPeople(_ detections: [ImageDetection], in pixelBuffer: CVPixelBuffer) -> [ImageDetection] {
        guard detections.contains(where: { $0.label == "person" && $0.box.height >= 0.25 }) else { return detections }
        let now = CACurrentMediaTime()
        if now - lastPoseTime > 0.15 {
            lastPoseTime = now
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
            var joints: [CGPoint] = []
            if (try? handler.perform([poseRequest])) != nil {
                for body in poseRequest.results ?? [] {
                    guard let points = try? body.recognizedPoints(.all) else { continue }
                    joints += points.values.filter { $0.confidence >= 0.3 }.map(\.location)
                }
            }
            lastJoints = joints
        }
        return detections.filter { detection in
            guard detection.label == "person", detection.box.height >= 0.25 else { return true }
            let box = detection.box.insetBy(dx: -0.03, dy: -0.03)
            return lastJoints.filter { box.contains($0) }.count >= 3
        }
    }
}
