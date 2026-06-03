import UIKit
import SwiftUI
import AVFoundation
import FirebaseFirestore
import PhotosUI
import Vision

// MARK: - Report Scanner View
struct ReportScannerView: View {

    @Environment(\.dismiss) var dismiss
    @State private var scannedCode: String? = nil
    @State private var manualCode: String = ""
    @State private var report: ReportEntry? = nil
    @State private var errorMessage: String? = nil
    @State private var isLoading = false
    @State private var showManualEntry = false
    @State private var cameraPermissionDenied = false
    @State private var selectedPDFURL: URL? = nil
    @State private var pdfErrorMessage: String? = nil
    @State private var selectedBarcodePhotoItem: PhotosPickerItem? = nil
    @State private var isReadingBarcodePhoto = false
    @State private var isCameraFrozen = false      // true while a result card is shown
    @State private var scannerRestartToken: UUID = UUID()

    private var isBusy: Bool {
        isLoading || isReadingBarcodePhoto
    }

    var body: some View {
        ZStack {

            // MARK: Camera background
            if !cameraPermissionDenied {
                BarcodeScannerRepresentable(
                    isFrozen: isCameraFrozen,
                    restartToken: scannerRestartToken,
                    onScan: { code in
                        guard scannedCode == nil, report == nil else { return }
                        let cleanedCode = cleanBarcode(code)
                        scannedCode = cleanedCode
                        lookupReport(code: cleanedCode)
                    },
                    onPermissionDenied: {
                        cameraPermissionDenied = true
                        showManualEntry = true
                    }
                )
                .ignoresSafeArea()
                // Prevent the full-screen camera layer from eating taps
                // while the result card is visible.
                .allowsHitTesting(!isCameraFrozen)
            } else {
                Color.black.ignoresSafeArea()
            }

            // Scan frame overlay (only when idle)
            if report == nil && !isBusy && !showManualEntry {
                ScanFrameOverlay()
            }

            // MARK: UI overlay
            VStack(spacing: 0) {

                Spacer()

                // Loading indicator
                if isBusy {
                    HStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text(isReadingBarcodePhoto ? "Reading barcode from photo…" : "Looking up report…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 16)
                }

                // Error banner
                if let errorMessage, report == nil {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button {
                                prepareForReportRescan(clearError: true)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }

                        Button {
                            prepareForReportRescan(clearError: true)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "barcode.viewfinder")
                                Text("Scan Again")
                            }
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(HTXTheme.primaryPurple)
                            .clipShape(Capsule())
                        }
                        .disabled(isBusy)
                        .opacity(isBusy ? 0.55 : 1)
                    }
                    .padding(14)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }

                // Report result card
                if let report {
                    ReportResultCard(
                        report: report,
                        onViewPDF: { openPDF(for: report) },
                        onScanAnother: {
                            resetForAnotherLookup()
                        }
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }

                if let pdfErrorMessage, report != nil {
                    Text(pdfErrorMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                }

                // Bottom control panel
                VStack(spacing: 12) {

                    if showManualEntry && report == nil {
                        // Manual barcode entry
                        VStack(spacing: 10) {
                            Text("Enter Barcode Number")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)

                            HStack(spacing: 10) {
                                TextField("12-digit barcode number", text: $manualCode)
                                    .keyboardType(.numberPad)
                                    .padding(12)
                                    .background(Color(.systemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .frame(maxWidth: .infinity)

                                Button {
                                    let trimmed = cleanBarcode(manualCode)
                                    guard !trimmed.isEmpty else { return }
                                    scannedCode = trimmed
                                    lookupReport(code: trimmed)
                                } label: {
                                    Text("Search")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(HTXTheme.primaryPurple)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .disabled(isBusy)
                                .opacity(isBusy ? 0.55 : 1)
                            }
                        }
                        .padding(.horizontal)
                    }

                    if report == nil {
                        HStack(spacing: 10) {
                            Button {
                                withAnimation(.spring(response: 0.35)) {
                                    showManualEntry.toggle()
                                    if !showManualEntry {
                                        // Reset when switching back to camera
                                        errorMessage = nil
                                        scannedCode = nil
                                        manualCode = ""
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: showManualEntry ? "camera.fill" : "keyboard")
                                        .font(.subheadline)
                                    Text(showManualEntry ? "Use Camera" : "Type Manually")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Capsule())
                            }
                            .disabled(isBusy)

                            PhotosPicker(
                                selection: $selectedBarcodePhotoItem,
                                matching: .images
                            ) {
                                HStack(spacing: 6) {
                                    Image(systemName: "photo.on.rectangle")
                                        .font(.subheadline)
                                    Text("Upload Photo")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(HTXTheme.primaryPurple.opacity(0.88))
                                .clipShape(Capsule())
                            }
                            .disabled(isBusy)
                            .opacity(isBusy ? 0.55 : 1)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 40)
                .padding(.top, 8)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.65)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .navigationTitle("Scan Report Barcode")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedPDFURL) { url in
            ReportPDFPreviewView(url: url)
        }
        .onChange(of: selectedBarcodePhotoItem) { _, newItem in
            guard let newItem else { return }
            readBarcodeFromPhoto(newItem)
        }
    }

    // MARK: - Firestore Lookup
    private func lookupReport(code: String) {
        let cleanedCode = cleanBarcode(code)
        guard !cleanedCode.isEmpty else {
            errorMessage = "Please enter or scan a valid barcode number."
            return
        }

        isLoading = true
        errorMessage = nil
        pdfErrorMessage = nil

        Firestore.firestore()
            .collection("reports")
            .document(cleanedCode)
            .getDocument { snapshot, error in
                DispatchQueue.main.async {
                    isLoading = false

                    if let error {
                        self.errorMessage = "Could not look up report: \(error.localizedDescription). Tap Scan Again to try another barcode."
                        self.freezeReportScannerAfterError()
                        return
                    }

                    guard let data = snapshot?.data(), !data.isEmpty else {
                        self.errorMessage = "No report found for barcode: \(cleanedCode). Tap Scan Again to try another barcode."
                        self.freezeReportScannerAfterError()
                        return
                    }

                    guard
                        let reportNo = data["reportNo"] as? String,
                        let plate    = data["plate"]    as? String
                    else {
                        self.errorMessage = "Report data is incomplete. Tap Scan Again to try another barcode."
                        self.freezeReportScannerAfterError()
                        return
                    }

                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()

                    self.report = ReportEntry(
                        id:             snapshot!.documentID,
                        reportNo:       reportNo,
                        plate:          plate,
                        carType:        data["carType"]        as? String ?? "-",
                        generatedBy:    data["generatedBy"]    as? String ?? "-",
                        detectionCount: data["detectionCount"] as? Int    ?? 0,
                        createdAt:      createdAt,
                        barcodeId:      data["barcodeId"]      as? String ?? snapshot!.documentID,
                        pdfFileName:   data["pdfFileName"]   as? String,
                        pdfBase64:     data["pdfBase64"]     as? String,
                        pdfStoragePath: data["pdfStoragePath"] as? String
                    )
                    // Freeze the camera now that we have a result — regardless
                    // of whether the code came from camera, manual entry, or photo.
                    self.isCameraFrozen = true
                }
            }
    }

    // MARK: - Barcode Photo Upload
    private func readBarcodeFromPhoto(_ item: PhotosPickerItem) {
        isReadingBarcodePhoto = true
        errorMessage = nil
        pdfErrorMessage = nil
        scannedCode = nil
        report = nil

        Task {
            defer {
                Task { @MainActor in
                    selectedBarcodePhotoItem = nil
                    isReadingBarcodePhoto = false
                }
            }

            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let cgImage = image.normalizedForBarcodeScanning().cgImage else {
                    await MainActor.run {
                        errorMessage = "Could not read that image. Please try another photo."
                    }
                    return
                }

                let detectedCode = try await detectBarcode(in: cgImage)
                let cleanedCode = cleanBarcode(detectedCode)

                guard !cleanedCode.isEmpty else {
                    await MainActor.run {
                        errorMessage = "A barcode was detected, but it did not contain a valid number."
                    }
                    return
                }

                await MainActor.run {
                    scannedCode = cleanedCode
                    manualCode = cleanedCode
                    showManualEntry = true
                    lookupReport(code: cleanedCode)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "No barcode found in that photo. Try a clearer, straight-on image of the barcode."
                }
            }
        }
    }

    private func detectBarcode(in cgImage: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = (request.results as? [VNBarcodeObservation]) ?? []
                let payload = observations
                    .compactMap { $0.payloadStringValue }
                    .map { cleanBarcode($0) }
                    .first { !$0.isEmpty }

                if let payload {
                    continuation.resume(returning: payload)
                } else {
                    continuation.resume(throwing: BarcodePhotoError.noBarcodeFound)
                }
            }

            request.symbologies = [
                .code128,
                .qr,
                .ean13,
                .ean8
            ]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func openPDF(for report: ReportEntry) {
        isLoading = true
        pdfErrorMessage = nil

        ReportStore.resolvePDFURL(for: report) { url in
            isLoading = false
            guard let url else {
                pdfErrorMessage = "This report was found, but the PDF file is not available. Make sure Firebase Storage is enabled and the report has pdfStoragePath."
                return
            }
            selectedPDFURL = url
        }
    }


    private func freezeReportScannerAfterError() {
        // Keep the camera preview frozen behind the error card so the same
        // bad barcode is not scanned repeatedly. The Scan Again button calls
        // prepareForReportRescan(clearError: true), which unfreezes and restarts.
        isCameraFrozen = true
        report = nil
        pdfErrorMessage = nil
        selectedBarcodePhotoItem = nil
        isReadingBarcodePhoto = false
        showManualEntry = false
    }

    private func prepareForReportRescan(clearError: Bool) {
        if clearError {
            errorMessage = nil
        }
        scannedCode = nil
        report = nil
        pdfErrorMessage = nil
        manualCode = ""
        selectedBarcodePhotoItem = nil
        isReadingBarcodePhoto = false
        isCameraFrozen = false
        showManualEntry = false
        scannerRestartToken = UUID()
    }

    private func resetForAnotherLookup() {
        report = nil
        scannedCode = nil
        errorMessage = nil
        pdfErrorMessage = nil
        manualCode = ""
        showManualEntry = false
        selectedBarcodePhotoItem = nil
        isReadingBarcodePhoto = false
        isCameraFrozen = false
        // Bump token so updateUIViewController fires and restarts the session.
        scannerRestartToken = UUID()
    }

    private func cleanBarcode(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isNumber }
    }
}

private enum BarcodePhotoError: Error {
    case noBarcodeFound
}

private extension UIImage {
    func normalizedForBarcodeScanning() -> UIImage {
        guard imageOrientation != .up else { return self }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Report Result Card
private struct ReportResultCard: View {
    let report: ReportEntry
    let onViewPDF: () -> Void
    let onScanAnother: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            Label("Report Found", systemImage: "checkmark.seal.fill")
                .font(.headline.weight(.bold))
                .foregroundColor(.green)

            Divider()

            VStack(spacing: 8) {
                ResultRow(icon: "car.fill",             label: "Plate",        value: report.plate)
                ResultRow(icon: "doc.text",             label: "Report No.",   value: report.reportNo)
                ResultRow(icon: "barcode",              label: "Barcode",      value: report.barcodeId)
                ResultRow(icon: "car.2.fill",           label: "Vehicle Type", value: report.carType)
                ResultRow(icon: "exclamationmark.triangle", label: "Cases",    value: "\(report.detectionCount)")
                ResultRow(icon: "person.fill",          label: "Officer",      value: report.generatedBy)
                ResultRow(icon: "calendar",             label: "Date",         value: report.dateString)
            }

            Button(action: onViewPDF) {
                HStack {
                    Image(systemName: "doc.richtext.fill")
                    Text(report.hasPDF ? "View PDF Report" : "PDF Not Saved")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(report.hasPDF ? HTXTheme.primaryPurple : Color.gray)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button(action: onScanAnother) {
                HStack {
                    Image(systemName: "barcode.viewfinder")
                    Text("Scan Another Report")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .foregroundColor(HTXTheme.primaryPurple)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(HTXTheme.primaryPurple, lineWidth: 1.5)
                )
            }
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.green.opacity(0.3), lineWidth: 1.5)
        )
    }
}

private struct ResultRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(HTXTheme.primaryPurple)
                .frame(width: 18)

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()
        }
    }
}

// MARK: - Scan Frame Overlay
private struct ScanFrameOverlay: View {
    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 14) {
                // Corner-bracket scan frame
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        .frame(width: 260, height: 120)

                    // Corners
                    ForEach(["topLeft", "topRight", "bottomLeft", "bottomRight"], id: \.self) { corner in
                        CornerBracket(corner: corner)
                    }
                }

                Text("Point at the barcode on the report")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .shadow(radius: 2)
            }

            Spacer()
            Spacer()
        }
    }
}

private struct CornerBracket: View {
    let corner: String
    private let size: CGFloat = 22
    private let thickness: CGFloat = 3

    var body: some View {
        let isTop    = corner.hasPrefix("top")
        let isLeft   = corner.hasSuffix("Left")
        let xOffset: CGFloat = isLeft ? -130 + size / 2 : 130 - size / 2
        let yOffset: CGFloat = isTop  ? -60  + size / 2 : 60  - size / 2

        return ZStack {
            // Horizontal arm
            Rectangle()
                .frame(width: size, height: thickness)
                .offset(x: isLeft ? size / 2 - thickness / 2 : -(size / 2 - thickness / 2))

            // Vertical arm
            Rectangle()
                .frame(width: thickness, height: size)
                .offset(y: isTop ? size / 2 - thickness / 2 : -(size / 2 - thickness / 2))
        }
        .foregroundColor(.white)
        .offset(x: xOffset, y: yOffset)
    }
}

// MARK: - Camera Scanner (reads Code 128 barcodes)
struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    var isFrozen: Bool
    var restartToken: UUID
    var onScan: (String) -> Void
    var onPermissionDenied: () -> Void
    /// Must match the SwiftUI guide rectangle drawn in the overlay.
    var scanWindowSize: CGSize = CGSize(width: 260, height: 120)
    /// IU barcodes are tiny 1D barcodes, so allow scanning the full camera frame.
    /// Report barcodes keep this false so the scanner stays tied to the guide box.
    var scanFullFrame: Bool = false

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let vc = BarcodeScannerViewController()
        vc.scanWindowSize = scanWindowSize
        vc.scanFullFrame = scanFullFrame
        vc.onScan = onScan
        vc.onPermissionDenied = onPermissionDenied
        return vc
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {
        uiViewController.scanWindowSize = scanWindowSize
        uiViewController.scanFullFrame = scanFullFrame
        uiViewController.updateScanWindow()

        if isFrozen {
            uiViewController.stopSession()
            return
        }

        if context.coordinator.lastRestartToken != restartToken {
            context.coordinator.lastRestartToken = restartToken
            uiViewController.restartSession()
        } else {
            // Important for the initial camera presentation: if the view was
            // created before permission/configuration completed, this makes sure
            // the capture session actually starts once the view is ready.
            uiViewController.startSessionIfNeeded()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(token: restartToken) }

    final class Coordinator {
        var lastRestartToken: UUID
        init(token: UUID) { lastRestartToken = token }
    }
}

final class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    var onScan: ((String) -> Void)?
    var onPermissionDenied: (() -> Void)?

    /// The visible scan-window size in points (matches the SwiftUI guide rectangle).
    /// Set this before the view appears. Defaults to 260×120 (report scanner).
    var scanWindowSize: CGSize = CGSize(width: 260, height: 120) {
        didSet { updateScanWindow() }
    }

    /// When true, AVFoundation scans the whole frame instead of only the guide rectangle.
    /// This is intentionally used for IU barcode scanning because IU labels are small,
    /// tilted, and often behind glass.
    var scanFullFrame: Bool = false {
        didSet { updateScanWindow() }
    }

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "np299.barcode.session.queue")
    private let metadataOutput = AVCaptureMetadataOutput()

    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var captureDevice: AVCaptureDevice?
    private var isConfigured = false
    private var hasDeliveredScan = false

    // Rotation coordinator (iOS 17+) — keeps preview upright when device rotates.
    @available(iOS 17.0, *)
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator? {
        get { _rotationCoordinator as? AVCaptureDevice.RotationCoordinator }
        set { _rotationCoordinator = newValue }
    }
    private var _rotationCoordinator: AnyObject?
    private var rotationObservation: NSKeyValueObservation?

    // Lock scanner UI to portrait; the camera feed stays horizon-level via the coordinator.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        checkPermissionAndSetup()
    }

    deinit {
        rotationObservation?.invalidate()
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        updatePreviewRotation()
        updateScanWindow()
    }

    /// Returns the guide rectangle in the view's coordinate space.
    /// The SwiftUI overlay places the guide slightly above centre, so the scanner
    /// uses the same approximate placement instead of assuming the exact middle.
    private var scanWindowRect: CGRect {
        let viewSize = view.bounds.size
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }

        let width = min(scanWindowSize.width, viewSize.width - 48)
        let height = min(scanWindowSize.height, viewSize.height - 160)
        let originX = (viewSize.width - width) / 2

        // This matches the overlay that has one Spacer above and roughly two
        // Spacers below. The clamp prevents the rect from moving under the notch
        // or bottom controls on smaller devices.
        let desiredMidY = viewSize.height * 0.38
        let minY: CGFloat = view.safeAreaInsets.top + 80
        let maxY: CGFloat = viewSize.height - view.safeAreaInsets.bottom - 180 - height
        let originY = (desiredMidY - height / 2).clamped(to: minY...max(minY, maxY))

        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    // MARK: - Rotation

    private func setupRotationCoordinator() {
        guard #available(iOS 17.0, *),
              let device = captureDevice,
              let preview = previewLayer
        else { return }

        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: preview)
        rotationCoordinator = coordinator

        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updatePreviewRotation()
                self?.updateScanWindow()
            }
        }
    }

    private func updatePreviewRotation() {
        guard #available(iOS 17.0, *), let coordinator = rotationCoordinator else {
            if let connection = previewLayer?.connection,
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            return
        }

        let angle = coordinator.videoRotationAngleForHorizonLevelPreview
        if let connection = previewLayer?.connection,
           connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    // MARK: - Permission + setup

    private func checkPermissionAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.setupCamera() : self?.onPermissionDenied?()
                }
            }
        default:
            onPermissionDenied?()
        }
    }

    private func setupCamera() {
        guard !isConfigured else {
            startSessionIfNeeded()
            return
        }

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device)
        else {
            onPermissionDenied?()
            return
        }

        captureDevice = device

        session.beginConfiguration()
        session.sessionPreset = .high

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        guard session.canAddOutput(metadataOutput) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(metadataOutput)

        metadataOutput.setMetadataObjectsDelegate(self, queue: .main)

        let desiredTypes: [AVMetadataObject.ObjectType] = [
            .code128,
            .code39,
            .code39Mod43,
            .code93,
            .ean13,
            .ean8,
            .upce,
            .interleaved2of5,
            .itf14,
            .qr,
            .pdf417,
            .aztec,
            .dataMatrix
        ]
        metadataOutput.metadataObjectTypes = desiredTypes.filter {
            metadataOutput.availableMetadataObjectTypes.contains($0)
        }

        session.commitConfiguration()
        isConfigured = true

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview

        setupRotationCoordinator()
        updatePreviewRotation()
        updateScanWindow()
        startSessionIfNeeded()
    }

    // MARK: - Scan window

    func updateScanWindow() {
        if scanFullFrame {
            metadataOutput.rectOfInterest = CGRect(x: 0, y: 0, width: 1, height: 1)
            return
        }

        guard let previewLayer, !scanWindowRect.isEmpty else { return }

        // Use AVFoundation's own conversion so rectOfInterest stays correct
        // even with resizeAspectFill, device rotation, and different screen sizes.
        let metadataRect = previewLayer.metadataOutputRectConverted(fromLayerRect: scanWindowRect)
        let clampedRect = CGRect(
            x: metadataRect.origin.x.clamped(to: 0...1),
            y: metadataRect.origin.y.clamped(to: 0...1),
            width: metadataRect.width.clamped(to: 0...1),
            height: metadataRect.height.clamped(to: 0...1)
        )

        guard clampedRect.width > 0, clampedRect.height > 0 else { return }
        metadataOutput.rectOfInterest = clampedRect
    }

    // MARK: - Metadata delegate

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasDeliveredScan else { return }

        guard
            let preview = previewLayer,
            let obj = metadataObjects
                .compactMap({ $0 as? AVMetadataMachineReadableCodeObject })
                .first(where: { ($0.stringValue ?? "").isEmpty == false }),
            let code = obj.stringValue,
            !code.isEmpty
        else { return }

        // Safety filter: report scanning stays tied to the visible guide.
        // IU scanning intentionally skips this because the IU label is tiny and
        // often sits outside the guide even when the camera can read it.
        if !scanFullFrame, let transformed = preview.transformedMetadataObject(for: obj) {
            let looseWindow = scanWindowRect.insetBy(dx: -90, dy: -70)
            guard looseWindow.intersects(transformed.bounds) || looseWindow.contains(transformed.bounds.center) else {
                return
            }
        }

        hasDeliveredScan = true
        stopSession()
        onScan?(code)
    }

    // MARK: - Session control

    func startSessionIfNeeded() {
        guard isConfigured else { return }
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func restartSession() {
        hasDeliveredScan = false
        startSessionIfNeeded()
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Legacy QRScannerRepresentable (kept for compatibility)
struct QRScannerRepresentable: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let vc = BarcodeScannerViewController()
        vc.onScan = onScan
        return vc
    }
    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}
}
