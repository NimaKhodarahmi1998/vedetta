import Foundation
import simd

nonisolated final class MapBuilder {
    let cellSize: Float = 0.08
    private(set) var cells: [Int64: MapCell] = [:]

    func add(_ points: [SIMD3<Float>], colors: [SIMD3<Float>], time: Double) {
        for index in points.indices {
            let point = points[index]
            let key = cellKey(for: point)
            if var cell = cells[key] {
                cell.position += (point - cell.position) * 0.3
                cell.color += (colors[index] - cell.color) * 0.3
                cell.hits += 1
                cell.lastSeen = time
                cells[key] = cell
            } else {
                cells[key] = MapCell(position: point, color: colors[index], hits: 1, lastSeen: time)
            }
        }
    }

    /// Far cells go first, then the oldest.
    func prune(around center: SIMD3<Float>) {
        // Kept small enough that reading it five times a second never holds up the camera.
        guard cells.count > 30_000 else { return }
        cells = cells.filter { simd_distance($0.value.position, center) < 15 }
        if cells.count > 25_000 {
            let newest = cells.sorted { $0.value.lastSeen > $1.value.lastSeen }.prefix(20_000)
            cells = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
    }

    func reset() {
        cells.removeAll()
    }

    /// Certainty grows with sightings, so near cells fill in fast and far ones slowly.
    func vertices() -> [SplatVertex] {
        cells.values.map { cell in
            let brightened = cell.color * 1.15
            return SplatVertex(
                position: cell.position,
                color: SIMD3(min(1, brightened.x), min(1, brightened.y), min(1, brightened.z)),
                confidence: min(1, cell.hits / 5),
                size: 0.11,
                mode: .map
            )
        }
    }

    private func cellKey(for point: SIMD3<Float>) -> Int64 {
        let x = Int64(floor(point.x / cellSize)) + 1_000_000
        let y = Int64(floor(point.y / cellSize)) + 1_000_000
        let z = Int64(floor(point.z / cellSize)) + 1_000_000
        return (x << 42) | (y << 21) | z
    }
}
