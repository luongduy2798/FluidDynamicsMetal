//
//  Renderer.swift
//  FluidDynamicsMetal
//
//  Created by Andrei-Sergiu Pițiș on 20/12/2017.
//  Copyright © 2017 Andrei-Sergiu Pițiș. All rights reserved.
//

import MetalKit

typealias FloatTuple = (float2, float2, float2, float2, float2)

func / (rhs: FloatTuple, lhs: Float) -> FloatTuple {
    return FloatTuple(rhs.0 / lhs, rhs.1 / lhs, rhs.2 / lhs, rhs.3 / lhs, rhs.4 / lhs)
}

func - (rhs: FloatTuple, lhs: FloatTuple) -> FloatTuple {
    return FloatTuple(rhs.0 - lhs.0, rhs.1 - lhs.1, rhs.2 - lhs.2, rhs.3 - lhs.3, rhs.4 - lhs.4)
}

struct StaticData {
    var positions: FloatTuple
    var impulses: FloatTuple

    var impulseScalar: float2
    var offsets: float2
    
    var screenSize: float2
    var inkRadius: simd_float1
}

struct VertexData {
    let position: float2
    let texCoord: float2
}

class Renderer: NSObject {
    static let MaxBuffers = 3

    //Adjust this to reduce or increase the size of the slab textures. Reasonable values are in the range [0.5, 3.0]
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
    private let copyShader = RenderShader(fragmentShader: "copyShader", vertexShader: "baseVertexShader")
    private let clearShader = RenderShader(fragmentShader: "clearShader", vertexShader: "baseVertexShader")
    private let colorShader = RenderShader(fragmentShader: "colorShader", vertexShader: "baseVertexShader")
    private let displayShader = RenderShader(fragmentShader: "displayShader", vertexShader: "baseVertexShader")
    private let splatShader = RenderShader(fragmentShader: "splatShader", vertexShader: "baseVertexShader")
    private let advectionShader = RenderShader(fragmentShader: "advectionShader", vertexShader: "baseVertexShader")
    private let divergenceShader = RenderShader(fragmentShader: "divergenceShader", vertexShader: "baseVertexShader")
    private let curlShader = RenderShader(fragmentShader: "curlShader", vertexShader: "baseVertexShader")
    private let vorticityShader = RenderShader(fragmentShader: "vorticityShader", vertexShader: "baseVertexShader")
    private let pressureShader = RenderShader(fragmentShader: "pressureShader", vertexShader: "baseVertexShader")
    private let gradientSubtractShader = RenderShader(fragmentShader: "gradientSubtractShader", vertexShader: "baseVertexShader")

    //Touch or Mouse positions
    private var positions: FloatTuple?
    private var directions: FloatTuple?

    //Surfaces
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

    init(metalView: MTKView) {
        super.init()
        metalView.device = MetalDevice.sharedInstance.device
        metalView.colorPixelFormat = .bgra8Unorm
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
    }

    private final func initBuffers(width: Int, height: Int) {
        let bufferSize = MemoryLayout<StaticData>.stride

        var staticData = StaticData(positions: (float2(), float2(), float2(), float2(), float2()),
                                    impulses: (float2(), float2(), float2(), float2(), float2()),
                                    impulseScalar: float2(),
                                    offsets: float2(1.0/Float(width), 1.0/Float(height)),
                                    screenSize: float2(Float(width), Float(height)),
                                    inkRadius: 150 / Renderer.ScreenScaleAdjustment)

        uniformsBuffers.removeAll()
        for _ in 0..<Renderer.MaxBuffers {
            let buffer = MetalDevice.sharedInstance.device.makeBuffer(bytes: &staticData, length: bufferSize, options: .storageModeShared)!

            uniformsBuffers.append(buffer)
        }
    }

    private final func nextBuffer(positions: FloatTuple?, directions: FloatTuple?) -> MTLBuffer {
        let buffer = uniformsBuffers[avaliableBufferIndex]

        let bufferData = buffer.contents().bindMemory(to: StaticData.self, capacity: 1)

        if let positions = positions, let directions = directions {
            let alteredPositions = positions / Renderer.ScreenScaleAdjustment
            let impulses = (positions - directions) / Renderer.ScreenScaleAdjustment

            bufferData.pointee.positions = alteredPositions
            bufferData.pointee.impulses = impulses
            bufferData.pointee.impulseScalar = float2(0.8, 0.0)
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

//Fluid dynamics step methods
extension Renderer {
    private final func advect(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, velocity: Slab, source: Slab, destination: Slab) {
        advectionShader.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: Renderer.indices.count, texture: destination.pong) { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertData, offset: 0, index: 0)
            commandEncoder.setFragmentTexture(velocity.ping, index: 0)
            commandEncoder.setFragmentTexture(source.ping, index: 1)
            commandEncoder.setFragmentBuffer(dataBuffer, offset: 0, index: 0)
        }
        destination.swap()
    }

    private final func applySplat(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, destination: Slab) {
        splatShader.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: Renderer.indices.count, texture: destination.pong) { (commandEncoder) in
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

    private final func computeCurl(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, velocity: Slab, destination: Slab) {
        curlShader.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: Renderer.indices.count, texture: destination.pong) { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertData, offset: 0, index: 0)
            commandEncoder.setFragmentTexture(velocity.ping, index: 0)
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

    private final func computePressure(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, x: Slab, b: Slab, destination: Slab) {
        pressureShader.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: Renderer.indices.count, texture: destination.pong) { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertData, offset: 0, index: 0)
            commandEncoder.setFragmentTexture(x.ping, index: 0)
            commandEncoder.setFragmentTexture(b.ping, index: 1)
            commandEncoder.setFragmentBuffer(dataBuffer, offset: 0, index: 0)
        }
        destination.swap()
    }

    private final func subtractGradient(commandBuffer: MTLCommandBuffer, dataBuffer: MTLBuffer, p: Slab, w: Slab, destination: Slab) {
        gradientSubtractShader.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: Renderer.indices.count, texture: destination.pong) { (commandEncoder) in
            commandEncoder.setVertexBuffer(self.vertData, offset: 0, index: 0)
            commandEncoder.setFragmentTexture(p.ping, index: 0)
            commandEncoder.setFragmentTexture(w.ping, index: 1)
            commandEncoder.setFragmentBuffer(dataBuffer, offset: 0, index: 0)
        }
        destination.swap()
    }
    
    private final func render(commandBuffer: MTLCommandBuffer, destination: MTLTexture) {
       displayShader.calculateWithCommandBuffer(buffer: commandBuffer, indices: indexData, count: Renderer.indices.count, texture: destination) { (commandEncoder) in
           commandEncoder.setVertexBuffer(self.vertData, offset: 0, index: 0)
           commandEncoder.setFragmentTexture(self.density.ping, index: 0)
       }
    }
}

// Fluid dynamics step methods
extension Renderer: MTKViewDelegate {
    func draw(in view: MTKView) {
        semaphore.wait()
        let commandBuffer = MetalDevice.sharedInstance.newCommandBuffer()
        let dataBuffer = nextBuffer(positions: positions, directions: directions)

        commandBuffer.addCompletedHandler { _ in
            self.semaphore.signal()
        }

        computeCurl(commandBuffer: commandBuffer, dataBuffer: dataBuffer, velocity: velocity, destination: velocityVorticity)
        computeVorticity(commandBuffer: commandBuffer, dataBuffer: dataBuffer, velocity: velocity, destination: velocity)
        computeDivergence(commandBuffer: commandBuffer, dataBuffer: dataBuffer, velocity: velocity, destination: velocityDivergence)

        for _ in 0..<40 {
            computePressure(commandBuffer: commandBuffer, dataBuffer: dataBuffer, x: pressure, b: velocityDivergence, destination: pressure)
        }

        subtractGradient(commandBuffer: commandBuffer, dataBuffer: dataBuffer, p: pressure, w: velocity, destination: velocity)

        advect(commandBuffer: commandBuffer, dataBuffer: dataBuffer, velocity: velocity, source: velocity, destination: velocity)
        advect(commandBuffer: commandBuffer, dataBuffer: dataBuffer, velocity: velocity, source: density, destination: density)

        if let _ = positions, let _ = directions {
            applySplat(commandBuffer: commandBuffer, dataBuffer: dataBuffer, destination: density)
        }

        if let drawable = view.currentDrawable {
            let nextTexture = drawable.texture
            render(commandBuffer: commandBuffer, destination: nextTexture)
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
