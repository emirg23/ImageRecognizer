import SwiftUI

struct RealtimeBoundingBoxView: View {
    let object: RealtimeView.DetectedObject
    
    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            
            let box = object.boundingBox
            let flippedY = screenHeight - box.origin.y - box.height
            
            let x = box.origin.x
            let y = flippedY
            let width = box.width
            let height = box.height
            
            ZStack(alignment: .topLeading) {

                Rectangle()
                    .stroke(Color.red.opacity(0.5), lineWidth: 1.5)
                    .background(Color.red.opacity(0.05))
                    .frame(width: width, height: height)
                    .position(x: x + width / 2, y: y + height / 2)
                
                Text("\(object.label) (\(Int(object.confidence * 100))%)")
                    .font(.caption)
                    .padding(4)
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(5)
                    .position(x: x + width/2, y: y - 10)
            }
        }
    }
}
