import UIKit
import Metal

// Only captures an explicitly selected content UIWindow in this process.
// No screen/compositor capture, file output, keyboard view or remote surface IPC.
final class NTKWindowCapture {
    private let device: MTLDevice
    private var context: CGContext?
    private var textures: [MTLTexture] = []
    private var textureIndex = 0
    private var failureLogged = false

    init(device: MTLDevice) { self.device = device }

    func capture(window: UIWindow, region: CGRect, scale: CGFloat)
        -> (texture: MTLTexture, meanColor: CaptureColor)? {
        precondition(Thread.isMainThread)
        guard !window.isHidden, window.alpha > 0.99,
              window.windowScene?.activationState == .foregroundActive,
              region.origin.x.isFinite, region.origin.y.isFinite,
              region.width.isFinite, region.height.isFinite,
              scale.isFinite, scale > 0 else { return nil }
        let pixelsPerPoint = window.screen.scale * scale
        let widthFloat = ceil(region.width * pixelsPerPoint - 0.001)
        let heightFloat = ceil(region.height * pixelsPerPoint - 0.001)
        guard widthFloat > 0, heightFloat > 0, widthFloat <= 4096, heightFloat <= 4096,
              widthFloat * heightFloat <= 8_000_000 else { return nil }
        let width = Int(widthFloat), height = Int(heightFloat)
        if context?.width != width || context?.height != height {
            context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            descriptor.usage = .shaderRead
            descriptor.storageMode = .shared
            textures = (0..<3).compactMap { _ in device.makeTexture(descriptor: descriptor) }
        }
        guard let ctx = context, let data = ctx.data, textures.count == 3 else { return nil }
        ctx.saveGState()
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: pixelsPerPoint, y: -pixelsPerPoint)
        ctx.translateBy(x: -region.origin.x, y: -region.origin.y)
        UIGraphicsPushContext(ctx)
        // Source and overlay are disjoint window trees. Never hide the overlay to capture.
        let complete = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        UIGraphicsPopContext()
        ctx.restoreGState()
        guard complete else {
            NTKRecordStage("content-window-draw-failed")
            if !failureLogged { NTKRecordStage("content-window-capture-incomplete"); failureLogged = true }
            return nil
        }
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        var sums = [Int](repeating: 0, count: 4)
        for row in 0..<16 {
            let y = min(height - 1, (row * 2 + 1) * height / 32)
            for column in 0..<16 {
                let x = min(width - 1, (column * 2 + 1) * width / 32)
                let offset = y * ctx.bytesPerRow + x * 4
                for channel in 0..<4 { sums[channel] += Int(bytes[offset + channel]) }
            }
        }
        guard sums[3] > 256 * 16 else {
            NTKRecordStage("content-window-draw-transparent");
            if !failureLogged { NTKRecordStage("content-window-capture-transparent"); failureLogged = true }
            return nil
        }
        textureIndex = (textureIndex + 1) % textures.count
        let texture = textures[textureIndex]
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                        withBytes: data, bytesPerRow: ctx.bytesPerRow)
        let normalizer = CGFloat(256 * 255)
        return (texture, CaptureColor(red: CGFloat(sums[2]) / normalizer,
            green: CGFloat(sums[1]) / normalizer, blue: CGFloat(sums[0]) / normalizer))
    }
}
