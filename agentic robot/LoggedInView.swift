import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation

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
    
    private let fullText = "Okay, now I will need the licence plate. Please upload a photo of the car plate."
    
    @State private var showButtons = false
    @State private var localErrorMessage: String? = nil
    
    func sendToANPRServer(image: UIImage) {
        // REPLACE THIS IP ADDRESS
//        guard let url = URL(string: "http://127.0.0.1:8000/detect") else { return }
        guard let url = URL(string: "http://192.168.86.190:8000/detect") else { return }

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
        .navigationTitle("Report Generation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Logout") {
                    auth.logout()
                }
                .foregroundColor(.red)
            }
        }
        .padding(.top)
        .onAppear {

            displayedText = ""
            showButtons = false

            Task {
                for char in fullText {
                    try? await Task.sleep(for: .milliseconds(25))
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
        .fullScreenCover(isPresented: $showCamera) {
            PlateCameraImagePicker { image in
                self.selectedImage = image
                self.showCamera = false
            }
            .ignoresSafeArea()
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
            }
            .environmentObject(auth)
        }
    }
}


// MARK: - Plate Camera Picker
// Same camera style as ScratchScanView, but without the vehicle silhouette overlay.
// Includes torch button, pinch-to-zoom, zoom label, shutter, and cancel.

struct PlateCameraImagePicker: View {
    var onPick: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Color.black
            .ignoresSafeArea()
            .onAppear {
                PlateCameraWindowManager.shared.open(
                    onPick: { image in
                        onPick(image)
                        dismiss()
                    },
                    onCancel: {
                        dismiss()
                    }
                )
            }
            .onDisappear {
                PlateCameraWindowManager.shared.close()
            }
    }
}

final class PlateCameraWindowManager {
    static let shared = PlateCameraWindowManager()
    private init() {}

    private var cameraWindow: UIWindow?

    func open(
        onPick: @escaping (UIImage) -> Void,
        onCancel: @escaping () -> Void
    ) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        let viewController = PlateCameraViewController()
        viewController.onPick = { [weak self] image in
            self?.close()
            onPick(image)
        }
        viewController.onCancel = { [weak self] in
            self?.close()
            onCancel()
        }

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        cameraWindow = window
    }

    func close() {
        cameraWindow?.isHidden = true
        cameraWindow = nil
    }
}

final class PlateCameraViewController: UIViewController {

    var onPick: ((UIImage) -> Void)?
    var onCancel: (() -> Void)?

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private var device: AVCaptureDevice?
    private var lastPinchScale: CGFloat = 1.0
    private var isCapturing = false

    @available(iOS 17.0, *)
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObservation: NSKeyValueObservation?
    private var captureRotationObservation: NSKeyValueObservation?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }

    private let zoomLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        label.text = "1.0×"
        label.textAlignment = .center
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.7
        label.layer.shadowRadius = 3
        label.layer.shadowOffset = .zero
        return label
    }()

    private var torchIsOn = true
    private var torchButton: UIButton?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSession()
        setupPreview()
        setupControls()
        setupGestures()
    }

    deinit {
        previewRotationObservation?.invalidate()
        captureRotationObservation?.invalidate()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.session.startRunning()
            self.setTorch(on: true)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setTorch(on: false)
        session.stopRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        updateCameraRotationAngles()
    }

    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: camera),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }

        session.addInput(input)
        device = camera

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        session.commitConfiguration()
    }

    private func setupPreview() {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds

        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer

        setupRotationCoordinatorIfNeeded()
        updateCameraRotationAngles()
    }

    // Uses UIWindowScene.effectiveGeometry.interfaceOrientation instead of the deprecated
    // UIWindowScene.interfaceOrientation.
    private var currentInterfaceOrientation: UIInterfaceOrientation {
        if let orientation = view.window?.windowScene?.effectiveGeometry.interfaceOrientation,
           orientation != .unknown {
            return orientation
        }

        if let orientation = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .effectiveGeometry
            .interfaceOrientation,
           orientation != .unknown {
            return orientation
        }

        return .portrait
    }

    private func setupRotationCoordinatorIfNeeded() {
        guard #available(iOS 17.0, *),
              rotationCoordinator == nil,
              let device,
              let previewLayer
        else { return }

        let coordinator = AVCaptureDevice.RotationCoordinator(
            device: device,
            previewLayer: previewLayer
        )
        rotationCoordinator = coordinator

        previewRotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            self?.updateCameraRotationAngles()
        }

        captureRotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            self?.updateCameraRotationAngles()
        }
    }

    private func updateCameraRotationAngles() {
        _ = currentInterfaceOrientation

        guard #available(iOS 17.0, *), let rotationCoordinator else { return }

        let previewAngle = rotationCoordinator.videoRotationAngleForHorizonLevelPreview
        if let previewConnection = previewLayer?.connection,
           previewConnection.isVideoRotationAngleSupported(previewAngle) {
            previewConnection.videoRotationAngle = previewAngle
        }

        let captureAngle = rotationCoordinator.videoRotationAngleForHorizonLevelCapture
        if let photoConnection = photoOutput.connection(with: .video),
           photoConnection.isVideoRotationAngleSupported(captureAngle) {
            photoConnection.videoRotationAngle = captureAngle
        }
    }

    private func setupControls() {
        let bar = UIView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)

        let shutter = UIButton(type: .custom)
        shutter.translatesAutoresizingMaskIntoConstraints = false
        shutter.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)

        let ring = UIView()
        ring.translatesAutoresizingMaskIntoConstraints = false
        ring.layer.cornerRadius = 38
        ring.layer.borderWidth = 3
        ring.layer.borderColor = UIColor.white.cgColor
        ring.isUserInteractionEnabled = false

        let fill = UIView()
        fill.translatesAutoresizingMaskIntoConstraints = false
        fill.backgroundColor = .white
        fill.layer.cornerRadius = 30
        fill.isUserInteractionEnabled = false

        shutter.addSubview(ring)
        shutter.addSubview(fill)
        bar.addSubview(shutter)

        let cancel = UIButton(type: .system)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.setTitle("Cancel", for: .normal)
        cancel.setTitleColor(.white, for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        bar.addSubview(cancel)

        let torch = UIButton(type: .custom)
        torch.translatesAutoresizingMaskIntoConstraints = false
        torch.addTarget(self, action: #selector(torchToggled), for: .touchUpInside)
        torch.backgroundColor = UIColor(red: 1.0, green: 0.80, blue: 0.0, alpha: 1.0)
        torch.layer.cornerRadius = 22
        torch.clipsToBounds = true

        let torchImage = UIImage(
            systemName: "flashlight.on.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        )
        torch.setImage(torchImage, for: .normal)
        torch.tintColor = .black
        bar.addSubview(torch)
        torchButton = torch

        zoomLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(zoomLabel)

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 120),

            shutter.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            shutter.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            shutter.widthAnchor.constraint(equalToConstant: 76),
            shutter.heightAnchor.constraint(equalToConstant: 76),

            ring.topAnchor.constraint(equalTo: shutter.topAnchor),
            ring.leadingAnchor.constraint(equalTo: shutter.leadingAnchor),
            ring.trailingAnchor.constraint(equalTo: shutter.trailingAnchor),
            ring.bottomAnchor.constraint(equalTo: shutter.bottomAnchor),

            fill.centerXAnchor.constraint(equalTo: ring.centerXAnchor),
            fill.centerYAnchor.constraint(equalTo: ring.centerYAnchor),
            fill.widthAnchor.constraint(equalToConstant: 60),
            fill.heightAnchor.constraint(equalToConstant: 60),

            cancel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 24),
            cancel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            torch.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -20),
            torch.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            torch.widthAnchor.constraint(equalToConstant: 44),
            torch.heightAnchor.constraint(equalToConstant: 44),

            zoomLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            zoomLabel.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -10)
        ])
    }

    private func setupGestures() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinch)
    }

    private func setTorch(on: Bool) {
        guard
            let device,
            device.hasTorch,
            device.isTorchAvailable
        else { return }

        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let device else { return }

        switch gesture.state {
        case .began:
            lastPinchScale = device.videoZoomFactor
        case .changed:
            let maxZoom = min(device.maxAvailableVideoZoomFactor, 10)
            let desiredZoom = (lastPinchScale * gesture.scale)
                .clamped(to: device.minAvailableVideoZoomFactor...maxZoom)

            try? device.lockForConfiguration()
            device.videoZoomFactor = desiredZoom
            device.unlockForConfiguration()

            zoomLabel.text = String(format: "%.1f×", desiredZoom)
        default:
            break
        }
    }

    @objc private func shutterTapped() {
        guard !isCapturing else { return }
        isCapturing = true

        let flashView = UIView(frame: view.bounds)
        flashView.backgroundColor = .white
        flashView.alpha = 0
        view.addSubview(flashView)

        UIView.animate(withDuration: 0.05, animations: {
            flashView.alpha = 1
        }) { _ in
            UIView.animate(withDuration: 0.15, animations: {
                flashView.alpha = 0
            }) { _ in
                flashView.removeFromSuperview()
            }
        }

        updateCameraRotationAngles()

        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    @objc private func torchToggled() {
        torchIsOn.toggle()
        setTorch(on: torchIsOn)

        let activeColor = UIColor(red: 1.0, green: 0.80, blue: 0.0, alpha: 1.0)
        let inactiveColor = UIColor(white: 0.25, alpha: 1.0)
        let iconName = torchIsOn ? "flashlight.on.fill" : "flashlight.off.fill"

        UIView.animate(withDuration: 0.2) { [weak self] in
            guard let self else { return }
            torchButton?.backgroundColor = torchIsOn ? activeColor : inactiveColor
            torchButton?.tintColor = torchIsOn ? .black : .white
        }

        let image = UIImage(
            systemName: iconName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        )
        torchButton?.setImage(image, for: .normal)
    }
}

extension PlateCameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        isCapturing = false

        guard
            error == nil,
            let data = photo.fileDataRepresentation(),
            let image = UIImage(data: data)
        else { return }

        onPick?(image)
        dismiss(animated: true)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
