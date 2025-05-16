import SwiftUI
import ARKit
import RealityKit

struct RealtimeView: View {
    @Binding var realtime: Bool
    @State private var distanceText = "Calculating distance..."
    @State private var detectionStatus: DetectionStatus = .searching
    @State private var isResetting = false
    @State private var detectedObjects: [DetectedObject] = []
    @State private var detectingObject = false
    
    enum DetectionStatus {
        case searching, found, notFound
    }
    
    struct DetectedObject: Identifiable {
        let id = UUID()
        let label: String
        let confidence: Float
        let boundingBox: CGRect
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ARViewContainer(
                distanceText: $distanceText,
                detectionStatus: $detectionStatus,
                isResetting: $isResetting,
                detectedObjects: $detectedObjects,
                detectingObject: $detectingObject
            )
            .edgesIgnoringSafeArea(.all)
            
            // object detection overlay
            ZStack(alignment: .topLeading) {
                ForEach(detectedObjects) { object in
                    RealtimeBoundingBoxView(object: object)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            VStack {
                HStack {
                    Button {
                        realtime = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 25, weight: .light))
                            .padding(8)
                    }
                    .padding(.leading, 9)
                    .foregroundStyle(.white)
                    
                    Spacer()
                    
                    Button {
                        detectingObject.toggle()
                        detectedObjects = []
                    } label: {
                        ZStack {
                            Text("YOLO")
                                .font(.system(size: 17, weight: .bold))
                            if !detectingObject {
                                Color.white
                                    .frame(width: 40, height: 2)
                                    .rotationEffect(Angle(degrees: -12.5))
                            }
                        }
                        .padding(5)
                        .background(Color(.systemGray))
                        .cornerRadius(10)
                        .padding()
                    }
                    .foregroundStyle(.white)
                }
                
                Spacer()
                
                HStack {
                    Button {
                        isResetting = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isResetting = false
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.title)
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .foregroundColor(.white)
                            .clipShape(Circle())
                    }
                    .padding()
                    
                    Spacer()
                    
                    Text(distanceText)
                        .padding()
                        .background(backgroundColorForStatus)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding()
                }
            }
        }
    }
    
    var backgroundColorForStatus: Color {
        switch detectionStatus {
        case .searching:
            return Color.orange.opacity(0.7)
        case .found:
            return Color.green.opacity(0.7)
        case .notFound:
            return Color.red.opacity(0.7)
        }
    }
}

#Preview {
    RealtimeView(realtime: .constant(true))
}
