import AppKit
import MetalKit
import CoreVideo

private final class EffectMetalView: MTKView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in self?.draw() }
    }
}

final class DesktopRenderer: NSObject, MTKViewDelegate {
    let view: MTKView
    private let gpu: MTLDevice
    private let commands: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var textureCache: CVMetalTextureCache?
    private var latestBuffer: CVPixelBuffer?
    private var staticTexture: MTLTexture?
    private var bufferRevision = 0
    private var mipRevision = -1
    private var mipTexture: MTLTexture?
    private var params = BendParameters(angle: 135, clearAngle: 100, perspective: 1, blur: 0.65, shadow: 0.5, style: .silk)
    private let lock = NSLock()
    private let inflight = DispatchSemaphore(value: 2)
    private(set) var renderedFrames = 0
    init(configured: Bool = true) throws {
        guard let gpu = MTLCreateSystemDefaultDevice(), let commands = gpu.makeCommandQueue(), let library = gpu.makeDefaultLibrary() else {
            throw NSError(domain: "OpenBendy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal is unavailable on this Mac."])
        }
        self.gpu = gpu; self.commands = commands
        view = EffectMetalView(frame: .zero, device: gpu)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "bendVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "bendFragment")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipeline = try gpu.makeRenderPipelineState(descriptor: descriptor)
        super.init()
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, gpu, nil, &textureCache)
        view.delegate = self
    }
    func update(_ params: BendParameters) {
        lock.lock(); self.params = params; lock.unlock()
        // Draw explicitly from the animation clock. AppKit can coalesce or suppress
        // invalidations for a nonactivating, click-through overlay.
    }
    func submit(_ buffer: CVPixelBuffer) {
        lock.lock(); latestBuffer = buffer; bufferRevision += 1; lock.unlock()
    }
    func submitPreview(_ image: CGImage) throws {
        // Normalize SwiftUI's extended-color CGImage into the same 8-bit BGRA
        // format as capture frames; MTKTextureLoader cannot decode every variant.
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
              let bytes = context.data else {
            throw NSError(domain: "OpenBendy", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not prepare the preview image."])
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = .shaderRead
        guard let texture = gpu.makeTexture(descriptor: descriptor) else {
            throw NSError(domain: "OpenBendy", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not allocate the preview texture."])
        }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes, bytesPerRow: width * 4)
        lock.lock(); staticTexture = texture; bufferRevision += 1; lock.unlock()
    }
    func render() {
        guard view.window?.isVisible == true else { return }
        view.draw()
    }
    func clear() {
        lock.lock(); latestBuffer = nil; staticTexture = nil; lock.unlock()
        mipTexture = nil; mipRevision = -1
        if let textureCache { CVMetalTextureCacheFlush(textureCache, 0) }
    }
    func draw(in view: MTKView) {
        guard inflight.wait(timeout: .now()) == .success else { return }
        lock.lock()
        let buffer = latestBuffer, preview = staticTexture, revision = bufferRevision, p = params
        lock.unlock()
        var wrapped: CVMetalTexture?
        var source = preview
        if let buffer, let textureCache {
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, buffer, nil, .bgra8Unorm,
                CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &wrapped)
            source = wrapped.flatMap { CVMetalTextureGetTexture($0) }
        }
        guard let source, let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
              let command = commands.makeCommandBuffer() else { inflight.signal(); return }
        let width = source.width, height = source.height
        if mipTexture?.width != width || mipTexture?.height != height || mipTexture?.pixelFormat != source.pixelFormat {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: source.pixelFormat,
                width: width, height: height, mipmapped: true)
            descriptor.usage = .shaderRead; descriptor.storageMode = .private
            mipTexture = gpu.makeTexture(descriptor: descriptor); mipRevision = -1
        }
        guard let texture = mipTexture else { inflight.signal(); return }
        if revision != mipRevision {
            guard let blit = command.makeBlitCommandEncoder() else { inflight.signal(); return }
            blit.copy(from: source, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(x: 0, y: 0, z: 0),
                sourceSize: .init(width: width, height: height, depth: 1), to: texture, destinationSlice: 0,
                destinationLevel: 0, destinationOrigin: .init(x: 0, y: 0, z: 0))
            blit.generateMipmaps(for: texture); blit.endEncoding()
        }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { inflight.signal(); return }
        var uniforms = [SIMD4<Float>(Float(p.progress), Float(p.perspective), Float(p.blur), Float(p.shadow)), SIMD4<Float>(Float(p.style.index), Float(width), Float(height), 0)]
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride * 2, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        command.present(drawable)
        let semaphore = inflight
        command.addCompletedHandler { _ in
            _ = buffer; _ = wrapped // Hold the IOSurface-backed frame until GPU completion.
            semaphore.signal()
        }
        command.commit()
        mipRevision = revision
        renderedFrames += 1
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
