import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct LoggedInView: View {

    @EnvironmentObject var auth: AuthViewModel

    @State private var selectedImage: UIImage?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var plateResult: String = ""

    @State private var showCamera = false
    @State private var showImagePicker = false

    @State private var navigateToResultPage = false
    @State private var showFileImporter = false
    
    @State private var displayedText = ""
    
    private let fullText = "Okay, first I will have to check the car plate number. Please upload a photo of the car plate."
    
    @State private var showButtons = false
    @State private var localErrorMessage: String? = nil
    
    func sendToANPRServer(image: UIImage) {
        // REPLACE THIS IP ADDRESS
//        guard let url = URL(string: "http://127.0.0.1:8000/detect") else { return }
        guard let url = URL(string: "http://10.10.10.53:8000/detect") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let imageData = image.jpegData(compressionQuality: 0.8)!

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        URLSession.shared.uploadTask(with: request, from: body) { data, _, error in

            guard let data = data,
                  let response = try? JSONDecoder().decode([String: String].self, from: data),
                  let rawPlate = response["plate"] else {
                DispatchQueue.main.async {
                    self.localErrorMessage = "Could not reach the server. Please try again."
                }
                return
            }

            let trimmed = rawPlate.trimmingCharacters(in: .whitespacesAndNewlines)

            guard trimmed != "[]" && !trimmed.isEmpty else {
                DispatchQueue.main.async {
                    self.localErrorMessage = "No licence plate detected. Please try a clearer photo."
                }
                return
            }

            let plate: String
            if trimmed.contains("text='") {
                let components = trimmed.components(separatedBy: "text='")
                plate = components[1].components(separatedBy: "'").first ?? trimmed
            } else {
                plate = trimmed
            }

            DispatchQueue.main.async {
                self.plateResult = plate
                self.navigateToResultPage = true
            }

        }.resume()
    }
    
    var body: some View {
        VStack(spacing: 25) {

            HStack {
                Text("Welcome")
                    .font(.largeTitle)
                    .bold()

                Spacer()

                Button("Logout") {
                    displayedText = ""
                    auth.didShowIntroAnimation = false
                    auth.logout()
                    localErrorMessage = nil
                    selectedImage = nil
                    plateResult = ""
                }
                .foregroundColor(.red)
            }
            .padding(.horizontal)

            Text(displayedText)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let selectedImage = selectedImage {

                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .cornerRadius(12)
                    .padding(.horizontal)

                HStack(spacing: 20) {

                    Button("Choose Another Photo") {
                        self.selectedImage = nil
                        self.localErrorMessage = nil
                    }
                    .buttonStyle(.bordered)

                    Button("Confirm") {
                        sendToANPRServer(image: selectedImage)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {

                VStack(spacing: 15) {

                    Button("Take Photo") {

                        DispatchQueue.main.async {

                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                showCamera = true
                                localErrorMessage = nil
                            } else {
                                localErrorMessage = "Camera is not available on this device."
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    PhotosPicker(
                        selection: $selectedPhotoItem,
                        matching: .images
                    ) {
                        Text("Choose From Library")
                    }
                    .buttonStyle(.bordered)

                    Button("Upload JPG/PNG File") {
                        showFileImporter = true
                    }
                    .buttonStyle(.bordered)
                }
                .opacity(showButtons ? 1 : 0)
                .fileImporter(
                    isPresented: $showFileImporter,
                    allowedContentTypes: [.image],
                    allowsMultipleSelection: false
                ) { result in

                    switch result {

                    case .success(let urls):

                        guard let url = urls.first else { return }

                        if let data = try? Data(contentsOf: url),
                           let uiImage = UIImage(data: data) {
                            selectedImage = uiImage
                        }

                    case .failure(let error):
                        localErrorMessage = error.localizedDescription
                    }
                }
            }
            if let localErrorMessage = localErrorMessage {
                Text(localErrorMessage)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Spacer()
        }
        .padding(.top)
        .onAppear {

            displayedText = ""
            showButtons = false

            guard auth.didShowIntroAnimation == false else {
                showButtons = true
                displayedText = fullText
                return
            }

            auth.didShowIntroAnimation = true

            Task {
                for char in fullText {
                    try? await Task.sleep(for: .milliseconds(25)) // <-- speed control here
                    await MainActor.run {
                        displayedText.append(char)
                    }
                }

                await MainActor.run {
                    withAnimation(.easeIn(duration: 0.4)) {
                        showButtons = true
                    }
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera) { image in
                self.selectedImage = image
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem = newItem else { return }

            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        self.selectedImage = uiImage
                        self.selectedPhotoItem = nil
                    }
                }
            }
        }
        .navigationDestination(isPresented: $navigateToResultPage) {
            CarPlateResultView(plate: plateResult) {
                navigateToResultPage = false
                auth.logout()
            }
            .environmentObject(auth)
        }
    }
}
