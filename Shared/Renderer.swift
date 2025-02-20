//
//  Renderer.swift
//  FluidDynamicsMetal
//
//  Created by Andrei-Sergiu Pițiș on 20/12/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

import MetalKit
import AVFoundation
import UIKit

typealias FloatTuple = (float2, float2, float2, float2, float2)

func / (rhs: FloatTuple, lhs: Float) -> FloatTuple {
    return FloatTuple(rhs.0 / lhs, rhs.1 / lhs, rhs.2 / lhs, rhs.3 / lhs, rhs.4 / lhs)
}

func - (rhs: FloatTuple, lhs: FloatTuple) -> FloatTuple {
    return FloatTuple(rhs.0 - lhs.0, rhs.1 - lhs.1, rhs.2 - lhs.2, rhs.3 - lhs.3, rhs.4 - lhs.4)
}

struct ColorData {
    var colors: (float3, float3, float3, float3, float3)
}

struct StaticData {
    var positions: FloatTuple
    var impulses: FloatTuple

    var impulseScalar: float2
    var offsets: float2
    
    var screenSize: float2
    var inkRadius: simd_float1
    var colors: (float3, float3, float3, float3, float3)
    var countMedia: Int32
}

enum MediaType {
    case image
    case video
}

struct MediaData {
    let type: MediaType
    let src: String
    let position: CGPoint
    let size: CGSize
}

struct MediaInfo {
    var position: float2
    var size: float2
}

struct VertexData {
    let position: float2
    let texCoord: float2
}

class Renderer: NSObject {
    static let MaxBuffers = 3
  
    static let ScreenScaleAdjustment: Float = 1.0

    //Vertex and index data
    static let vertexData: [VertexData] = [
        VertexData(position: float2(x: -1.0, y: -1.0), texCoord: float2(x: 0.0, y: 1.0)),
        VertexData(position: float2(x: 1.0, y: -1.0), texCoord: float2(x: 1.0, y: 1.0)),
        VertexData(position: float2(x: -1.0, y: 1.0), texCoord: float2(x: 0.0, y: 0.0)),
        VertexData(position: float2(x: 1.0, y: 1.0), texCoord: float2(x: 1.0, y: 0.0)),
        ]

    static let indices: [UInt16] = [2, 1, 0, 1, 2, 3]

    //Vertex and Index Metal buffers
    private let vertData = MetalDevice.sharedInstance.buffer(array: Renderer.vertexData, storageMode: [.storageModeShared])
    private let indexData = MetalDevice.sharedInstance.buffer(array: Renderer.indices, storageMode: [.storageModeShared])

    //Shaders
    private let applyForceVectorShader: RenderShader = RenderShader(fragmentShader: "applyForceVector", vertexShader: "vertexShader", pixelFormat: .rg16Float)
    private let applyForceScalarShader: RenderShader = RenderShader(fragmentShader: "applyForceScalar", vertexShader: "vertexShader", pixelFormat: .rg16Float)
    private let advectShader: RenderShader = RenderShader(fragmentShader: "advect", vertexShader: "vertexShader", pixelFormat: .rg16Float)
    private let divergenceShader: RenderShader = RenderShader(fragmentShader: "divergence", vertexShader: "vertexShader", pixelFormat: .rg16Float)
    private let jacobiShader: RenderShader = RenderShader(fragmentShader: "jacobi", vertexShader: "vertexShader", pixelFormat: .rg16Float)
    private let vorticityShader: RenderShader = RenderShader(fragmentShader: "vorticity", vertexShader: "vertexShader", pixelFormat: .rg16Float)
    private let vorticityConfinementShader: RenderShader = RenderShader(fragmentShader: "vorticityConfinement", vertexShader: "vertexShader", pixelFormat: .rg16Float)
    private let gradientShader: RenderShader = RenderShader(fragmentShader: "gradient", vertexShader: "vertexShader", pixelFormat: .rg16Float)

    private let renderVector: RenderShader = RenderShader(fragmentShader: "visualizeVector", vertexShader: "vertexShader")
    private let renderScalar: RenderShader = RenderShader(fragmentShader: "visualizeScalar", vertexShader: "vertexShader")
    private let renderScalarWithMedia: RenderShader = RenderShader(fragmentShader: "visualizeScalarWithMedia", vertexShader: "vertexShader")


    //Touch or Mouse positions
    private var positions: FloatTuple?
    private var directions: FloatTuple?

    //Surfaces
    private var mediaSlab: Slab!
    private var velocity: Slab!
    private var density: Slab!
    private var velocityDivergence: Slab!
    private var velocityVorticity: Slab!
    private var pressure: Slab!

    //Inflight buffers
    private var uniformsBuffers: [MTLBuffer] = []
    private var avaliableBufferIndex: Int = 0

    private let semaphore = DispatchSemaphore(value: MaxBuffers)

    //Index of the displayed slab
    private var currentIndex = 0
    
    private func randomColor() -> float3 {
        let hue = Float.random(in: 0...1)
        let saturation = Float.random(in: 0.8...1.0) // Giữ bão hòa cao
        let brightness = Float.random(in: 0.7...1.0) // Giữ sáng cao

        return HSVtoRGB(h: hue, s: saturation, v: brightness)
    }

    private func HSVtoRGB(h: Float, s: Float, v: Float) -> float3 {
        let i = Int(h * 6.0)
        let f = h * 6.0 - Float(i)
        let p = v * (1.0 - s)
        let q = v * (1.0 - f * s)
        let t = v * (1.0 - (1.0 - f) * s)

        switch i % 6 {
        case 0: return float3(v, t, p)      // Đỏ -> Vàng
        case 1: return float3(q, v, p)      // Vàng -> Xanh lá
        case 2: return float3(p, v, t)      // Xanh lá -> Cyan
        case 3: return float3(p, q, v)      // Cyan -> Xanh dương
        case 4: return float3(t, p, v)      // Xanh dương -> Tím
        case 5: return float3(v, p, q)      // Tím -> Đỏ (Quan trọng cho hồng/tím)
        default: return float3(1.0, 1.0, 1.0)
        }
    }
    
    private var textureArray: MTLTexture?
    
    func createTextureArray(from textures: [MTLTexture], device: MTLDevice) -> MTLTexture? {
        guard let firstTexture = textures.first else { return nil }

        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DArray
        descriptor.pixelFormat = firstTexture.pixelFormat
        descriptor.width = firstTexture.width
        descriptor.height = firstTexture.height
        descriptor.arrayLength = textures.count
        descriptor.usage = [.shaderRead]

        guard let textureArray = device.makeTexture(descriptor: descriptor) else { return nil }

        let region = MTLRegionMake2D(0, 0, firstTexture.width, firstTexture.height)
        let bytesPerRow = firstTexture.width * 4
        let bytesPerImage = bytesPerRow * firstTexture.height // ✅ Thêm bytesPerImage

        for (index, texture) in textures.enumerated() {
            let data = texture.bufferBytes() // Lấy dữ liệu pixel của texture
            textureArray.replace(region: region,
                                 mipmapLevel: 0,
                                 slice: index,
                                 withBytes: data,
                                 bytesPerRow: bytesPerRow,
                                 bytesPerImage: bytesPerImage) // ✅ Thêm bytesPerImage
            free(UnsafeMutableRawPointer(mutating: data)) // ✅ Giải phóng bộ nhớ ngay sau khi dùng
        }

        return textureArray
    }



    func updateTextureArrayIfNeeded() {
        if let array = createTextureArray(from: mediaTextures.compactMap { $0 }, device: MetalDevice.sharedInstance.device) {
            self.textureArray = array
        }
    }
    
    private var mediaList: [MediaData] = []
    private var mediaTextures: [MTLTexture?] = []
    private var mediaInfos: [MediaInfo] = []

    func setMediaList(_ list: [MediaData], device: MTLDevice) {
        self.mediaList = list
        self.mediaTextures = Array(repeating: nil, count: list.count)
        self.mediaInfos = list.map { media in
            return MediaInfo(position: float2(Float(media.position.x), Float(media.position.y)),
                             size: float2(Float(media.size.width), Float(media.size.height)))
        }

        for (index, media) in list.enumerated() {
            if media.type == .image {
                loadNetworkImage(urlString: media.src, device: device, index: index)
            } else if media.type == .video {
                loadNetworkVideo(urlString: media.src, device: device, index: index)
            }
        }
    }
    
    private func loadNetworkImage(urlString: String, device: MTLDevice, index: Int) {
        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }
            guard let data = data, error == nil, let image = UIImage(data: data) else {
                print("Failed to download image: \(error?.localizedDescription ?? "Unknown error")")
                return
            }

            let textureLoader = MTKTextureLoader(device: device)
            guard let cgImage = image.cgImage else {
                print("Failed to create CGImage")
                return
            }

            do {
                self.mediaTextures[index] = try textureLoader.newTexture(cgImage: cgImage, options: [
                    MTKTextureLoader.Option.SRGB: false,
                    MTKTextureLoader.Option.origin: MTKTextureLoader.Origin.topLeft
                ])
                updateTextureArrayIfNeeded()
                print("Network image texture loaded successfully at index \(index)")
            } catch {
                print("Failed to load texture: \(error)")
            }
        }.resume()
    }

    
    private var videoPlayer: AVPlayer?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var videoTimer: CADisplayLink?
    
    private func pixelBufferToMTLTexture(pixelBuffer: CVPixelBuffer, device: MTLDevice) -> MTLTexture? {
        let textureLoader = MTKTextureLoader(device: device)
        
        var texture: MTLTexture?
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)

        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            do {
                texture = try textureLoader.newTexture(cgImage: cgImage, options: [
                    .SRGB: false,
                    .origin: MTKTextureLoader.Origin.topLeft // Đảm bảo video không bị lật ngược
                ])
            } catch {
                print("Failed to load video frame as texture: \(error)")
            }
        }
        return texture
    }

    
    @objc private func updateVideoFrame(_ displayLink: CADisplayLink) {
        guard let videoOutput = videoOutput else { return }
        let currentTime = videoPlayer?.currentTime() ?? kCMTimeZero

        if videoOutput.hasNewPixelBuffer(forItemTime: currentTime),
           let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) {

            // Lấy index của video trong danh sách
            if let index = mediaList.firstIndex(where: { $0.type == .video }) {
                self.mediaTextures[index] = pixelBufferToMTLTexture(pixelBuffer: pixelBuffer, device: MetalDevice.sharedInstance.device)
                updateTextureArrayIfNeeded()
            }
        }
    }


    private func loadNetworkVideo(urlString: String, device: MTLDevice, index: Int) {
        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            return
        }

        let videoPlayer = AVPlayer(url: url)
        let playerItem = AVPlayerItem(url: url)

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: outputSettings)
        playerItem.add(videoOutput)

        videoPlayer.replaceCurrentItem(with: playerItem)
        videoPlayer.play()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let displayLink = CADisplayLink(target: self, selector: #selector(self.updateVideoFrame(_:)))
            displayLink.add(to: .main, forMode: RunLoopMode.commonModes)

            self.videoOutput = videoOutput
            self.videoPlayer = videoPlayer
            self.videoTimer = displayLink
        }
    }




    init(metalView: MTKView) {
        super.init()
        metalView.device = MetalDevice.sharedInstance.device
        metalView.colorPixelFormat = .rgba16Float
        metalView.framebufferOnly = true
        metalView.preferredFramesPerSecond = 60

        
        mtkView(metalView, drawableSizeWillChange: metalView.drawableSize)
    }
    

    func nextSlab() {
        currentIndex = (currentIndex + 1) % 4
    }
    

    func updateInteraction(points: FloatTuple?, in view: MTKView) {
        positions = points
    }

    private final func initSurfaces(width: Int, height: Int) {
        velocity = Slab(width: width, height: height, format: .rg16Float, name: "Velocity")
        density = Slab(width: width, height: height, format: .rg16Float, name: "Density")
        velocityDivergence = Slab(width: width, height: height, format: .rg16Float, name: "Divergence")
        velocityVorticity = Slab(width: width, height: height, format: .rg16Float, name: "Vorticity")
        pressure = Slab(width: width, height: height, format: .rg16Float, name: "Pressure")
        mediaSlab = Slab(width: width, height: height, name: "mediaSlab")
    }

    private final func initBuffers(width: Int, height: Int) {
        let bufferSize = MemoryLayout<StaticData>.stride
        let colors = (randomColor(), randomColor(), randomColor(), randomColor(), randomColor())

        var staticData = StaticData(positions: (float2(), float2(), float2(), float2(), float2()),
                                    impulses: (float2(), float2(), float2(), float2(), float2()),
                                    impulseScalar: float2(),
                                    offsets: float2(1.0/Float(width), 1.0/Float(height)),
                                    screenSize: float2(Float(width), Float(height)),
                                    inkRadius: 150 / Renderer.ScreenScaleAdjustment,
                                    colors: colors,
                                    countMedia: Int32(mediaInfos.count))

        uniformsBuffers.removeAll()
        for _ in 0..<Renderer.MaxBuffers {
            let buffer = MetalDevice.sharedInstance.device.makeBuffer(bytes: &staticData, length: bufferSize, options: .storageModeShared)!

            uniformsBuffers.append(buffer)
        }
    }

    private final func nextBuffer(positions: FloatTuple?, directions: FloatTuple?) -> MTLBuffer {
        let buffer = uniformsBuffers[avaliableBufferIndex]
        let bufferData = buffer.contents().bindMemory(to: StaticData.self, capacity: 1)
        bufferData.pointee.countMedia = Int32(mediaInfos.count)

        if let positions = positions, let directions = directions {
            let alteredPositions = positions / Renderer.ScreenScaleAdjustment
            let impulses = (positions - directions) / Renderer.ScreenScaleAdjustment
            let colors = (randomColor(), randomColor(), randomColor(), randomColor(), randomColor())

            bufferData.pointee.positions = alteredPositions
            bufferData.pointee.impulses = impulses
            bufferData.pointee.impulseScalar = float2(0.8, 0.0)
            bufferData.pointee.colors = colors
        }

        avaliableBufferIndex = (avaliableBufferIndex + 1) % Renderer.MaxBuffers
        return buffer
    }


    private final func drawSlab() -> Slab {
        switch currentIndex {
        case 1:
            return pressure
        case 2:
            return velocity
        case 3:
            return velocityVorticity
        default:
            return density
        }
    }
}

extension MTLTexture {
    func bufferBytes() -> UnsafeRawPointer {
        let pixelFormatSize = self.pixelFormatSize() // Lấy kích thước mỗi pixel (bytes)
        let byteCount = width * height * pixelFormatSize
        let pixelData = malloc(byteCount)!

        self.getBytes(pixelData,
                      bytesPerRow: width * pixelFormatSize,
                      from: MTLRegionMake2D(0, 0, width, height),
                      mipmapLevel: 0)

        return UnsafeRawPointer(pixelData)
    }

    // Hàm tính kích thước pixel dựa trên pixelFormat
    private func pixelFormatSize() -> Int {
        switch self.pixelFormat {
        case .rgba8Unorm, .rgba8Unorm_srgb, .bgra8Unorm, .bgra8Unorm_srgb:
            return 4 // 4 bytes per pixel (RGBA hoặc BGRA 8 bits mỗi channel)
        case .r8Unorm:
            return 1
        case .rg8Unorm:
            return 2
        case .rgba16Float:
            return 8
        default:
            fatalError("Unsupported pixel format: \(self.pixelFormat)")
        }
    }
}

//Fluid dynamics step methods
extension Renderer {
    private final func advect(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, velocity: Slab, source: Slab, destination: Slab) {
        advectShader.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: Renderer.indices.count, texture: destination.pong) { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertData, offset: 0, index: 0)
            commandEncoder.setFragmentTexture(velocity.ping, index: 0)
            commandEncoder.setFragmentTexture(source.ping, index: 1)

            commandEncoder.setFragmentBuffer(dataBuffer, offset: 0, index: 0)
        }

        destination.swap()
    }

    private final func applyForceVector(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, destination: Slab) {
        applyForceVectorShader.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: Renderer.indices.count, texture: destination.pong) { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertData, offset: 0, index: 0)
            commandEncoder.setFragmentTexture(destination.ping, index: 0)

            commandEncoder.setFragmentBuffer(dataBuffer, offset: 0, index: 0)
        }

        destination.swap()
    }

    private final func applyForceScalar(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, destination: Slab) {
        applyForceScalarShader.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: Renderer.indices.count, texture: destination.pong) { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertData, offset: 0, index: 0)
            commandEncoder.setFragmentTexture(destination.ping, index: 0)

            commandEncoder.setFragmentBuffer(dataBuffer, offset: 0, index: 0)
        }

        destination.swap()
    }

    private final func computeDivergence(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, velocity: Slab, destination: Slab) {
        divergenceShader.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: Renderer.indices.count, texture: destination.pong) { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertData, offset: 0, index: 0)
            commandEncoder.setFragmentTexture(velocity.ping, index: 0)

            commandEncoder.setFragmentBuffer(dataBuffer, offset: 0, index: 0)
        }

        destination.swap()
    }

    private final func computePressure(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, x: Slab, b: Slab, destination: Slab) {
        jacobiShader.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: Renderer.indices.count, texture: destination.pong) { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertData, offset: 0, index: 0)
            commandEncoder.setFragmentTexture(x.ping, index: 0)
            commandEncoder.setFragmentTexture(b.ping, index: 1)

            commandEncoder.setFragmentBuffer(dataBuffer, offset: 0, index: 0)
        }

        destination.swap()
    }

    private final func computeVorticity(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, velocity: Slab, destination: Slab) {
        vorticityShader.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: Renderer.indices.count, texture: destination.pong) { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertData, offset: 0, index: 0)
            commandEncoder.setFragmentTexture(velocity.ping, index: 0)

            commandEncoder.setFragmentBuffer(dataBuffer, offset: 0, index: 0)
        }

        destination.swap()
    }

    private final func computeVorticityConfinement(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, velocity: Slab, vorticity: Slab, destination: Slab) {
        vorticityConfinementShader.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: Renderer.indices.count, texture: destination.pong) { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertData, offset: 0, index: 0)
            commandEncoder.setFragmentTexture(velocity.ping, index: 0)
            commandEncoder.setFragmentTexture(vorticity.ping, index: 1)

            commandEncoder.setFragmentBuffer(dataBuffer, offset: 0, index: 0)
        }

        destination.swap()
    }

    private final func subtractGradient(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, p: Slab, w: Slab, destination: Slab) {
        gradientShader.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: Renderer.indices.count, texture: destination.pong) { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertData, offset: 0, index: 0)
            commandEncoder.setFragmentTexture(p.ping, index: 0)
            commandEncoder.setFragmentTexture(w.ping, index: 1)

            commandEncoder.setFragmentBuffer(dataBuffer, offset: 0, index: 0)
        }

        destination.swap()
    }
    
    private final func showMedia(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, destination: MTLTexture) {
        if !mediaTextures.isEmpty {
           for (index, mediaTexture) in mediaTextures.enumerated() {
               guard let texture = mediaTexture else { continue }
               renderScalarWithMedia.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: Renderer.indices.count, texture: destination) { commandEncoder in
                   commandEncoder.setVertexBuffer(self.vertData, offset: 0, index: 0)
                   commandEncoder.setFragmentTexture(self.drawSlab().ping, index: 0)
                   commandEncoder.setFragmentTexture(texture, index: 1) // Truyền texture hiện tại
                   commandEncoder.setFragmentBuffer(dataBuffer, offset: 0, index: 0)

                   var singleMediaInfo = mediaInfos[index]
                   commandEncoder.setFragmentBytes(&singleMediaInfo, length: MemoryLayout<MediaInfo>.size, index: 1) // Truyền vị trí và kích thước
               }
           }
       }
    }

    private final func scalarWithMedia(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, p: Slab, w: Slab, destination: Slab) {
        gradientShader.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: Renderer.indices.count, texture: destination.pong) { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertData, offset: 0, index: 0)
            commandEncoder.setFragmentTexture(p.ping, index: 0)
            commandEncoder.setFragmentTexture(w.ping, index: 1)

            commandEncoder.setFragmentBuffer(dataBuffer, offset: 0, index: 0)
        }

        destination.swap()
    }

    private final func render(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, destination: MTLTexture) {
        if currentIndex == 2 {
            renderVector.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: Renderer.indices.count, texture: destination) { (commandEncoder) in
                commandEncoder.setVertexBuffer(self.vertData, offset: 0, index: 0)
                commandEncoder.setFragmentTexture(self.drawSlab().ping, index: 0)
            }
        } else {
//            renderScalar.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: Renderer.indices.count, texture: destination) { (commandEncoder) in
//                commandEncoder.setVertexBuffer(self.vertData, offset: 0, index: 0)
//                commandEncoder.setFragmentTexture(self.drawSlab().ping, index: 0)
//                commandEncoder.setFragmentBuffer(dataBuffer, offset: 0, index: 0)
//            }
        }
    }
}

extension Renderer: MTKViewDelegate {
    func draw(in view: MTKView) {
        semaphore.wait()
        let commandBuffer = MetalDevice.sharedInstance.newCommandBuffer()

        let dataBuffer = nextBuffer(positions: positions, directions: directions)

        commandBuffer.addCompletedHandler({ (commandBuffer) in
            self.semaphore.signal()
        })
        advect(commandBuffer: commandBuffer, dataBuffer: dataBuffer, velocity: velocity, source: velocity, destination: velocity)
        advect(commandBuffer: commandBuffer, dataBuffer: dataBuffer, velocity: velocity, source: density, destination: density)

        if let _ = positions, let _ = directions {
            applyForceVector(commandBuffer: commandBuffer, dataBuffer: dataBuffer, destination: velocity)
            applyForceScalar(commandBuffer: commandBuffer, dataBuffer: dataBuffer, destination: density)
        }

        computeVorticity(commandBuffer: commandBuffer, dataBuffer: dataBuffer, velocity: velocity, destination: velocityVorticity)
        computeVorticityConfinement(commandBuffer: commandBuffer, dataBuffer: dataBuffer, velocity: velocity, vorticity: velocityVorticity, destination: velocity)

        computeDivergence(commandBuffer: commandBuffer, dataBuffer: dataBuffer, velocity: velocity, destination: velocityDivergence)

        for _ in 0..<40 {
            computePressure(commandBuffer: commandBuffer, dataBuffer: dataBuffer, x: pressure, b: velocityDivergence, destination: pressure)
        }

        subtractGradient(commandBuffer: commandBuffer, dataBuffer: dataBuffer, p: pressure, w: velocity, destination: velocity)

        if let drawable = view.currentDrawable {

            let nextTexture = drawable.texture
            showMedia(commandBuffer: commandBuffer, dataBuffer: dataBuffer, destination: nextTexture)

            render(commandBuffer: commandBuffer, dataBuffer: dataBuffer, destination: nextTexture)

            commandBuffer.present(drawable)
        }

        commandBuffer.commit()

        directions = positions
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let width = Int(Float(view.bounds.width) / Renderer.ScreenScaleAdjustment)
        let height = Int(Float(view.bounds.height) / Renderer.ScreenScaleAdjustment)

        initSurfaces(width: width, height: height)
        initBuffers(width: width, height: height)
    }
}
