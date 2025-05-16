import UIKit
import CoreML
import RealityFoundation

extension UIImage {
    var fixedOrientation: UIImage {
        if imageOrientation == .up {
            return self
        }

        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalizedImage ?? self
    }
    
    func resize(to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        draw(in: CGRect(origin: .zero, size: size))
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result
    }

    func toMLMultiArray() -> MLMultiArray? {
        guard let cgImage = self.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height

        guard let pixelData = cgImage.dataProvider?.data else { return nil }
        let bytes = Data(referencing: pixelData)

        do {
            let array = try MLMultiArray(shape: [3, NSNumber(value: height), NSNumber(value: width)], dataType: .float32)

            func indexForChannel(_ c: Int, y: Int, x: Int) -> Int {
                return c * height * width + y * width + x
            }

            for y in 0..<height {
                for x in 0..<width {
                    let pixelIndex = (y * width + x) * 4
                    let r = Float(bytes[pixelIndex]) / 255.0
                    let g = Float(bytes[pixelIndex + 1]) / 255.0
                    let b = Float(bytes[pixelIndex + 2]) / 255.0

                    array[indexForChannel(0, y: y, x: x)] = NSNumber(value: r) // red
                    array[indexForChannel(1, y: y, x: x)] = NSNumber(value: g) // green
                    array[indexForChannel(2, y: y, x: x)] = NSNumber(value: b) // blue
                }
            }

            return array
        } catch {
            print("Error creating MLMultiArray: \(error)")
            return nil
        }
    }
}

extension MLMultiArray {
    func toUIImage() -> UIImage? {
        let shape = self.shape.map { $0.intValue }
        guard shape.count == 2 else { return nil }

        let height = shape[0]
        let width = shape[1]

        let pointer = UnsafeMutablePointer<Float32>(OpaquePointer(self.dataPointer))
        let count = width * height
        let buffer = UnsafeBufferPointer(start: pointer, count: count)

        let minValue = buffer.min() ?? 0
        let maxValue = buffer.max() ?? 1
        let normalized = buffer.map { UInt8(255.0 * (($0 - minValue) / (maxValue - minValue))) }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)

        guard let providerRef = CGDataProvider(data: NSData(bytes: normalized, length: count)) else { return nil }

        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: providerRef,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }

        return UIImage(cgImage: cgImage)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

extension simd_float4x4 {
    var translation: SIMD3<Float> {
        return SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}
