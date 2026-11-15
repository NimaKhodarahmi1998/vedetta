/// The only colours on the monochrome map: the path, the warning and danger.
nonisolated enum SplatPalette {
    static let accent = SIMD3<Float>(0x5E, 0x5C, 0xE6) / 255
    static let danger = SIMD3<Float>(0xFF, 0x45, 0x3A) / 255
    static let warn = SIMD3<Float>(0xFF, 0xD6, 0x0A) / 255
}
