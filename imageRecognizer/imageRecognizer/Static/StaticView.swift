import SwiftUI
import Vision
import PhotosUI

struct StaticView: View {
    @Binding var realtime: Bool
    @State private var predictions: [VNRecognizedObjectObservation] = []
    @State private var imageRect: CGRect = .zero
    @State private var selectedImage: UIImage? = nil
    @State private var photoItem: PhotosPickerItem?
    @State var loading = false
    @State var photoWidth: CGFloat = 0
    @State var photoHeight: CGFloat = 0
    @State private var isCameraPresented = false
    @State var depthOpacity = 0.75

    var body: some View {
        VStack {
            ZStack {
                HStack { // for a symmetric look
                    Spacer()
                    Button {
                        isCameraPresented = true
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "camera")
                            Text("Take")
                        }
                        .padding()
                    }
                    .sheet(isPresented: $isCameraPresented) {
                        CameraPicker(image: $selectedImage) {
                            if let image = $0 {
                                self.selectedImage = image
                                processImage(image)
                            }
                        }
                    }
                    Spacer()
                }
                
                HStack {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        VStack(spacing: 3) {
                            Image(systemName: "photo")
                            Text("Select")
                        }
                        .padding()
                    }
                    Spacer()
                    Button {
                        realtime = true
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                            Text("Realtime")
                        }
                        .padding()
                    }
                }
            }
            .background(.gray.opacity(0.15))
            .cornerRadius(20)
            .foregroundStyle(.primary)
            .onChange(of: photoItem) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        let fixedImage = uiImage.fixedOrientation
                        self.selectedImage = fixedImage
                        processImage(fixedImage)
                    }
                }
            }
            ScrollView {
                VStack {
                    GeometryReader { geometry in
                        ZStack(alignment: .topLeading) {
                            if let uiImage = selectedImage {
                                
                                // base image
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFit()
                                    .background(
                                        GeometryReader { imageGeometry in
                                            Color.clear
                                                .onAppear {
                                                    self.imageRect = imageGeometry.frame(in: .local)
                                                    photoWidth = imageGeometry.size.width
                                                    photoHeight = imageGeometry.size.height
                                                }
                                                .onChange(of: imageGeometry.size) { _ in
                                                    self.imageRect = imageGeometry.frame(in: .local)
                                                    photoWidth = imageGeometry.size.width
                                                    photoHeight = imageGeometry.size.height
                                                }
                                        }
                                    )
                                
                                if loading {
                                    Rectangle()
                                        .fill(Color.black.opacity(0.5))
                                        .frame(width: geometry.size.width, height: imageRect.height)
                                        .overlay(
                                            ProgressView()
                                                .tint(.white)
                                                .scaleEffect(1.5)
                                        )
                                } else {
                                    // depth image
                                    StaticImageDepthView(photoWidth: $photoWidth, photoHeight: $photoHeight, image: $selectedImage)
                                        .opacity(depthOpacity)
                                    
                                    // YOLO bounding boxes
                                    BoundingBoxView(predictions: predictions, imageRect: imageRect)
                                    VStack {
                                        HStack {
                                            Text("Depth Opacity")
                                            Slider(value: $depthOpacity, in: 0...1)
                                        }
                                        .padding()
                                        .background(Color(.systemGray2).opacity(0.5))
                                        .cornerRadius(10)
                                        

                                        VStack(alignment: .leading) {
                                            Text("Total \(predictions.count) prediction\(predictions.count <= 1 ? "" : "s")")
                                                .padding(.top)
                                                .font(.system(size: 20))
                                            
                                            ScrollView(.horizontal) {
                                                HStack {
                                                    ForEach(predictions, id: \.self) { prediction in
                                                        if let topLabel = prediction.labels.first {
                                                            Text(topLabel.identifier)
                                                                .padding()
                                                                .background(Color.gray.opacity(0.2))
                                                                .cornerRadius(8)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        .padding()
                                        
                                    }
                                    .offset(y: photoHeight * 1.1)
                                }
                            } else {
                                VStack {
                                    Text("No image selected")
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .padding(.vertical)
                                        .background(Color.gray.opacity(0.2))
                                    
                                    Text("Tap 'Select' or 'Take' to choose an image and start scanning.")
                                         .font(.subheadline)
                                         .foregroundColor(.gray)
                                         .multilineTextAlignment(.center)
                                         .padding(.top)
                                }
                            }
                        }
                    }
                }
                .frame(height: photoHeight + 300)
            }
        }
        .padding()
    }
    
    func processImage(_ image: UIImage) {
        self.loading = true
        recognizeObjects(in: image)
    }
    
    func recognizeObjects(in image: UIImage) {
        guard let cgImage = image.cgImage else {
            print("Failed to get CGImage.")
            return
        }

        guard let coreMLModel = try? yolo11s(configuration: MLModelConfiguration()).model,
              let visionModel = try? VNCoreMLModel(for: coreMLModel) else {
            print("Model loading failed.")
            DispatchQueue.main.async {
                self.loading = false
            }
            return
        }
        
        let request = VNCoreMLRequest(model: visionModel) { request, _ in
            if let results = request.results as? [VNRecognizedObjectObservation] {
                DispatchQueue.main.async {
                    self.predictions = results
                    withAnimation(.easeInOut(duration: 0.25)) {
                        self.loading = false
                    }
                }
            }
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("Failed to perform detection: \(error)")
                DispatchQueue.main.async {
                    self.loading = false
                }
            }
        }
    }
}

#Preview {
    BindingPage()
}
