import Foundation
import simd

/// Local coordinates, +z forward.
nonisolated enum SplatShapes {
    static func build() -> [ObjectKind: [SIMD3<Float>]] {
        var random = SeededRandom(seed: 7)

        func cylinder(
            points count: Int,
            bottomRadius: Float,
            topRadius: Float,
            bottomY: Float,
            topY: Float,
            offsetZ: Float = 0,
            tilt: Float = 0
        ) -> [SIMD3<Float>] {
            var points: [SIMD3<Float>] = []
            for _ in 0..<count {
                let u = random.next()
                let angle = random.next() * 2 * .pi
                let y = bottomY + (topY - bottomY) * u
                let radius = bottomRadius + (topRadius - bottomRadius) * u
                points.append(SIMD3(cos(angle) * radius, y, sin(angle) * radius + offsetZ + (y - bottomY) * tilt))
            }
            return points
        }

        func sphere(points count: Int, center: SIMD3<Float>, radius: Float) -> [SIMD3<Float>] {
            var points: [SIMD3<Float>] = []
            for _ in 0..<count {
                let direction = SIMD3<Float>(random.next() * 2 - 1, random.next() * 2 - 1, random.next() * 2 - 1) + SIMD3(0.0001, 0, 0)
                points.append(center + simd_normalize(direction) * radius)
            }
            return points
        }

        func box(points count: Int, width: Float, height: Float, length: Float) -> [SIMD3<Float>] {
            var points: [SIMD3<Float>] = []
            for _ in 0..<count {
                // Five faces, no bottom
                let face = Int(random.next() * 5)
                let u = random.next() - 0.5
                let v = random.next() - 0.5
                switch face {
                    case 0: points.append(SIMD3(-width / 2, (v + 0.5) * height, u * length))
                    case 1: points.append(SIMD3(width / 2, (v + 0.5) * height, u * length))
                    case 2: points.append(SIMD3(u * width, height, v * length))
                    case 3: points.append(SIMD3(u * width, (v + 0.5) * height, -length / 2))
                    default: points.append(SIMD3(u * width, (v + 0.5) * height, length / 2))
                }
            }
            return points
        }

        let person = cylinder(points: 110, bottomRadius: 0.15, topRadius: 0.2, bottomY: 0.05, topY: 0.8)
            + cylinder(points: 120, bottomRadius: 0.21, topRadius: 0.19, bottomY: 0.8, topY: 1.5)
            + sphere(points: 45, center: SIMD3(0, 1.64, 0), radius: 0.12)

        var bike: [SIMD3<Float>] = []
        for wheelZ: Float in [0.55, -0.55] {
            for _ in 0..<60 {
                let angle = random.next() * 2 * .pi
                bike.append(SIMD3(0, 0.34 + sin(angle) * 0.33, wheelZ + cos(angle) * 0.33))
            }
        }
        bike += cylinder(points: 70, bottomRadius: 0.13, topRadius: 0.16, bottomY: 0.3, topY: 0.95)
            + cylinder(points: 80, bottomRadius: 0.19, topRadius: 0.17, bottomY: 0.95, topY: 1.55, offsetZ: 0.05, tilt: 0.45)
            + sphere(points: 30, center: SIMD3(0, 1.72, 0.33), radius: 0.11)

        let car = box(points: 420, width: 1.8, height: 1.45, length: 4.2)
        let vehicle = box(points: 600, width: 2.5, height: 3.0, length: 9.0)
        let dog = box(points: 120, width: 0.3, height: 0.55, length: 0.8)
        let thing = cylinder(points: 140, bottomRadius: 0.25, topRadius: 0.25, bottomY: 0.0, topY: 0.9)

        return [
            .person: person,
            .bike: bike,
            .motorbike: bike,
            .car: car,
            .bus: vehicle,
            .truck: vehicle,
            .dog: dog,
            .animal: dog,
            .thing: thing
        ]
    }
}
