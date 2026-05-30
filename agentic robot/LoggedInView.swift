import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import FirebaseFirestore

struct LoggedInView: View {

    @EnvironmentObject var auth: AuthViewModel

    // ── Licence-plate photo flow (existing) ────────────────────────────────
    @State private var selectedImage: UIImage?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var plateResult: String = ""

    @State private var showCamera = false
    @State private var showImagePicker = false
    @State private var showFileImporter = false

    // ── IU barcode flow (new) ───────────────────────────────────────────────
    @State private var showIUBarcodeScanner = false
    @State private var iuManualCode: String = ""
    @State private var showIUManualEntry = false
    @State private var isLookingUpIU = false

    // ── Shared ──────────────────────────────────────────────────────────────
    @State private var navigateToResultPage = false
    @State private var displayedText = ""
    @State private var didRunTypewriter = false
    @State private var isSubmitting = false
    @State private var showButtons = false
    @State private var localErrorMessage: String? = nil

    /// Which input mode is selected
    @State private var inputMode: InputMode = .licencePlate

    private enum InputMode {
        case licencePlate
        case iuBarcode
    }

    private let fullText =
        "Okay, I need to identify the vehicle. Scan the IU barcode or photograph the licence plate."

    // MARK: - ANPR API Call (unchanged)
    func sendToANPRServer(image: UIImage) {
        guard let url = URL(string: "http://192.168.86.216:8000/detect") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")

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
                    self.isSubmitting = false
                    self.localErrorMessage = "Could not reach the server. Please try again."
                }
                return
            }

            let trimmed = rawPlate.trimmingCharacters(in: .whitespacesAndNewlines)

            guard trimmed != "[]" && !trimmed.isEmpty else {
                DispatchQueue.main.async {
                    self.isSubmitting = false
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
                self.isSubmitting = false
                self.plateResult = plate
                self.navigateToResultPage = true
            }

        }.resume()
    }

    // MARK: - IU Barcode Firestore Lookup (new)
    func lookupIUBarcode(_ rawCode: String) {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).filter { $0.isNumber }
        guard !code.isEmpty else {
            localErrorMessage = "Please enter or scan a valid IU barcode number."
            return
        }

        isLookingUpIU = true
        localErrorMessage = nil

        Firestore.firestore()
            .collection("iu_barcodes")
            .document(code)
            .getDocument { snapshot, error in
                DispatchQueue.main.async {
                    self.isLookingUpIU = false

                    if let error {
                        self.localErrorMessage = "IU lookup failed: \(error.localizedDescription)"
                        return
                    }

                    guard
                        let data = snapshot?.data(), !data.isEmpty,
                        let plate = data["plate"] as? String, !plate.isEmpty
                    else {
                        self.localErrorMessage = "No vehicle found for IU barcode \(code). Make sure it has been registered."
                        return
                    }

                    guard (data["isActive"] as? Bool) != false else {
                        self.localErrorMessage = "This IU barcode has been deactivated. Please contact your administrator."
                        return
                    }

                    self.plateResult = plate.uppercased()
                    self.navigateToResultPage = true
                }
            }
    }

    // MARK: - UI
    var body: some View {

        ZStack {
            SubtleHTXBackground()

            VStack(spacing: 20) {

                Spacer().frame(height: 52)

                Text(displayedText)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // ── Mode picker ──────────────────────────────────────────
                if showButtons {
                    Picker("Identification method", selection: $inputMode) {
                        Label("IU Barcode", systemImage: "barcode.viewfinder")
                            .tag(InputMode.iuBarcode)
                        Label("Licence Plate", systemImage: "camera.fill")
                            .tag(InputMode.licencePlate)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .onChange(of: inputMode) { _, _ in
                        // Clear state when switching modes
                        localErrorMessage = nil
                        selectedImage = nil
                        iuManualCode = ""
                        showIUManualEntry = false
                    }
                }

                // ── IU Barcode panel ─────────────────────────────────────
                if inputMode == .iuBarcode && showButtons {
                    iuBarcodePanel
                }

                // ── Licence Plate panel ──────────────────────────────────
                if inputMode == .licencePlate && showButtons {
                    if let selectedImage = selectedImage {
                        platePanelWithImage(selectedImage)
                    } else {
                        platePanelButtons
                    }
                }

                // ── Error message ────────────────────────────────────────
                if let localErrorMessage = localErrorMessage {
                    Text(localErrorMessage)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()
            }

            // MARK: - Loading overlay
            if isSubmitting || isLookingUpIU {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.3)

                    Text(isLookingUpIU ? "Looking up IU barcode…" : "Processing image…")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
        }

        .navigationTitle("Report Generation")
        .navigationBarTitleDisplayMode(.inline)
        .tint(HTXTheme.primaryPurple)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Logout") {
                    auth.logout()
                }
                .foregroundColor(.red)
            }
        }

        .padding(.top)

        // MARK: - Typewriter (runs once)
        .onAppear {
            guard !didRunTypewriter else { return }
            didRunTypewriter = true

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

        // MARK: - Camera (licence plate)
        .fullScreenCover(isPresented: $showCamera) {
            PlateCameraImagePicker { image in
                self.selectedImage = image
                self.showCamera = false
            }
            .ignoresSafeArea()
        }

        // MARK: - IU Barcode scanner
        .fullScreenCover(isPresented: $showIUBarcodeScanner) {
            IUBarcodeScannerSheet(
                onScan: { code in
                    showIUBarcodeScanner = false
                    iuManualCode = code
                    lookupIUBarcode(code)
                },
                onCancel: {
                    showIUBarcodeScanner = false
                }
            )
        }

        // MARK: - Photo picker
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

        // MARK: - File importer
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.jpeg, .png],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    localErrorMessage = "No file was selected."
                    return
                }

                let didStartAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccessing {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                do {
                    let data = try Data(contentsOf: url)
                    guard let uiImage = UIImage(data: data) else {
                        localErrorMessage = "The selected file could not be opened as a JPG/PNG image."
                        return
                    }
                    selectedImage = uiImage
                    localErrorMessage = nil
                } catch {
                    localErrorMessage = "Could not read the selected file: \(error.localizedDescription)"
                }

            case .failure(let error):
                localErrorMessage = "File selection failed: \(error.localizedDescription)"
            }
        }

        // MARK: - Navigation
        .navigationDestination(isPresented: $navigateToResultPage) {
            CarPlateResultView(plate: plateResult) {
                auth.logout()
            }
            .environmentObject(auth)
        }
    }

    // MARK: - IU Barcode sub-views

    @ViewBuilder
    private var iuBarcodePanel: some View {
        VStack(spacing: 14) {

            // Camera scan button
            Button {
                localErrorMessage = nil
                iuManualCode = ""
                showIUBarcodeScanner = true
            } label: {
                HStack {
                    Image(systemName: "barcode.viewfinder")
                    Text("Scan IU Barcode")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(HTXTheme.primaryPurple)
                .foregroundColor(.white)
                .cornerRadius(14)
                .padding(.horizontal)
            }
            .disabled(isLookingUpIU)

            // Manual entry toggle
            Button {
                withAnimation(.spring(response: 0.35)) {
                    showIUManualEntry.toggle()
                    if !showIUManualEntry { iuManualCode = "" }
                    localErrorMessage = nil
                }
            } label: {
                HStack {
                    Image(systemName: showIUManualEntry ? "xmark" : "keyboard")
                    Text(showIUManualEntry ? "Cancel Manual Entry" : "Type Barcode Manually")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground))
                .foregroundColor(HTXTheme.primaryPurple)
                .cornerRadius(12)
                .padding(.horizontal)
            }
            .disabled(isLookingUpIU)

            if showIUManualEntry {
                HStack(spacing: 10) {
                    TextField("Enter barcode number", text: $iuManualCode)
                        .keyboardType(.numberPad)
                        .padding(12)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .frame(maxWidth: .infinity)

                    Button {
                        lookupIUBarcode(iuManualCode)
                    } label: {
                        Text("Search")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(HTXTheme.primaryPurple)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(isLookingUpIU || iuManualCode.isEmpty)
                    .opacity((isLookingUpIU || iuManualCode.isEmpty) ? 0.55 : 1)
                }
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(20)
        .subtleHTXCard()
        .padding(.horizontal)
    }

    // MARK: - Licence Plate sub-views
    @ViewBuilder
    private func platePanelWithImage(_ image: UIImage) -> some View {
        VStack(spacing: 14) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 260)
                .cornerRadius(12)

            HStack(spacing: 10) {
                Button {
                    self.selectedImage = nil
                    self.localErrorMessage = nil
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Retake")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .foregroundColor(HTXTheme.primaryPurple)
                    .cornerRadius(12)
                }

                Button {
                    guard !isSubmitting else { return }
                    isSubmitting = true
                    sendToANPRServer(image: image)
                } label: {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("Confirm")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(HTXTheme.primaryPurple)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isSubmitting)
                .opacity(isSubmitting ? 0.55 : 1)
            }
        }
        .padding(20)
        .subtleHTXCard()
        .padding(.horizontal)
    }

    @ViewBuilder
    private var platePanelButtons: some View {
        VStack(spacing: 14) {

            // Primary: Take Photo
            Button {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showCamera = true
                    localErrorMessage = nil
                } else {
                    localErrorMessage = "Camera is not available on this device."
                }
            } label: {
                HStack {
                    Image(systemName: "camera.fill")
                    Text("Take Photo of Plate")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(HTXTheme.primaryPurple)
                .foregroundColor(.white)
                .cornerRadius(14)
            }

            // Secondary: Choose from Library
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                HStack {
                    Image(systemName: "photo.on.rectangle")
                    Text("Choose From Library")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground))
                .foregroundColor(HTXTheme.primaryPurple)
                .cornerRadius(12)
            }

            // Tertiary: Upload file
            Button {
                showFileImporter = true
            } label: {
                HStack {
                    Image(systemName: "doc.badge.plus")
                    Text("Upload JPG / PNG File")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground))
                .foregroundColor(HTXTheme.primaryPurple)
                .cornerRadius(12)
            }
        }
        .padding(20)
        .subtleHTXCard()
        .padding(.horizontal)
        .opacity(showButtons ? 1 : 0)
    }
}

// MARK: - IU Barcode Scanner Sheet

/// Full-screen barcode scanner used exclusively for IU card scanning.
/// Reuses the existing BarcodeScannerRepresentable / BarcodeScannerViewController
/// from ReportScannerView — no new AVFoundation code needed.
struct IUBarcodeScannerSheet: View {

    var onScan: (String) -> Void
    var onCancel: () -> Void

    @State private var isFrozen = false
    @State private var restartToken = UUID()
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            // Camera layer
            BarcodeScannerRepresentable(
                isFrozen: isFrozen,
                restartToken: restartToken,
                onScan: { raw in
                    let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).filter { $0.isNumber }
                    guard !code.isEmpty else {
                        errorMessage = "Barcode detected but no numeric value found. Try again."
                        return
                    }
                    isFrozen = true
                    onScan(code)
                },
                onPermissionDenied: {
                    errorMessage = "Camera access is required to scan barcodes. Enable it in Settings."
                }
            )
            .ignoresSafeArea()

            // Scan guide
            VStack {
                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        .frame(width: 280, height: 120)

                    Text("Point at the IU card barcode")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                        .offset(y: 74)
                }

                Spacer()
                Spacer()
            }

            // Error + Cancel bar at bottom
            VStack {
                Spacer()

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .background(Color.red.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                        .padding(.horizontal)
                }
                .padding(.bottom, 40)
            }
        }
    }
}


// MARK: - Plate Camera Picker (unchanged from original)

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
