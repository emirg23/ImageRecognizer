import SwiftUI
import RealityFoundation
import ARKit
import RealityKit

struct ARViewContainer: UIViewRepresentable {
    @Binding var distanceText: String
    @Binding var detectionStatus: RealtimeView.DetectionStatus
    @Binding var isResetting: Bool
    @Binding var detectedObjects: [RealtimeView.DetectedObject]
    @Binding var detectingObject: Bool
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        arView.session.run(config)
        arView.session.delegate = context.coordinator
        
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.session = arView.session
        coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coachingOverlay.goal = .horizontalPlane
        arView.addSubview(coachingOverlay)
        
        let reticleView = UIView(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        reticleView.backgroundColor = .clear
        reticleView.layer.borderWidth = 2
        reticleView.layer.borderColor = UIColor.white.cgColor
        reticleView.layer.cornerRadius = 10
        reticleView.center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        reticleView.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin,
                                        .flexibleLeftMargin, .flexibleRightMargin]
        arView.addSubview(reticleView)
        
        context.coordinator.arView = arView
        context.coordinator.setupVisionModel()
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        if isResetting {
            // reset the AR session
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal, .vertical]
            uiView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
            
            context.coordinator.resetState()
            
            DispatchQueue.main.async {
                distanceText = "Calculating distance..."
                detectionStatus = .searching
                detectedObjects = []
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(
            distanceText: $distanceText,
            detectionStatus: $detectionStatus,
            detectedObjects: $detectedObjects,
            detectingObject: $detectingObject
        )
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        var arView: ARView?
        @Binding var distanceText: String
        @Binding var detectionStatus: RealtimeView.DetectionStatus
        @Binding var detectedObjects: [RealtimeView.DetectedObject]
        @Binding var detectingObject: Bool
        
        var labelEntity: ModelEntity?
        private var lastMeasurementTime: Date = Date()
        private let measurementTimeout: TimeInterval = 2.0
        private var recentMeasurements: [Float] = []
        private let maxHistoryCount = 5
        
        private var visionModel: VNCoreMLModel?
        private var lastYoloDetectionTime = Date()
        private let yoloDetectionInterval: TimeInterval = 0.5
        
        init(distanceText: Binding<String>,
             detectionStatus: Binding<RealtimeView.DetectionStatus>,
             detectedObjects: Binding<[RealtimeView.DetectedObject]>,
             detectingObject: Binding<Bool>) {
            _distanceText = distanceText
            _detectionStatus = detectionStatus
            _detectedObjects = detectedObjects
            _detectingObject = detectingObject
            
            super.init()
        }
        
        func setupVisionModel() {
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let coreMLModel = try yolo11s(configuration: MLModelConfiguration()).model
                    let visionModel = try VNCoreMLModel(for: coreMLModel)
                    DispatchQueue.main.async {
                        self.visionModel = visionModel
                        print("YOLOv11 model loaded successfully")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.visionModel = nil
                    }
                }
            }
        }
        
        func resetState() {
            labelEntity = nil
            lastMeasurementTime = Date()
            recentMeasurements = []
            DispatchQueue.main.async {
                self.detectedObjects = []
            }
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard let arView = arView else { return }
            
            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            
            if let query = arView.makeRaycastQuery(from: center, allowing: .estimatedPlane, alignment: .any) {
                if let result = arView.session.raycast(query).first {
                    processMeasurementResult(result, arView: arView)
                } else if let widerQuery = arView.makeRaycastQuery(from: center, allowing: .existingPlaneInfinite, alignment: .any),
                          let widerResult = arView.session.raycast(widerQuery).first {
                    processMeasurementResult(widerResult, arView: arView)
                } else {
                    handleNoResult()
                }
            } else {
                handleNoResult()
            }
            
            let currentTime = Date()
            if currentTime.timeIntervalSince(lastYoloDetectionTime) >= yoloDetectionInterval && detectingObject {
                    lastYoloDetectionTime = currentTime
                    performObjectDetection(on: frame)
            }
        }
        
        private func performObjectDetection(on frame: ARFrame) {
            guard let visionModel = self.visionModel else { return }
            
            let pixelBuffer = frame.capturedImage
            let imageRequestHandler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .right
            )
            
            let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("YOLO detection error: \(error)")
                    return
                }
                
                self.processDetectionResults(request)
            }
            
            request.usesCPUOnly = false
            
            do {
                try imageRequestHandler.perform([request])
            } catch {
                print("Failed to perform YOLO detection: \(error)")
            }
        }
        
        private func processDetectionResults(_ request: VNRequest) {
            guard let results = request.results as? [VNRecognizedObjectObservation],
                  let arView = self.arView else { return }
            
            let detectedItems = results.map { observation -> RealtimeView.DetectedObject in

                let identifier: String
                let confidence: Float
                
                if let firstLabel = observation.labels.first {
                    identifier = firstLabel.identifier
                    confidence = firstLabel.confidence
                } else {
                    identifier = "Unknown"
                    confidence = 0
                }
                
                let boundingBox = VNImageRectForNormalizedRect(
                    observation.boundingBox,
                    Int(arView.bounds.width),
                    Int(arView.bounds.height)
                )
                
                return RealtimeView.DetectedObject(
                    label: identifier,
                    confidence: confidence,
                    boundingBox: boundingBox
                )
            }
            
            let highConfidenceItems = detectedItems.filter { $0.confidence > 0.5 }
            
            DispatchQueue.main.async {
                self.detectedObjects = highConfidenceItems
            }
        }
        
        private func processMeasurementResult(_ result: ARRaycastResult, arView: ARView) {

            lastMeasurementTime = Date()
            
            let worldTransform = result.worldTransform
            let translation = SIMD3<Float>(worldTransform.columns.3.x, worldTransform.columns.3.y, worldTransform.columns.3.z)
            let cameraPosition = arView.cameraTransform.translation
            let distanceVector = translation - cameraPosition
            let distance = simd_length(distanceVector)
            
            recentMeasurements.append(distance)
            if recentMeasurements.count > maxHistoryCount {
                recentMeasurements.removeFirst()
            }
            
            let avgDistance = recentMeasurements.reduce(0, +) / Float(recentMeasurements.count)
            let cmDistance = Int(avgDistance * 100)
            
            DispatchQueue.main.async {
                self.distanceText = "\(cmDistance) cm away"
                self.detectionStatus = .found
            }
            
            updateOrCreateLabel(at: translation, with: "\(cmDistance) cm", in: arView)
        }
        
        private func handleNoResult() {

            let timeElapsed = Date().timeIntervalSince(lastMeasurementTime)
            
            DispatchQueue.main.async {
                if timeElapsed < 0.5 {
                } else if timeElapsed < self.measurementTimeout {
                    self.distanceText = "Searching for surface..."
                    self.detectionStatus = .searching
                } else {
                    self.distanceText = "Object not found. Point at a flat surface."
                    self.detectionStatus = .notFound
                }
            }
        }
        
        private func updateOrCreateLabel(at position: SIMD3<Float>, with text: String, in arView: ARView) {
            if self.labelEntity == nil {

                let mesh = MeshResource.generateText(
                    text,
                    extrusionDepth: 0.01,
                    font: .systemFont(ofSize: 0.1),
                    containerFrame: .zero,
                    alignment: .center,
                    lineBreakMode: .byWordWrapping
                )
                
                let material = SimpleMaterial(color: .blue, isMetallic: false)
                let modelEntity = ModelEntity(mesh: mesh, materials: [material])
                
                let anchor = AnchorEntity(world: position)
                anchor.addChild(modelEntity)
                
                arView.scene.addAnchor(anchor)
                
                self.labelEntity = modelEntity
            } else {
                if let mesh = try? MeshResource.generateText(
                    text,
                    extrusionDepth: 0.01,
                    font: .systemFont(ofSize: 0.1),
                    containerFrame: .zero,
                    alignment: .center,
                    lineBreakMode: .byWordWrapping
                ) {
                    self.labelEntity?.model?.mesh = mesh
                    self.labelEntity?.position = position
                }
            }
        }
    }
}
