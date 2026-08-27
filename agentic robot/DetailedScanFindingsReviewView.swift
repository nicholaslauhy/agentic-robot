import SwiftUI
import UIKit

struct DetailedScanReviewOutcome {
    let acceptedFindings: [MutableDamageDetection]
    let manualDetections: [MutableDamageDetection]
}

private struct DetailedReviewCandidate: Identifiable {
    let id: UUID
    let finding: DetailedProjectedDamageFinding
    let detection: MutableDamageDetection
}

private struct DetailedDetectionEditItem: Identifiable {
    let id: UUID
    let candidateID: UUID?
    let detection: MutableDamageDetection

    init(candidateID: UUID? = nil, detection: MutableDamageDetection) {
        self.id = detection.id
        self.candidateID = candidateID
        self.detection = detection
    }
}

struct DetailedScanFindingsReviewView: View {
    let analysisResult: DetailedScanAnalysisBatchResult
    let scanImages: [UIImage]
    let onComplete: (DetailedScanReviewOutcome) -> Void
    let onBack: () -> Void

    @State private var candidates: [DetailedReviewCandidate]
    @State private var decisions: [UUID: Bool] = [:]
    @State private var manualDetections: [MutableDamageDetection] = []
    @State private var detectionToEdit: DetailedDetectionEditItem?
    @State private var manuallyConfirmedProjectionIDs: Set<UUID> = []
    @State private var zoomedImage: DetailedScanZoomItem?
    @State private var showManualAdd = false

    init(
        findings: [DetailedProjectedDamageFinding],
        analysisResult: DetailedScanAnalysisBatchResult,
        scanImages: [UIImage],
        onComplete: @escaping (DetailedScanReviewOutcome) -> Void,
        onBack: @escaping () -> Void
    ) {
        self.analysisResult = analysisResult
        self.scanImages = scanImages
        self.onComplete = onComplete
        self.onBack = onBack
        _candidates = State(initialValue: findings.map { finding in
            let detection = MutableDamageDetection(from: finding.damage)
            // Keep the projected overview image/coordinates for location and
            // baseline use, but retain the high-detail source crop for review
            // and the final report's close-up column.
            if let sourceCrop = finding.sourceDamage?.cropImage {
                detection.cropImage = sourceCrop
            }
            detection.captureSource = .detailedMultiAngle
            detection.observedFrameCount = finding.observedFrames
            detection.totalFrameCount = finding.totalFrames
            detection.detailedPanelIDs = finding.panelIds
            return DetailedReviewCandidate(id: finding.id, finding: finding, detection: detection)
        })
    }

    private var everyCandidateReviewed: Bool {
        candidates.allSatisfy { decisions[$0.id] != nil }
    }

    private var acceptedCount: Int {
        candidates.filter { decisions[$0.id] == true }.count + manualDetections.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SubtleHTXBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        reviewHeader
                        completedAnalysisCard

                        if candidates.isEmpty {
                            noFindingsCard
                        } else {
                            ForEach(candidates) { candidate in
                                DetailedFindingReviewCard(
                                    finding: candidate.finding,
                                    detection: candidate.detection,
                                    sourceDamage: candidate.finding.sourceDamage,
                                    decision: decisions[candidate.id],
                                    projectionManuallyConfirmed: manuallyConfirmedProjectionIDs.contains(candidate.id),
                                    onDecision: { decisions[candidate.id] = $0 },
                                    onZoom: { selection in
                                        zoomedImage = DetailedScanZoomItem(
                                            title: "\(candidate.detection.damageType.capitalized) · \(candidate.detection.angleName)",
                                            fullImage: candidate.detection.contextImage
                                                ?? candidate.detection.cleanContextImage,
                                            closeUpImage: candidate.finding.sourceDamage?.cropImage
                                                ?? candidate.finding.sourceDamage?.contextImage
                                                ?? candidate.finding.sourceDamage?.cleanContextImage
                                                ?? candidate.detection.cropImage,
                                            initialSelection: selection
                                        )
                                    },
                                    onEdit: {
                                        detectionToEdit = DetailedDetectionEditItem(
                                            candidateID: candidate.id,
                                            detection: candidate.detection
                                        )
                                    }
                                )
                            }
                        }

                        manualSection

                        Button {
                            let accepted = candidates.compactMap { candidate in
                                decisions[candidate.id] == true ? candidate.detection : nil
                            }
                            onComplete(
                                DetailedScanReviewOutcome(
                                    acceptedFindings: accepted,
                                    manualDetections: manualDetections
                                )
                            )
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                Text(acceptedCount == 0 ? "Continue Without Added Damage" : "Confirm \(acceptedCount) Damage Case\(acceptedCount == 1 ? "" : "s")")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(HTXTheme.primaryPurple)
                        .disabled(!everyCandidateReviewed)

                        if !everyCandidateReviewed {
                            Text("Choose Yes or No for every suggested damage before continuing.")
                                .font(.footnote)
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .frame(maxWidth: 900)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Review Detailed Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { onBack() }
                }
            }
        }
        .fullScreenCover(item: $detectionToEdit) { editItem in
            BoundingBoxEditorSheet(
                detection: editItem.detection,
                accentColor: HTXTheme.primaryPurple,
                scanImage: scanImages.indices.contains(editItem.detection.angleIndex)
                    ? scanImages[editItem.detection.angleIndex]
                    : nil,
                onSave: {
                    if let candidateID = editItem.candidateID {
                        manuallyConfirmedProjectionIDs.insert(candidateID)
                    }
                },
                preserveExistingCropOnSave: editItem.candidateID != nil
            )
        }
        .fullScreenCover(item: $zoomedImage) { item in
            DetailedScanZoomViewer(item: item)
        }
        .fullScreenCover(isPresented: $showManualAdd) {
            AddCaseSheet(scanImages: scanImages, accentColor: HTXTheme.primaryPurple) { detection in
                manualDetections.append(detection)
            }
        }
    }

    private var completedAnalysisCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 32))
                .foregroundColor(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text("Detailed analysis completed")
                    .font(.headline)
                Text(
                    "The backend processed \(analysisResult.receipts.count) of "
                        + "\(DetailedScanSubmissionValidator.requiredPanelCount) panels and "
                        + "\(analysisResult.processedFrameCount) viewpoints."
                )
                .font(.subheadline)
                .foregroundColor(.secondary)

                if analysisResult.rejectedProjectionCount > 0 {
                    Text(
                        "\(analysisResult.rejectedProjectionCount) suggestion"
                            + "\(analysisResult.rejectedProjectionCount == 1 ? " was" : "s were") "
                            + "excluded because the location did not match the selected panel."
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.orange)
                }
            }
            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.09))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.green.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var reviewHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Confirm what the scan found", systemImage: "checkmark.bubble.fill")
                .font(.title2.bold())
                .foregroundColor(HTXTheme.primaryPurple)

            Text("The detailed scan only suggests possible damage. Check each location, zoom in if needed, then choose Yes or No. You can also correct its box or add damage manually.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var noFindingsCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 42))
                .foregroundColor(HTXTheme.primaryPurple)
            Text("No persistent damage was found")
                .font(.headline)
            Text("The completed backend analysis returned no persistent damage suggestions. If you can see damage that it missed, draw its location manually below. Otherwise, continue without adding damage.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.systemBackground).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Manual Damage", systemImage: "hand.draw.fill")
                    .font(.headline)
                    .foregroundColor(HTXTheme.primaryPurple)
                Spacer()
                Button {
                    showManualAdd = true
                } label: {
                    Label("Draw Damage Box", systemImage: "plus.rectangle.on.rectangle")
                }
                .buttonStyle(.bordered)
                .tint(HTXTheme.primaryPurple)
            }

            if manualDetections.isEmpty {
                Text("Use this when a visible scratch, dent or other defect was not suggested above.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(manualDetections) { detection in
                    DetailedManualFindingRow(
                        detection: detection,
                        onZoom: { selection in
                            zoomedImage = DetailedScanZoomItem(
                                detection: detection,
                                initialSelection: selection
                            )
                        },
                        onEdit: {
                            detectionToEdit = DetailedDetectionEditItem(detection: detection)
                        },
                        onDelete: { manualDetections.removeAll { $0.id == detection.id } }
                    )
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct DetailedFindingReviewCard: View {
    let finding: DetailedProjectedDamageFinding
    @ObservedObject var detection: MutableDamageDetection
    let sourceDamage: DamageDetection?
    let decision: Bool?
    let projectionManuallyConfirmed: Bool
    let onDecision: (Bool) -> Void
    let onZoom: (DetailedScanZoomSelection) -> Void
    let onEdit: () -> Void

    private var needsLocationReview: Bool {
        DetailedProjectionReviewPolicy.requiresManualConfirmation(finding)
    }

    private var canAcceptLocation: Bool {
        DetailedProjectionReviewPolicy.canAccept(
            finding,
            manuallyConfirmed: projectionManuallyConfirmed
        )
    }

    private var projectionWarningReason: String {
        let reason = finding.projectionReason.trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.isEmpty
            ? "The backend could not verify this location against the selected vehicle panel."
            : reason
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(detection.damageType.capitalized)
                        .font(.title3.bold())
                    Text(detection.angleName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("Seen in \(finding.observedFrames) of \(finding.totalFrames) views")
                    .font(.caption.bold())
                    .foregroundColor(HTXTheme.primaryPurple)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(HTXTheme.primaryPurple.opacity(0.10))
                    .clipShape(Capsule())
            }

            if fullImage != nil || closeUpImage != nil {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 250), spacing: 12)],
                    spacing: 12
                ) {
                    if let fullImage {
                        imagePreview(
                            image: fullImage,
                            title: "Vehicle Location",
                            systemImage: "car.side",
                            selection: .vehicleLocation
                        )
                    }
                    if let closeUpImage {
                        imagePreview(
                            image: closeUpImage,
                            title: "Damage Close-Up",
                            systemImage: "viewfinder.circle",
                            selection: .damageCloseUp
                        )
                    }
                }
            }

            if needsLocationReview {
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        projectionManuallyConfirmed
                            ? "Projected location manually confirmed"
                            : "Location confirmation required",
                        systemImage: projectionManuallyConfirmed
                            ? "checkmark.shield.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline.bold())
                    .foregroundColor(projectionManuallyConfirmed ? .green : .orange)

                    if !projectionManuallyConfirmed {
                        Text(projectionWarningReason)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Open Adjust Box, check the projected location, then press Done before choosing Yes.")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    (projectionManuallyConfirmed ? Color.green : Color.orange)
                        .opacity(0.09)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if !detection.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(detection.explanation)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Button(action: onEdit) {
                    Label("Adjust Box", systemImage: "rectangle.and.pencil.and.ellipsis")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(HTXTheme.primaryPurple)

                Button { onDecision(false) } label: {
                    Label("No", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(decision == false ? .red : Color(.systemGray4))

                Button { onDecision(true) } label: {
                    Label("Yes", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(decision == true ? .green : Color(.systemGray4))
                .disabled(!canAcceptLocation)
                .accessibilityHint(
                    canAcceptLocation
                        ? "Accepts this damage suggestion"
                        : "Open Adjust Box and confirm the projected location first"
                )
            }
        }
        .padding(20)
        .background(Color(.systemBackground).opacity(0.96))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    decision == true ? Color.green.opacity(0.55)
                        : (decision == false ? Color.red.opacity(0.45) : HTXTheme.softPurpleBorder),
                    lineWidth: decision == nil ? 1 : 2
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var fullImage: UIImage? {
        detection.contextImage ?? detection.cleanContextImage
    }

    private var closeUpImage: UIImage? {
        sourceDamage?.cropImage
            ?? sourceDamage?.contextImage
            ?? sourceDamage?.cleanContextImage
            ?? detection.cropImage
    }

    private func imagePreview(
        image: UIImage,
        title: String,
        systemImage: String,
        selection: DetailedScanZoomSelection
    ) -> some View {
        Button { onZoom(selection) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)

                ZStack(alignment: .bottomTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 230)
                        .background(Color.black.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Label("Zoom", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.bold())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(title.lowercased())")
        .accessibilityHint("Opens a full-screen image that supports pinch and drag gestures")
    }
}

private struct DetailedManualFindingRow: View {
    @ObservedObject var detection: MutableDamageDetection
    let onZoom: (DetailedScanZoomSelection) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            if let image = detection.cropImage ?? detection.contextImage {
                Button {
                    onZoom(detection.cropImage == nil ? .vehicleLocation : .damageCloseUp)
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 86)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(detection.damageType.capitalized).font(.headline)
                Text(detection.angleName).font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: onEdit) { Image(systemName: "pencil.circle.fill") }
                .buttonStyle(.borderless)
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash.circle.fill") }
                .buttonStyle(.borderless)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

enum DetailedScanZoomSelection: String, CaseIterable, Identifiable {
    case vehicleLocation
    case damageCloseUp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vehicleLocation: return "Vehicle Location"
        case .damageCloseUp: return "Damage Close-Up"
        }
    }
}

private struct DetailedScanZoomItem: Identifiable {
    let id = UUID()
    let title: String
    let fullImage: UIImage?
    let closeUpImage: UIImage?
    let initialSelection: DetailedScanZoomSelection

    init(
        detection: MutableDamageDetection,
        initialSelection: DetailedScanZoomSelection
    ) {
        self.init(
            title: "\(detection.damageType.capitalized) · \(detection.angleName)",
            fullImage: detection.contextImage ?? detection.cleanContextImage,
            closeUpImage: detection.cropImage,
            initialSelection: initialSelection
        )
    }

    init(
        title: String,
        fullImage: UIImage?,
        closeUpImage: UIImage?,
        initialSelection: DetailedScanZoomSelection
    ) {
        self.title = title
        self.fullImage = fullImage
        self.closeUpImage = closeUpImage
        let requestedImageExists = initialSelection == .vehicleLocation
            ? fullImage != nil
            : closeUpImage != nil
        if requestedImageExists {
            self.initialSelection = initialSelection
        } else if fullImage != nil {
            self.initialSelection = .vehicleLocation
        } else {
            self.initialSelection = .damageCloseUp
        }
    }

    var availableSelections: [DetailedScanZoomSelection] {
        DetailedScanZoomSelection.allCases.filter { image(for: $0) != nil }
    }

    func image(for selection: DetailedScanZoomSelection) -> UIImage? {
        switch selection {
        case .vehicleLocation: return fullImage
        case .damageCloseUp: return closeUpImage
        }
    }
}

enum DetailedScanZoomGeometry {
    static let maximumRelativeScale: CGFloat = 6

    static func aspectFitScale(imageSize: CGSize, viewportSize: CGSize) -> CGFloat {
        guard imageSize.width > 0,
              imageSize.height > 0,
              viewportSize.width > 0,
              viewportSize.height > 0 else { return 1 }
        return min(
            viewportSize.width / imageSize.width,
            viewportSize.height / imageSize.height
        )
    }

    static func maximumScale(minimumScale: CGFloat) -> CGFloat {
        max(minimumScale, minimumScale * maximumRelativeScale)
    }

    static func centeredInsets(contentSize: CGSize, viewportSize: CGSize) -> UIEdgeInsets {
        UIEdgeInsets(
            top: max(0, (viewportSize.height - contentSize.height) / 2),
            left: max(0, (viewportSize.width - contentSize.width) / 2),
            bottom: max(0, (viewportSize.height - contentSize.height) / 2),
            right: max(0, (viewportSize.width - contentSize.width) / 2)
        )
    }
}

private struct DetailedScanZoomViewer: View {
    let item: DetailedScanZoomItem
    @Environment(\.dismiss) private var dismiss
    @State private var selection: DetailedScanZoomSelection

    init(item: DetailedScanZoomItem) {
        self.item = item
        _selection = State(initialValue: item.initialSelection)
    }

    private var selectedImage: UIImage {
        item.image(for: selection)
            ?? item.fullImage
            ?? item.closeUpImage
            ?? UIImage()
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.headline)
                        Text(selection.title)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.72))
                    }
                    .foregroundColor(.white)

                    Spacer()

                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Close image viewer")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

                if item.availableSelections.count > 1 {
                    Picker("Image", selection: $selection) {
                        ForEach(item.availableSelections) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
                }

                DetailedCenteredZoomImage(image: selectedImage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                Text("Pinch to zoom · Drag to move · Double-tap to zoom or reset")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.13), in: Capsule())
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
            }
        }
        .statusBarHidden(true)
    }
}

private struct DetailedCenteredZoomImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> DetailedCenteredZoomScrollView {
        let scrollView = DetailedCenteredZoomScrollView()
        scrollView.configure(image: image)
        return scrollView
    }

    func updateUIView(_ scrollView: DetailedCenteredZoomScrollView, context: Context) {
        scrollView.configure(image: image)
    }
}

private final class DetailedCenteredZoomScrollView: UIScrollView, UIScrollViewDelegate {
    private let zoomImageView = UIImageView()
    private var displayedImage: UIImage?
    private var lastViewportSize = CGSize.zero
    private var needsInitialReset = true
    private var normalisedVisibleCenter = CGPoint(x: 0.5, y: 0.5)
    private var isRestoringViewport = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = .black
        contentInsetAdjustmentBehavior = .never
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        alwaysBounceHorizontal = false
        alwaysBounceVertical = false
        bouncesZoom = true
        decelerationRate = .normal

        zoomImageView.contentMode = .scaleAspectFit
        zoomImageView.isUserInteractionEnabled = true
        addSubview(zoomImageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(image: UIImage) {
        guard displayedImage !== image else { return }
        displayedImage = image
        zoomImageView.image = image
        zoomImageView.frame = CGRect(origin: .zero, size: image.size)
        contentSize = image.size
        needsInitialReset = true
        lastViewportSize = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let image = displayedImage,
              bounds.width > 0,
              bounds.height > 0 else { return }

        var shouldCenterAtMinimum = false
        if needsInitialReset || bounds.size != lastViewportSize {
            let viewportChanged = !needsInitialReset && bounds.size != lastViewportSize
            let centreToRestore = normalisedVisibleCenter
            let oldMinimum = minimumZoomScale
            let relativeScale = needsInitialReset || oldMinimum <= 0
                ? 1
                : max(1, zoomScale / oldMinimum)
            shouldCenterAtMinimum = relativeScale <= 1.01
            let newMinimum = DetailedScanZoomGeometry.aspectFitScale(
                imageSize: image.size,
                viewportSize: bounds.size
            )
            minimumZoomScale = newMinimum
            maximumZoomScale = DetailedScanZoomGeometry.maximumScale(minimumScale: newMinimum)
            zoomScale = min(maximumZoomScale, max(minimumZoomScale, newMinimum * relativeScale))
            lastViewportSize = bounds.size
            needsInitialReset = false

            centerImage()
            if viewportChanged && !shouldCenterAtMinimum {
                restoreVisibleCenter(centreToRestore)
            }
        }

        centerImage()
        if shouldCenterAtMinimum {
            contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        zoomImageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
        rememberVisibleCenter()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        rememberVisibleCenter()
    }

    func scrollViewDidEndZooming(
        _ scrollView: UIScrollView,
        with view: UIView?,
        atScale scale: CGFloat
    ) {
        centerImage()
        if scale <= minimumZoomScale * 1.01 {
            setContentOffset(
                CGPoint(x: -contentInset.left, y: -contentInset.top),
                animated: false
            )
        }
    }

    private func centerImage() {
        contentInset = DetailedScanZoomGeometry.centeredInsets(
            contentSize: contentSize,
            viewportSize: bounds.size
        )
    }

    private func rememberVisibleCenter() {
        guard !isRestoringViewport,
              zoomImageView.bounds.width > 0,
              zoomImageView.bounds.height > 0 else { return }
        let viewportCentre = CGPoint(x: bounds.midX, y: bounds.midY)
        let imagePoint = zoomImageView.convert(viewportCentre, from: self)
        normalisedVisibleCenter = CGPoint(
            x: min(1, max(0, imagePoint.x / zoomImageView.bounds.width)),
            y: min(1, max(0, imagePoint.y / zoomImageView.bounds.height))
        )
    }

    private func restoreVisibleCenter(_ normalisedCentre: CGPoint) {
        isRestoringViewport = true
        defer { isRestoringViewport = false }
        centerImage()
        let scaledCentre = CGPoint(
            x: normalisedCentre.x * zoomImageView.bounds.width * zoomScale,
            y: normalisedCentre.y * zoomImageView.bounds.height * zoomScale
        )
        let minimumOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
        let maximumOffset = CGPoint(
            x: max(minimumOffset.x, contentSize.width - bounds.width + contentInset.right),
            y: max(minimumOffset.y, contentSize.height - bounds.height + contentInset.bottom)
        )
        contentOffset = CGPoint(
            x: min(maximumOffset.x, max(minimumOffset.x, scaledCentre.x - bounds.width / 2)),
            y: min(maximumOffset.y, max(minimumOffset.y, scaledCentre.y - bounds.height / 2))
        )
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale * 1.05 {
            setZoomScale(minimumZoomScale, animated: true)
            return
        }

        let targetScale = min(maximumZoomScale, minimumZoomScale * 2.5)
        let point = gesture.location(in: zoomImageView)
        let zoomRect = CGRect(
            x: point.x - bounds.width / targetScale / 2,
            y: point.y - bounds.height / targetScale / 2,
            width: bounds.width / targetScale,
            height: bounds.height / targetScale
        )
        zoom(to: zoomRect, animated: true)
    }
}

enum DetailedFindingIntegrator {
    static func integrating(
        existing: [MutableDamageDetection],
        outcome: DetailedScanReviewOutcome
    ) -> [MutableDamageDetection] {
        var result = existing
        for candidate in outcome.acceptedFindings where !result.contains(where: { isDuplicate($0, candidate) }) {
            result.insert(candidate, at: 0)
        }
        // A manual box is an explicit user decision, so never silently discard it.
        result.insert(contentsOf: outcome.manualDetections, at: 0)
        return result
    }

    private static func isDuplicate(_ first: MutableDamageDetection, _ second: MutableDamageDetection) -> Bool {
        guard first.angleIndex == second.angleIndex,
              canonical(first.damageType) == canonical(second.damageType),
              let firstBox = first.normalizedBBox,
              let secondBox = second.normalizedBBox else { return false }
        let intersection = firstBox.intersection(secondBox)
        guard !intersection.isNull else { return false }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = firstBox.width * firstBox.height + secondBox.width * secondBox.height - intersectionArea
        return unionArea > 0 && intersectionArea / unionArea >= 0.35
    }

    private static func canonical(_ value: String) -> String {
        let label = value.lowercased().replacingOccurrences(of: "_", with: " ")
        let scratchFamily = ["scratch", "scuff", "crack", "paint damage", "paint chip", "paint chipping", "paint peel", "paint peeling", "peeling"]
        return scratchFamily.contains(label) ? "scratch" : label
    }
}
