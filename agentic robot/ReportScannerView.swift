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

    private var isBusy: Bool {
        isLoading || isReadingBarcodePhoto
    }

    var body: some View {
        ZStack {

            // MARK: Camera background
            if !cameraPermissionDenied {
                BarcodeScannerRepresentable(
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
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Spacer()
                        Button {
                            self.errorMessage = nil
                            scannedCode = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
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
                        self.errorMessage = "Could not look up report: \(error.localizedDescription)"
                        self.scannedCode = nil
                        return
                    }

                    guard let data = snapshot?.data(), !data.isEmpty else {
                        self.errorMessage = "No report found for barcode: \(cleanedCode)"
                        self.scannedCode = nil
                        return
                    }

                    guard
                        let reportNo = data["reportNo"] as? String,
                        let plate    = data["plate"]    as? String
                    else {
                        self.errorMessage = "Report data is incomplete."
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
                        pdfBase64:     data["pdfBase64"]     as? String
                    )
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
        guard let url = ReportStore.resolvedPDFURL(for: report) else {
            pdfErrorMessage = "This report was found, but the PDF file is not available. Generate it again with the updated app so the PDF can be saved."
            return
        }
        pdfErrorMessage = nil
        selectedPDFURL = url
    }

    private func resetForAnotherLookup() {
        report = nil
        scannedCode = nil
        errorMessage = nil
        pdfErrorMessage = nil
        manualCode = ""
        selectedBarcodePhotoItem = nil
        isReadingBarcodePhoto = false
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

            HStack {
                Label("Report Found", systemImage: "checkmark.seal.fill")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.green)
                Spacer()
                Button(action: onScanAnother) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(HTXTheme.primaryPurple)
                }
            }

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
    var onScan: (String) -> Void
    var onPermissionDenied: () -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let vc = BarcodeScannerViewController()
        vc.onScan = onScan
        vc.onPermissionDenied = onPermissionDenied
        return vc
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}
}

class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    var onScan: ((String) -> Void)?
    var onPermissionDenied: (() -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        checkPermissionAndSetup()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func checkPermissionAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.setupCamera() }
                    else { self?.onPermissionDenied?() }
                }
            }
        default:
            DispatchQueue.main.async { self.onPermissionDenied?() }
        }
    }

    private func setupCamera() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.beginConfiguration()
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)

        // Support both Code 128 barcodes AND QR codes for flexibility
        output.metadataObjectTypes = [.code128, .qr, .ean13, .ean8]

        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard
            let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            let code = obj.stringValue,
            !code.isEmpty
        else { return }

        session.stopRunning()
        onScan?(code)
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
