import simd

/// Layout must match Uniforms in the Metal source: 116 bytes, padded to 128.
nonisolated struct SplatUniforms {
    let viewProjection: simd_float4x4
    let pointScale: Float
    let frozenAmount: Float
    let waveRadius: Float
    let waveAmplitude: Float
    let walkerX: Float
    let walkerY: Float
    let walkerZ: Float
    let groundRed: Float
    let groundGreen: Float
    let groundBlue: Float
    let inkRed: Float
    let inkGreen: Float
    let inkBlue: Float
}
