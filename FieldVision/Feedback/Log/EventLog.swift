import Foundation

/// A JSON line per event for real-life tests, in Files > On My iPhone > FieldVision.
nonisolated final class EventLog: @unchecked Sendable {
    private let queue = DispatchQueue(label: "fv.log")
    private let handle: FileHandle?
    private let startDate = Date()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    init() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = URL.documentsDirectory.appending(path: "fieldvision-\(formatter.string(from: Date())).jsonl")
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        handle = try? FileHandle(forWritingTo: url)
    }

    func write(_ fields: [String: LogValue]) {
        queue.async { [weak self] in
            guard let self, let handle = self.handle else { return }

            var entry = fields
            entry["wall"] = .number(Date().timeIntervalSince(self.startDate))
            guard var line = try? self.encoder.encode(entry) else { return }

            line.append(0x0A)
            try? handle.write(contentsOf: line)
        }
    }
}
