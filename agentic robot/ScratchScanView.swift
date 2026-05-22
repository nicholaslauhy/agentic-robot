import SwiftUI
import PhotosUI
import Photos

// MARK: - Scan Angle Model

struct ScanAngle: Identifiable {
    let id: Int
    let label: String
    let instruction: String
    let iconName: String
}

let scanAngles: [ScanAngle] = [
    ScanAngle(id: 0, label: "Front",      instruction: "Stand in front — aim at the bonnet",    iconName: "car.front.waves.up"),
    ScanAngle(id: 1, label: "Rear",       instruction: "Stand behind — aim at the boot",         iconName: "car.rear.waves.up"),
    ScanAngle(id: 2, label: "Left Side",  instruction: "Stand on the left side of the vehicle",  iconName: "arrow.left.square"),
    ScanAngle(id: 3, label: "Right Side", instruction: "Stand on the right side of the vehicle", iconName: "arrow.right.square"),
]

// MARK: - Main View

struct ScratchScanView: View {

    @Environment(\.dismiss) private var dismiss

    let plate: String
    let carType: CarType
    var onLogout: () -> Void
    var onBackToPlateResult: () -> Void
    var initialImages: [UIImage] = []
    var startOnReviewScreen: Bool = false
    var onScanComplete: ([UIImage], @escaping () -> Void) -> Void

    @State private var currentAngleIndex: Int
    @State private var capturedImages: [UIImage?]
    @State private var showCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showCompletionScreen: Bool
    @State private var localErrorMessage: String? = nil
    @State private var isSubmittingAnalysis = false

    // Replace flow — single source of truth
    @State private var replacingIndex: Int? = nil
    @State private var showReplaceSheet = false     // confirmationDialog trigger
    @State private var showReplaceCamera = false
    @State private var showReplaceLibrary = false
    @State private var replaceImage: UIImage? = nil // set by PHPicker callback

    private var capturedCount: Int { capturedImages.compactMap { $0 }.count }
    private var progress: Double { Double(capturedCount) / Double(scanAngles.count) }

    init(
        plate: String,
        carType: CarType,
        onLogout: @escaping () -> Void,
        onBackToPlateResult: @escaping () -> Void,
        initialImages: [UIImage] = [],
        startOnReviewScreen: Bool = false,
        onScanComplete: @escaping ([UIImage], @escaping () -> Void) -> Void
    ) {
        self.plate = plate
        self.carType = carType
        self.onLogout = onLogout
        self.onBackToPlateResult = onBackToPlateResult
        self.initialImages = initialImages
        self.startOnReviewScreen = startOnReviewScreen
        self.onScanComplete = onScanComplete

        var imageSlots: [UIImage?] = Array(repeating: nil, count: 4)
        for index in 0..<min(initialImages.count, 4) {
            imageSlots[index] = initialImages[index]
        }

        _capturedImages = State(initialValue: imageSlots)
        _showCompletionScreen = State(initialValue: startOnReviewScreen || initialImages.count == 4)
        _currentAngleIndex = State(initialValue: min(initialImages.count, 3))
    }
    
    var body: some View {
        ZStack {
            SubtleHTXBackground()

            VStack(spacing: 0) {

            // HEADER
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scratch Scan").font(.largeTitle).bold().foregroundColor(HTXTheme.primaryPurple)
                    Text("\(carType.rawValue)  ·  \(plate)")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                Button("Logout") { onLogout() }.foregroundColor(.red)
            }
            .padding()

            // PROGRESS BAR
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(capturedCount) of \(scanAngles.count) angles captured")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.caption.bold()).foregroundColor(HTXTheme.primaryPurple)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray5)).frame(height: 8)
                        RoundedRectangle(cornerRadius: 4).fill(HTXTheme.primaryPurple)
                            .frame(width: geo.size.width * progress, height: 8)
                            .animation(.spring(response: 0.5), value: progress)
                    }
                }
                .frame(height: 8)
            }
            .padding(.horizontal).padding(.bottom, 12)

            if showCompletionScreen { reviewView } else { scanGuideView }
        }
        }
        .overlay {
            if isSubmittingAnalysis {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()

                    VStack(spacing: 14) {
                        ProgressView()
                            .scaleEffect(1.3)

                        Text("Analyzing your pictures for any dents or scratches...")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(24)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(radius: 10)
                    .padding(.horizontal, 28)
                }
            }
        }

        // ── Main capture ───────────────────────────────────────────────────
        .navigationBarBackButtonHidden(true)
        .tint(HTXTheme.primaryPurple)

        // ── Main capture ───────────────────────────────────────────────────
        .fullScreenCover(isPresented: $showCamera) {
            CameraOverlayImagePicker(
                carType: carType,
                angleId: currentAngleIndex
            ) { image in
                capturedImages[currentAngleIndex] = image
                showCamera = false
                advanceOrComplete()
            }
            .ignoresSafeArea()
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run {
                        capturedImages[currentAngleIndex] = img
                        selectedPhotoItem = nil
                        advanceOrComplete()
                    }
                }
            }
        }

        // ── Replace: confirmation sheet ────────────────────────────────────
        .confirmationDialog(
            replacingIndex.map { "Replace \(scanAngles[$0].label) Photo" } ?? "Replace Photo",
            isPresented: $showReplaceSheet,
            titleVisibility: .visible
        ) {
            Button("Take New Photo") {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showReplaceCamera = true
                } else {
                    localErrorMessage = "Camera is not available on this device."
                    replacingIndex = nil
                }
            }
            Button("Choose from Library") {
                showReplaceLibrary = true
            }
            Button("Cancel", role: .cancel) { replacingIndex = nil }
        }

        // ── Replace: camera ────────────────────────────────────────────────
        .fullScreenCover(isPresented: $showReplaceCamera) {
            CameraOverlayImagePicker(
                carType: carType,
                angleId: replacingIndex ?? currentAngleIndex
            ) { image in
                if let idx = replacingIndex { capturedImages[idx] = image }
                replacingIndex = nil
                showReplaceCamera = false
            }
            .ignoresSafeArea()
        }

        // ── Replace: photo library (PHPicker — writes directly to replaceImage) ──
        .sheet(isPresented: $showReplaceLibrary) {
            PHPickerRepresentable { image in
                if let idx = replacingIndex { capturedImages[idx] = image }
                replacingIndex = nil
                showReplaceLibrary = false
            }
        }
    }

    // MARK: - Advance or Complete

    private func advanceOrComplete() {
        if currentAngleIndex < scanAngles.count - 1 {
            withAnimation { currentAngleIndex += 1 }
        } else {
            withAnimation { showCompletionScreen = true }
        }
    }

    // MARK: - Scan Guide View

    private var scanGuideView: some View {
        VStack(spacing: 16) {

            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground))
                CarSilhouetteView(carType: carType, angleId: currentAngleIndex).padding(.horizontal, 18).padding(.vertical, 10)
            }
            .frame(height: 310).padding(.horizontal)

            HStack(spacing: 16) {
                Image(systemName: scanAngles[currentAngleIndex].iconName)
                    .font(.system(size: 26, weight: .bold)).foregroundColor(HTXTheme.primaryPurple).frame(width: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(scanAngles[currentAngleIndex].label).font(.headline)
                    Text(scanAngles[currentAngleIndex].instruction)
                        .font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<scanAngles.count, id: \.self) { idx in
                        AngleThumbnail(
                            label: scanAngles[idx].label,
                            image: capturedImages[idx],
                            isCurrent: idx == currentAngleIndex,
                            accentColor: HTXTheme.primaryPurple
                        )
                        .onTapGesture { withAnimation { currentAngleIndex = idx } }
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 90)

            if let err = localErrorMessage {
                Text(err).foregroundColor(.red).font(.footnote)
                    .multilineTextAlignment(.center).padding(.horizontal)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { localErrorMessage = nil }
                    }
            }

            Spacer()

            HStack(spacing: 12) {
                Button {
                    if currentAngleIndex > 0 {
                        withAnimation { currentAngleIndex -= 1 }
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(HTXTheme.primaryPurple)
                        .frame(width: 52, height: 52)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                }

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Library", systemImage: "photo.on.rectangle")
                        .foregroundColor(HTXTheme.primaryPurple)
                        .frame(maxWidth: .infinity).padding()
                        .background(Color(.secondarySystemBackground)).cornerRadius(12)
                }
                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        localErrorMessage = nil; showCamera = true
                    } else {
                        localErrorMessage = "Camera is not available on this device."
                    }
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity).padding()
                        .background(HTXTheme.primaryPurple).foregroundColor(.white).cornerRadius(12)
                }
            }
            .padding(.horizontal).padding(.bottom, 24)
        }
        .animation(.easeInOut, value: currentAngleIndex)
    }

    // MARK: - Review View

    private var reviewView: some View {
        ScrollView {
            VStack(spacing: 20) {

                // ── Header ────────────────────────────────────────────────────
                HStack {
                    // Back to scan guide
                    Button {
                        onBackToPlateResult()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .fontWeight(.semibold)
                            Text("Back")
                        }
                        .foregroundColor(HTXTheme.primaryPurple)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                        Text("All Angles Captured").font(.title3.bold())
                    }

                    Spacer()

                    // Invisible balance element so the title stays centred
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .hidden()
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Text("Tap any photo to replace it, then submit.")
                    .font(.subheadline).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)

                LazyVStack(spacing: 16) {
                    ForEach(0..<scanAngles.count, id: \.self) { idx in
                        ReviewThumbnail(
                            label: scanAngles[idx].label,
                            image: capturedImages[idx],
                            accentColor: HTXTheme.primaryPurple
                        ) {
                            replacingIndex = idx
                            showReplaceSheet = true
                        }
                    }
                }
                .padding(.horizontal)

                if let err = localErrorMessage {
                    Text(err).foregroundColor(.red).font(.footnote)
                        .multilineTextAlignment(.center).padding(.horizontal)
                }

                Button {
                    isSubmittingAnalysis = true
                    onScanComplete(capturedImages.compactMap { $0 }) {
                        isSubmittingAnalysis = false
                    }
                } label: {
                    Text("Submit for Analysis")
                        .font(.headline).frame(maxWidth: .infinity).padding()
                        .background(HTXTheme.primaryPurple).foregroundColor(.white)
                        .cornerRadius(14).padding(.horizontal)
                }
                .disabled(isSubmittingAnalysis)
                .opacity(isSubmittingAnalysis ? 0.6 : 1)
                .padding(.bottom, 32)
            }
        }
    }
}



// MARK: - Camera with Vehicle Silhouette Overlay (Magnifier-style AVFoundation)
//
// Presented via a dedicated UIWindow so the portrait lock is enforced at the
// window level — immune to the SwiftUI fullScreenCover hosting hierarchy which
// ignores shouldAutorotate on child view controllers.

import AVFoundation

// MARK: SwiftUI wrapper — manages its own UIWindow

struct CameraOverlayImagePicker: View {
    let carType: CarType
    let angleId: Int
    var onPick:  (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Invisible placeholder. The real camera lives in a UIWindow
        // we open on appear and tear down on disappear / pick / cancel.
        Color.black.ignoresSafeArea()
            .onAppear  { MagnifierWindowManager.shared.open(carType: carType, angleId: angleId, onPick: { img in onPick(img); dismiss() }, onCancel: { dismiss() }) }
            .onDisappear { MagnifierWindowManager.shared.close() }
    }
}

// MARK: Window manager — singleton

final class MagnifierWindowManager {
    static let shared = MagnifierWindowManager()
    private init() {}

    private var cameraWindow: UIWindow?

    func open(carType: CarType, angleId: Int, onPick: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first
        else { return }

        let vc        = MagnifierCameraViewController()
        vc.onPick     = { [weak self] img in self?.close(); onPick(img) }
        vc.onCancel   = { [weak self] in self?.close(); onCancel() }
        vc.carType    = carType
        vc.angleId    = angleId

        let win = UIWindow(windowScene: scene)
        win.windowLevel          = .alert + 1          // above everything
        win.rootViewController   = vc
        win.makeKeyAndVisible()
        cameraWindow = win
    }

    func close() {
        cameraWindow?.isHidden = true
        cameraWindow           = nil
    }
}

// MARK: Magnifier Camera View Controller

final class MagnifierCameraViewController: UIViewController {

    var onPick:   ((UIImage) -> Void)?
    var onCancel: (() -> Void)?
    var carType:  CarType = .sedan
    var angleId:  Int = 0

    // AVFoundation
    private let session     = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    // Zoom
    private var device:         AVCaptureDevice?
    private var lastPinchScale: CGFloat = 1.0

    // Capture guard
    private var isCapturing = false

    // Overlay
    private var overlayHost: UIHostingController<CameraSilhouetteOverlay>?

    // Rotation coordinator. This is the modern AVFoundation way to keep the preview
    // and captured photo level as the physical device rotates.
    @available(iOS 17.0, *)
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObservation: NSKeyValueObservation?
    private var captureRotationObservation: NSKeyValueObservation?

    // Allow the camera screen itself to rotate so the guide can stretch in landscape.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSession()
        setupPreview()
        setupOverlay()
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
            self?.session.startRunning()
            self?.setTorch(on: true)
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
        overlayHost?.view.frame = view.bounds

        // Re-apply after rotation/layout changes.
        updateCameraRotationAngles()
    }

    // MARK: – Session

    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard
            let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: cam),
            session.canAddInput(input)
        else { session.commitConfiguration(); return }

        session.addInput(input)
        device = cam

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        session.commitConfiguration()
    }

    // MARK: – Preview

    private func setupPreview() {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds

        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer

        setupRotationCoordinatorIfNeeded()
        updateCameraRotationAngles()
    }

    // MARK: – Camera rotation

    /// Uses the scene's effective geometry. This avoids the iOS 26 deprecation warning
    /// from UIWindowScene.interfaceOrientation.
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

    /// Creates Apple's rotation coordinator. Do not use AVCaptureVideoOrientation here;
    /// that API is deprecated. The coordinator gives separate angles for preview and capture.
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

    /// Applies modern AVCaptureConnection.videoRotationAngle values from
    /// AVCaptureDevice.RotationCoordinator.
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

    // MARK: – Silhouette overlay

    private func setupOverlay() {
        let host = UIHostingController(
            rootView: CameraSilhouetteOverlay(carType: carType, angleId: angleId)
        )
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        host.view.frame = view.bounds
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        overlayHost = host
    }

    // MARK: – Controls  (shutter + cancel + zoom label + torch button)

    private let zoomLabel: UILabel = {
        let l = UILabel()
        l.textColor   = .white
        l.font        = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        l.text        = "1.0×"
        l.textAlignment = .center
        l.layer.shadowColor   = UIColor.black.cgColor
        l.layer.shadowOpacity = 0.7
        l.layer.shadowRadius  = 3
        l.layer.shadowOffset  = .zero
        return l
    }()

    /// Tracks torch state so the button icon can reflect it
    private var torchIsOn = true
    private var torchButton: UIButton?

    private func setupControls() {

        // ── Bottom bar ──────────────────────────────────────────────────────
        let bar = UIView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)

        // Shutter button
        let shutter = UIButton(type: .custom)
        shutter.translatesAutoresizingMaskIntoConstraints = false
        shutter.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)

        // Outer ring
        let ring = UIView()
        ring.translatesAutoresizingMaskIntoConstraints = false
        ring.layer.cornerRadius  = 38
        ring.layer.borderWidth   = 3
        ring.layer.borderColor   = UIColor.white.cgColor
        ring.isUserInteractionEnabled = false

        // Inner fill
        let fill = UIView()
        fill.translatesAutoresizingMaskIntoConstraints = false
        fill.backgroundColor      = .white
        fill.layer.cornerRadius   = 30
        fill.isUserInteractionEnabled = false

        shutter.addSubview(ring)
        shutter.addSubview(fill)
        bar.addSubview(shutter)

        // Cancel button
        let cancel = UIButton(type: .system)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.setTitle("Cancel", for: .normal)
        cancel.setTitleColor(.white, for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        bar.addSubview(cancel)

        // ── Torch toggle button (right side, replaces static zoom label) ───
        let torch = UIButton(type: .custom)
        torch.translatesAutoresizingMaskIntoConstraints = false
        torch.addTarget(self, action: #selector(torchToggled), for: .touchUpInside)

        // Yellow filled circle background — matches Magnifier active-torch style
        torch.backgroundColor    = UIColor(red: 1.0, green: 0.80, blue: 0.0, alpha: 1.0)
        torch.layer.cornerRadius = 22
        torch.clipsToBounds      = true

        let torchImg = UIImage(systemName: "flashlight.on.fill",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        torch.setImage(torchImg, for: .normal)
        torch.tintColor = .black
        bar.addSubview(torch)
        torchButton = torch

        // ── Zoom label — sits just above the bar ───────────────────────────
        zoomLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(zoomLabel)   // added to view, not bar, so it floats above

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 120),

            // Shutter — centred in bar
            shutter.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            shutter.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            shutter.widthAnchor.constraint(equalToConstant: 76),
            shutter.heightAnchor.constraint(equalToConstant: 76),

            // Ring fills shutter
            ring.topAnchor.constraint(equalTo: shutter.topAnchor),
            ring.leadingAnchor.constraint(equalTo: shutter.leadingAnchor),
            ring.trailingAnchor.constraint(equalTo: shutter.trailingAnchor),
            ring.bottomAnchor.constraint(equalTo: shutter.bottomAnchor),

            // Fill inside ring
            fill.centerXAnchor.constraint(equalTo: ring.centerXAnchor),
            fill.centerYAnchor.constraint(equalTo: ring.centerYAnchor),
            fill.widthAnchor.constraint(equalToConstant: 60),
            fill.heightAnchor.constraint(equalToConstant: 60),

            // Cancel — left side
            cancel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 24),
            cancel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            // Torch button — right side, 44×44 tap target inside 44pt circle
            torch.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -20),
            torch.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            torch.widthAnchor.constraint(equalToConstant: 44),
            torch.heightAnchor.constraint(equalToConstant: 44),

            // Zoom label — centred horizontally, just above the bar
            zoomLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            zoomLabel.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -10),
        ])
    }

    // MARK: – Gestures

    private func setupGestures() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinch)
    }

    // MARK: – Torch

    /// Turns the rear torch on or off. Safe to call from any thread.
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

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard let device else { return }

        switch g.state {
        case .began:
            lastPinchScale = device.videoZoomFactor
        case .changed:
            let desired = (lastPinchScale * g.scale)
                .clamped(to: device.minAvailableVideoZoomFactor...min(device.maxAvailableVideoZoomFactor, 10))
            try? device.lockForConfiguration()
            device.videoZoomFactor = desired
            device.unlockForConfiguration()
            zoomLabel.text = String(format: "%.1f×", desired)
        default:
            break
        }
    }

    // MARK: – Actions

    @objc private func shutterTapped() {
        guard !isCapturing else { return }
        isCapturing = true

        // Brief visual flash like the native camera
        let flash = UIView(frame: view.bounds)
        flash.backgroundColor = .white
        flash.alpha = 0
        view.addSubview(flash)
        UIView.animate(withDuration: 0.05, animations: { flash.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.15) { flash.alpha = 0 } completion: { _ in flash.removeFromSuperview() }
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

        // Update button appearance: yellow = on, dark grey = off
        let activeColor   = UIColor(red: 1.0, green: 0.80, blue: 0.0, alpha: 1.0)
        let inactiveColor = UIColor(white: 0.25, alpha: 1.0)
        let iconName      = torchIsOn ? "flashlight.on.fill" : "flashlight.off.fill"

        UIView.animate(withDuration: 0.2) { [weak self] in
            self?.torchButton?.backgroundColor = self?.torchIsOn == true ? activeColor : inactiveColor
            self?.torchButton?.tintColor       = self?.torchIsOn == true ? .black : .white
        }
        let img = UIImage(systemName: iconName,
                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        torchButton?.setImage(img, for: .normal)
    }
}

// MARK: – Photo capture delegate

extension MagnifierCameraViewController: AVCapturePhotoCaptureDelegate {

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        isCapturing = false
        guard
            error == nil,
            let data  = photo.fileDataRepresentation(),
            let image = UIImage(data: data)
        else { return }

        onPick?(image)
        dismiss(animated: true)
    }
}

// MARK: – Comparable clamping helper (local to this file)

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

struct CameraSilhouetteOverlay: View {
    let carType: CarType
    let angleId: Int

    private var safeAngleId: Int {
        min(max(angleId, 0), scanAngles.count - 1)
    }

    var body: some View {
        GeometryReader { geo in
            // Make the capture guide big enough to feel natural in full-screen camera.
            // This is intentionally about 80% of the screen height, and almost the full
            // usable width, so front/rear/side shots do not feel cramped.
            let guideWidth = geo.size.width * 0.94
            let guideHeight = geo.size.height * 0.80
            let silhouetteHorizontalPadding: CGFloat = safeAngleId <= 1 ? 8 : 14
            let silhouetteVerticalPadding: CGFloat = safeAngleId <= 1 ? 18 : 10

            ZStack {
                // Slight vignette so the guide stays visible on bright scenes,
                // but keep the middle mostly clear for the actual camera preview.
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.30),
                        Color.black.opacity(0.04),
                        Color.black.opacity(0.34)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack {
                    Spacer()

                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(
                                style: StrokeStyle(
                                    lineWidth: 3,
                                    lineCap: .round,
                                    dash: [14, 9]
                                )
                            )
                            .foregroundColor(HTXTheme.primaryPurple.opacity(0.95))

                        CarSilhouetteView(
                            carType: carType,
                            angleId: safeAngleId
                        )
                        .opacity(0.52)
                        .padding(.horizontal, silhouetteHorizontalPadding)
                        .padding(.vertical, silhouetteVerticalPadding)

                        VStack(spacing: 6) {
                            Text(scanAngles[safeAngleId].label)
                                .font(.headline.bold())
                                .foregroundColor(.white)

                            Text(scanAngles[safeAngleId].instruction)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.92))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 12)

                        Text("Align vehicle inside this guide")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.black.opacity(0.45))
                            .clipShape(Capsule())
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, 12)
                    }
                    .frame(width: guideWidth, height: guideHeight)

                    Spacer()
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

// MARK: - PHPicker wrapper
// Delivers UIImage directly — no PhotosPickerItem conversion needed

struct PHPickerRepresentable: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (UIImage) -> Void
        init(onPick: @escaping (UIImage) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else { return }
            result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                if let image = object as? UIImage {
                    DispatchQueue.main.async { self.onPick(image) }
                }
            }
        }
    }
}

// MARK: - Angle Thumbnail

struct AngleThumbnail: View {
    let label: String
    let image: UIImage?
    let isCurrent: Bool
    let accentColor: Color

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCurrent ? accentColor.opacity(0.15) : Color(.systemGray6))
                    .frame(width: 60, height: 60)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(isCurrent ? accentColor : Color.clear, lineWidth: 2))
                if let img = image {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 60, height: 60).clipShape(RoundedRectangle(cornerRadius: 8))
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        .background(Circle().fill(Color.white).padding(1))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(3)
                } else {
                    Image(systemName: isCurrent ? "camera.fill" : "circle.dashed")
                        .foregroundColor(isCurrent ? accentColor : .secondary)
                }
            }
            Text(label).font(.system(size: 9, weight: isCurrent ? .bold : .regular))
                .foregroundColor(isCurrent ? accentColor : .secondary).lineLimit(1)
        }
        .frame(width: 64)
    }
}

// MARK: - Review Thumbnail

struct ReviewThumbnail: View {
    let label: String
    let image: UIImage?
    let accentColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    if let img = image {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()          // never squishes or crops
                            .frame(maxWidth: .infinity)
                            .background(Color(.systemGray6))
                    } else {
                        Color(.systemGray5)
                            .frame(maxWidth: .infinity)
                            .frame(height: 200)
                        Text("No photo yet")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    // Label + edit hint gradient bar
                    HStack {
                        Text(label).font(.subheadline.bold()).foregroundColor(.white)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "pencil.circle.fill")
                            Text("Tap to replace")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [Color.black.opacity(0.65), Color.clear],
                            startPoint: .bottom, endPoint: .top
                        )
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(accentColor.opacity(0.4), lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}



// MARK: - Car Silhouette View

struct CarSilhouetteView: View {
    let carType: CarType
    let angleId: Int   // 0=Front, 1=Rear, 2=Left, 3=Right

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                VehicleGuideDrawing(
                    carType: carType,
                    angleId: angleId,
                    w: w,
                    h: h
                )

                Text(scanAngles[angleId].label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.72))
                    .position(x: w / 2, y: h - 12)
            }
        }
    }
}

// MARK: - Vehicle Kind

enum VehicleVisualKind {
    case sedan
    case suv
    case mpv
    case lightFireAttackVehicle
    case ambulance
    case medicalSupportVehicle
    case pumpLadder
    case responderPerformanceVehicle
    case hazmat
    case fireTruck
    case genericLarge
}

extension CarType {
    var visualKind: VehicleVisualKind {
        let name = rawValue.lowercased()

        if name.contains("hazmat") || name.contains("hazardous") || name.contains("haz mat") {
            return .hazmat
        }

        if name.contains("responder performance") || name.contains("performance vehicle") || name.contains("rpv") {
            return .responderPerformanceVehicle
        }

        if name.contains("pump ladder") || name.contains("platform ladder") || name.contains("combined platform") ||
           name.contains("ladder") || name.contains("pl ") || name == "pl" {
            return .pumpLadder
        }

        if name.contains("medical support") || name.contains("msv") {
            return .medicalSupportVehicle
        }

        if name.contains("ambulance") || name.contains("emergency ambulance") {
            return .ambulance
        }

        if name.contains("light fire") || name.contains("red rhino") || name.contains("lfav") || name.contains("lf6g") {
            return .lightFireAttackVehicle
        }

        if name.contains("pump") || name.contains("fire engine") || name.contains("fire truck") {
            return .fireTruck
        }

        if self == .suv || name.contains("suv") {
            return .suv
        }

        if self == .mpv || name.contains("mpv") || name.contains("multi purpose") || name.contains("multi-purpose") {
            return .mpv
        }

        if category == .scdf {
            return .genericLarge
        }

        return .sedan
    }
}

// MARK: - Vehicle Guide Drawing

struct VehicleGuideDrawing: View {
    let carType: CarType
    let angleId: Int
    let w: CGFloat
    let h: CGFloat

    private var kind: VehicleVisualKind { carType.visualKind }
    private var isFront: Bool { angleId == 0 }
    private var isRear: Bool { angleId == 1 }
    private var isSide: Bool { angleId == 2 || angleId == 3 }
    private var flipped: Bool { angleId == 3 }

    var body: some View {
        ZStack {
            SoftGroundShadow(w: w, h: h)

            if isSide {
                VehicleSideDrawing(
                    kind: kind,
                    flipped: flipped,
                    w: w,
                    h: h
                )
            } else {
                VehicleFaceDrawing(
                    kind: kind,
                    isFront: isFront,
                    w: w,
                    h: h
                )
            }
        }
    }
}

// MARK: - Shared Drawing Helpers

struct SoftGroundShadow: View {
    let w: CGFloat
    let h: CGFloat

    var body: some View {
        Ellipse()
            .fill(Color.black.opacity(0.045))
            .frame(width: w * 0.72, height: h * 0.052)
            .position(x: w / 2, y: h * 0.805)
    }
}

extension Path {
    mutating func roundedRect(_ rect: CGRect, radius: CGFloat) {
        let r = min(radius, min(rect.width, rect.height) / 2)
        move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                     control: CGPoint(x: rect.maxX, y: rect.minY))
        addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                     control: CGPoint(x: rect.maxX, y: rect.maxY))
        addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                     control: CGPoint(x: rect.minX, y: rect.maxY))
        addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                     control: CGPoint(x: rect.minX, y: rect.minY))
        closeSubpath()
    }
}

struct VehiclePalette {
    let body: Color
    let bodyDark: Color
    let glass: Color
    let stripe: Color?
    let marking: Color?

    static func forKind(_ kind: VehicleVisualKind) -> VehiclePalette {
        switch kind {
        case .lightFireAttackVehicle, .pumpLadder, .responderPerformanceVehicle, .hazmat, .fireTruck, .genericLarge:
            return VehiclePalette(
                body: Color.red.opacity(0.80),
                bodyDark: Color.red.opacity(0.95),
                glass: Color(.systemGray6).opacity(0.86),
                stripe: Color.white.opacity(0.95),
                marking: Color.yellow.opacity(0.90)
            )
        case .ambulance:
            return VehiclePalette(
                body: Color.white.opacity(0.96),
                bodyDark: Color(.systemGray4).opacity(0.75),
                glass: Color(.systemGray6).opacity(0.88),
                stripe: Color.red.opacity(0.78),
                marking: Color.blue.opacity(0.72)
            )
        case .medicalSupportVehicle:
            return VehiclePalette(
                body: Color.white.opacity(0.96),
                bodyDark: Color(.systemGray4).opacity(0.78),
                glass: Color(.systemGray6).opacity(0.88),
                stripe: Color.blue.opacity(0.70),
                marking: Color.red.opacity(0.72)
            )
        default:
            return VehiclePalette(
                body: Color(.systemGray3).opacity(0.92),
                bodyDark: Color(.systemGray2).opacity(0.72),
                glass: Color(.systemGray6).opacity(0.82),
                stripe: nil,
                marking: nil
            )
        }
    }
}

// MARK: - Face View

struct VehicleFaceDrawing: View {
    let kind: VehicleVisualKind
    let isFront: Bool
    let w: CGFloat
    let h: CGFloat

    private var palette: VehiclePalette { .forKind(kind) }
    private var cx: CGFloat { w / 2 }

    var body: some View {
        switch kind {
        case .lightFireAttackVehicle:
            compactEmergencyFace
        case .ambulance:
            ambulanceFace(isMSV: false)
        case .medicalSupportVehicle:
            ambulanceFace(isMSV: true)
        case .pumpLadder:
            ladderTruckFace
        case .responderPerformanceVehicle:
            boxyEmergencyFaceNoLight(title: "RPV")
        case .hazmat:
            boxyEmergencyFaceNoLight(title: "HAZMAT")
        case .fireTruck, .genericLarge:
            boxyEmergencyFace(title: "SCDF")
        case .mpv:
            mpvFace
        case .suv:
            suvFace
        case .sedan:
            sedanFace
        }
    }

    // MARK: Normal vehicles

    private var sedanFace: some View {
        // User preferred the previous SUV-like face proportions for sedan:
        // wider, clearer, less squashed than the original sedan.
        boxyPassengerFace(
            bodyW: w * 0.64,
            bodyH: h * 0.56,
            topY: h * 0.195,
            roofWRatio: 0.72,
            glassWRatio: 0.64,
            label: nil
        )
    }

    private var suvFace: some View {
        // More boxed-in SUV: higher rear/cabin and less sedan-like front.
        boxyPassengerFace(
            bodyW: w * 0.66,
            bodyH: h * 0.60,
            topY: h * 0.170,
            roofWRatio: 0.82,
            glassWRatio: 0.70,
            label: nil
        )
    }

    private var mpvFace: some View {
        // MPV should look like a box car/minivan: very tall, wide, and flat.
        mpvBoxFace
    }

    private var mpvBoxFace: some View {
        // MPV: intentionally squeezed-in box-car look.
        // Shorter width + taller body makes it look like a literal box instead of a long van.
        let bodyW = w * 0.33
        let bodyH = h * 0.66
        let topY = h * 0.125
        let leftX = cx - bodyW / 2
        let rightX = cx + bodyW / 2
        let bottomY = topY + bodyH

        return ZStack {
            faceTyres(leftX: leftX, rightX: rightX, bodyW: bodyW, bodyH: bodyH, bottomY: bottomY)

            Path { p in
                p.roundedRect(
                    CGRect(
                        x: leftX,
                        y: topY + bodyH * 0.045,
                        width: bodyW,
                        height: bodyH * 0.910
                    ),
                    radius: 0
                )
            }
            .fill(
                LinearGradient(
                    colors: [palette.bodyDark, palette.body, Color(.systemGray4).opacity(0.90)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                Path { p in
                    p.roundedRect(
                        CGRect(
                            x: leftX,
                            y: topY + bodyH * 0.045,
                            width: bodyW,
                            height: bodyH * 0.910
                        ),
                        radius: 0
                    )
                }
                .stroke(Color(.systemGray2).opacity(0.35), lineWidth: 1.2)
            )

            // Large square windscreen/rear window.
            RoundedRectangle(cornerRadius: 0)
                .fill(palette.glass)
                .frame(width: bodyW * 0.78, height: bodyH * 0.31)
                .position(x: cx, y: topY + bodyH * 0.250)

            Path { p in
                p.move(to: CGPoint(x: cx, y: topY + bodyH * 0.105))
                p.addLine(to: CGPoint(x: cx, y: topY + bodyH * 0.395))
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 1)

            // Boxy MPV front/rear grille panel.
            RoundedRectangle(cornerRadius: 0)
                .fill(Color(.systemGray5).opacity(0.90))
                .frame(width: bodyW * 0.58, height: bodyH * 0.145)
                .position(x: cx, y: topY + bodyH * 0.625)

            VStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(.systemGray3).opacity(0.95))
                        .frame(width: bodyW * 0.48, height: 2)
                }
            }
            .position(x: cx, y: topY + bodyH * 0.625)

            carLights(leftX: leftX, rightX: rightX, bodyW: bodyW, bodyH: bodyH, topY: topY)
            numberPlate(bodyW: bodyW, bodyH: bodyH, topY: topY, yRatio: isFront ? 0.80 : 0.70)
            mirrorPair(leftX: leftX, rightX: rightX, bodyW: bodyW, bodyH: bodyH, topY: topY)
        }
    }

    private func boxyPassengerFace(
        bodyW: CGFloat,
        bodyH: CGFloat,
        topY: CGFloat,
        roofWRatio: CGFloat,
        glassWRatio: CGFloat,
        label: String?
    ) -> some View {
        let leftX = cx - bodyW / 2
        let rightX = cx + bodyW / 2
        let bottomY = topY + bodyH
        let roofW = bodyW * roofWRatio
        let roofLeft = cx - roofW / 2
        let roofRight = cx + roofW / 2

        return ZStack {
            faceTyres(leftX: leftX, rightX: rightX, bodyW: bodyW, bodyH: bodyH, bottomY: bottomY)

            Path { p in
                // squarer/boxier front profile: taller cabin, flatter roof, more vertical sides
                p.move(to: CGPoint(x: leftX + bodyW * 0.07, y: bottomY))
                p.addLine(to: CGPoint(x: leftX + bodyW * 0.02, y: topY + bodyH * 0.43))
                p.addQuadCurve(to: CGPoint(x: leftX + bodyW * 0.15, y: topY + bodyH * 0.16),
                               control: CGPoint(x: leftX + bodyW * 0.03, y: topY + bodyH * 0.20))
                p.addLine(to: CGPoint(x: roofLeft, y: topY + bodyH * 0.075))
                p.addQuadCurve(to: CGPoint(x: roofRight, y: topY + bodyH * 0.075),
                               control: CGPoint(x: cx, y: topY + bodyH * 0.025))
                p.addLine(to: CGPoint(x: rightX - bodyW * 0.15, y: topY + bodyH * 0.16))
                p.addQuadCurve(to: CGPoint(x: rightX - bodyW * 0.02, y: topY + bodyH * 0.43),
                               control: CGPoint(x: rightX - bodyW * 0.03, y: topY + bodyH * 0.20))
                p.addLine(to: CGPoint(x: rightX - bodyW * 0.07, y: bottomY))
                p.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [palette.bodyDark, palette.body, Color(.systemGray4).opacity(0.90)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                Path { p in
                    p.move(to: CGPoint(x: leftX + bodyW * 0.07, y: bottomY))
                    p.addLine(to: CGPoint(x: leftX + bodyW * 0.02, y: topY + bodyH * 0.43))
                    p.addQuadCurve(to: CGPoint(x: leftX + bodyW * 0.15, y: topY + bodyH * 0.16),
                                   control: CGPoint(x: leftX + bodyW * 0.03, y: topY + bodyH * 0.20))
                    p.addLine(to: CGPoint(x: roofLeft, y: topY + bodyH * 0.075))
                    p.addQuadCurve(to: CGPoint(x: roofRight, y: topY + bodyH * 0.075),
                                   control: CGPoint(x: cx, y: topY + bodyH * 0.025))
                    p.addLine(to: CGPoint(x: rightX - bodyW * 0.15, y: topY + bodyH * 0.16))
                    p.addQuadCurve(to: CGPoint(x: rightX - bodyW * 0.02, y: topY + bodyH * 0.43),
                                   control: CGPoint(x: rightX - bodyW * 0.03, y: topY + bodyH * 0.20))
                    p.addLine(to: CGPoint(x: rightX - bodyW * 0.07, y: bottomY))
                    p.closeSubpath()
                }
                .stroke(Color(.systemGray2).opacity(0.35), lineWidth: 1.2)
            )

            RoundedRectangle(cornerRadius: 8)
                .fill(palette.glass)
                .frame(width: bodyW * glassWRatio, height: bodyH * 0.27)
                .position(x: cx, y: topY + bodyH * 0.255)

            Path { p in
                p.move(to: CGPoint(x: cx, y: topY + bodyH * 0.12))
                p.addLine(to: CGPoint(x: cx, y: topY + bodyH * 0.39))
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 1)

            mirrorPair(leftX: leftX, rightX: rightX, bodyW: bodyW, bodyH: bodyH, topY: topY)
            carLights(leftX: leftX, rightX: rightX, bodyW: bodyW, bodyH: bodyH, topY: topY)
            grilleOrBoot(leftX: leftX, rightX: rightX, bodyW: bodyW, bodyH: bodyH, topY: topY)
            numberPlate(bodyW: bodyW, bodyH: bodyH, topY: topY, yRatio: isFront ? 0.78 : 0.68)

            if let label {
                Text(label)
                    .font(.system(size: max(8, h * 0.032), weight: .black))
                    .foregroundColor(Color(.systemGray2).opacity(0.85))
                    .position(x: cx, y: topY + bodyH * 0.88)
            }
        }
    }

    private func realisticCarFace(bodyW: CGFloat, bodyH: CGFloat, topY: CGFloat, roofRatio: CGFloat, tallness: CGFloat) -> some View {
        let leftX = cx - bodyW / 2
        let rightX = cx + bodyW / 2
        let bottomY = topY + bodyH
        let winW = bodyW * (0.53 + tallness * 0.10)
        let winH = bodyH * (0.245 + tallness * 0.035)

        return ZStack {
            faceTyres(leftX: leftX, rightX: rightX, bodyW: bodyW, bodyH: bodyH, bottomY: bottomY)

            faceShell(leftX: leftX, rightX: rightX, bodyW: bodyW, bodyH: bodyH, topY: topY, bottomY: bottomY)
                .fill(
                    LinearGradient(
                        colors: [palette.bodyDark, palette.body, Color(.systemGray4).opacity(0.90)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(faceShell(leftX: leftX, rightX: rightX, bodyW: bodyW, bodyH: bodyH, topY: topY, bottomY: bottomY)
                    .stroke(Color(.systemGray2).opacity(0.35), lineWidth: 1.2))

            RoundedRectangle(cornerRadius: 8)
                .fill(palette.glass)
                .frame(width: winW, height: winH)
                .position(x: cx, y: topY + bodyH * 0.255)

            Path { p in
                p.move(to: CGPoint(x: cx, y: topY + bodyH * 0.125))
                p.addLine(to: CGPoint(x: cx, y: topY + bodyH * 0.375))
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 1)

            mirrorPair(leftX: leftX, rightX: rightX, bodyW: bodyW, bodyH: bodyH, topY: topY)
            carLights(leftX: leftX, rightX: rightX, bodyW: bodyW, bodyH: bodyH, topY: topY)
            grilleOrBoot(leftX: leftX, rightX: rightX, bodyW: bodyW, bodyH: bodyH, topY: topY)
            numberPlate(bodyW: bodyW, bodyH: bodyH, topY: topY, yRatio: isFront ? 0.78 : 0.68)

            Path { p in
                p.move(to: CGPoint(x: leftX + bodyW * (1 - roofRatio) / 2, y: topY + bodyH * 0.06))
                p.addQuadCurve(to: CGPoint(x: rightX - bodyW * (1 - roofRatio) / 2, y: topY + bodyH * 0.06),
                               control: CGPoint(x: cx, y: topY + bodyH * 0.01))
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 1)
        }
    }

    private func faceShell(leftX: CGFloat, rightX: CGFloat, bodyW: CGFloat, bodyH: CGFloat, topY: CGFloat, bottomY: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: leftX + bodyW * 0.08, y: bottomY))
        p.addLine(to: CGPoint(x: leftX, y: topY + bodyH * 0.60))
        p.addQuadCurve(to: CGPoint(x: leftX + bodyW * 0.11, y: topY + bodyH * 0.24),
                       control: CGPoint(x: leftX + bodyW * 0.01, y: topY + bodyH * 0.35))
        p.addQuadCurve(to: CGPoint(x: leftX + bodyW * 0.31, y: topY + bodyH * 0.06),
                       control: CGPoint(x: leftX + bodyW * 0.18, y: topY + bodyH * 0.08))
        p.addLine(to: CGPoint(x: rightX - bodyW * 0.31, y: topY + bodyH * 0.06))
        p.addQuadCurve(to: CGPoint(x: rightX - bodyW * 0.11, y: topY + bodyH * 0.24),
                       control: CGPoint(x: rightX - bodyW * 0.18, y: topY + bodyH * 0.08))
        p.addQuadCurve(to: CGPoint(x: rightX, y: topY + bodyH * 0.60),
                       control: CGPoint(x: rightX - bodyW * 0.01, y: topY + bodyH * 0.35))
        p.addLine(to: CGPoint(x: rightX - bodyW * 0.08, y: bottomY))
        p.closeSubpath()
        return p
    }

    private func faceTyres(leftX: CGFloat, rightX: CGFloat, bodyW: CGFloat, bodyH: CGFloat, bottomY: CGFloat) -> some View {
        let wheelW = bodyW * 0.105
        let wheelH = bodyH * 0.205
        let y = bottomY - wheelH * 0.35

        return ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(.systemGray2).opacity(0.95))
                .frame(width: wheelW, height: wheelH)
                .position(x: leftX + bodyW * 0.10, y: y)
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(.systemGray2).opacity(0.95))
                .frame(width: wheelW, height: wheelH)
                .position(x: rightX - bodyW * 0.10, y: y)
        }
    }

    private func mirrorPair(leftX: CGFloat, rightX: CGFloat, bodyW: CGFloat, bodyH: CGFloat, topY: CGFloat) -> some View {
        let y = topY + bodyH * 0.43
        let mirrorW = bodyW * 0.12
        let mirrorH = bodyH * 0.075

        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(palette.bodyDark.opacity(0.72))
                .frame(width: mirrorW, height: mirrorH)
                .rotationEffect(.degrees(-5))
                .position(x: leftX - mirrorW * 0.26, y: y)

            RoundedRectangle(cornerRadius: 4)
                .fill(palette.bodyDark.opacity(0.72))
                .frame(width: mirrorW, height: mirrorH)
                .rotationEffect(.degrees(5))
                .position(x: rightX + mirrorW * 0.26, y: y)
        }
    }

    private func carLights(leftX: CGFloat, rightX: CGFloat, bodyW: CGFloat, bodyH: CGFloat, topY: CGFloat) -> some View {
        let y = topY + bodyH * (isFront ? 0.56 : 0.50)
        let lightW = bodyW * 0.20
        let lightH = bodyH * 0.052
        let color = isFront ? Color.white.opacity(0.92) : Color.red.opacity(0.70)

        return ZStack {
            Capsule()
                .fill(color)
                .frame(width: lightW, height: lightH)
                .rotationEffect(.degrees(5))
                .position(x: leftX + bodyW * 0.22, y: y)

            Capsule()
                .fill(color)
                .frame(width: lightW, height: lightH)
                .rotationEffect(.degrees(-5))
                .position(x: rightX - bodyW * 0.22, y: y)
        }
    }

    private func grilleOrBoot(leftX: CGFloat, rightX: CGFloat, bodyW: CGFloat, bodyH: CGFloat, topY: CGFloat) -> some View {
        let y = topY + bodyH * (isFront ? 0.65 : 0.61)

        return ZStack {
            if isFront {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(.systemGray5).opacity(0.88))
                    .frame(width: bodyW * 0.45, height: bodyH * 0.105)
                    .position(x: cx, y: y)

                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color(.systemGray3).opacity(0.95))
                            .frame(width: bodyW * 0.39, height: 2)
                    }
                }
                .position(x: cx, y: y)

                Circle()
                    .fill(Color(.systemGray2).opacity(0.75))
                    .frame(width: bodyH * 0.09, height: bodyH * 0.09)
                    .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                    .position(x: cx, y: y)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray4).opacity(0.45))
                    .frame(width: bodyW * 0.50, height: bodyH * 0.14)
                    .position(x: cx, y: y)
            }
        }
    }

    private func numberPlate(bodyW: CGFloat, bodyH: CGFloat, topY: CGFloat, yRatio: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(.systemGray5).opacity(0.96))
            .frame(width: bodyW * 0.23, height: bodyH * 0.075)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.55), lineWidth: 0.8))
            .position(x: cx, y: topY + bodyH * yRatio)
    }

    // MARK: Emergency faces

    private var compactEmergencyFace: some View {
        let bodyW = w * 0.62
        let bodyH = h * 0.54
        let topY = h * 0.21
        let leftX = cx - bodyW / 2
        let rightX = cx + bodyW / 2
        let bottomY = topY + bodyH

        return ZStack {
            faceTyres(leftX: leftX, rightX: rightX, bodyW: bodyW, bodyH: bodyH, bottomY: bottomY)

            Path { p in
                p.roundedRect(CGRect(x: leftX, y: topY + bodyH * 0.10, width: bodyW, height: bodyH * 0.86), radius: 16)
            }
            .fill(LinearGradient(colors: [palette.bodyDark, palette.body], startPoint: .top, endPoint: .bottom))

            RoundedRectangle(cornerRadius: 8)
                .fill(palette.glass)
                .frame(width: bodyW * 0.60, height: bodyH * 0.28)
                .position(x: cx, y: topY + bodyH * 0.30)

            EmergencyLightBar(width: bodyW * 0.34, height: bodyH * 0.060)
                .position(x: cx, y: topY + bodyH * 0.10)

            Capsule()
                .fill(Color.white.opacity(0.95))
                .frame(width: bodyW * 0.80, height: bodyH * 0.075)
                .position(x: cx, y: topY + bodyH * 0.53)

            Text("RED RHINO")
                .font(.system(size: max(8, h * 0.032), weight: .black))
                .foregroundColor(.white)
                .position(x: cx, y: topY + bodyH * 0.66)

            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.systemGray6).opacity(0.90))
                .frame(width: bodyW * 0.46, height: bodyH * 0.11)
                .position(x: cx, y: topY + bodyH * 0.77)

            emergencyFaceLights(leftX: leftX, rightX: rightX, bodyW: bodyW, bodyH: bodyH, topY: topY)
        }
    }

    private func ambulanceFace(isMSV: Bool) -> some View {
        let bodyW = w * (isMSV ? 0.66 : 0.62)
        let bodyH = h * 0.58
        let topY = h * 0.19
        let leftX = cx - bodyW / 2
        let rightX = cx + bodyW / 2
        let bottomY = topY + bodyH

        return ZStack {
            faceTyres(leftX: leftX, rightX: rightX, bodyW: bodyW, bodyH: bodyH, bottomY: bottomY)

            Path { p in
                p.roundedRect(CGRect(x: leftX, y: topY + bodyH * 0.05, width: bodyW, height: bodyH * 0.90), radius: 16)
            }
            .fill(LinearGradient(colors: [palette.body, Color(.systemGray5).opacity(0.93)], startPoint: .top, endPoint: .bottom))
            .overlay(
                Path { p in
                    p.roundedRect(CGRect(x: leftX, y: topY + bodyH * 0.05, width: bodyW, height: bodyH * 0.90), radius: 16)
                }
                .stroke(Color(.systemGray3).opacity(0.65), lineWidth: 1.2)
            )

            RoundedRectangle(cornerRadius: 8)
                .fill(palette.glass)
                .frame(width: bodyW * 0.58, height: bodyH * 0.25)
                .position(x: cx, y: topY + bodyH * 0.27)

            EmergencyLightBar(width: bodyW * 0.30, height: bodyH * 0.055)
                .position(x: cx, y: topY + bodyH * 0.075)

            Capsule()
                .fill((isMSV ? Color.blue : Color.red).opacity(0.72))
                .frame(width: bodyW * 0.82, height: bodyH * 0.070)
                .position(x: cx, y: topY + bodyH * 0.54)

            MedicalCross(size: bodyH * 0.22, color: isMSV ? .blue : .red)
                .position(x: cx, y: topY + bodyH * 0.68)

            Text(isMSV ? "MSV" : "AMB")
                .font(.system(size: max(9, h * 0.040), weight: .black))
                .foregroundColor((isMSV ? Color.blue : Color.red).opacity(0.72))
                .position(x: cx, y: topY + bodyH * 0.84)

            emergencyFaceLights(leftX: leftX, rightX: rightX, bodyW: bodyW, bodyH: bodyH, topY: topY)
        }
    }

    private var ladderTruckFace: some View {
        let bodyW = w * 0.68
        let bodyH = h * 0.58
        let topY = h * 0.19
        let leftX = cx - bodyW / 2
        let rightX = cx + bodyW / 2
        let bottomY = topY + bodyH

        return ZStack {
            faceTyres(leftX: leftX, rightX: rightX, bodyW: bodyW, bodyH: bodyH, bottomY: bottomY)

            Path { p in
                p.roundedRect(CGRect(x: leftX, y: topY + bodyH * 0.14, width: bodyW, height: bodyH * 0.80), radius: 15)
            }
            .fill(LinearGradient(colors: [palette.bodyDark, palette.body], startPoint: .top, endPoint: .bottom))

            RoundedRectangle(cornerRadius: 8)
                .fill(palette.glass)
                .frame(width: bodyW * 0.58, height: bodyH * 0.24)
                .position(x: cx, y: topY + bodyH * 0.31)

            // Folded ladder visible even from front.
            ZStack {
                Capsule()
                    .fill(Color(.systemGray5).opacity(0.95))
                    .frame(width: bodyW * 0.72, height: bodyH * 0.060)
                Capsule()
                    .stroke(Color(.systemGray2).opacity(0.75), lineWidth: 2)
                    .frame(width: bodyW * 0.72, height: bodyH * 0.060)
            }
            .position(x: cx, y: topY + bodyH * 0.09)

            EmergencyLightBar(width: bodyW * 0.26, height: bodyH * 0.050)
                .position(x: cx, y: topY + bodyH * 0.17)

            Text("PL")
                .font(.system(size: max(10, h * 0.040), weight: .black))
                .foregroundColor(.white)
                .position(x: cx, y: topY + bodyH * 0.66)

            Capsule()
                .fill(Color.white.opacity(0.95))
                .frame(width: bodyW * 0.78, height: bodyH * 0.070)
                .position(x: cx, y: topY + bodyH * 0.54)

            emergencyFaceLights(leftX: leftX, rightX: rightX, bodyW: bodyW, bodyH: bodyH, topY: topY)
            numberPlate(bodyW: bodyW, bodyH: bodyH, topY: topY, yRatio: 0.80)
        }
    }

    private func boxyEmergencyFace(title: String) -> some View {
        let bodyW = w * 0.66
        let bodyH = h * 0.57
        let topY = h * 0.20
        let leftX = cx - bodyW / 2
        let rightX = cx + bodyW / 2
        let bottomY = topY + bodyH

        return ZStack {
            faceTyres(leftX: leftX, rightX: rightX, bodyW: bodyW, bodyH: bodyH, bottomY: bottomY)

            Path { p in
                p.roundedRect(CGRect(x: leftX, y: topY + bodyH * 0.10, width: bodyW, height: bodyH * 0.84), radius: 14)
            }
            .fill(LinearGradient(colors: [palette.bodyDark, palette.body], startPoint: .top, endPoint: .bottom))

            RoundedRectangle(cornerRadius: 8)
                .fill(palette.glass)
                .frame(width: bodyW * 0.60, height: bodyH * 0.26)
                .position(x: cx, y: topY + bodyH * 0.29)

            EmergencyLightBar(width: bodyW * 0.32, height: bodyH * 0.055)
                .position(x: cx, y: topY + bodyH * 0.09)

            Capsule()
                .fill(Color.white.opacity(0.95))
                .frame(width: bodyW * 0.78, height: bodyH * 0.070)
                .position(x: cx, y: topY + bodyH * 0.54)

            Text(title)
                .font(.system(size: max(9, h * 0.040), weight: .black))
                .foregroundColor(.white)
                .position(x: cx, y: topY + bodyH * 0.67)

            emergencyFaceLights(leftX: leftX, rightX: rightX, bodyW: bodyW, bodyH: bodyH, topY: topY)
        }
    }

    private func boxyEmergencyFaceNoLight(title: String) -> some View {
        let bodyW = w * (title == "RPV" ? 0.70 : 0.66)
        let bodyH = h * (title == "HAZMAT" ? 0.61 : 0.57)
        let topY = h * (title == "HAZMAT" ? 0.17 : 0.20)
        let leftX = cx - bodyW / 2
        let rightX = cx + bodyW / 2
        let bottomY = topY + bodyH

        return ZStack {
            faceTyres(leftX: leftX, rightX: rightX, bodyW: bodyW, bodyH: bodyH, bottomY: bottomY)

            Path { p in
                p.roundedRect(CGRect(x: leftX, y: topY + bodyH * 0.10, width: bodyW, height: bodyH * 0.84), radius: 14)
            }
            .fill(LinearGradient(colors: [palette.bodyDark, palette.body], startPoint: .top, endPoint: .bottom))

            RoundedRectangle(cornerRadius: 8)
                .fill(palette.glass)
                .frame(width: bodyW * 0.60, height: bodyH * 0.26)
                .position(x: cx, y: topY + bodyH * 0.29)

            Capsule()
                .fill(Color.white.opacity(0.95))
                .frame(width: bodyW * 0.78, height: bodyH * 0.070)
                .position(x: cx, y: topY + bodyH * 0.54)

            Text(title)
                .font(.system(size: max(9, h * 0.040), weight: .black))
                .foregroundColor(.white)
                .position(x: cx, y: topY + bodyH * 0.67)

            emergencyFaceLights(leftX: leftX, rightX: rightX, bodyW: bodyW, bodyH: bodyH, topY: topY)
        }
    }

    private func emergencyFaceLights(leftX: CGFloat, rightX: CGFloat, bodyW: CGFloat, bodyH: CGFloat, topY: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.88))
                .frame(width: bodyW * 0.16, height: bodyH * 0.055)
                .position(x: leftX + bodyW * 0.22, y: topY + bodyH * 0.77)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.88))
                .frame(width: bodyW * 0.16, height: bodyH * 0.055)
                .position(x: rightX - bodyW * 0.22, y: topY + bodyH * 0.77)
        }
    }
}

// MARK: - Side View

struct VehicleSideDrawing: View {
    let kind: VehicleVisualKind
    let flipped: Bool
    let w: CGFloat
    let h: CGFloat

    private var palette: VehiclePalette { .forKind(kind) }

    var body: some View {
        let transform = flipped
            ? CGAffineTransform(translationX: w, y: 0).scaledBy(x: -1, y: 1)
            : CGAffineTransform.identity

        ZStack {
            switch kind {
            case .suv:
                passengerVehicleSide(.suv, transform: transform)
            case .mpv:
                passengerVehicleSide(.mpv, transform: transform)
            case .lightFireAttackVehicle:
                lightFireAttackVehicleSide(transform: transform)
            case .ambulance:
                medicalVanSide(isMSV: false, transform: transform)
            case .medicalSupportVehicle:
                medicalVanSide(isMSV: true, transform: transform)
            case .pumpLadder:
                pumpLadderSide(transform: transform)
            case .responderPerformanceVehicle:
                responderPerformanceVehicleSide(transform: transform)
            case .hazmat:
                hazmatTruckSide(transform: transform)
            case .fireTruck, .genericLarge:
                fireTruckSide(transform: transform)
            case .sedan:
                passengerVehicleSide(.sedan, transform: transform)
            }
        }
    }

    private enum PassengerStyle {
        case sedan
        case suv
        case mpv
    }

    // MARK: Passenger side drawings

    private func passengerVehicleSide(_ style: PassengerStyle, transform: CGAffineTransform) -> some View {
        let m = passengerMetrics(style)
        let bodyPath = passengerBodyPath(style, m: m).applying(transform)
        let windowPath = passengerWindowPath(style, m: m).applying(transform)

        return ZStack {
            bodyPath
                .fill(
                    LinearGradient(
                        colors: [palette.bodyDark, palette.body, Color(.systemGray4).opacity(0.90)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(bodyPath.stroke(Color(.systemGray2).opacity(0.38), lineWidth: 1.2))

            windowPath.fill(palette.glass)
            windowPath.stroke(Color.white.opacity(0.35), lineWidth: 1)

            passengerDetails(style, m: m, transform: transform)
            wheels(frontX: m.left + m.width * (style == .mpv ? 0.11 : 0.22), rearX: m.left + m.width * (style == .mpv ? 0.89 : 0.76), y: m.groundY, r: m.wheelR, transform: transform)
            passengerLightsAndMirror(style, m: m, transform: transform)
        }
    }

    private func passengerMetrics(_ style: PassengerStyle) -> SideMetrics {
        let bodyW: CGFloat
        switch style {
        case .sedan:
            bodyW = w * 0.80
        case .suv:
            bodyW = w * 0.78
        case .mpv:
            // Final MPV tweak: another 0.75x shorter, literal box profile.
            bodyW = w * 0.345
        }

        let left = (w - bodyW) / 2
        let right = left + bodyW
        let wheelR = min(
            w * (style == .suv ? 0.053 : style == .mpv ? 0.043 : 0.048),
            h * (style == .suv ? 0.130 : style == .mpv ? 0.105 : 0.118)
        )
        let groundY = h * 0.775
        let sillY = groundY - wheelR * (style == .suv ? 0.15 : style == .mpv ? 0.20 : 0.28)

        return SideMetrics(left: left, right: right, width: bodyW, wheelR: wheelR, groundY: groundY, sillY: sillY)
    }

    private func passengerBodyPath(_ style: PassengerStyle, m: SideMetrics) -> Path {
        var p = Path()

        switch style {
        case .sedan:
            // User asked to reuse the previous SUV-looking silhouette for sedan.
            let hoodTop = m.sillY - h * 0.178
            let roofTop = m.sillY - h * 0.330
            let rearTop = m.sillY - h * 0.185

            p.move(to: CGPoint(x: m.left + m.width * 0.02, y: m.sillY))
            p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.09, y: hoodTop + h * 0.030),
                           control: CGPoint(x: m.left + m.width * 0.02, y: hoodTop + h * 0.070))
            p.addLine(to: CGPoint(x: m.left + m.width * 0.27, y: hoodTop))
            p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.36, y: roofTop + h * 0.035),
                           control: CGPoint(x: m.left + m.width * 0.31, y: hoodTop - h * 0.012))
            p.addLine(to: CGPoint(x: m.left + m.width * 0.73, y: roofTop + h * 0.035))
            p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.84, y: rearTop),
                           control: CGPoint(x: m.left + m.width * 0.80, y: roofTop + h * 0.075))
            p.addLine(to: CGPoint(x: m.right - m.width * 0.06, y: rearTop + h * 0.018))
            p.addQuadCurve(to: CGPoint(x: m.right - m.width * 0.02, y: m.sillY),
                           control: CGPoint(x: m.right - m.width * 0.01, y: rearTop + h * 0.080))
            p.closeSubpath()

        case .suv:
            // New SUV: short bonnet, upright cabin, high rear quarter; much boxier than sedan.
            let hoodTop = m.sillY - h * 0.215
            let roofTop = m.sillY - h * 0.385
            let rearTop = m.sillY - h * 0.285

            p.move(to: CGPoint(x: m.left + m.width * 0.025, y: m.sillY))
            p.addLine(to: CGPoint(x: m.left + m.width * 0.030, y: hoodTop + h * 0.055))
            p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.095, y: hoodTop),
                           control: CGPoint(x: m.left + m.width * 0.028, y: hoodTop + h * 0.012))
            // Shorter front bonnet
            p.addLine(to: CGPoint(x: m.left + m.width * 0.220, y: hoodTop - h * 0.006))
            // Upright A-pillar
            p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.335, y: roofTop + h * 0.040),
                           control: CGPoint(x: m.left + m.width * 0.270, y: hoodTop - h * 0.035))
            // Flat SUV roof
            p.addLine(to: CGPoint(x: m.left + m.width * 0.760, y: roofTop + h * 0.040))
            // Tall, high rear portion
            p.addLine(to: CGPoint(x: m.left + m.width * 0.900, y: rearTop))
            p.addLine(to: CGPoint(x: m.right - m.width * 0.030, y: rearTop + h * 0.025))
            p.addQuadCurve(to: CGPoint(x: m.right - m.width * 0.020, y: m.sillY),
                           control: CGPoint(x: m.right + m.width * 0.005, y: rearTop + h * 0.115))
            p.closeSubpath()

        case .mpv:
            // MPV: extremely short, tall, and angular. No rounded edges.
            let roofTop = m.sillY - h * 0.390
            let frontTop = m.sillY - h * 0.250
            let rearTop = m.sillY - h * 0.250

            p.move(to: CGPoint(x: m.left + m.width * 0.010, y: m.sillY))
            p.addLine(to: CGPoint(x: m.left + m.width * 0.010, y: frontTop))
            p.addLine(to: CGPoint(x: m.left + m.width * 0.135, y: roofTop))
            p.addLine(to: CGPoint(x: m.right - m.width * 0.010, y: roofTop))
            p.addLine(to: CGPoint(x: m.right - m.width * 0.010, y: rearTop))
            p.addLine(to: CGPoint(x: m.right - m.width * 0.010, y: m.sillY))
            p.closeSubpath()
        }

        return p
    }

    private func passengerWindowPath(_ style: PassengerStyle, m: SideMetrics) -> Path {
        var p = Path()

        switch style {
        case .sedan:
            // Match the previous SUV-like window style.
            let top = m.sillY - h * 0.300
            let base = m.sillY - h * 0.145
            p.move(to: CGPoint(x: m.left + m.width * 0.25, y: base))
            p.addLine(to: CGPoint(x: m.left + m.width * 0.34, y: top + h * 0.035))
            p.addLine(to: CGPoint(x: m.left + m.width * 0.72, y: top + h * 0.035))
            p.addLine(to: CGPoint(x: m.left + m.width * 0.84, y: base))
            p.closeSubpath()
        case .suv:
            // SUV window area shortened by about half so it no longer looks like a long sedan cabin.
            let top = m.sillY - h * 0.345
            let base = m.sillY - h * 0.160
            p.move(to: CGPoint(x: m.left + m.width * 0.310, y: base))
            p.addLine(to: CGPoint(x: m.left + m.width * 0.405, y: top + h * 0.042))
            p.addLine(to: CGPoint(x: m.left + m.width * 0.635, y: top + h * 0.042))
            p.addLine(to: CGPoint(x: m.left + m.width * 0.725, y: base))
            p.closeSubpath()
        case .mpv:
            let top = m.sillY - h * 0.358
            let base = m.sillY - h * 0.162
            p.move(to: CGPoint(x: m.left + m.width * 0.145, y: base))
            p.addLine(to: CGPoint(x: m.left + m.width * 0.260, y: top + h * 0.040))
            p.addLine(to: CGPoint(x: m.left + m.width * 0.740, y: top + h * 0.040))
            p.addLine(to: CGPoint(x: m.left + m.width * 0.860, y: base))
            p.closeSubpath()
        }

        return p
    }

    private func passengerDetails(_ style: PassengerStyle, m: SideMetrics, transform: CGAffineTransform) -> some View {
        let beltY = m.sillY - h * (style == .mpv ? 0.124 : 0.116)
        let lowerY = m.sillY - h * 0.050

        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: m.left + m.width * 0.10, y: beltY))
                p.addLine(to: CGPoint(x: m.right - m.width * 0.10, y: beltY))
                p.move(to: CGPoint(x: m.left + m.width * 0.18, y: lowerY))
                p.addLine(to: CGPoint(x: m.right - m.width * 0.18, y: lowerY))

                let door1 = m.left + m.width * (style == .mpv ? 0.36 : 0.48)
                let door2 = m.left + m.width * (style == .mpv ? 0.60 : 0.64)
                p.move(to: CGPoint(x: door1, y: m.sillY - h * 0.135))
                p.addLine(to: CGPoint(x: door1, y: m.sillY - h * 0.010))
                p.move(to: CGPoint(x: door2, y: m.sillY - h * 0.130))
                p.addLine(to: CGPoint(x: door2, y: m.sillY - h * 0.015))
            }
            .applying(transform)
            .stroke(Color(.systemGray2).opacity(0.50), lineWidth: 1.15)

            if style == .suv || style == .mpv {
                Path { p in
                    p.move(to: CGPoint(x: m.left + m.width * (style == .mpv ? 0.22 : 0.36),
                                       y: m.sillY - h * (style == .mpv ? 0.365 : 0.348)))
                    p.addLine(to: CGPoint(x: m.left + m.width * (style == .mpv ? 0.78 : 0.74),
                                          y: m.sillY - h * (style == .mpv ? 0.365 : 0.348)))
                }
                .applying(transform)
                .stroke(Color(.systemGray2).opacity(0.50), lineWidth: 1.4)
            }

            Path { p in
                let pillar1 = m.left + m.width * (style == .mpv ? 0.36 : style == .suv ? 0.49 : 0.51)
                let pillar2 = m.left + m.width * (style == .mpv ? 0.60 : style == .suv ? 0.66 : 0.65)
                p.move(to: CGPoint(x: pillar1, y: m.sillY - h * 0.288))
                p.addLine(to: CGPoint(x: pillar1, y: m.sillY - h * 0.135))
                p.move(to: CGPoint(x: pillar2, y: m.sillY - h * 0.288))
                p.addLine(to: CGPoint(x: pillar2, y: m.sillY - h * 0.135))
            }
            .applying(transform)
            .stroke(Color(.systemGray3).opacity(0.75), lineWidth: 3)

            ForEach([m.left + m.width * 0.43, m.left + m.width * 0.61], id: \.self) { x in
                Capsule()
                    .fill(Color(.systemGray2).opacity(0.60))
                    .frame(width: w * 0.032, height: h * 0.010)
                    .position(CGPoint(x: x, y: m.sillY - h * 0.105).applying(transform))
            }
        }
    }

    private func passengerLightsAndMirror(_ style: PassengerStyle, m: SideMetrics, transform: CGAffineTransform) -> some View {
        let frontLight = CGPoint(x: m.left + m.width * 0.055, y: m.sillY - h * 0.135).applying(transform)
        let rearLight = CGPoint(x: m.right - m.width * 0.055, y: m.sillY - h * 0.115).applying(transform)
        let mirror = CGPoint(x: m.left + m.width * (style == .mpv ? 0.225 : 0.265), y: m.sillY - h * 0.175).applying(transform)

        return ZStack {
            Capsule()
                .fill(Color.white.opacity(0.88))
                .frame(width: w * 0.040, height: h * 0.020)
                .position(frontLight)

            Capsule()
                .fill(Color.red.opacity(0.62))
                .frame(width: w * 0.040, height: h * 0.022)
                .position(rearLight)

            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.systemGray3).opacity(0.95))
                .frame(width: w * 0.035, height: h * 0.030)
                .position(mirror)
        }
    }

    // MARK: SCDF / medical side drawings

    private func lightFireAttackVehicleSide(transform: CGAffineTransform) -> some View {
        // LFAV / Red Rhino should read as a compact red 4x4 pickup/SUV with an equipment pod,
        // not a full-size box truck.
        let m = passengerMetrics(.suv)
        let bodyPath = redRhinoBody(m: m).applying(transform)
        let windowPath = redRhinoWindow(m: m).applying(transform)

        return ZStack {
            bodyPath
                .fill(LinearGradient(colors: [Color.red.opacity(0.96), Color.red.opacity(0.72)],
                                     startPoint: .top,
                                     endPoint: .bottom))
                .overlay(bodyPath.stroke(Color.red.opacity(0.60), lineWidth: 1.2))

            windowPath.fill(palette.glass)
            windowPath.stroke(Color.white.opacity(0.35), lineWidth: 1)

            // Rear equipment module/pod like the reference image.
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.78))
                .frame(width: m.width * 0.24, height: h * 0.235)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.28), lineWidth: 1)
                )
                .position(CGPoint(x: m.left + m.width * 0.73, y: m.sillY - h * 0.215).applying(transform))

            // Equipment panel details.
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.white.opacity(0.38), lineWidth: 1)
                    .frame(width: m.width * 0.055, height: h * 0.072)
                    .position(CGPoint(x: m.left + m.width * (0.66 + CGFloat(i) * 0.055),
                                      y: m.sillY - h * 0.220).applying(transform))
            }

            Capsule()
                .fill(Color.white.opacity(0.94))
                .frame(width: m.width * 0.70, height: h * 0.040)
                .position(CGPoint(x: m.left + m.width * 0.52, y: m.sillY - h * 0.112).applying(transform))

            Text("RED\nRHINO")
                .font(.system(size: max(7, h * 0.028), weight: .black))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .position(CGPoint(x: m.left + m.width * 0.50, y: m.sillY - h * 0.205).applying(transform))

            EmergencyLightBar(width: m.width * 0.15, height: h * 0.030)
                .position(CGPoint(x: m.left + m.width * 0.32, y: m.sillY - h * 0.348).applying(transform))

            wheels(frontX: m.left + m.width * 0.23,
                   rearX: m.left + m.width * 0.72,
                   y: m.groundY,
                   r: m.wheelR * 1.03,
                   transform: transform)

            emergencySideLights(m: SideMetrics(left: m.left, right: m.right, width: m.width,
                                               wheelR: m.wheelR, groundY: m.groundY, sillY: m.sillY),
                                transform: transform)
        }
    }

    private func medicalVanSide(isMSV: Bool, transform: CGAffineTransform) -> some View {
        // Ambulance should read as a shorter van, not a tall lorry.
        let m = truckMetrics(widthRatio: isMSV ? 0.73 : 0.525, wheelRatio: 0.045)
        let body = ambulanceBody(m: m, boxier: isMSV).applying(transform)
        let mainColor = isMSV ? Color.blue.opacity(0.66) : Color.red.opacity(0.72)

        return ZStack {
            body.fill(LinearGradient(colors: [Color.white.opacity(0.98), Color(.systemGray5).opacity(0.95)],
                                     startPoint: .top,
                                     endPoint: .bottom))
                .overlay(body.stroke(Color(.systemGray3).opacity(0.65), lineWidth: 1.2))

            RoundedRectangle(cornerRadius: 7)
                .fill(palette.glass)
                .frame(width: m.width * 0.22, height: h * 0.118)
                .position(CGPoint(x: m.left + m.width * 0.20, y: m.sillY - h * 0.238).applying(transform))

            RoundedRectangle(cornerRadius: 7)
                .fill(palette.glass)
                .frame(width: m.width * (isMSV ? 0.25 : 0.21), height: h * 0.108)
                .position(CGPoint(x: m.left + m.width * (isMSV ? 0.52 : 0.56), y: m.sillY - h * 0.225).applying(transform))

            Capsule()
                .fill(mainColor)
                .frame(width: m.width * 0.72, height: h * 0.044)
                .position(CGPoint(x: m.left + m.width * 0.55, y: m.sillY - h * 0.125).applying(transform))

            MedicalCross(size: h * 0.105, color: isMSV ? .blue : .red)
                .position(CGPoint(x: m.left + m.width * (isMSV ? 0.74 : 0.78), y: m.sillY - h * 0.230).applying(transform))

            Text(isMSV ? "MSV" : "AMBULANCE")
                .font(.system(size: max(7, h * 0.028), weight: .black))
                .foregroundColor(mainColor)
                .position(CGPoint(x: m.left + m.width * 0.50, y: m.sillY - h * 0.183).applying(transform))

            EmergencyLightBar(width: m.width * 0.14, height: h * 0.028)
                .position(CGPoint(x: m.left + m.width * 0.31, y: m.sillY - h * 0.335).applying(transform))

            wheels(frontX: m.left + m.width * 0.24, rearX: m.left + m.width * 0.76, y: m.groundY, r: m.wheelR, transform: transform)
            emergencySideLights(m: m, transform: transform)
        }
    }

    private func pumpLadderSide(transform: CGAffineTransform) -> some View {
        let m = truckMetrics(widthRatio: 0.86, wheelRatio: 0.046)
        let body = fireTruckBody(m: m).applying(transform)

        return ZStack {
            body.fill(LinearGradient(colors: [Color.red.opacity(0.96), Color.red.opacity(0.74)], startPoint: .top, endPoint: .bottom))
                .overlay(body.stroke(Color.red.opacity(0.55), lineWidth: 1.2))

            RoundedRectangle(cornerRadius: 6)
                .fill(palette.glass)
                .frame(width: m.width * 0.18, height: h * 0.145)
                .position(CGPoint(x: m.left + m.width * 0.15, y: m.sillY - h * 0.245).applying(transform))

            // The important part: visibly show the folded ladder and platform bucket.
            LadderAssembly(m: m, transform: transform, w: w, h: h)

            Capsule()
                .fill(Color.white.opacity(0.92))
                .frame(width: m.width * 0.52, height: h * 0.042)
                .position(CGPoint(x: m.left + m.width * 0.58, y: m.sillY - h * 0.118).applying(transform))

            Text("PL")
                .font(.system(size: max(8, h * 0.034), weight: .black))
                .foregroundColor(.white)
                .position(CGPoint(x: m.left + m.width * 0.45, y: m.sillY - h * 0.205).applying(transform))

            equipmentLines(m: m, transform: transform)
            wheels(frontX: m.left + m.width * 0.18, rearX: m.left + m.width * 0.78, y: m.groundY, r: m.wheelR, transform: transform)
            emergencySideLights(m: m, transform: transform)
        }
    }

    private func responderPerformanceVehicleSide(transform: CGAffineTransform) -> some View {
        // RPV reference reads like a long red bus/coach: low, long, many window panels.
        let m = truckMetrics(widthRatio: 0.88, wheelRatio: 0.043)
        let body = responderBusBody(m: m).applying(transform)

        return ZStack {
            body.fill(LinearGradient(colors: [Color.red.opacity(0.95), Color.red.opacity(0.70)],
                                     startPoint: .top,
                                     endPoint: .bottom))
                .overlay(body.stroke(Color.red.opacity(0.55), lineWidth: 1.2))

            // Long dark windscreen + side windows.
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(.systemGray6).opacity(0.86))
                .frame(width: m.width * 0.17, height: h * 0.145)
                .position(CGPoint(x: m.left + m.width * 0.14, y: m.sillY - h * 0.250).applying(transform))

            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(.systemGray6).opacity(0.84))
                    .frame(width: m.width * 0.090, height: h * 0.115)
                    .position(CGPoint(x: m.left + m.width * (0.33 + CGFloat(i) * 0.105),
                                      y: m.sillY - h * 0.250).applying(transform))
            }

            Capsule()
                .fill(Color.white.opacity(0.95))
                .frame(width: m.width * 0.60, height: h * 0.045)
                .position(CGPoint(x: m.left + m.width * 0.58, y: m.sillY - h * 0.120).applying(transform))

            Text("RPV")
                .font(.system(size: max(8, h * 0.034), weight: .black))
                .foregroundColor(.white)
                .position(CGPoint(x: m.left + m.width * 0.54, y: m.sillY - h * 0.190).applying(transform))

            wheels(frontX: m.left + m.width * 0.18, rearX: m.left + m.width * 0.79, y: m.groundY, r: m.wheelR, transform: transform)
            emergencySideLights(m: m, transform: transform)
        }
    }

    private func hazmatTruckSide(transform: CGAffineTransform) -> some View {
        // HazMat should read as a taller heavy appliance with a high rear module.
        let m = truckMetrics(widthRatio: 0.84, wheelRatio: 0.047)
        let body = hazmatBody(m: m).applying(transform)

        return ZStack {
            body.fill(LinearGradient(colors: [Color.red.opacity(0.96), Color.red.opacity(0.72)],
                                     startPoint: .top,
                                     endPoint: .bottom))
                .overlay(body.stroke(Color.red.opacity(0.55), lineWidth: 1.2))

            RoundedRectangle(cornerRadius: 7)
                .fill(palette.glass)
                .frame(width: m.width * 0.20, height: h * 0.145)
                .position(CGPoint(x: m.left + m.width * 0.16, y: m.sillY - h * 0.258).applying(transform))

            // Tall equipment/container section.
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    .frame(width: m.width * 0.115, height: h * 0.145)
                    .position(CGPoint(x: m.left + m.width * (0.41 + CGFloat(i) * 0.12),
                                      y: m.sillY - h * 0.240).applying(transform))
            }

            Capsule()
                .fill(Color.white.opacity(0.95))
                .frame(width: m.width * 0.58, height: h * 0.044)
                .position(CGPoint(x: m.left + m.width * 0.60, y: m.sillY - h * 0.120).applying(transform))

            Text("HAZMAT")
                .font(.system(size: max(8, h * 0.032), weight: .black))
                .foregroundColor(.white)
                .position(CGPoint(x: m.left + m.width * 0.58, y: m.sillY - h * 0.200).applying(transform))

            wheels(frontX: m.left + m.width * 0.18, rearX: m.left + m.width * 0.77, y: m.groundY, r: m.wheelR, transform: transform)
            emergencySideLights(m: m, transform: transform)
        }
    }

    private func responderBusBody(m: SideMetrics) -> Path {
        var p = Path()
        let roofTop = m.sillY - h * 0.365
        let bodyTop = m.sillY - h * 0.315
        p.move(to: CGPoint(x: m.left + m.width * 0.02, y: m.sillY))
        p.addLine(to: CGPoint(x: m.left + m.width * 0.02, y: bodyTop + h * 0.055))
        p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.10, y: roofTop),
                       control: CGPoint(x: m.left + m.width * 0.035, y: roofTop + h * 0.020))
        p.addLine(to: CGPoint(x: m.right - m.width * 0.07, y: roofTop + h * 0.010))
        p.addQuadCurve(to: CGPoint(x: m.right - m.width * 0.025, y: bodyTop + h * 0.040),
                       control: CGPoint(x: m.right - m.width * 0.020, y: roofTop + h * 0.060))
        p.addLine(to: CGPoint(x: m.right - m.width * 0.02, y: m.sillY))
        p.closeSubpath()
        return p
    }

    private func hazmatBody(m: SideMetrics) -> Path {
        var p = Path()
        let cabTop = m.sillY - h * 0.382
        let boxTop = m.sillY - h * 0.380
        let boxEnd = m.right - m.width * 0.025
        let cabEnd = m.left + m.width * 0.30

        p.move(to: CGPoint(x: m.left + m.width * 0.02, y: m.sillY))
        p.addLine(to: CGPoint(x: m.left + m.width * 0.02, y: cabTop + h * 0.070))
        p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.08, y: cabTop),
                       control: CGPoint(x: m.left + m.width * 0.025, y: cabTop + h * 0.015))
        p.addLine(to: CGPoint(x: cabEnd - m.width * 0.035, y: cabTop))
        p.addLine(to: CGPoint(x: cabEnd, y: boxTop + h * 0.025))
        p.addLine(to: CGPoint(x: boxEnd, y: boxTop))
        p.addQuadCurve(to: CGPoint(x: m.right - m.width * 0.015, y: boxTop + h * 0.040),
                       control: CGPoint(x: boxEnd + m.width * 0.015, y: boxTop))
        p.addLine(to: CGPoint(x: m.right - m.width * 0.020, y: m.sillY))
        p.closeSubpath()
        return p
    }

    private func fireTruckSide(transform: CGAffineTransform) -> some View {
        let m = truckMetrics(widthRatio: 0.84, wheelRatio: 0.047)
        let body = fireTruckBody(m: m).applying(transform)

        return ZStack {
            body.fill(LinearGradient(colors: [Color.red.opacity(0.96), Color.red.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                .overlay(body.stroke(Color.red.opacity(0.55), lineWidth: 1.2))

            RoundedRectangle(cornerRadius: 6)
                .fill(palette.glass)
                .frame(width: m.width * 0.19, height: h * 0.145)
                .position(CGPoint(x: m.left + m.width * 0.15, y: m.sillY - h * 0.245).applying(transform))

            Capsule()
                .fill(Color.white.opacity(0.92))
                .frame(width: m.width * 0.55, height: h * 0.042)
                .position(CGPoint(x: m.left + m.width * 0.58, y: m.sillY - h * 0.118).applying(transform))

            Text("SCDF")
                .font(.system(size: max(8, h * 0.034), weight: .black))
                .foregroundColor(.white)
                .position(CGPoint(x: m.left + m.width * 0.54, y: m.sillY - h * 0.205).applying(transform))

            equipmentLines(m: m, transform: transform)
            wheels(frontX: m.left + m.width * 0.18, rearX: m.left + m.width * 0.76, y: m.groundY, r: m.wheelR, transform: transform)
            emergencySideLights(m: m, transform: transform)
        }
    }

    private func redRhinoBody(m: SideMetrics) -> Path {
        var p = Path()
        let hoodTop = m.sillY - h * 0.175
        let roofTop = m.sillY - h * 0.335
        let rearTop = m.sillY - h * 0.210

        p.move(to: CGPoint(x: m.left + m.width * 0.03, y: m.sillY))
        p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.09, y: hoodTop + h * 0.035),
                       control: CGPoint(x: m.left + m.width * 0.02, y: hoodTop + h * 0.080))
        p.addLine(to: CGPoint(x: m.left + m.width * 0.26, y: hoodTop))
        p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.36, y: roofTop + h * 0.035),
                       control: CGPoint(x: m.left + m.width * 0.31, y: hoodTop - h * 0.012))
        p.addLine(to: CGPoint(x: m.left + m.width * 0.55, y: roofTop + h * 0.040))
        p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.61, y: rearTop),
                       control: CGPoint(x: m.left + m.width * 0.59, y: roofTop + h * 0.080))
        p.addLine(to: CGPoint(x: m.right - m.width * 0.055, y: rearTop))
        p.addQuadCurve(to: CGPoint(x: m.right - m.width * 0.025, y: m.sillY),
                       control: CGPoint(x: m.right - m.width * 0.005, y: rearTop + h * 0.080))
        p.closeSubpath()
        return p
    }

    private func redRhinoWindow(m: SideMetrics) -> Path {
        var p = Path()
        let top = m.sillY - h * 0.300
        let base = m.sillY - h * 0.150
        p.move(to: CGPoint(x: m.left + m.width * 0.25, y: base))
        p.addLine(to: CGPoint(x: m.left + m.width * 0.34, y: top + h * 0.035))
        p.addLine(to: CGPoint(x: m.left + m.width * 0.53, y: top + h * 0.040))
        p.addLine(to: CGPoint(x: m.left + m.width * 0.60, y: base))
        p.closeSubpath()
        return p
    }

    private func truckMetrics(widthRatio: CGFloat, wheelRatio: CGFloat) -> SideMetrics {
        let bodyW = w * widthRatio
        let left = (w - bodyW) / 2
        let right = left + bodyW
        let wheelR = min(w * wheelRatio, h * 0.120)
        let groundY = h * 0.778
        let sillY = groundY - wheelR * 0.34
        return SideMetrics(left: left, right: right, width: bodyW, wheelR: wheelR, groundY: groundY, sillY: sillY)
    }

    private func compactFireBody(m: SideMetrics) -> Path {
        var p = Path()
        let roofY = m.sillY - h * 0.365
        let bodyTop = m.sillY - h * 0.265
        p.move(to: CGPoint(x: m.left + m.width * 0.04, y: m.sillY))
        p.addLine(to: CGPoint(x: m.left + m.width * 0.04, y: bodyTop + h * 0.05))
        p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.18, y: roofY),
                       control: CGPoint(x: m.left + m.width * 0.06, y: roofY + h * 0.03))
        p.addLine(to: CGPoint(x: m.left + m.width * 0.38, y: roofY))
        p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.48, y: bodyTop),
                       control: CGPoint(x: m.left + m.width * 0.44, y: roofY + h * 0.06))
        p.addLine(to: CGPoint(x: m.right - m.width * 0.05, y: bodyTop))
        p.addQuadCurve(to: CGPoint(x: m.right - m.width * 0.02, y: bodyTop + h * 0.05),
                       control: CGPoint(x: m.right, y: bodyTop))
        p.addLine(to: CGPoint(x: m.right - m.width * 0.02, y: m.sillY))
        p.closeSubpath()
        return p
    }

    private func ambulanceBody(m: SideMetrics, boxier: Bool) -> Path {
        var p = Path()
        let cabTop = m.sillY - h * 0.335
        let boxTop = m.sillY - h * (boxier ? 0.325 : 0.300)
        let noseTop = m.sillY - h * 0.230

        p.move(to: CGPoint(x: m.left + m.width * 0.03, y: m.sillY))
        p.addLine(to: CGPoint(x: m.left + m.width * 0.03, y: noseTop))
        p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.20, y: cabTop),
                       control: CGPoint(x: m.left + m.width * 0.07, y: cabTop + h * 0.030))
        p.addLine(to: CGPoint(x: m.left + m.width * 0.36, y: boxTop))
        p.addLine(to: CGPoint(x: m.right - m.width * 0.035, y: boxTop))
        p.addQuadCurve(to: CGPoint(x: m.right - m.width * 0.02, y: boxTop + h * 0.030),
                       control: CGPoint(x: m.right - m.width * 0.01, y: boxTop))
        p.addLine(to: CGPoint(x: m.right - m.width * 0.02, y: m.sillY))
        p.closeSubpath()
        return p
    }

    private func fireTruckBody(m: SideMetrics) -> Path {
        var p = Path()
        let cabTop = m.sillY - h * 0.365
        let boxTop = m.sillY - h * 0.315
        let cabEnd = m.left + m.width * 0.30
        p.move(to: CGPoint(x: m.left + m.width * 0.02, y: m.sillY))
        p.addLine(to: CGPoint(x: m.left + m.width * 0.02, y: cabTop + h * 0.070))
        p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.08, y: cabTop),
                       control: CGPoint(x: m.left + m.width * 0.025, y: cabTop + h * 0.015))
        p.addLine(to: CGPoint(x: cabEnd - m.width * 0.035, y: cabTop))
        p.addLine(to: CGPoint(x: cabEnd, y: boxTop))
        p.addLine(to: CGPoint(x: m.right - m.width * 0.025, y: boxTop))
        p.addLine(to: CGPoint(x: m.right - m.width * 0.02, y: m.sillY))
        p.closeSubpath()
        return p
    }

    private func wheels(frontX: CGFloat, rearX: CGFloat, y: CGFloat, r: CGFloat, transform: CGAffineTransform) -> some View {
        ZStack {
            ForEach([frontX, rearX], id: \.self) { x in
                let pt = CGPoint(x: x, y: y).applying(transform)

                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: r * 2.58, height: r * 2.58)
                    .position(pt)

                Circle()
                    .fill(Color(.systemGray2).opacity(0.96))
                    .frame(width: r * 2, height: r * 2)
                    .position(pt)

                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: r * 1.05, height: r * 1.05)
                    .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                    .position(pt)

                ForEach(0..<6, id: \.self) { spoke in
                    Capsule()
                        .fill(Color(.systemGray3))
                        .frame(width: r * 0.08, height: r * 0.78)
                        .rotationEffect(.degrees(Double(spoke) * 30))
                        .position(pt)
                }
            }
        }
    }

    private func equipmentLines(m: SideMetrics, transform: CGAffineTransform) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.white.opacity(0.34), lineWidth: 1)
                    .frame(width: m.width * 0.14, height: h * 0.090)
                    .position(CGPoint(x: m.left + m.width * (0.46 + CGFloat(i) * 0.16),
                                      y: m.sillY - h * 0.220).applying(transform))
            }
        }
    }

    private func emergencySideLights(m: SideMetrics, transform: CGAffineTransform) -> some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.88))
                .frame(width: w * 0.036, height: h * 0.020)
                .position(CGPoint(x: m.left + m.width * 0.055, y: m.sillY - h * 0.115).applying(transform))

            Capsule()
                .fill(Color.yellow.opacity(0.85))
                .frame(width: w * 0.030, height: h * 0.018)
                .position(CGPoint(x: m.left + m.width * 0.45, y: m.sillY - h * 0.090).applying(transform))

            Capsule()
                .fill(Color.red.opacity(0.70))
                .frame(width: w * 0.036, height: h * 0.022)
                .position(CGPoint(x: m.right - m.width * 0.050, y: m.sillY - h * 0.115).applying(transform))
        }
    }
}

// MARK: - Emergency Drawing Components

struct EmergencyLightBar: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: height * 0.25)
                .fill(Color.blue.opacity(0.82))
            RoundedRectangle(cornerRadius: height * 0.25)
                .fill(Color.red.opacity(0.82))
        }
        .frame(width: width, height: height)
        .overlay(
            RoundedRectangle(cornerRadius: height * 0.25)
                .stroke(Color.white.opacity(0.60), lineWidth: 0.8)
        )
    }
}

struct MedicalCross: View {
    let size: CGFloat
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.06)
                .fill(color.opacity(0.78))
                .frame(width: size * 0.32, height: size)
            RoundedRectangle(cornerRadius: size * 0.06)
                .fill(color.opacity(0.78))
                .frame(width: size, height: size * 0.32)
        }
    }
}

struct LadderAssembly: View {
    let m: SideMetrics
    let transform: CGAffineTransform
    let w: CGFloat
    let h: CGFloat

    var body: some View {
        ZStack {
            ladderRail(yOffset: 0)
            ladderRail(yOffset: h * 0.032)

            ForEach(0..<9, id: \.self) { i in
                let x = m.left + m.width * (0.34 + CGFloat(i) * 0.050)
                Path { p in
                    p.move(to: CGPoint(x: x, y: m.sillY - h * 0.410))
                    p.addLine(to: CGPoint(x: x + m.width * 0.015, y: m.sillY - h * 0.378))
                }
                .applying(transform)
                .stroke(Color(.systemGray3).opacity(0.95), lineWidth: 1.3)
            }

            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5).opacity(0.95))
                .frame(width: m.width * 0.09, height: h * 0.062)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(.systemGray2), lineWidth: 1))
                .position(CGPoint(x: m.left + m.width * 0.84, y: m.sillY - h * 0.388).applying(transform))

            Circle()
                .fill(Color(.systemGray4))
                .frame(width: h * 0.080, height: h * 0.080)
                .overlay(Circle().stroke(Color(.systemGray2), lineWidth: 1))
                .position(CGPoint(x: m.left + m.width * 0.38, y: m.sillY - h * 0.330).applying(transform))
        }
    }

    private func ladderRail(yOffset: CGFloat) -> some View {
        Path { p in
            p.move(to: CGPoint(x: m.left + m.width * 0.30, y: m.sillY - h * 0.410 + yOffset))
            p.addLine(to: CGPoint(x: m.left + m.width * 0.83, y: m.sillY - h * 0.390 + yOffset))
        }
        .applying(transform)
        .stroke(Color(.systemGray5).opacity(0.98), lineWidth: 3)
    }
}

// MARK: - Side Metrics

struct SideMetrics {
    let left: CGFloat
    let right: CGFloat
    let width: CGFloat
    let wheelR: CGFloat
    let groundY: CGFloat
    let sillY: CGFloat
}
