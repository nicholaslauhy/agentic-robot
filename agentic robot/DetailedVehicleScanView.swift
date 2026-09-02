import AVFoundation
import AVKit
import CoreTransferable
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DetailedPanelCapture: Identifiable {
    let panel: DetailedVehiclePanel
    let previewImage: UIImage
    let videoURL: URL
    let durationSeconds: Double
    let representativeFrames: [DetailedScanFrame]
    let qualityAssessment: DetailedScanQualityAssessment

    var id: String { panel.id }
    var image: UIImage { previewImage }

    func removeTemporaryVideo() {
        try? FileManager.default.removeItem(at: videoURL)
    }
}

private struct DetailedDurationOverride: Identifiable {
    let id = UUID()
    let videoURL: URL
    let panel: DetailedVehiclePanel
    let durationSeconds: Double
}

/// Optional close-up capture performed after the four overview photographs.
/// These images are kept separate from the four-angle baseline so later phases
/// can analyse and project them without changing the existing baseline format.
struct DetailedVehicleScanView: View {
    let plate: String
    let carType: CarType
    let replacementPanel: DetailedVehiclePanel?
    let onCancel: () -> Void
    let onComplete: ([DetailedPanelCapture]) -> Void

    @State private var selectedPanel = DetailedVehicleScanSpecification.panels[0]
    @State private var captures: [DetailedVehiclePanel: DetailedPanelCapture] = [:]
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showRecordingGuide = false
    @State private var showExitConfirmation = false
    @State private var errorMessage: String?
    @State private var isPreparingCapture = false
    @State private var isRequestingCaptureAccess = false
    @State private var playbackCapture: DetailedPanelCapture?
    @State private var durationOverride: DetailedDurationOverride?
    @State private var preparationTask: Task<Void, Never>?

    init(
        plate: String,
        carType: CarType,
        initialCaptures: [DetailedPanelCapture] = [],
        replacementPanel: DetailedVehiclePanel? = nil,
        onCancel: @escaping () -> Void,
        onComplete: @escaping ([DetailedPanelCapture]) -> Void
    ) {
        self.plate = plate
        self.carType = carType
        self.replacementPanel = replacementPanel
        self.onCancel = onCancel
        self.onComplete = onComplete
        _selectedPanel = State(
            initialValue: replacementPanel ?? DetailedVehicleScanSpecification.panels[0]
        )
        _captures = State(
            initialValue: Dictionary(uniqueKeysWithValues: initialCaptures.map { ($0.panel, $0) })
        )
    }

    private var currentIndex: Int {
        DetailedVehicleScanSpecification.panels.firstIndex(of: selectedPanel) ?? 0
    }

    private var progress: Double {
        Double(captures.count) / Double(max(1, DetailedVehicleScanSpecification.panels.count))
    }

    private var orderedCaptures: [DetailedPanelCapture] {
        DetailedVehicleScanSpecification.panels.compactMap { panel in
            captures[panel]
        }
    }

    private var isSubmissionReady: Bool {
        orderedCaptures.count == DetailedVehicleScanSpecification.panels.count
            && orderedCaptures.allSatisfy {
                $0.representativeFrames.count == DetailedScanFrameProcessor.representativeFrameCount
                    && $0.qualityAssessment.passed
            }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SubtleHTXBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        header
                        progressCard
                        if let replacementPanel,
                           captures[replacementPanel] == nil {
                            replacementNotice(replacementPanel)
                        }
                        panelGuideCard
                        captureCard
                        panelStrip
                        actionButtons
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") {
                        if captures.isEmpty && !isPreparingCapture {
                            onCancel()
                        } else {
                            showExitConfirmation = true
                        }
                    }
                }
            }
            .confirmationDialog(
                "Leave Detailed Scan?",
                isPresented: $showExitConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard Detailed Recordings", role: .destructive) {
                    preparationTask?.cancel()
                    removeAllCaptureFiles()
                    onCancel()
                }
                Button("Continue Scanning", role: .cancel) {}
            } message: {
                Text("The detailed recordings captured in this scan will be discarded. Your four overview photos will not be affected.")
            }
            .fullScreenCover(isPresented: $showCamera) {
                DetailedVideoPicker(
                    panel: selectedPanel,
                    carType: carType,
                    completionHandler: { sourceURL in
                        showCamera = false
                        prepareCapture(from: sourceURL, for: selectedPanel)
                    },
                    cancellationHandler: { showCamera = false }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showRecordingGuide) {
                DetailedRecordingGuideView(
                    panel: selectedPanel,
                    carType: carType,
                    onCancel: { showRecordingGuide = false },
                    onStartRecording: {
                        showRecordingGuide = false
                        requestAccessAndPresentRecorder()
                    }
                )
                .presentationDetents([.large])
                .interactiveDismissDisabled(isRequestingCaptureAccess)
            }
            .sheet(item: $playbackCapture) { capture in
                DetailedVideoPlaybackView(capture: capture)
            }
            .alert(item: $durationOverride) { pending in
                Alert(
                    title: Text("Use This Recording?"),
                    message: Text(
                        String(
                            format: "This recording is %.1f seconds. A 3–7 second sweep is recommended so the five sampled viewpoints are well spaced, but you can still continue with this recording.",
                            pending.durationSeconds
                        )
                    ),
                    primaryButton: .default(Text("Use Recording Anyway")) {
                        prepareCapture(
                            from: pending.videoURL,
                            for: pending.panel,
                            sourceIsPersistent: true,
                            allowDurationOverride: true
                        )
                    },
                    secondaryButton: .destructive(Text("Retake")) {
                        try? FileManager.default.removeItem(at: pending.videoURL)
                    }
                )
            }
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task {
                    do {
                        guard let imported = try await item.loadTransferable(
                            type: DetailedImportedVideo.self
                        ) else {
                            await MainActor.run {
                                errorMessage = "The selected recording could not be opened."
                                selectedPhotoItem = nil
                            }
                            return
                        }
                        let importedURL = try DetailedCaptureFileStore.copyImportedVideo(
                            from: imported.url,
                            panel: selectedPanel
                        )
                        try? FileManager.default.removeItem(at: imported.url)
                        await MainActor.run {
                            selectedPhotoItem = nil
                            prepareCapture(from: importedURL, for: selectedPanel, sourceIsPersistent: true)
                        }
                    } catch {
                        await MainActor.run {
                            errorMessage = "The selected recording could not be opened: \(error.localizedDescription)"
                            selectedPhotoItem = nil
                        }
                    }
                }
            }
            .task {
                DetailedCaptureFileStore.removeStaleFiles()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Optional Detailed Scan")
                .font(.largeTitle.bold())
                .foregroundColor(HTXTheme.primaryPurple)
            Text("\(carType.rawValue) · \(plate)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Record one slow multi-angle sweep for each highlighted vehicle panel. This does not replace the four overview images.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .padding(.top, 18)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Detailed coverage")
                    .font(.headline)
                Spacer()
                Text("\(captures.count) of \(DetailedVehicleScanSpecification.panels.count)")
                    .font(.subheadline.bold())
                    .foregroundColor(HTXTheme.primaryPurple)
            }
            ProgressView(value: progress)
                .tint(HTXTheme.primaryPurple)
        }
        .padding()
        .background(HTXTheme.softPurpleCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func replacementNotice(_ panel: DetailedVehiclePanel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Replace only \(panel.displayName)", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.headline)
                .foregroundColor(.orange)
            Text("Your other \(captures.count) panel recordings are still saved. Keep the highlighted panel centred and fully visible while taking one or two small sideways steps from the start position through the centre to the end position. Do not continue into the next panel.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var panelGuideCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Panel \(currentIndex + 1) of \(DetailedVehicleScanSpecification.panels.count)")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Text(selectedPanel.displayName)
                        .font(.title2.bold())
                        .foregroundColor(HTXTheme.primaryPurple)
                }
                Spacer()
                Text(selectedPanel.overviewAngle.label)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(HTXTheme.primaryPurple.opacity(0.12))
                    .foregroundColor(HTXTheme.primaryPurple)
                    .clipShape(Capsule())
            }

            ZStack {
                CarSilhouetteView(
                    carType: carType,
                    angleId: selectedPanel.overviewAngle.rawValue
                )

                DetailedPanelHighlightOverlay(panel: selectedPanel)
                DetailedPanelSweepDirectionOverlay(panel: selectedPanel)
            }
            .frame(maxWidth: 780)
            .frame(height: 280)
            .frame(maxWidth: .infinity)
            .background(HTXTheme.softPurpleCard.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .topLeading) {
                Label(selectedPanel.displayName, systemImage: "viewfinder")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial)
                    .foregroundColor(HTXTheme.primaryPurple)
                    .clipShape(Capsule())
                    .padding(10)
            }

            DetailedScanSweepGuide()

            VStack(alignment: .leading, spacing: 6) {
                Label(selectedPanel.coverageHint, systemImage: "camera.viewfinder")
                Label(DetailedVehicleScanSpecification.operatorInstruction, systemImage: "arrow.left.and.right")
            }
            .font(.footnote)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(HTXTheme.softPurpleBorder, lineWidth: 1))
    }

    private var captureCard: some View {
        Group {
            if let capture = captures[selectedPanel] {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        playbackCapture = capture
                    } label: {
                        ZStack {
                            Image(uiImage: capture.previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 16))

                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 54))
                                .foregroundStyle(.white, HTXTheme.primaryPurple.opacity(0.88))
                                .shadow(radius: 5)
                        }
                        .overlay(alignment: .topTrailing) {
                            Label(
                                String(format: "%.1f s", capture.durationSeconds),
                                systemImage: "checkmark.circle.fill"
                            )
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.green.opacity(0.92))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                            .padding(10)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play recorded sweep for \(selectedPanel.displayName)")

                    Label(capture.qualityAssessment.summary, systemImage: "checkmark.shield.fill")
                        .font(.footnote.bold())
                        .foregroundColor(.green)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(capture.representativeFrames.enumerated()), id: \.element.id) { index, frame in
                                VStack(spacing: 4) {
                                    Image(uiImage: frame.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 112, height: 72)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 9))
                                    Text("View \(index + 1)")
                                        .font(.caption2.bold())
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 42))
                        .foregroundColor(HTXTheme.primaryPurple)
                    Text("No sweep recorded for this panel")
                        .font(.headline)
                    Text("Record for about five seconds while moving through the three demonstrated camera positions.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 190)
                .background(HTXTheme.softPurpleCard)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var panelStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(DetailedVehicleScanSpecification.panels) { panel in
                    Button {
                        selectedPanel = panel
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(captures[panel] == nil ? Color(.systemGray5) : Color.green.opacity(0.18))
                                    .frame(width: 38, height: 38)
                                Image(systemName: captures[panel] == nil ? "video" : "checkmark")
                                    .font(.caption.bold())
                                    .foregroundColor(captures[panel] == nil ? .secondary : .green)
                            }
                            Text("\(panel.sequenceNumber)")
                                .font(.caption2.bold())
                        }
                        .padding(8)
                        .background(selectedPanel == panel ? HTXTheme.primaryPurple.opacity(0.13) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Panel \(panel.sequenceNumber), \(panel.displayName)")
                }
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .videos) {
                    Label("Choose Existing Video", systemImage: "video.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemBackground))
                        .foregroundColor(HTXTheme.primaryPurple)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    errorMessage = nil
                    showRecordingGuide = true
                } label: {
                    Label("Record Guided Sweep", systemImage: "video.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(HTXTheme.primaryPurple)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isRequestingCaptureAccess)
            }

            if isPreparingCapture {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(HTXTheme.primaryPurple)
                    Text("Checking lighting and sharpness, then extracting stable viewpoints…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Button {
                onComplete(orderedCaptures)
            } label: {
                Label("Complete Detailed Scan", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(isSubmissionReady ? HTXTheme.primaryPurple : Color(.systemGray4))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(
                !isSubmissionReady || isPreparingCapture
            )
        }
    }

    private func requestAccessAndPresentRecorder() {
        guard DetailedVideoPicker.isRecordingAvailable else {
            errorMessage = "Video recording is not available in the Simulator or on this device. Choose an existing video instead."
            return
        }

        isRequestingCaptureAccess = true
        Task {
            // Let the guide sheet finish dismissing before iOS presents its
            // privacy prompts or the camera controller.
            try? await Task.sleep(for: .milliseconds(300))

            let cameraAllowed = await DetailedCapturePermission.request(.video)
            guard cameraAllowed else {
                await MainActor.run {
                    isRequestingCaptureAccess = false
                    errorMessage = "Camera access is required to record the panel sweep. Enable Camera access in Settings, or choose an existing video."
                }
                return
            }

            let microphoneAllowed = await DetailedCapturePermission.request(.audio)
            guard microphoneAllowed else {
                await MainActor.run {
                    isRequestingCaptureAccess = false
                    errorMessage = "Microphone access is required by the iOS video recorder. Enable Microphone access in Settings, or choose an existing video."
                }
                return
            }

            await MainActor.run {
                isRequestingCaptureAccess = false
                showCamera = true
            }
        }
    }

    private func prepareCapture(
        from sourceURL: URL,
        for panel: DetailedVehiclePanel,
        sourceIsPersistent: Bool = false,
        allowDurationOverride: Bool = false
    ) {
        isPreparingCapture = true
        errorMessage = nil

        preparationTask?.cancel()
        preparationTask = Task {
            var preparedURL: URL?
            do {
                let storedURL = sourceIsPersistent
                    ? sourceURL
                    : try DetailedCaptureFileStore.copyRecordedVideo(from: sourceURL, panel: panel)
                preparedURL = storedURL
                try Task.checkCancellation()
                let metadata = try await DetailedCaptureFileStore.previewMetadata(for: storedURL)
                try Task.checkCancellation()

                if !allowDurationOverride,
                   !DetailedVehicleScanSpecification.recommendedRecordingDurationSeconds
                    .contains(metadata.durationSeconds) {
                    await MainActor.run {
                        isPreparingCapture = false
                        preparationTask = nil
                        durationOverride = DetailedDurationOverride(
                            videoURL: storedURL,
                            panel: panel,
                            durationSeconds: metadata.durationSeconds
                        )
                    }
                    return
                }

                let processed = try await DetailedScanFrameProcessor.process(
                    videoURL: storedURL,
                    durationSeconds: metadata.durationSeconds
                )
                try Task.checkCancellation()

                await MainActor.run {
                    if let previous = captures[panel], previous.videoURL != storedURL {
                        try? FileManager.default.removeItem(at: previous.videoURL)
                    }
                    captures[panel] = DetailedPanelCapture(
                        panel: panel,
                        previewImage: metadata.preview,
                        videoURL: storedURL,
                        durationSeconds: metadata.durationSeconds,
                        representativeFrames: processed.frames,
                        qualityAssessment: processed.assessment
                    )
                    isPreparingCapture = false
                    preparationTask = nil
                    advanceAfterCapture(panel)
                }
            } catch is CancellationError {
                if let preparedURL {
                    try? FileManager.default.removeItem(at: preparedURL)
                }
                await MainActor.run {
                    isPreparingCapture = false
                    preparationTask = nil
                }
            } catch {
                if let preparedURL {
                    try? FileManager.default.removeItem(at: preparedURL)
                }
                await MainActor.run {
                    isPreparingCapture = false
                    preparationTask = nil
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func advanceAfterCapture(_ panel: DetailedVehiclePanel) {
        let completedIndex = DetailedVehicleScanSpecification.panels.firstIndex(of: panel) ?? currentIndex
        guard let next = DetailedVehicleScanSpecification.panels
            .dropFirst(completedIndex + 1)
            .first(where: { captures[$0] == nil }) else { return }
        withAnimation { selectedPanel = next }
    }

    private func removeAllCaptureFiles() {
        if let durationOverride {
            try? FileManager.default.removeItem(at: durationOverride.videoURL)
            self.durationOverride = nil
        }
        for capture in captures.values {
            capture.removeTemporaryVideo()
        }
        captures.removeAll()
    }
}

private enum DetailedCaptureError: LocalizedError {
    case previewUnavailable

    var errorDescription: String? {
        switch self {
        case .previewUnavailable:
            return "A preview could not be created from this recording. Please record the panel again."
        }
    }
}

private enum DetailedCapturePermission {
    static func request(_ mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: mediaType)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

/// Imports a movie as a file rather than materialising the entire recording as
/// `Data`. High-resolution iPad recordings can be hundreds of megabytes, so a
/// file-backed transfer avoids a large memory spike while choosing a video.
private struct DetailedImportedVideo: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let fileExtension = received.file.pathExtension.isEmpty
                ? "mov"
                : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("detailed-import-\(UUID().uuidString).\(fileExtension)")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return DetailedImportedVideo(url: destination)
        }
    }
}

private enum DetailedCaptureFileStore {
    struct PreviewMetadata {
        let preview: UIImage
        let durationSeconds: Double
    }

    static func copyRecordedVideo(from sourceURL: URL, panel: DetailedVehiclePanel) throws -> URL {
        let destination = try destinationURL(panel: panel, extension: sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    static func copyImportedVideo(from sourceURL: URL, panel: DetailedVehiclePanel) throws -> URL {
        let pathExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let destination = try destinationURL(panel: panel, extension: pathExtension)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    static func previewMetadata(for url: URL) async throws -> PreviewMetadata {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw DetailedCaptureError.previewUnavailable
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        let previewTime = CMTime(
            seconds: min(max(0.25, durationSeconds * 0.5), durationSeconds),
            preferredTimescale: 600
        )
        let generated = try await generator.image(at: previewTime)
        return PreviewMetadata(
            preview: UIImage(cgImage: generated.image).htxNormalizedImage(),
            durationSeconds: durationSeconds
        )
    }

    /// A crash or force-quit can bypass the normal cancellation cleanup. Remove
    /// abandoned recordings on the next scan without touching recent active work.
    static func removeStaleFiles(olderThan age: TimeInterval = 24 * 60 * 60) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("detailed-vehicle-scan", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-age)
        for file in files {
            let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if modified.map({ $0 < cutoff }) ?? true {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private static func destinationURL(panel: DetailedVehiclePanel, extension pathExtension: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("detailed-vehicle-scan", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent(
            "\(panel.rawValue)-\(UUID().uuidString).\(pathExtension.lowercased())"
        )
    }
}

private struct DetailedVideoPicker: UIViewControllerRepresentable {
    let panel: DetailedVehiclePanel
    let carType: CarType
    let completionHandler: (URL) -> Void
    let cancellationHandler: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    static var isRecordingAvailable: Bool {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return false }
        return UIImagePickerController.availableMediaTypes(for: .camera)?
            .contains(UTType.movie.identifier) == true
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        // The parent view checks this before presentation. Retaining a safe
        // fallback here prevents UIImagePickerController from throwing an
        // Objective-C exception if camera availability changes mid-transition.
        picker.sourceType = Self.isRecordingAvailable ? .camera : .photoLibrary
        picker.mediaTypes = [UTType.movie.identifier]
        if picker.sourceType == .camera {
            picker.cameraDevice = .rear
            picker.cameraCaptureMode = .video
            picker.videoQuality = .typeHigh
            picker.videoMaximumDuration = DetailedVehicleScanSpecification.maximumRecordingDurationSeconds
            picker.showsCameraControls = true
        }

        if picker.sourceType == .camera {
            let overlayController = UIHostingController(
                rootView: DetailedCameraOverlay(panel: panel, carType: carType)
            )
            overlayController.view.backgroundColor = .clear
            overlayController.view.isUserInteractionEnabled = false
            overlayController.view.frame = picker.view.bounds
            overlayController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            picker.cameraOverlayView = overlayController.view
            context.coordinator.overlayController = overlayController
        }

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: DetailedVideoPicker
        var overlayController: UIViewController?

        init(parent: DetailedVideoPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let url = info[.mediaURL] as? URL else {
                parent.cancellationHandler()
                return
            }
            parent.completionHandler(url)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.cancellationHandler()
        }
    }
}

private struct DetailedRecordingGuideView: View {
    let panel: DetailedVehiclePanel
    let carType: CarType
    let onCancel: () -> Void
    let onStartRecording: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 7) {
                        Text("How to record this panel")
                            .font(.title.bold())
                            .foregroundColor(HTXTheme.primaryPurple)
                        Text(panel.displayName)
                            .font(.headline)
                        Text("This is a short sideways sweep—not a full walk around the car.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    ZStack {
                        CarSilhouetteView(
                            carType: carType,
                            angleId: panel.overviewAngle.rawValue
                        )
                        .opacity(0.86)

                        DetailedPanelHighlightOverlay(panel: panel)
                        DetailedPanelSweepDirectionOverlay(panel: panel)
                    }
                    .frame(maxWidth: 760)
                    .frame(height: 270)
                    .frame(maxWidth: .infinity)
                    .background(HTXTheme.softPurpleCard.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    DetailedScanSweepGuide()

                    VStack(alignment: .leading, spacing: 13) {
                        recordingStep(1, "Stand slightly to the left of the highlighted panel and point the rear camera at it.")
                        recordingStep(2, "Tap the red Record button, then take two slow sideways steps.")
                        recordingStep(3, "Keep the highlighted panel centred and fully visible as its reflection changes.")
                        recordingStep(4, "Stop after the camera reaches the right-hand position (about five seconds).")
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    HStack(spacing: 12) {
                        Button("Cancel") { onCancel() }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemBackground))
                            .foregroundColor(HTXTheme.primaryPurple)
                            .clipShape(RoundedRectangle(cornerRadius: 14))

                        Button(action: onStartRecording) {
                            Label("Open Recorder", systemImage: "video.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(HTXTheme.primaryPurple)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .padding(24)
            }
            .background(SubtleHTXBackground())
        }
    }

    private func recordingStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(HTXTheme.primaryPurple)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DetailedCameraGuideLayout: Equatable {
    let guideRect: CGRect
    let silhouetteRect: CGRect

    init(size: CGSize, angle: VehicleOverviewAngle) {
        let horizontalInset = max(18, size.width * 0.018)
        let topInset = max(86, size.height * 0.072)
        let bottomInset = max(108, size.height * 0.09)
        let width = max(1, size.width - (horizontalInset * 2))
        let height = max(1, size.height - topInset - bottomInset)

        guideRect = CGRect(
            x: horizontalInset,
            y: topInset,
            width: width,
            height: height
        )

        let contentInset = max(10, min(size.width, size.height) * 0.012)
        let available = guideRect.insetBy(dx: contentInset, dy: contentInset)
        let targetAspect: CGFloat = switch angle {
        case .front, .rear: 1.55
        case .leftSide, .rightSide: 2.05
        }
        let availableAspect = available.width / max(1, available.height)
        let fittedSize: CGSize

        if availableAspect > targetAspect {
            fittedSize = CGSize(
                width: available.height * targetAspect,
                height: available.height
            )
        } else {
            fittedSize = CGSize(
                width: available.width,
                height: available.width / targetAspect
            )
        }

        silhouetteRect = CGRect(
            x: guideRect.midX - (fittedSize.width / 2),
            y: guideRect.midY - (fittedSize.height / 2),
            width: fittedSize.width,
            height: fittedSize.height
        )
    }
}

private struct DetailedCameraOverlay: View {
    let panel: DetailedVehiclePanel
    let carType: CarType

    var body: some View {
        GeometryReader { geometry in
            let layout = DetailedCameraGuideLayout(
                size: geometry.size,
                angle: panel.overviewAngle
            )

            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        Color.white.opacity(0.92),
                        style: StrokeStyle(lineWidth: 3, dash: [12, 9])
                    )
                    .frame(
                        width: layout.guideRect.width,
                        height: layout.guideRect.height
                    )
                    .position(
                        x: layout.guideRect.midX,
                        y: layout.guideRect.midY
                    )

                ZStack {
                    CarSilhouetteView(
                        carType: carType,
                        angleId: panel.overviewAngle.rawValue
                    )
                    .opacity(0.48)

                    DetailedPanelHighlightOverlay(panel: panel)
                    DetailedPanelSweepDirectionOverlay(panel: panel)
                }
                .frame(
                    width: layout.silhouetteRect.width,
                    height: layout.silhouetteRect.height
                )
                .position(
                    x: layout.silhouetteRect.midX,
                    y: layout.silhouetteRect.midY
                )

                HStack {
                    Label(panel.displayName, systemImage: "viewfinder")
                        .font(.headline.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.68))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    Spacer()
                    Text("Aim for ~5 sec")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.68))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 20)
                .position(
                    x: geometry.size.width / 2,
                    y: max(46, layout.guideRect.minY * 0.48)
                )

                Text("Move with the arrow:  −20°  →  straight  →  +20°")
                    .font(.headline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.72))
                    .clipShape(Capsule())
                    .position(
                        x: geometry.size.width / 2,
                        y: layout.guideRect.maxY
                            + ((geometry.size.height - layout.guideRect.maxY) * 0.50)
                    )
            }
        }
        .accessibilityHidden(true)
    }
}

private struct DetailedVideoPlaybackView: View {
    let capture: DetailedPanelCapture

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer

    init(capture: DetailedPanelCapture) {
        self.capture = capture
        _player = State(initialValue: AVPlayer(url: capture.videoURL))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VideoPlayer(player: player)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            }
            .navigationTitle(capture.panel.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
    }
}

private struct DetailedPanelHighlightOverlay: View {
    let panel: DetailedVehiclePanel

    var body: some View {
        GeometryReader { geometry in
            let rect = detailedPanelHighlightRect(panel, in: geometry.size)

            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            HTXTheme.primaryPurple.opacity(0.10),
                            HTXTheme.primaryPurple.opacity(0.38),
                            Color.cyan.opacity(0.20)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(HTXTheme.primaryPurple, style: StrokeStyle(lineWidth: 3, dash: [9, 6]))
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .shadow(color: HTXTheme.primaryPurple.opacity(0.20), radius: 8)
                .allowsHitTesting(false)
        }
        .accessibilityHidden(true)
    }
}

private struct DetailedPanelSweepDirectionOverlay: View {
    let panel: DetailedVehiclePanel

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            GeometryReader { geometry in
                let rect = detailedPanelHighlightRect(panel, in: geometry.size)
                let horizontalPadding = min(18, rect.width * 0.12)
                let travel = max(0, rect.width - horizontalPadding * 2)
                let cycle = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 3.6) / 3.6
                let progress = min(1, cycle / 0.82)

                ZStack {
                    Path { path in
                        path.move(
                            to: CGPoint(
                                x: rect.minX + horizontalPadding,
                                y: rect.midY
                            )
                        )
                        path.addLine(
                            to: CGPoint(
                                x: rect.maxX - horizontalPadding,
                                y: rect.midY
                            )
                        )
                    }
                        .stroke(
                            Color.white.opacity(0.80),
                            style: StrokeStyle(lineWidth: 2, dash: [7, 6])
                        )

                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: min(48, max(28, rect.height * 0.34))))
                        .foregroundStyle(.white, HTXTheme.primaryPurple)
                        .shadow(color: .black.opacity(0.35), radius: 4)
                        .position(
                            x: rect.minX + horizontalPadding + (travel * progress),
                            y: rect.midY
                        )
                }
                .allowsHitTesting(false)
            }
        }
        .accessibilityHidden(true)
    }
}

private func detailedPanelHighlightRect(
    _ panel: DetailedVehiclePanel,
    in size: CGSize
) -> CGRect {
    let normalized: CGRect

    switch panel {
    case .frontUpper, .rearUpper:
        normalized = CGRect(x: 0.30, y: 0.31, width: 0.40, height: 0.25)
    case .frontLower, .rearLower:
        normalized = CGRect(x: 0.25, y: 0.57, width: 0.50, height: 0.20)
    case .leftFrontQuarter, .rightRearQuarter:
        normalized = CGRect(x: 0.15, y: 0.49, width: 0.18, height: 0.25)
    case .leftFrontDoor, .rightRearDoor:
        normalized = CGRect(x: 0.31, y: 0.47, width: 0.19, height: 0.27)
    case .leftRearDoor, .rightFrontDoor:
        normalized = CGRect(x: 0.50, y: 0.47, width: 0.18, height: 0.27)
    case .leftRearQuarter, .rightFrontQuarter:
        normalized = CGRect(x: 0.67, y: 0.49, width: 0.18, height: 0.25)
    }

    return CGRect(
        x: normalized.minX * size.width,
        y: normalized.minY * size.height,
        width: normalized.width * size.width,
        height: normalized.height * size.height
    )
}

private struct DetailedScanSweepGuide: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Camera movement demonstration", systemImage: "figure.walk.motion")
                    .font(.caption.bold())
                    .foregroundColor(HTXTheme.primaryPurple)
                Spacer()
                Text("NOT A CONTROL")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(.systemGray5))
                    .clipShape(Capsule())
            }

            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                GeometryReader { geometry in
                    let startX: CGFloat = 64
                    let endX = max(startX, geometry.size.width - 64)
                    let startY: CGFloat = 94
                    let controlY: CGFloat = 14
                    let cycle = timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 4.2) / 4.2
                    let progress = CGFloat(min(1, cycle / 0.80))
                    let inverse = 1 - progress
                    let x = startX + ((endX - startX) * progress)
                    let y = (inverse * inverse * startY)
                        + (2 * inverse * progress * controlY)
                        + (progress * progress * startY)

                    ZStack {
                        Path { path in
                            path.move(to: CGPoint(x: startX, y: startY))
                            path.addQuadCurve(
                                to: CGPoint(x: endX, y: startY),
                                control: CGPoint(x: geometry.size.width / 2, y: controlY)
                            )
                        }
                        .stroke(
                            HTXTheme.primaryPurple.opacity(0.55),
                            style: StrokeStyle(lineWidth: 3, dash: [8, 6])
                        )

                        Image(systemName: "chevron.right.2")
                            .font(.caption.bold())
                            .foregroundColor(HTXTheme.primaryPurple)
                            .position(x: geometry.size.width * 0.35, y: 42)
                        Image(systemName: "chevron.right.2")
                            .font(.caption.bold())
                            .foregroundColor(HTXTheme.primaryPurple)
                            .position(x: geometry.size.width * 0.65, y: 42)

                        VStack(spacing: 2) {
                            Image(systemName: "car.side.fill")
                                .font(.system(size: 42))
                            Text("KEEP PANEL CENTRED")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundColor(.secondary.opacity(0.72))
                        .position(x: geometry.size.width / 2, y: 98)

                        operatorBadge
                            .position(x: x, y: y)

                        marker("START", degrees: "−20°")
                            .position(x: startX, y: 136)
                        marker("FINISH & STOP", degrees: "+20°")
                            .position(x: endX, y: 136)
                    }
                }
            }
            .frame(height: 154)
            .clipped()

            Text("Record once from START to FINISH, then stop. Do not record the return journey. The demonstration pauses at FINISH and resets to START for the next example.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .background(HTXTheme.softPurpleCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Record once from minus 20 degrees to plus 20 degrees around the highlighted panel, then stop")
    }

    private var operatorBadge: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(.regularMaterial)
                .frame(width: 48, height: 48)
                .shadow(color: .black.opacity(0.16), radius: 4, y: 2)

            Image(systemName: "figure.walk.motion")
                .font(.system(size: 25, weight: .semibold))
                .foregroundColor(HTXTheme.primaryPurple)
                .frame(width: 48, height: 48)

            Image(systemName: "video.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(HTXTheme.primaryPurple)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
        }
    }

    private func marker(_ title: String, degrees: String) -> some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
            Text(degrees)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .accessibilityHidden(true)
    }
}
