import SwiftUI
import CoreML

struct StaticImageDepthView: View {
    @State private var depthImage: UIImage? = nil
    @Binding var photoWidth: CGFloat
    @Binding var photoHeight: CGFloat
    @Binding var image: UIImage?
    
    var body: some View {
        VStack {
            if let img = depthImage {
                Image(uiImage: img)
                    .resizable()
                    .frame(width: photoWidth, height: photoHeight)
                    .onChange(of: image) {
                        if let cgImage = image?.cgImage {
                            runMidasModel(with: cgImage)
                        } else {
                            print("Couldn't load image")
                        }
                    }
            } else {
                ProgressView()
                    .frame(width: photoWidth, height: photoHeight)
                    .onAppear() {
                        if let cgImage = image?.cgImage {
                            runMidasModel(with: cgImage)
                        } else {
                            print("Couldn't load image")
                        }
                    }
                
            }
        }
    }
    
    func runMidasModel(with cgImage: CGImage) {
        // resize for model input
        let targetSize = CGSize(width: 256, height: 256)
        guard let resizedCGImage = UIImage(cgImage: cgImage).resize(to: targetSize)?.cgImage else {
            print("Failed to resize image")
            return
        }
        
        guard let pixelBuffer = cgImageToPixelBuffer(resizedCGImage, width: Int(targetSize.width), height: Int(targetSize.height)) else {
            print("Failed to convert to CVPixelBuffer")
            return
        }
        
        do {
            let model = try midas_small(configuration: MLModelConfiguration())
            let input = midas_smallInput(x_1: pixelBuffer)
            let output = try model.prediction(input: input)
            
            let depthMap = output.var_1438
            print("Depth map shape: \(depthMap.shape)")
            
            if let depthUIImage = convertDepthMapToUIImage(depthMap: depthMap) {
                self.depthImage = depthUIImage
            }
        } catch {
            print("Error running model: \(error)")
        }
    }
    
    func cgImageToPixelBuffer(_ image: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs,
            &pixelBuffer
        )
        
        guard let buffer = pixelBuffer else { return nil }
        
        let ciImage = CIImage(cgImage: image)
        let context = CIContext()
        context.render(ciImage, to: buffer)
        return buffer
    }
    
    func convertDepthMapToUIImage(depthMap: MLMultiArray) -> UIImage? {
        
        let shape = depthMap.shape.map { $0.intValue }
        guard shape.count == 3, let height = shape[safe: 1], let width = shape[safe: 2] else {
            print("Invalid MLMultiArray shape")
            return nil
        }
        
        let depthPointer = UnsafeMutablePointer<Float32>(OpaquePointer(depthMap.dataPointer))
        let totalElements = height * width
        
        var pixels = [UInt8](repeating: 0, count: totalElements * 4)
        
        let depthBuffer = UnsafeBufferPointer(start: depthPointer, count: totalElements)
        
        let minDepth = depthBuffer.min() ?? 0
        let maxDepth = depthBuffer.max() ?? 1
        
        let depthRange = maxDepth - minDepth
        
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let depthValue = depthBuffer[index]
                
                let normalizedDepth = depthRange > 0 ?
                UInt8(min(max((depthValue - minDepth) / depthRange, 0), 1) * 255) : 0
                
                let pixelIndex = (y * width + x) * 4
                
                pixels[pixelIndex] = normalizedDepth
                pixels[pixelIndex + 1] = normalizedDepth
                pixels[pixelIndex + 2] = normalizedDepth
                pixels[pixelIndex + 3] = 255
            }
        }
        
        let bitsPerComponent = 8
        let bitsPerPixel = 32
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let data = CFDataCreate(nil, pixels, pixels.count),
              let provider = CGDataProvider(data: data),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bitsPerPixel: bitsPerPixel,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            print("Failed to create CGImage")
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
}
