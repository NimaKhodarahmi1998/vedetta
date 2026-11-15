import MetalKit
import QuartzCore
import simd

/// Chase camera low behind the walker, looking ahead along the path.
final class SplatRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let store: SplatStore
    private var mapBuffer: MTLBuffer?
    private var mapCount = 0
    private var mapVersion = -1
    private var eye = SIMD3<Float>(0, 4.2, 6)
    private var target = SIMD3<Float>(0, 0, -10)
    private var hasStarted = false
    private var frozenAmount: Float = 0

    init?(view: MTKView, store: SplatStore) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: SplatShader.source, options: nil) else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "splatVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "splatFragment")
        guard let colorAttachment = descriptor.colorAttachments[0] else { return nil }
        colorAttachment.pixelFormat = view.colorPixelFormat
        colorAttachment.isBlendingEnabled = true
        colorAttachment.rgbBlendOperation = .add
        colorAttachment.alphaBlendOperation = .add
        colorAttachment.sourceRGBBlendFactor = .one
        colorAttachment.sourceAlphaBlendFactor = .one
        colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.device = device
        self.commandQueue = commandQueue
        self.pipeline = pipeline
        self.store = store
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let snapshot = store.snapshot(knownVersion: mapVersion)
        if snapshot.mapVersion != mapVersion {
            mapVersion = snapshot.mapVersion
            mapCount = snapshot.mapVertices.count
            mapBuffer = makeBuffer(for: snapshot.mapVertices)
        }
        frozenAmount += ((snapshot.isReliable ? 0 : 1) - frozenAmount) * 0.15

        let up = SIMD3<Float>(0, 1, 0)
        let base = SIMD3<Float>(snapshot.walker.x, snapshot.ground, snapshot.walker.z)
        let forward = SIMD3<Float>(snapshot.forward.x, 0, snapshot.forward.y)
        let desiredEye = base - forward * 6 + up * 4.2
        let desiredTarget = base + forward * 10
        if hasStarted {
            eye += (desiredEye - eye) * 0.08
            target += (desiredTarget - target) * 0.08
        } else {
            eye = desiredEye
            target = desiredTarget
            hasStarted = true
        }

        let drawableSize = view.drawableSize
        guard drawableSize.width > 0, drawableSize.height > 0 else { return }
        let fieldOfView: Float = 50 * .pi / 180
        let projection = simd_float4x4.perspective(
            fieldOfViewY: fieldOfView,
            aspectRatio: Float(drawableSize.width / drawableSize.height),
            nearZ: 0.1,
            farZ: 200
        )
        let viewProjection = projection * simd_float4x4.lookAt(eye: eye, target: target, up: up)
        let waveAge = Float(CACurrentMediaTime() - snapshot.waveStartTime)
        let theme = snapshot.theme
        var uniforms = SplatUniforms(
            viewProjection: viewProjection,
            pointScale: Float(drawableSize.height) / (2 * tan(fieldOfView / 2)),
            frozenAmount: frozenAmount,
            waveRadius: waveAge * 15,
            waveAmplitude: snapshot.isReliable ? max(0, 1 - waveAge / 1.7) : 0,
            walkerX: snapshot.walker.x,
            walkerY: snapshot.ground,
            walkerZ: snapshot.walker.z,
            groundRed: theme.ground.x,
            groundGreen: theme.ground.y,
            groundBlue: theme.ground.z,
            inkRed: theme.ink.x,
            inkGreen: theme.ink.y,
            inkBlue: theme.ink.z
        )
        view.clearColor = MTLClearColor(red: Double(theme.ground.x), green: Double(theme.ground.y), blue: Double(theme.ground.z), alpha: 1)

        guard let passDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<SplatUniforms>.stride, index: 1)
        if let mapBuffer {
            encoder.setVertexBuffer(mapBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: mapCount)
        }
        if let overlayBuffer = makeBuffer(for: snapshot.overlayVertices) {
            encoder.setVertexBuffer(overlayBuffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: snapshot.overlayVertices.count)
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func makeBuffer(for vertices: [SplatVertex]) -> MTLBuffer? {
        guard !vertices.isEmpty else { return nil }
        return vertices.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return nil }
            return device.makeBuffer(bytes: baseAddress, length: bytes.count, options: .storageModeShared)
        }
    }
}
