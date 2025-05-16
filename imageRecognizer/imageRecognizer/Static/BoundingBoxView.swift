import SwiftUI
import Vision

struct BoundingBoxView: View {
    let predictions: [VNRecognizedObjectObservation]
    let imageRect: CGRect
    let confidenceThreshold: Float = 0.5
    
    var body: some View {
        ZStack {
            ForEach(predictions.filter { $0.confidence > confidenceThreshold }, id: \.uuid) { prediction in
                if let topLabel = prediction.labels.first {
                    let boxRect = calculateBoxRect(for: prediction)
                    
                    ZStack(alignment: .top) {
                        Rectangle()
                            .stroke(Color.yellow, lineWidth: 3)
                            .background(Color.yellow.opacity(0.1))
                            .frame(width: boxRect.width, height: boxRect.height)
                        
                        Text("\(topLabel.identifier) \(String(format: "%.2f", prediction.confidence))")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                            .offset(y: -20)
                    }
                    .position(x: boxRect.midX, y: boxRect.midY)
                }
            }
        }
    }
    
    private func calculateBoxRect(for prediction: VNRecognizedObjectObservation) -> CGRect {
        let boundingBox = prediction.boundingBox
        
        let x = boundingBox.origin.x * imageRect.width + imageRect.origin.x
        let y = (1 - boundingBox.origin.y - boundingBox.height) * imageRect.height + imageRect.origin.y
        let width = boundingBox.width * imageRect.width
        let height = boundingBox.height * imageRect.height
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
