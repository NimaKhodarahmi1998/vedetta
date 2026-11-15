import CoreML
import Foundation

/// The exported YOLO pipeline has NMS built in and takes its two thresholds as inputs.
nonisolated final class DetectorThresholds: NSObject, MLFeatureProvider {
    private let values: [String: MLFeatureValue]

    init(iou: Double, confidence: Double) {
        values = [
            "iouThreshold": MLFeatureValue(double: iou),
            "confidenceThreshold": MLFeatureValue(double: confidence)
        ]
    }

    var featureNames: Set<String> { Set(values.keys) }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        values[featureName]
    }
}
