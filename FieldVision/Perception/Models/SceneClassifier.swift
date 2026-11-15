import CoreVideo
import Foundation
import Vision

/// Apple's built-in image classifier (no download, no licence) as a slow hint about the kind of place, about once a
/// second. It only ever makes the guide more alert: it can nominate stairs or a station, and the floor reader still
/// decides. It never delays or silences a warning.
nonisolated final class SceneClassifier: @unchecked Sendable {
    /// Labels from Vision's taxonomy; `checkLabels` reports which ones this iPhone really has.
    static let stairsLabels = ["stairs", "escalator"]
    static let stationLabels = ["train_station", "railroad", "track_rail", "subway", "platform"]
    static let wanted = stairsLabels + stationLabels
        + ["crosswalk", "sidewalk", "street", "road", "door", "elevator", "corridor", "hallway"]

    private let queue = DispatchQueue(label: "fv.scene", qos: .utility)

    /// Which of the wanted labels this iPhone's classifier knows, with the iOS version and the model, for the log.
    func checkLabels(completion: @escaping @Sendable (_ found: [String], _ missing: [String], _ system: String) -> Void) {
        queue.async {
            let known = Set((try? VNClassifyImageRequest().supportedIdentifiers()) ?? [])
            let system = "\(Self.deviceModel()), \(ProcessInfo.processInfo.operatingSystemVersionString)"
            completion(Self.wanted.filter { known.contains($0) }, Self.wanted.filter { !known.contains($0) }, system)
        }
    }

    /// The highest score among the stairs labels and among the station labels, and the top label overall.
    func classify(_ pixelBuffer: CVPixelBuffer,
                  completion: @escaping @Sendable (_ stairs: Float, _ station: Float, _ top: String) -> Void) {
        nonisolated(unsafe) let pixelBuffer = pixelBuffer
        queue.async {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
            guard (try? handler.perform([request])) != nil, let results = request.results else {
                completion(0, 0, "")
                return
            }
            var scores: [String: Float] = [:]
            for observation in results { scores[observation.identifier] = observation.confidence }
            let stairs = Self.stairsLabels.compactMap { scores[$0] }.max() ?? 0
            let station = Self.stationLabels.compactMap { scores[$0] }.max() ?? 0
            let best = results.max { $0.confidence < $1.confidence }
            let top = best.map { "\($0.identifier) \(String(format: "%.2f", $0.confidence))" } ?? ""
            completion(stairs, station, top)
        }
    }

    /// For example "iPhone15,2".
    static func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
