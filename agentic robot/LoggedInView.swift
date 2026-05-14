import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct LoggedInView: View {

    @EnvironmentObject var auth: AuthViewModel

    @State private var selectedImage: UIImage?
    @State private var selectedPhotoItem: PhotosPickerItem?

    @State private var showCamera = false
    @State private var showImagePicker = false

    @State private var navigateToResultPage = false
    @State private var showFileImporter = false
    
    @State private var displayedText = ""
    
    private let fullText = "Okay, first I will have to check the car plate number. Please upload a photo of the car plate."
    
    @State private var hasRunTypewriter = false
    @State private var showButtons = false
    @State private var hasAnimatedText = false
    
    @State private var localErrorMessage: String? = nil
    
    var body: some View {
        VStack(spacing: 25) {

            // HEADER
            HStack {

                Text("Welcome")
                    .font(.largeTitle)
                    .bold()

                Spacer()

                Button("Logout") {
                    hasAnimatedText = false
                    displayedText = ""
                    
                    auth.logout()
                }
                .foregroundColor(.red)
            }
            .padding(.horizontal)

            Text(displayedText)
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // IMAGE PREVIEW
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
                    }
                    .buttonStyle(.bordered)

                    Button("Confirm") {
                        navigateToResultPage = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity)
            } else {

                VStack(spacing: 15) {
                    
                    Button("Take Photo") {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            showCamera = true
                            localErrorMessage = nil
                        } else {
                            localErrorMessage = "Camera is not available on this device."
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    
                    // PHOTO LIBRARY BUTTON
                    PhotosPicker(
                        selection: $selectedPhotoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Text("Choose From Library")
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Upload JPG/PNG File") {
                        showFileImporter = true
                    }
                    .buttonStyle(.bordered)
                    
                    if let localErrorMessage = localErrorMessage {
                        Text(localErrorMessage)
                            .foregroundColor(.red)
                            .font(.footnote)
                            .padding(.top, 10)
                            .onAppear {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    self.localErrorMessage = nil
                                }
                            }
                    }
                }
                .opacity(showButtons ? 1 : 0)
                .animation(.easeIn(duration: 0.5), value: showButtons)
                .fileImporter(
                    isPresented: $showFileImporter,
                    allowedContentTypes: [.image],
                    allowsMultipleSelection: false
                ) { result in

                    switch result {

                    case .success(let files):

                        guard let selectedFile = files.first else { return }

                        if let data = try? Data(contentsOf: selectedFile),
                           let uiImage = UIImage(data: data) {

                            selectedImage = uiImage
                        }

                    case .failure(let error):
                        auth.errorMessage = error.localizedDescription
                    }
                }
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

            let words = fullText.split(separator: " ")

            Task {
                for word in words {
                    try? await Task.sleep(for: .milliseconds(120))
                    displayedText += word + " "
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
            CarPlateResultView(image: selectedImage)
                .environmentObject(auth)
        }
    }
}
