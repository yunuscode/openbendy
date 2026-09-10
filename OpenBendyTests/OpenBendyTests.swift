import XCTest
import Metal
import AppKit
import SwiftUI
@testable import OpenBendy

final class OpenBendyTests: XCTestCase {
    func testProgressIsContinuousMonotonicAndClamped() {
        var previous = 1.0
        for angle in stride(from: -10.0, through: 180.0, by: 0.1) {
            let p = BendParameters(angle: angle, clearAngle: 100, perspective: 1, blur: 0.65, shadow: 0.5, style: .silk).progress
            XCTAssertTrue((0...1).contains(p))
            XCTAssertLessThanOrEqual(p, previous + 0.00001)
            XCTAssertLessThan(abs(p - previous), 0.003)
            previous = p
        }
        XCTAssertEqual(previous, 0)
    }
    func testPreferencesPersistAndReset() {
        let key = "openbendy.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: key)!
        defer { defaults.removePersistentDomain(forName: key) }
        let p = Preferences(defaults: defaults)
        p.style = .arc; p.blur = 0.23; p.clearAngle = 120; p.sound = false
        let restored = Preferences(defaults: defaults)
        XCTAssertEqual(restored.style, .arc); XCTAssertEqual(restored.blur, 0.23)
        XCTAssertEqual(restored.clearAngle, 120); XCTAssertFalse(restored.sound)
        p.enabled = true
        XCTAssertTrue(Preferences(defaults: defaults).resumeDesktopEffect)
        let restarted = Preferences(defaults: defaults)
        XCTAssertFalse(restarted.enabled, "Do not report live capture active before it starts.")
        XCTAssertTrue(restarted.resumeDesktopEffect, "Preserve the user's enable choice across launch.")
        restarted.enabled = false
        XCTAssertFalse(Preferences(defaults: defaults).resumeDesktopEffect)
        restored.reset()
        let reset = Preferences(defaults: defaults)
        XCTAssertEqual(reset.style, .silk); XCTAssertEqual(reset.blur, 0.65)
        XCTAssertEqual(reset.perspective, 1); XCTAssertEqual(reset.shadow, 0.5)
        XCTAssertEqual(reset.clearAngle, 100)
    }
    func testGPUClearFrameAndBentFrame() throws {
        let fixture = try GPUFixture(width: 256, height: 256)
        let clear = try fixture.render(progress: 0)
        XCTAssertTrue(clear.allSatisfy { $0 >= 254 }, "An open lid must reproduce the unmodified desktop.")
        let bent = try fixture.render(progress: 0.7, style: 1)
        XCTAssertEqual(bent[(5 * 256 + 128) * 4], 0)
        XCTAssertGreaterThan(bent[(254 * 256 + 128) * 4], 240, "The hinge remains visible.")
        let silk = try fixture.render(progress: 0.5, style: 0)
        let shade = try fixture.render(progress: 0.5, style: 1)
        let frost = try fixture.render(progress: 0.5, style: 2)
        let pixel = (150 * 256 + 128) * 4
        XCTAssertLessThan(shade[pixel], silk[pixel])
        XCTAssertGreaterThanOrEqual(frost[pixel], silk[pixel])
    }

    func testFoldEdgeIsSoftMonotonicAndResolutionIndependent() throws {
        func edge(_ size: Int) throws -> (Double, Double) {
            let f = try GPUFixture(width: size, height: size)
            let pixels = try f.render(progress: 0.6, blur: 1, shadow: 0)
            let column = (0..<size).map { Int(pixels[($0 * size + size / 2) * 4]) }
            let low = try XCTUnwrap(column.firstIndex(where: { $0 >= 15 }))
            let high = try XCTUnwrap(column.firstIndex(where: { $0 >= 240 }))
            XCTAssertGreaterThan(high - low, size / 40, "A hard clipped edge must fail this check.")
            for y in low..<high { XCTAssertGreaterThanOrEqual(column[y + 1], column[y]) }
            XCTAssertLessThan(column[low - 3], 15, "The dark field stays dark away from the edge.")
            XCTAssertGreaterThan(column[size - 3], 250, "No blur halo or darkening at the hinge.")
            return (Double(low) / Double(size), Double(high - low) / Double(size))
        }
        let small = try edge(256), retina = try edge(512)
        XCTAssertEqual(small.0, retina.0, accuracy: 0.008)
        XCTAssertEqual(small.1, retina.1, accuracy: 0.008)
    }

    func testBlurBeginsEarlyAndPreservesLowerDetail() throws {
        let size = 512
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size { for x in 0..<size {
            let value: UInt8 = (x / 3) % 2 == 0 ? 255 : 0
            for c in 0..<3 { pixels[(y * size + x) * 4 + c] = value }
        } }
        let fixture = try GPUFixture(width: size, height: size, pixels: pixels)
        let clear = try fixture.render(progress: 0)
        XCTAssertEqual(clear, pixels)
        let blurred = try fixture.render(progress: 0.08, perspective: 0, blur: 1, shadow: 0)
        func contrast(_ y: Int) -> Int {
            let values = (100..<400).map { Int(blurred[(y * size + $0) * 4]) }
            return values.max()! - values.min()!
        }
        XCTAssertLessThan(contrast(75), 150, "Upper detail blurs early in the closing movement.")
        XCTAssertGreaterThan(contrast(500), 240, "The Dock/hinge region remains sharp.")
        let white = try GPUFixture(width: size, height: size)
        let early = try white.render(progress: 0.08, blur: 0, shadow: 0)
        let firstWhite = try XCTUnwrap((0..<size).first { early[($0 * size + size / 2) * 4] >= 128 })
        XCTAssertLessThan(firstWhite, size / 30, "Early blur should precede strong geometric compression.")
    }

    @MainActor func testNativeLandscapePreviewUploadsToMetal() async throws {
        let image = ImageRenderer(content: Landscape().frame(width: 640, height: 400))
        let cgImage = try XCTUnwrap(image.cgImage)
        let renderer = try DesktopRenderer()
        XCTAssertNoThrow(try renderer.submitPreview(cgImage))
    }

    func testArcBowsSidesWhilePreservingFullHeightAndPinnedEdges() throws {
        func geometry(_ size: Int) throws -> Double {
            let fixture = try GPUFixture(width: size, height: size)
            var previousInset = 0
            for progress: Float in [0, 0.2, 0.6, 0.9] {
                let pixels = try fixture.render(progress: progress, blur: 0, shadow: 0, style: 3)
                for y in 0..<size {
                    XCTAssertGreaterThan(pixels[(y * size + size / 2) * 4], 250, "Arc must keep the desktop at full height.")
                }
                for y in [size / 50, size - 3] { for x in 0..<size {
                    XCTAssertEqual(pixels[(y * size + x) * 4], 255, "The menu and hinge edges stay pinned.")
                } }
                let row = (0..<size).map { Int(pixels[(size / 2 * size + $0) * 4]) }
                let inset = try XCTUnwrap(row.firstIndex(where: { $0 >= 128 }))
                XCTAssertGreaterThanOrEqual(inset, previousInset)
                previousInset = inset
                for x in 0..<size / 2 { XCTAssertEqual(row[x], row[size - 1 - x], accuracy: 1) }
            }
            XCTAssertGreaterThan(previousInset, size / 10, "The body must visibly curve inward.")
            return Double(previousInset) / Double(size)
        }
        XCTAssertEqual(try geometry(256), try geometry(512), accuracy: 0.005)
    }

    func testArcDiffusionPreservesMenuAndDockAndClearsExactly() throws {
        let size = 512
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size { for x in 0..<size { for channel in 0..<3 {
            pixels[(y * size + x) * 4 + channel] = (x / 3) % 2 == 0 ? 255 : 0
        } } }
        let fixture = try GPUFixture(width: size, height: size, pixels: pixels)
        let blurred = try fixture.render(progress: 0.12, perspective: 0, blur: 1, shadow: 0, style: 3)
        let row = (100..<400).map { Int(blurred[(size / 3 * size + $0) * 4]) }
        XCTAssertLessThan(row.max()! - row.min()!, 100, "The body diffuses early in the lid movement.")
        for y in [size / 50, size - 3] { for x in 0..<size {
            XCTAssertEqual(blurred[(y * size + x) * 4], pixels[(y * size + x) * 4])
        } }
        XCTAssertEqual(try fixture.render(progress: 0, style: 3), pixels, "Reopening must restore every pixel.")
    }

    func testRenderReferenceReviewFrames() throws {
        let width = 960, height = 600
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue))
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for (label, y, fontSize) in [("Your desktop follows the lid.", 465, 40), ("Upper content softens first", 400, 22),
                                      ("Live content, a fixed bottom edge", 230, 30), ("Lower text remains sharp", 55, 23)] {
            (label as NSString).draw(at: NSPoint(x: 60, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: CGFloat(fontSize)), .foregroundColor: NSColor.black])
        }
        for i in 0..<18 {
            NSColor(calibratedRed: CGFloat(i % 3) * 0.22 + 0.15, green: 0.38, blue: 0.55, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 60 + i * 45, y: 15, width: 31, height: 22), xRadius: 5, yRadius: 5).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let raw = try XCTUnwrap(context.data)
        let bytes = Array(UnsafeBufferPointer(start: raw.assumingMemoryBound(to: UInt8.self), count: width * height * 4))
        let fixture = try GPUFixture(width: width, height: height, pixels: bytes)
        let directory = URL(fileURLWithPath: "/private/tmp/openbendy-qa")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (label, style) in [("frame", Float(0)), ("arc", Float(3))] {
          for (index, progress) in [Float(0), 0.08, 0.3, 0.6, 0.9].enumerated() {
            let output = try fixture.render(progress: progress, shadow: 0.5, style: style)
            let provider = try XCTUnwrap(CGDataProvider(data: Data(output) as CFData))
            let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("\(label)-\(index).png"))
          }
        }
    }
}

private final class GPUFixture {
    let gpu: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    let input: MTLTexture
    let target: MTLTexture
    let width: Int
    let height: Int
    init(width: Int, height: Int, pixels: [UInt8]? = nil) throws {
        self.width = width; self.height = height
        gpu = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        queue = try XCTUnwrap(gpu.makeCommandQueue())
        let library = try gpu.makeDefaultLibrary(bundle: Bundle(for: DesktopRenderer.self))
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "bendVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "bendFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try gpu.makeRenderPipelineState(descriptor: descriptor)
        let textureDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: true)
        textureDesc.usage = [.shaderRead, .renderTarget]; textureDesc.storageMode = .shared
        input = try XCTUnwrap(gpu.makeTexture(descriptor: textureDesc))
        textureDesc.mipmapLevelCount = 1
        target = try XCTUnwrap(gpu.makeTexture(descriptor: textureDesc))
        let data = pixels ?? [UInt8](repeating: 255, count: width * height * 4)
        data.withUnsafeBytes { input.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width * 4) }
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        let blit = try XCTUnwrap(command.makeBlitCommandEncoder())
        blit.generateMipmaps(for: input); blit.endEncoding(); command.commit(); command.waitUntilCompleted()
    }
    func render(progress: Float, perspective: Float = 1, blur: Float = 0.65, shadow: Float = 0.8, style: Float = 0) throws -> [UInt8] {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        let command = try XCTUnwrap(queue.makeCommandBuffer())
        let encoder = try XCTUnwrap(command.makeRenderCommandEncoder(descriptor: pass))
        encoder.setRenderPipelineState(pipeline); encoder.setFragmentTexture(input, index: 0)
        var u = [SIMD4<Float>(progress, perspective, blur, shadow), SIMD4<Float>(style, Float(width), Float(height), 0)]
        encoder.setFragmentBytes(&u, length: 32, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed)
        var output = [UInt8](repeating: 0, count: width * height * 4)
        output.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0) }
        return output
    }
}
