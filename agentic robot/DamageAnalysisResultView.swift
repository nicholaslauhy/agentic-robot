import SwiftUI
import UIKit
import Combine
import FirebaseAuth
import FirebaseFirestore

struct NP299EscalationContext {
    let checklistID: String
    let checklistReportNo: String
    let informantName: String
    let workContact: String
    let incidentDate: Date?
    let onReportSaved: (String) -> Void
}

private struct NP299EscalationContextKey: EnvironmentKey {
    static let defaultValue: NP299EscalationContext? = nil
}

extension EnvironmentValues {
    var htxNP299EscalationContext: NP299EscalationContext? {
        get { self[NP299EscalationContextKey.self] }
        set { self[NP299EscalationContextKey.self] = newValue }
    }
}

// Make URL usable as a sheet item
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

extension UIApplication {
    func endEditing() {
        sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    /// Replacement for `UIScreen.main.bounds`, which is deprecated in newer iOS SDKs.
    /// Uses the active key window size instead, which is what this editor actually needs.
    var htxActiveWindowBounds: CGRect {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first { $0.isKeyWindow }?
            .bounds
        ?? CGRect(x: 0, y: 0, width: 390, height: 844)
    }
}

// MARK: - Navigation Helper

private enum HTXNavigationHelper {
    static func popToActivityList() {
        DispatchQueue.main.async {
            guard let root = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })?
                .windows
                .first(where: { $0.isKeyWindow })?
                .rootViewController else { return }

            root.findNavigationController()?.popToRootViewController(animated: true)
        }
    }
}

private extension UIViewController {
    func findNavigationController() -> UINavigationController? {
        if let navigationController = self as? UINavigationController {
            return navigationController
        }

        for child in children {
            if let navigationController = child.findNavigationController() {
                return navigationController
            }
        }

        return presentedViewController?.findNavigationController()
    }
}

// MARK: - Mutable Detection Model

enum DamageCaptureSource: String {
    case overviewAnalysis
    case detailedMultiAngle
    case manual
}

class MutableDamageDetection: ObservableObject, Identifiable {
    let id: UUID
    @Published var angleIndex: Int
    @Published var angleName: String
    @Published var damageType: String
    @Published var confidence: Double
    @Published var cropImage: UIImage?
    /// Annotated image (mask + bbox burned in by backend) — shown read-only in detail view.
    @Published var contextImage: UIImage?
    /// Pristine image with no annotations — used as the base layer in the bounding-box editor.
    @Published var cleanContextImage: UIImage?
    /// Normalized bounding box rect (0–1) drawn by the user, overlaid on cleanContextImage.
    @Published var normalizedBBox: CGRect?
    /// Original-image pixel-space box returned by backend. Used when saving the benchmark.
    @Published var x1: Int?
    @Published var y1: Int?
    @Published var x2: Int?
    @Published var y2: Int?
    /// Original backend image dimensions for coordinate scaling.
    @Published var imageWidth: Int?
    @Published var imageHeight: Int?
    /// True when this case came from the stored benchmark/baseline.
    @Published var isBaseline: Bool

    // ── VLM fields ──
    @Published var isVerifiedDamage: Bool
    @Published var vlmDamageType: String
    @Published var severity: String
    @Published var repairRecommendation: String
    @Published var repairComplexity: String
    @Published var likelyFalsePositive: Bool
    @Published var explanation: String

    // ── Capture provenance ──
    // Detailed-scan findings are still normal report damage cases, but retaining
    // this evidence lets the review screen and PDF explain how they were found.
    @Published var captureSource: DamageCaptureSource
    @Published var observedFrameCount: Int?
    @Published var totalFrameCount: Int?
    @Published var detailedPanelIDs: [String]

    init(from detection: DamageDetection) {
        self.id                    = detection.id
        self.angleIndex            = detection.angleIndex
        self.angleName             = detection.angleName
        self.damageType            = detection.damageType
        self.confidence            = detection.confidence
        self.cropImage             = detection.cropImage
        self.contextImage          = detection.contextImage
        self.cleanContextImage     = detection.cleanContextImage
        self.x1                    = detection.x1
        self.y1                    = detection.y1
        self.x2                    = detection.x2
        self.y2                    = detection.y2
        self.imageWidth            = detection.imageWidth
        self.imageHeight           = detection.imageHeight

        // Backend x1/y1/x2/y2 are pixel coordinates in the ORIGINAL image.
        // cleanContextImage/contextImage are downscaled for display, so do not
        // divide by the displayed UIImage size. Use backend imageWidth/imageHeight
        // when available, then fall back to the image size for manually-created cases.
        if let x1 = detection.x1, let y1 = detection.y1, let x2 = detection.x2, let y2 = detection.y2 {
            // Prefer the backend-reported image dimensions (pixel-exact).
            // Fall back to the actual pixel size of the context image — this
            // handles baseline detections that pre-date the imageWidth/imageHeight
            // fields, and local-cache items where those fields may be nil.
            let fallbackImage = detection.cleanContextImage ?? detection.contextImage
            let sourceWidth  = CGFloat(detection.imageWidth  ?? Int(fallbackImage?.size.width  ?? 0))
            let sourceHeight = CGFloat(detection.imageHeight ?? Int(fallbackImage?.size.height ?? 0))

            if sourceWidth > 0, sourceHeight > 0 {
                let nx1 = max(0, min(1, CGFloat(x1) / sourceWidth))
                let ny1 = max(0, min(1, CGFloat(y1) / sourceHeight))
                let nx2 = max(0, min(1, CGFloat(x2) / sourceWidth))
                let ny2 = max(0, min(1, CGFloat(y2) / sourceHeight))

                if nx2 > nx1, ny2 > ny1 {
                    self.normalizedBBox = CGRect(
                        x: nx1,
                        y: ny1,
                        width: nx2 - nx1,
                        height: ny2 - ny1
                    )
                } else {
                    self.normalizedBBox = nil
                }
            } else {
                // Last resort: we have pixel coords but no image size at all.
                // Store nil — the box simply won't be drawn rather than crashing.
                self.normalizedBBox = nil
            }
        } else {
            self.normalizedBBox = nil
        }
        self.isBaseline            = detection.isBaseline ?? false
        self.isVerifiedDamage      = detection.isVerifiedDamage
        self.vlmDamageType         = detection.vlmDamageType
        self.severity              = detection.severity
        self.repairRecommendation  = detection.repairRecommendation
        self.repairComplexity      = detection.repairComplexity
        self.likelyFalsePositive   = detection.likelyFalsePositive
        self.explanation           = detection.explanation
        self.captureSource         = .overviewAnalysis
        self.observedFrameCount    = nil
        self.totalFrameCount       = nil
        self.detailedPanelIDs      = []
    }

    /// Manual / user-created detection (no VLM data available)
    init(
        angleIndex: Int,
        angleName: String,
        damageType: String,
        confidence: Double,
        cropImage: UIImage?,
        contextImage: UIImage?,
        cleanContextImage: UIImage?,
        normalizedBBox: CGRect?,
        isBaseline: Bool = false,
        explanation: String = "",
        severity: String = "unassessed",
        captureSource: DamageCaptureSource = .manual,
        observedFrameCount: Int? = nil,
        totalFrameCount: Int? = nil,
        detailedPanelIDs: [String] = []
    ) {
        self.id                    = UUID()
        self.angleIndex            = angleIndex
        self.angleName             = angleName
        self.damageType            = damageType
        self.confidence            = confidence
        self.cropImage             = cropImage
        self.contextImage          = contextImage
        self.cleanContextImage     = cleanContextImage
        self.normalizedBBox        = normalizedBBox
        self.x1                    = nil
        self.y1                    = nil
        self.x2                    = nil
        self.y2                    = nil
        let baseImage              = cleanContextImage ?? contextImage ?? cropImage
        self.imageWidth            = baseImage.map { Int($0.size.width) }
        self.imageHeight           = baseImage.map { Int($0.size.height) }
        self.isBaseline            = isBaseline
        self.isVerifiedDamage      = true
        self.vlmDamageType         = damageType
        self.severity              = severity
        self.repairRecommendation  = ""
        self.repairComplexity      = ""
        self.likelyFalsePositive   = false
        self.explanation           = explanation
        self.captureSource         = captureSource
        self.observedFrameCount    = observedFrameCount
        self.totalFrameCount       = totalFrameCount
        self.detailedPanelIDs      = detailedPanelIDs
    }

    var detailedEvidenceDescription: String {
        guard captureSource == .detailedMultiAngle else { return "Overview image" }
        if let observedFrameCount, let totalFrameCount, totalFrameCount > 0 {
            return "Confirmed from \(observedFrameCount) of \(totalFrameCount) multi-angle views"
        }
        return "Confirmed by the detailed multi-angle scan"
    }
}

// MARK: - Result List View

private struct DetailedScanWorkflowPresentation: Identifiable {
    let id = UUID()
}

private enum DamageSummaryDestination {
    case detailedScan
    case reportDetails
}

struct DamageAnalysisResultView: View {

    let plate: String
    let carType: CarType
    let detections: [DamageDetection]
    var onBackToScratchScan: () -> Void
    var onLogout: () -> Void

    // Mutable state
    @State private var mutableDetections: [MutableDamageDetection] = []

    // Sheet / navigation state
    @State private var selectedDetection: MutableDamageDetection? = nil
    @State private var showAddCase     = false
    @State private var detectionToEdit: MutableDamageDetection? = nil
    
    @State private var pdfURL: URL? = nil
    @State private var isGeneratingReport = false
    @State private var showIncidentStageOne = false
    @State private var showDamageSummaryReview = false
    @State private var pendingSummaryDestination: DamageSummaryDestination?
    @State private var detailedScanWorkflow: DetailedScanWorkflowPresentation?
    @State private var openReportAfterDetailedScan = false

    // The 4 angle images passed from ScratchScanView
    // We re-use the scanned images stored in the detections; if none exist we show placeholders.
    // For "Add Case", the user picks which of the 4 slots they want.
    let scanImages: [UIImage]   // front, back, left, right  (may have fewer)

    private var newDamageDetections: [MutableDamageDetection] {
        mutableDetections.filter { !$0.isBaseline }
    }

    private var existingDamageDetections: [MutableDamageDetection] {
        mutableDetections.filter { $0.isBaseline }
    }

    init(
        plate: String,
        carType: CarType,
        detections: [DamageDetection],
        scanImages: [UIImage] = [],
        onBackToScratchScan: @escaping () -> Void,
        onLogout: @escaping () -> Void
    ) {
        self.plate              = plate
        self.carType            = carType
        self.detections         = detections
        self.scanImages         = scanImages
        self.onBackToScratchScan = onBackToScratchScan
        self.onLogout           = onLogout
    }

    var body: some View {
        ZStack {
            SubtleHTXBackground()

            ScrollView {
            VStack(spacing: 18) {

                // ── Header ────────────────────────────────────────────────────
                HStack(alignment: .top) {
                    Button {
                        onBackToScratchScan()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").fontWeight(.semibold)
                            Text("Back")
                        }
                        .foregroundColor(HTXTheme.primaryPurple)
                    }

                    Spacer()

                    VStack(alignment: .center, spacing: 4) {
                        Text("Damage Analysis")
                            .font(.title2).bold()
                            .foregroundColor(HTXTheme.primaryPurple)
                        Text("\(carType.rawValue) · \(plate)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        // Add Case button
                        Button {
                            showAddCase = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                Text("Add")
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(HTXTheme.primaryPurple)
                        }

                        Button("Logout") { onLogout() }
                            .foregroundColor(.red)
                    }
                    .frame(width: 130, alignment: .trailing)
                }
                .padding(.horizontal, 24)
                .padding(.top, 44)

                // ── Content ───────────────────────────────────────────────────
                if mutableDetections.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        Text("No damage cases")
                            .font(.title3.bold())
                        Text("All cases have been removed, or none were detected.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)

                } else {
                    Text("Review the newly identified damage first. Existing benchmark damage is shown below in a separate section.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    DamageSectionView(
                        title: "New dents and scratches",
                        subtitle: newDamageDetections.isEmpty
                            ? "No new damage was identified against the current benchmark."
                            : "These are the new regions found in this scan.",
                        iconName: "sparkles",
                        detections: newDamageDetections,
                        emptySystemImage: "checkmark.seal.fill",
                        emptyText: "No new damage found",
                        accentColor: HTXTheme.primaryPurple,
                        selectedDetection: $selectedDetection,
                        detectionToEdit: $detectionToEdit,
                        onDelete: remove
                    )

                    DamageSectionView(
                        title: "Existing benchmark damage",
                        subtitle: existingDamageDetections.isEmpty
                            ? "No previous benchmark damage was returned for this plate. If you expected old cases here, regenerate one report after applying this fix so the benchmark is saved."
                            : "These scratches and dents were already recorded for this vehicle.",
                        iconName: "clock.arrow.circlepath",
                        detections: existingDamageDetections,
                        emptySystemImage: "tray",
                        emptyText: "No existing benchmark damage saved yet",
                        accentColor: .gray,
                        selectedDetection: $selectedDetection,
                        detectionToEdit: $detectionToEdit,
                        onDelete: remove
                    )
                }

                // ── Next: collect police-report details ─────────────────────────
                Button {
                    showDamageSummaryReview = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("Next")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(HTXTheme.primaryPurple)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                    .padding(.horizontal)
                }
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
        }
        }
        .overlay {
            if isGeneratingReport {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.4)
                            .tint(HTXTheme.primaryPurple)
                        Image(systemName: "doc.richtext.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundColor(HTXTheme.primaryPurple)
                        Text("Generating your report…")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("This may take a few seconds.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(HTXTheme.softPurpleCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(HTXTheme.softPurpleBorder, lineWidth: 1)
                    )
                    .shadow(color: HTXTheme.primaryPurple.opacity(0.18), radius: 16, y: 6)
                    .padding(.horizontal, 40)
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
        }
        .navigationBarBackButtonHidden(true)
        // ── Detail sheet ──────────────────────────────────────────────────────
        .sheet(item: $selectedDetection) { detection in
            DamageDetailSheet(
                detection: detection,
                accentColor: HTXTheme.primaryPurple
            )
        }
        // ── Edit bounding-box screen ──────────────────────────────────────────
        // Full-screen is required here. A normal .sheet makes the wide vehicle
        // image too small, so drawing boxes becomes inaccurate/frustrating.
        .fullScreenCover(item: $detectionToEdit) { detection in
            BoundingBoxEditorSheet(
                detection: detection,
                accentColor: HTXTheme.primaryPurple,
                scanImage: detection.angleIndex < scanImages.count ? scanImages[detection.angleIndex] : nil
            )
        }
        // ── Add Case screen ───────────────────────────────────────────────────
        // Same reason: drawing must happen on a full-screen canvas, not a small sheet.
        .fullScreenCover(isPresented: $showAddCase) {
            AddCaseSheet(
                scanImages: scanImages,
                accentColor: HTXTheme.primaryPurple
            ) { newDetection in
                mutableDetections.insert(newDetection, at: 0)
            }
        }
        // ── Damage summary review before report details ───────────────────────
        .fullScreenCover(
            isPresented: $showDamageSummaryReview,
            onDismiss: continueAfterDamageSummary
        ) {
            DamageSummaryReviewBeforeReportView(
                plate: plate,
                carType: carType,
                newDetections: newDamageDetections,
                existingDetections: existingDamageDetections,
                scanImages: scanImages,
                onBack: { showDamageSummaryReview = false },
                onStartDetailedScan: {
                    pendingSummaryDestination = .detailedScan
                    showDamageSummaryReview = false
                },
                onSkipDetailedScan: {
                    pendingSummaryDestination = .reportDetails
                    showDamageSummaryReview = false
                }
            )
        }
        .fullScreenCover(
            item: $detailedScanWorkflow,
            onDismiss: continueAfterDetailedScan
        ) { _ in
            DetailedScanWorkflowView(
                plate: plate,
                carType: carType,
                overviewImages: scanImages,
                onCancel: {
                    detailedScanWorkflow = nil
                },
                onContinueWithoutResults: {
                    openReportAfterDetailedScan = true
                    detailedScanWorkflow = nil
                },
                onComplete: { outcome in
                    mutableDetections = DetailedFindingIntegrator.integrating(
                        existing: mutableDetections,
                        outcome: outcome
                    )
                    openReportAfterDetailedScan = true
                    detailedScanWorkflow = nil
                }
            )
        }
        // ── Report details flow ───────────────────────────────────────────────
        .fullScreenCover(isPresented: $showIncidentStageOne) {
            PoliceReportStageZeroView(
                plate: plate,
                carType: carType,
                detections: mutableDetections,
                scanImages: scanImages,
                onLogout: onLogout,
                isGeneratingReport: $isGeneratingReport,
                pdfURL: $pdfURL,
                isPresented: $showIncidentStageOne
            )
        }
        .onAppear {
            if mutableDetections.isEmpty {
                mutableDetections = detections.map { MutableDamageDetection(from: $0) }
            }
        }
    }

    private func remove(_ detection: MutableDamageDetection) {
        withAnimation {
            mutableDetections.removeAll { $0.id == detection.id }
        }
    }

    private func continueAfterDamageSummary() {
        guard let destination = pendingSummaryDestination else { return }
        pendingSummaryDestination = nil
        switch destination {
        case .detailedScan:
            detailedScanWorkflow = DetailedScanWorkflowPresentation()
        case .reportDetails:
            showIncidentStageOne = true
        }
    }

    private func continueAfterDetailedScan() {
        guard openReportAfterDetailedScan else { return }
        openReportAfterDetailedScan = false
        showIncidentStageOne = true
    }
}


// MARK: - Damage Sections

private struct DamageSectionView: View {
    let title: String
    let subtitle: String
    let iconName: String
    let detections: [MutableDamageDetection]
    let emptySystemImage: String
    let emptyText: String
    let accentColor: Color
    @Binding var selectedDetection: MutableDamageDetection?
    @Binding var detectionToEdit: MutableDamageDetection?
    var onDelete: (MutableDamageDetection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundColor(accentColor)
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(detections.count)")
                    .font(.caption.bold())
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(accentColor.opacity(0.12))
                    .foregroundColor(accentColor)
                    .clipShape(Capsule())
            }

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)

            if detections.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: emptySystemImage)
                        .font(.title2)
                        .foregroundColor(.green)
                    Text(emptyText)
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color(.secondarySystemBackground).opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(detections) { detection in
                        DamageDetectionCard(
                            detection: detection,
                            accentColor: accentColor,
                            onEdit: { detectionToEdit = detection },
                            onDelete: { onDelete(detection) }
                        )
                        .onTapGesture { selectedDetection = detection }
                    }
                }
            }
        }
        .padding(16)
        .background(HTXTheme.softPurpleCard.opacity(accentColor == .gray ? 0.55 : 1.0))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(accentColor.opacity(0.18), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

// MARK: - Card

struct DamageDetectionCard: View {
    @ObservedObject var detection: MutableDamageDetection
    let accentColor: Color
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                // Show the full vehicle location with the exact orange region,
                // instead of only showing the close-up crop. This makes both
                // new damage and existing benchmark damage visually traceable.
                if detection.cleanContextImage != nil || detection.contextImage != nil || detection.cropImage != nil {
                    DamageLocationPreviewView(
                        detection: detection,
                        accentColor: accentColor
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    ZStack {
                        Color(.systemGray5)
                        VStack(spacing: 8) {
                            Image(systemName: "photo").font(.title).foregroundColor(.secondary)
                            Text("Could not load image").font(.footnote).foregroundColor(.secondary)
                        }
                    }
                    .frame(height: 200)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(accentColor.opacity(0.35), lineWidth: 1))

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(detection.damageType.capitalized).font(.headline).foregroundColor(HTXTheme.primaryPurple)
                    Text(detection.angleName).font(.subheadline).foregroundColor(.secondary)
                    Text(detection.isBaseline ? "Existing benchmark" : "New damage")
                        .font(.caption.bold())
                        .foregroundColor(detection.isBaseline ? .gray : accentColor)
                }
                Spacer()
                HStack(spacing: 8) {
                    Text("\(Int(detection.confidence * 100))%")
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(accentColor.opacity(0.12))
                        .foregroundColor(accentColor)
                        .clipShape(Capsule())

                    // Edit bbox button
                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "pencil.and.outline")
                            .font(.subheadline)
                            .foregroundColor(accentColor)
                            .padding(8)
                            .background(accentColor.opacity(0.1))
                            .clipShape(Circle())
                    }

                    // Delete button
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .padding(8)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.top, 10)
        }
        .padding(12)
        .background(HTXTheme.softPurpleCard)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(HTXTheme.softPurpleBorder, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}



// MARK: - Damage Image Preview Helpers

private struct DamageLocationPreviewView: View {
    @ObservedObject var detection: MutableDamageDetection
    let accentColor: Color

    var body: some View {
        Group {
            if let bbox = detection.normalizedBBox,
               let image = detection.cleanContextImage ?? detection.contextImage {
                BoundingBoxOverlayView(
                    image: image,
                    normalizedBBox: .constant(Optional(bbox)),
                    accentColor: .orange,
                    isInteractive: false
                )
            } else if let annotated = detection.contextImage {
                Image(uiImage: annotated)
                    .resizable()
                    .scaledToFit()
            } else if let crop = detection.cropImage {
                Image(uiImage: drawOrangeOutlineOnWholeImage(crop))
                    .resizable()
                    .scaledToFit()
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.orange.opacity(0.55), lineWidth: 1.5)
        )
    }
}

private struct DamageCloseUpPreviewView: View {
    @ObservedObject var detection: MutableDamageDetection
    let accentColor: Color

    var body: some View {
        Group {
            if let bbox = detection.normalizedBBox,
               let image = detection.cleanContextImage ?? detection.contextImage {
                Image(uiImage: renderAnnotatedCrop(image: image, bbox: bbox, padding: 0.55))
                    .resizable()
                    .scaledToFit()
            } else if let crop = detection.cropImage {
                Image(uiImage: drawOrangeOutlineOnWholeImage(crop))
                    .resizable()
                    .scaledToFit()
            } else if let context = detection.contextImage {
                Image(uiImage: drawOrangeOutlineOnWholeImage(context))
                    .resizable()
                    .scaledToFit()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.orange.opacity(0.75), lineWidth: 2)
        )
    }
}

// MARK: - Damage Summary Review Before Police Report

private struct DamageSummaryReviewBeforeReportView: View {
    let plate: String
    let carType: CarType
    let newDetections: [MutableDamageDetection]
    let existingDetections: [MutableDamageDetection]
    let scanImages: [UIImage]
    let onBack: () -> Void
    let onStartDetailedScan: () -> Void
    let onSkipDetailedScan: () -> Void

    @State private var selectedAngle: SummaryAngleSelection? = nil

    private var allDetections: [MutableDamageDetection] {
        existingDetections + newDetections
    }

    private var angleCount: Int {
        let maxDetectionAngle = allDetections.map(\.angleIndex).max().map { $0 + 1 } ?? 0
        return max(4, scanImages.count, maxDetectionAngle)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SubtleHTXBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        VStack(spacing: 6) {
                            Text("Damage Summary")
                                .font(.largeTitle.bold())
                                .foregroundColor(HTXTheme.primaryPurple)
                            Text("\(carType.rawValue) · \(plate)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Yellow = new damage. Existing benchmark damage is colour-coded by damage type.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.top, 20)

                        SummaryDamageLegendView()
                        .padding(.horizontal)

                        if allDetections.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.green)
                                Text("No scratches or dents to show")
                                    .font(.title3.bold())
                                Text("No new damage was identified against the current benchmark.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(28)
                            .frame(maxWidth: .infinity)
                            .background(HTXTheme.softPurpleCard)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .padding(.horizontal)
                        } else {
                            ForEach(0..<angleCount, id: \.self) { angleIndex in
                                let existingForAngle = existingDetections.filter { $0.angleIndex == angleIndex }
                                let newForAngle = newDetections.filter { $0.angleIndex == angleIndex }
                                let image = angleIndex < scanImages.count ? scanImages[angleIndex] : nil

                                SummaryAngleCardView(
                                    angleIndex: angleIndex,
                                    image: image,
                                    existingDetections: existingForAngle,
                                    newDetections: newForAngle
                                ) {
                                    selectedAngle = SummaryAngleSelection(index: angleIndex)
                                }
                                .padding(.horizontal)
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Report will include new damage only")
                                    .font(.headline)
                                Text("Existing benchmark scratches/dents are displayed above with damage-type colours for reference, but they will not be added into the final NP299 report. New damage is shown in yellow and will be included in the report.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if newDetections.isEmpty {
                                    Text("No new scratches or dents identified.")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.secondary)
                                        .padding(.top, 4)
                                } else {
                                    ForEach(Array(newDetections.enumerated()), id: \.element.id) { idx, det in
                                        HStack(alignment: .top, spacing: 10) {
                                            Text("\(idx + 1)")
                                                .font(.caption.bold())
                                                .frame(width: 24, height: 24)
                                                .background(Color.orange.opacity(0.18))
                                                .foregroundColor(.orange)
                                                .clipShape(Circle())
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(det.damageType.capitalized)
                                                    .font(.subheadline.bold())
                                                Text(det.angleName)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            Spacer()
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(HTXTheme.softPurpleCard)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .padding(.horizontal)
                        }

                        VStack(spacing: 12) {
                            VStack(spacing: 5) {
                                Text("Would you like a closer inspection?")
                                    .font(.headline)
                                Text("The optional detailed scan captures 12 vehicle panels after the four overview photos.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }

                            Button {
                                onStartDetailedScan()
                            } label: {
                                HStack {
                                    Image(systemName: "viewfinder.circle.fill")
                                    Text("Continue with 12-Panel Scan")
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(HTXTheme.primaryPurple)
                                .foregroundColor(.white)
                                .cornerRadius(14)
                            }

                            Button {
                                onSkipDetailedScan()
                            } label: {
                                HStack {
                                    Image(systemName: "doc.text.fill")
                                    Text("Skip to Report Details")
                                }
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .foregroundColor(HTXTheme.primaryPurple)
                                .cornerRadius(14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(HTXTheme.softPurpleBorder, lineWidth: 1)
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 6)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { onBack() }
                }
            }
            .fullScreenCover(item: $selectedAngle) { selection in
                SummaryAngleDetailView(
                    angleIndex: selection.index,
                    image: selection.index < scanImages.count ? scanImages[selection.index] : nil,
                    existingDetections: existingDetections.filter { $0.angleIndex == selection.index },
                    newDetections: newDetections.filter { $0.angleIndex == selection.index }
                )
            }
        }
    }
}

private struct SummaryAngleSelection: Identifiable {
    let index: Int
    var id: Int { index }
}

private struct SummaryLegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(text)
                .font(.caption.bold())
                .foregroundColor(.secondary)
        }
    }
}


private struct SummaryDamageLegendView: View {
    private let legendItems: [(Color, String)] = [
        (.yellow, "New damage"),
        (summaryExistingDamageColor(for: "scratch"), "Existing scratch"),
        (summaryExistingDamageColor(for: "dent"), "Existing dent"),
        (summaryExistingDamageColor(for: "crack"), "Existing crack"),
        (summaryExistingDamageColor(for: "deformation"), "Existing deformation"),
        (summaryExistingDamageColor(for: "broken glass"), "Existing broken glass"),
        (summaryExistingDamageColor(for: "paint chip"), "Existing paint chip"),
        (summaryExistingDamageColor(for: "rust"), "Existing rust"),
        (summaryExistingDamageColor(for: "other"), "Existing other"),
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 8) {
            ForEach(Array(legendItems.enumerated()), id: \.offset) { _, item in
                SummaryLegendDot(color: item.0, text: item.1)
            }
        }
    }
}

private func summaryDamageName(_ detection: MutableDamageDetection) -> String {
    canonicalSummaryDamageName(detection.damageType)
}

private func summaryColor(for detection: MutableDamageDetection, isNew: Bool) -> Color {
    if isNew {
        return .yellow
    }
    return summaryExistingDamageColor(for: detection.damageType)
}

private func canonicalSummaryDamageName(_ rawValue: String) -> String {
    let value = rawValue
        .lowercased()
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")

    if value.contains("scratch") { return "Scratch" }
    if value.contains("dent") { return "Dent" }
    if value.contains("crack") { return "Crack" }
    if value.contains("deform") { return "Deformation" }
    if value.contains("glass") || value.contains("broken") { return "Broken Glass" }
    if value.contains("paint") || value.contains("chip") { return "Paint Chip" }
    if value.contains("rust") { return "Rust" }
    return "Other"
}

private func summaryExistingDamageColor(for rawValue: String) -> Color {
    switch canonicalSummaryDamageName(rawValue) {
    case "Scratch":
        return .blue
    case "Dent":
        return .purple
    case "Crack":
        return .red
    case "Deformation":
        return .brown
    case "Broken Glass":
        return .cyan
    case "Paint Chip":
        return .pink
    case "Rust":
        return .orange
    default:
        return .gray
    }
}

private struct SummaryAngleCardView: View {
    let angleIndex: Int
    let image: UIImage?
    let existingDetections: [MutableDamageDetection]
    let newDetections: [MutableDamageDetection]
    let onTap: () -> Void

    private var angleTitle: String {
        angleIndex < angleNames.count ? angleNames[angleIndex] : "Angle \(angleIndex + 1)"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(angleTitle)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("\(existingDetections.count) existing · \(newDetections.count) new")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.bold())
                        .foregroundColor(HTXTheme.primaryPurple)
                }

                if let image {
                    MultiDamageOverlayImageView(
                        image: image,
                        existingDetections: existingDetections,
                        newDetections: newDetections,
                        showBadges: true,
                        lineWidth: 2.5,
                        badgeSize: 24
                    )
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.title2)
                        Text("No image available")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .background(Color.black.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(14)
            .background(HTXTheme.softPurpleCard)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(HTXTheme.softPurpleBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SummaryAngleDetailView: View {
    let angleIndex: Int
    let image: UIImage?
    let existingDetections: [MutableDamageDetection]
    let newDetections: [MutableDamageDetection]
    @Environment(\.dismiss) private var dismiss

    private var angleTitle: String {
        angleIndex < angleNames.count ? angleNames[angleIndex] : "Angle \(angleIndex + 1)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        if let image {
                            MultiDamageOverlayImageView(
                                image: image,
                                existingDetections: existingDetections,
                                newDetections: newDetections,
                                showBadges: true,
                                lineWidth: 4,
                                badgeSize: 34
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                            .padding(.top, 12)
                        } else {
                            Text("No image available")
                                .foregroundColor(.white.opacity(0.75))
                                .padding(.top, 80)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            SummaryDamageLegendView()

                            if existingDetections.isEmpty && newDetections.isEmpty {
                                Text("No damage regions for this angle.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(Array(existingDetections.enumerated()), id: \.element.id) { idx, det in
                                    SummaryDamageRow(
                                        detection: det,
                                        color: summaryColor(for: det, isNew: false),
                                        label: "E\(idx + 1): \(summaryDamageName(det))"
                                    )
                                }
                                ForEach(Array(newDetections.enumerated()), id: \.element.id) { idx, det in
                                    SummaryDamageRow(
                                        detection: det,
                                        color: summaryColor(for: det, isNew: true),
                                        label: "N\(idx + 1): \(summaryDamageName(det))"
                                    )
                                }
                            }
                        }
                        .padding()
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle(angleTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.white)
                }
            }
        }
    }
}

private struct SummaryDamageRow: View {
    @ObservedObject var detection: MutableDamageDetection
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                Text(detection.angleName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
}

private struct MultiDamageOverlayImageView: View {
    let image: UIImage
    let existingDetections: [MutableDamageDetection]
    let newDetections: [MutableDamageDetection]
    var showBadges: Bool
    var lineWidth: CGFloat
    var badgeSize: CGFloat

    var body: some View {
        GeometryReader { geo in
            let imageRect = fittedImageRect(imageSize: image.size, in: geo.size)

            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)

                ForEach(Array(existingDetections.enumerated()), id: \.element.id) { idx, det in
                    if let box = screenBox(for: det, imageRect: imageRect) {
                        DamageSummaryBoxOverlay(
                            rect: box,
                            color: summaryColor(for: det, isNew: false),
                            label: showBadges ? "E\(idx + 1): \(summaryDamageName(det))" : nil,
                            lineWidth: lineWidth,
                            badgeSize: badgeSize
                        )
                    }
                }

                ForEach(Array(newDetections.enumerated()), id: \.element.id) { idx, det in
                    if let box = screenBox(for: det, imageRect: imageRect) {
                        DamageSummaryBoxOverlay(
                            rect: box,
                            color: summaryColor(for: det, isNew: true),
                            label: showBadges ? "N\(idx + 1): \(summaryDamageName(det))" : nil,
                            lineWidth: lineWidth,
                            badgeSize: badgeSize
                        )
                    }
                }
            }
        }
        .aspectRatio(image.size, contentMode: .fit)
    }

    private func fittedImageRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }

        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    private func screenBox(for detection: MutableDamageDetection, imageRect: CGRect) -> CGRect? {
        guard let bbox = detection.normalizedBBox else { return nil }

        let raw = CGRect(
            x: imageRect.minX + bbox.minX * imageRect.width,
            y: imageRect.minY + bbox.minY * imageRect.height,
            width: bbox.width * imageRect.width,
            height: bbox.height * imageRect.height
        )

        let clamped = raw.intersection(imageRect)
        guard !clamped.isNull, clamped.width > 1, clamped.height > 1 else { return nil }
        return clamped
    }
}

private struct DamageSummaryBoxOverlay: View {
    let rect: CGRect
    let color: Color
    let label: String?
    let lineWidth: CGFloat
    let badgeSize: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(color, lineWidth: lineWidth)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)

            if let label {
                Text(label)
                    .font(.system(size: max(badgeSize * 0.38, 9), weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, max(badgeSize * 0.18, 4))
                    .frame(minWidth: badgeSize, minHeight: badgeSize)
                    .background(color)
                    .clipShape(Capsule())
                    .offset(
                        x: max(rect.minX - badgeSize * 0.25, 0),
                        y: max(rect.minY - badgeSize * 0.45, 0)
                    )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Detail Sheet

struct DamageDetailSheet: View {
    @ObservedObject var detection: MutableDamageDetection
    let accentColor: Color
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Location on car", systemImage: "viewfinder")
                            .font(.headline).padding(.horizontal)

                        // For manual cases, use the clean full-car image + the saved bbox so the
                        // orange box is positioned from the same coordinates used for the crop.
                        // For backend cases without a saved bbox, fall back to the annotated context image.
                        if detection.cleanContextImage != nil || detection.contextImage != nil || detection.cropImage != nil {
                            DamageLocationPreviewView(
                                detection: detection,
                                accentColor: accentColor
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal)
                        } else {
                            Text("Context image not available")
                                .font(.footnote).foregroundColor(.secondary).padding(.horizontal)
                        }
                    }

                    Divider().padding(.horizontal)

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Damage close-up", systemImage: "magnifyingglass")
                            .font(.headline).padding(.horizontal)

                        DamageCloseUpPreviewView(
                            detection: detection,
                            accentColor: accentColor
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal)
                    }

                    VStack(spacing: 0) {
                        metaRow(label: "Type",       value: detection.damageType.capitalized)
                        Divider()
                        metaRow(label: "Angle",      value: detection.angleName)
                        Divider()
                        metaRow(label: "Confidence", value: "\(Int(detection.confidence * 100))%")
                        if !detection.severity.isEmpty {
                            Divider()
                            metaRow(label: "Severity", value: detection.severity.capitalized)
                        }
                        if detection.captureSource == .detailedMultiAngle {
                            Divider()
                            metaRow(label: "Evidence", value: detection.detailedEvidenceDescription)
                        }
                        if !detection.repairComplexity.isEmpty {
                            Divider()
                            metaRow(label: "Repair Complexity", value: detection.repairComplexity.capitalized)
                        }
                    }
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)

                    if !detection.repairRecommendation.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Repair Recommendation", systemImage: "wrench.and.screwdriver")
                                .font(.headline)
                            Text(detection.repairRecommendation)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)
                    }

                    if !detection.explanation.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("AI Analysis", systemImage: "sparkles")
                                .font(.headline)
                            Text(detection.explanation)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 30)
            }
            .navigationTitle("Damage Detail")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(SubtleHTXBackground())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
        .padding(.horizontal).padding(.vertical, 12)
    }
}

// MARK: - Bounding Box Overlay View

/// Shows an image with an orange bounding box drawn on it.
/// When isInteractive = false it is read-only. When true a draw gesture replaces the box.
/// The drag gesture is strictly clamped to the image bounds — drawing outside is impossible.
struct BoundingBoxOverlayView: View {
    let image: UIImage
    @Binding var normalizedBBox: CGRect?
    let accentColor: Color
    var isInteractive: Bool

    @State private var currentDrag: CGRect? = nil

    var body: some View {
        // Use a fixed aspect-ratio frame so the rendered image size is exactly known.
        GeometryReader { geo in
            let imageRect = fittedImageRect(in: geo.size)

            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)

                // Overlay: in-progress drag OR committed bbox, both in screen coords
                if let screenRect = currentDrag ?? normalizedBBox.map({ denorm($0, imageRect: imageRect) }) {
                    Rectangle()
                        .stroke(Color.orange, lineWidth: 2.5)
                        .frame(width: screenRect.width, height: screenRect.height)
                        .offset(x: screenRect.minX, y: screenRect.minY)
                        .allowsHitTesting(false)
                }
            }
            // Only attach gesture to the actual image area, not the full GeometryReader frame
            .contentShape(
                Rectangle()
                    .path(in: imageRect)   // hit-test region == image only
            )
            .gesture(
                isInteractive
                ? DragGesture(minimumDistance: 4, coordinateSpace: .local)
                    .onChanged { val in
                        let rect = clampedRect(from: val.startLocation,
                                              to: val.location,
                                              within: imageRect)
                        currentDrag = rect
                    }
                    .onEnded { val in
                        let rect = clampedRect(from: val.startLocation,
                                              to: val.location,
                                              within: imageRect)
                        normalizedBBox = normalize(rect, imageRect: imageRect)

                        // IMPORTANT:
                        // Do not keep the screen-space drag rectangle after the drag ends.
                        // When normalizedBBox becomes non-nil, the preview below appears and
                        // the layout can change. If currentDrag stays set, SwiftUI keeps drawing
                        // the old screen-space rectangle using the old image size/position, so
                        // the first box appears shifted/wrong. Clearing it forces the overlay to
                        // redraw from normalizedBBox in the new layout.
                        currentDrag = nil
                    }
                : nil
            )
        }
        .aspectRatio(image.size, contentMode: .fit)
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /// The rect (in the GeometryReader's coordinate space) that the image actually occupies.
    /// scaledToFit centres the image horizontally and/or vertically within the container.
    private func fittedImageRect(in containerSize: CGSize) -> CGRect {
        let imgAspect = image.size.width / image.size.height
        let conAspect = containerSize.width / containerSize.height
        let imgW: CGFloat
        let imgH: CGFloat
        if imgAspect > conAspect {
            // Image is wider relative to container → fit by width
            imgW = containerSize.width
            imgH = containerSize.width / imgAspect
        } else {
            // Image is taller relative to container → fit by height
            imgH = containerSize.height
            imgW = containerSize.height * imgAspect
        }
        let originX = (containerSize.width  - imgW) / 2
        let originY = (containerSize.height - imgH) / 2
        return CGRect(x: originX, y: originY, width: imgW, height: imgH)
    }

    /// Clamps both points to imageRect then returns the normalised (minX,minY,w,h) screen rect.
    private func clampedRect(from start: CGPoint, to end: CGPoint, within bounds: CGRect) -> CGRect {
        let clamp = { (pt: CGPoint) -> CGPoint in
            CGPoint(
                x: min(max(pt.x, bounds.minX), bounds.maxX),
                y: min(max(pt.y, bounds.minY), bounds.maxY)
            )
        }
        let s = clamp(start)
        let e = clamp(end)
        return CGRect(
            x: min(s.x, e.x),
            y: min(s.y, e.y),
            width:  abs(e.x - s.x),
            height: abs(e.y - s.y)
        )
    }

    /// Convert normalised (0–1 within image) bbox → screen coords within imageRect.
    private func denorm(_ rect: CGRect, imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + rect.minX * imageRect.width,
            y: imageRect.minY + rect.minY * imageRect.height,
            width:  rect.width  * imageRect.width,
            height: rect.height * imageRect.height
        )
    }

    /// Convert screen rect (within imageRect) → normalised (0–1 within image).
    private func normalize(_ rect: CGRect, imageRect: CGRect) -> CGRect {
        CGRect(
            x: (rect.minX - imageRect.minX) / imageRect.width,
            y: (rect.minY - imageRect.minY) / imageRect.height,
            width:  rect.width  / imageRect.width,
            height: rect.height / imageRect.height
        )
    }
}

// MARK: - Bounding Box Editor Sheet

struct BoundingBoxEditorSheet: View {
    @ObservedObject var detection: MutableDamageDetection
    let accentColor: Color
    /// The full original scan photo for this angle — used as both the drawing
    /// canvas and the crop source. Falls back to cleanContextImage if nil.
    let scanImage: UIImage?
    /// Called only after the user explicitly commits a valid box with Done.
    /// Detailed-scan projections use this acknowledgement to prevent an
    /// unverified backend location from being accepted silently.
    var onSave: (() -> Void)? = nil
    /// A detailed scan keeps its source-frame crop as the classification
    /// evidence while this editor changes only the overview location.
    var preserveExistingCropOnSave = false
    @Environment(\.dismiss) private var dismiss

    // Local working state — not committed to detection until Done is tapped
    @State private var pendingBBox: CGRect? = nil
    @State private var pendingDamageType: String = ""

    /// The image the user draws on — always the full car photo.
    private var canvasImage: UIImage? { scanImage ?? detection.cleanContextImage ?? detection.contextImage }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // ── Damage type picker ────────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Damage Type")
                            .font(.headline)
                            .padding(.horizontal)

                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 10
                        ) {
                            ForEach(damageTypes, id: \.self) { type in
                                Text(type.capitalized)
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(pendingDamageType == type ? accentColor : Color(.secondarySystemBackground))
                                    .foregroundColor(pendingDamageType == type ? .white : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .onTapGesture { pendingDamageType = type }
                            }
                        }
                        .padding(.horizontal)
                    }

                    Divider().padding(.horizontal)

                    // ── Bounding box editor ───────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bounding Box")
                            .font(.headline)
                            .padding(.horizontal)

                        Text("Drag on the image to draw the boundary around the damage area.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        if let img = canvasImage {
                            BoundingBoxOverlayView(
                                image: img,
                                normalizedBBox: $pendingBBox,
                                accentColor: .orange,
                                isInteractive: true
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: max(430, UIApplication.shared.htxActiveWindowBounds.height * 0.65))
                            .background(Color.black.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal)

                            if let bbox = pendingBBox {
                                VStack(alignment: .center, spacing: 10) {
                                    Label("Close-up Preview", systemImage: "magnifyingglass")
                                        .font(.subheadline.bold())

                                    Image(uiImage: renderAnnotatedCrop(image: img, bbox: bbox))
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: .infinity)
                                        .frame(maxHeight: 190)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(accentColor.opacity(0.35), lineWidth: 1)
                                        )
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.horizontal)
                                .padding(.top, 10)

                                Text("Boundary drawn. Draw again to replace it.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                            } else {
                                Text("No boundary drawn yet.")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding(.horizontal)
                            }
                        } else {
                            Text("No image available for this detection.")
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Edit Case")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                pendingDamageType = detection.damageType
                pendingBBox = detection.normalizedBBox
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        guard let bbox = pendingBBox, let baseImg = canvasImage else { return }

                        // Keep the saved preview images lightweight.
                        // If we store full-resolution camera images for every manual case,
                        // iOS can run out of render memory after several cases and the next
                        // annotated preview may appear as a blank white image.
                        let previewImg = resizedImageForPreview(baseImg)

                        detection.normalizedBBox  = bbox
                        // contextImage = full car photo preview with orange box burned in
                        detection.contextImage    = renderContext(image: previewImg, bbox: bbox)
                        // cleanContextImage = full car photo preview with no annotations (for future edits)
                        detection.cleanContextImage = normalizedImage(previewImg)
                        // For ordinary/manual cases, cropImage follows the
                        // edited overview. Detailed scans retain the original
                        // panel-frame close-up as their damage evidence.
                        if !preserveExistingCropOnSave {
                            detection.cropImage = renderAnnotatedCrop(image: previewImg, bbox: bbox)
                        }

                        // If the user changed the damage type, update explanation to match.
                        if pendingDamageType != detection.damageType {
                            let canonical = pendingDamageType.capitalized
                            let angle     = detection.angleName
                            // Rebuild the AI analysis sentence to reflect the corrected type.
                            detection.explanation = "\(canonical) detected on the \(angle)."
                            detection.vlmDamageType = pendingDamageType
                        }

                        detection.damageType = pendingDamageType
                        detection.confidence = 1.0
                        onSave?()
                        dismiss()
                    }
                    .disabled(pendingBBox == nil || pendingDamageType.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear Box") { pendingBBox = nil }
                        .foregroundColor(.red)
                }
            }
        }
    }
}

// MARK: - Add Case Sheet

private let angleNames = ["Front", "Back", "Left Side", "Right Side"]

private let damageTypes = [
    "scratch", "dent", "crack", "deformation",
    "broken glass", "paint chip", "rust", "other"
]

struct AddCaseSheet: View {
    let scanImages: [UIImage]
    let accentColor: Color
    var onAdd: (MutableDamageDetection) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedAngleIndex: Int = 0
    @State private var selectedDamageType: String = damageTypes[0]
    @State private var normalizedBBox: CGRect? = nil
    @State private var step: Int = 0  // 0 = pick angle + type, 1 = draw bbox

    var selectedImage: UIImage? {
        guard selectedAngleIndex < scanImages.count else { return nil }
        return scanImages[selectedAngleIndex]
    }

    var body: some View {
        NavigationStack {
            Group {
                if step == 0 {
                    selectStep
                } else {
                    drawStep
                }
            }
            .navigationTitle(step == 0 ? "Add Damage Case" : "Draw Boundary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == 0 ? "Cancel" : "Back") {
                        if step == 0 { dismiss() } else { step = 0 }
                    }
                }
                if step == 1 {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add Case") {
                            let angleName  = angleNames[selectedAngleIndex]
                            let explanation = "\(selectedDamageType.capitalized) detected on the \(angleName)."
                            let previewImage = selectedImage.map { resizedImageForPreview($0) }

                            let detection  = MutableDamageDetection(
                                angleIndex:        selectedAngleIndex,
                                angleName:         angleName,
                                damageType:        selectedDamageType,
                                confidence:        1.0,
                                cropImage:         previewImage.flatMap { img in
                                    guard let bbox = normalizedBBox else { return normalizedImage(img) }
                                    return renderAnnotatedCrop(image: img, bbox: bbox)
                                },
                                contextImage:      previewImage.map { renderContext(image: $0, bbox: normalizedBBox) },
                                cleanContextImage: previewImage.map { normalizedImage($0) },
                                normalizedBBox:    normalizedBBox,
                                explanation:       explanation
                            )
                            onAdd(detection)
                            dismiss()
                        }
                        .bold()
                        .disabled(normalizedBBox == nil)
                    }
                }
            }
        }
    }

    // ── Step 0: Select angle + damage type ───────────────────────────────────
    private var selectStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Angle picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Image Angle")
                        .font(.headline)
                        .padding(.horizontal)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<angleNames.count, id: \.self) { idx in
                                let hasImage = idx < scanImages.count
                                VStack(spacing: 8) {
                                    ZStack {
                                        if hasImage {
                                            Image(uiImage: scanImages[idx])
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 110, height: 80)
                                                .clipped()
                                        } else {
                                            Rectangle()
                                                .fill(Color(.systemGray5))
                                                .frame(width: 110, height: 80)
                                            Text("No Image")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(selectedAngleIndex == idx ? accentColor : Color.clear, lineWidth: 2.5)
                                    )

                                    Text(angleNames[idx])
                                        .font(.caption)
                                        .foregroundColor(selectedAngleIndex == idx ? accentColor : .primary)
                                }
                                .onTapGesture {
                                    if hasImage {
                                        selectedAngleIndex = idx
                                        normalizedBBox = nil
                                    }
                                }
                                .opacity(hasImage ? 1 : 0.4)
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                // Damage type picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Damage Type")
                        .font(.headline)
                        .padding(.horizontal)

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 10
                    ) {
                        ForEach(damageTypes, id: \.self) { type in
                            Text(type.capitalized)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(selectedDamageType == type ? accentColor : Color(.secondarySystemBackground))
                                .foregroundColor(selectedDamageType == type ? .white : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .onTapGesture { selectedDamageType = type }
                        }
                    }
                    .padding(.horizontal)
                }

                // Next button
                Button {
                    step = 1
                } label: {
                    Text("Next — Draw Boundary")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedAngleIndex < scanImages.count ? accentColor : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                        .padding(.horizontal)
                }
                .disabled(selectedAngleIndex >= scanImages.count)
                .padding(.bottom, 20)
            }
            .padding(.top)
        }
    }

    // ── Step 1: Draw bounding box ─────────────────────────────────────────────
    private var drawStep: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 12) {
                    Text("Drag on the vehicle photo to draw the orange boundary around the damage.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if let img = selectedImage {
                        // Bigger full-screen canvas. The close-up preview stays below it,
                        // so users can scroll down after drawing instead of losing canvas space.
                        BoundingBoxOverlayView(
                            image: img,
                            normalizedBBox: $normalizedBBox,
                            accentColor: .orange,
                            isInteractive: true
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: max(430, geo.size.height * 0.72))
                        .background(Color.black.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)

                        HStack(spacing: 10) {
                            if normalizedBBox != nil {
                                Label("Boundary set. Drag again to replace it.", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Label("No boundary drawn yet.", systemImage: "exclamationmark.circle")
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if normalizedBBox != nil {
                                Button("Clear") { normalizedBBox = nil }
                                    .foregroundColor(.red)
                            }
                        }
                        .font(.caption)
                        .padding(.horizontal)

                        if let bbox = normalizedBBox {
                            VStack(alignment: .center, spacing: 10) {
                                Label("Close-up Preview", systemImage: "magnifyingglass")
                                    .font(.caption.bold())

                                Image(uiImage: renderAnnotatedCrop(image: img, bbox: bbox))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .frame(maxHeight: 190)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(accentColor.opacity(0.35), lineWidth: 1)
                                    )
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal)
                            .padding(.top, 8)
                        }
                    } else {
                        Text("No image available for this angle.")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /// Crop with surrounding context padding, matching renderCrop behaviour.
    private func croppedImage() -> UIImage? {
        guard let img = selectedImage, let bbox = normalizedBBox else { return selectedImage }
        return renderAnnotatedCrop(image: img, bbox: bbox)
    }
}

/// Downscales large camera images before saving annotated previews into each damage case.
/// This prevents later manual cases from turning into a blank white image because of
/// accumulated full-resolution UIImage memory. The normalized bbox still stays accurate
/// because it is stored as 0–1 coordinates.
private func resizedImageForPreview(_ image: UIImage, maxDimension: CGFloat = 1800) -> UIImage {
    let normalized = normalizedImage(image)
    let width = normalized.size.width
    let height = normalized.size.height
    let longestSide = max(width, height)

    guard longestSide > maxDimension else { return normalized }

    let scale = maxDimension / longestSide
    let newSize = CGSize(width: width * scale, height: height * scale)

    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true

    let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
    return renderer.image { _ in
        normalized.draw(in: CGRect(origin: .zero, size: newSize))
    }
}

/// Renders the full image with an orange bounding box drawn on it.
/// Used as contextImage — both for user-added cases and after the user edits a bbox.
private func renderContext(image: UIImage, bbox: CGRect?) -> UIImage {
    // Normalize first so image.size and the drawn rect are in the same coordinate space
    let img = normalizedImage(image)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true

    let renderer = UIGraphicsImageRenderer(size: img.size, format: format)
    return renderer.image { _ in
        UIColor.white.setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: img.size)).fill()
        img.draw(at: .zero)
        guard let bbox else { return }
        let rect = CGRect(
            x: bbox.minX * img.size.width,
            y: bbox.minY * img.size.height,
            width: bbox.width * img.size.width,
            height: bbox.height * img.size.height
        )
        UIColor.orange.setStroke()
        let path = UIBezierPath(rect: rect)
        path.lineWidth = max(img.size.width * 0.004, 3)
        path.stroke()
    }
}

/// Re-draws `image` into a new bitmap with `.up` orientation so that
/// `cgImage` pixel coordinates always match `image.size` coordinates.
/// We always re-render (ignoring the orientation flag) because some images
/// report `.up` but still have a transposed cgImage pixel buffer.
private func normalizedImage(_ image: UIImage) -> UIImage {
    // Force scale = 1 so UIImage.size, UIGraphics coordinates, and cgImage pixel
    // coordinates all describe the same bitmap dimensions. Without this, a 3x
    // screen renderer creates a cgImage that is 3x larger than image.size, and
    // cgImage.cropping(to:) receives the wrong coordinate system.
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1

    let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
    return renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: image.size))
    }
}

/// Calculates the pixel-space crop rect and bbox rect from a normalised bbox.
/// The crop rect is padded so the close-up still has surrounding car context.
private func cropGeometry(
    for bbox: CGRect,
    imageWidth imgW: CGFloat,
    imageHeight imgH: CGFloat,
    padding: CGFloat
) -> (cropRect: CGRect, bboxRect: CGRect) {
    let safeMinX = max(0, min(1, bbox.minX))
    let safeMinY = max(0, min(1, bbox.minY))
    let safeWidth = max(0, min(1 - safeMinX, bbox.width))
    let safeHeight = max(0, min(1 - safeMinY, bbox.height))

    let clampedBBox = CGRect(
        x: safeMinX,
        y: safeMinY,
        width: safeWidth,
        height: safeHeight
    )

    let bboxRect = CGRect(
        x: clampedBBox.minX * imgW,
        y: clampedBBox.minY * imgH,
        width: max(1, clampedBBox.width * imgW),
        height: max(1, clampedBBox.height * imgH)
    )

    let padX = bboxRect.width * padding
    let padY = bboxRect.height * padding

    let cropRect = CGRect(
        x: max(0, bboxRect.minX - padX),
        y: max(0, bboxRect.minY - padY),
        width: min(imgW, bboxRect.maxX + padX) - max(0, bboxRect.minX - padX),
        height: min(imgH, bboxRect.maxY + padY) - max(0, bboxRect.minY - padY)
    )
    .integral

    return (cropRect, bboxRect)
}

/// Crops the image to the normalised bbox, expanded by `padding` so the result
/// is a close-up of the damage spot with some surrounding context.
/// If bbox is nil the full image is returned.
private func renderCrop(image: UIImage, bbox: CGRect?, padding: CGFloat = 0.6) -> UIImage {
    guard let bbox else { return normalizedImage(image) }

    let img = normalizedImage(image)
    guard let cgImage = img.cgImage else { return img }

    let geometry = cropGeometry(
        for: bbox,
        imageWidth: CGFloat(cgImage.width),
        imageHeight: CGFloat(cgImage.height),
        padding: padding
    )

    guard let cropped = cgImage.cropping(to: geometry.cropRect) else { return img }
    return UIImage(cgImage: cropped, scale: 1, orientation: .up)
}

/// Produces the manual-case close-up as a *zoomed-in version of the vehicle
/// location image*. In other words: first draw the orange box on the full car
/// image, then crop around that same box. This guarantees the close-up matches
/// the vehicle-location image visually and keeps the orange outline visible
/// without any shaded fill.
func renderAnnotatedCrop(image: UIImage, bbox: CGRect?, padding: CGFloat = 0.55) -> UIImage {
    guard let bbox else { return normalizedImage(image) }

    let img = normalizedImage(image)
    guard let cgImage = img.cgImage else { return img }

    let geometry = cropGeometry(
        for: bbox,
        imageWidth: CGFloat(cgImage.width),
        imageHeight: CGFloat(cgImage.height),
        padding: padding
    )

    guard let croppedCG = cgImage.cropping(to: geometry.cropRect) else { return img }
    let croppedImage = UIImage(cgImage: croppedCG, scale: 1, orientation: .up)

    // Draw the orange box *after* cropping, using coordinates relative to the crop.
    // This prevents the whole close-up from becoming orange and avoids using the
    // backend's mask-filled context image as the crop source.
    let cropRect = geometry.cropRect
    let localBox = CGRect(
        x: geometry.bboxRect.minX - cropRect.minX,
        y: geometry.bboxRect.minY - cropRect.minY,
        width: geometry.bboxRect.width,
        height: geometry.bboxRect.height
    ).intersection(CGRect(origin: .zero, size: cropRect.size))

    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true

    let renderer = UIGraphicsImageRenderer(size: cropRect.size, format: format)
    return renderer.image { _ in
        UIColor.white.setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: cropRect.size)).fill()
        croppedImage.draw(in: CGRect(origin: .zero, size: cropRect.size))

        UIColor.orange.setStroke()
        let path = UIBezierPath(rect: localBox.insetBy(dx: 1.5, dy: 1.5))
        path.lineWidth = max(cropRect.width * 0.01, 3)
        path.stroke()
    }
}



/// Draws a simple orange outline on the visible image when we only have a close-up
/// image and no reliable original bounding-box coordinates. This is used as a safe
/// fallback so the preview still clearly marks the damage region without filling the
/// whole crop in orange.
private func drawOrangeOutlineOnWholeImage(_ image: UIImage) -> UIImage {
    let img = normalizedImage(image)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true

    let renderer = UIGraphicsImageRenderer(size: img.size, format: format)
    return renderer.image { _ in
        UIColor.white.setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: img.size)).fill()
        img.draw(at: .zero)

        let inset = max(min(img.size.width, img.size.height) * 0.06, 8)
        let rect = CGRect(origin: .zero, size: img.size).insetBy(dx: inset, dy: inset)
        UIColor.orange.setStroke()
        let path = UIBezierPath(roundedRect: rect, cornerRadius: max(inset * 0.35, 6))
        path.lineWidth = max(min(img.size.width, img.size.height) * 0.018, 4)
        path.stroke()
    }
}

/// Renders one combined image containing the vehicle photos with numbered orange
/// damage boxes, plus a compact summary list. This is shown before Stage 0 so the
/// user can verify the scratches/dents that will go into the final report.
private func renderDamageSummaryImage(
    plate: String,
    carType: String,
    scanImages: [UIImage],
    detections: [MutableDamageDetection]
) -> UIImage {
    let pageWidth: CGFloat = 1400
    let margin: CGFloat = 60
    let titleHeight: CGFloat = 145
    let gap: CGFloat = 28
    let panelWidth = (pageWidth - margin * 2 - gap) / 2
    let panelHeight: CGFloat = 360
    let rows = max(1, Int(ceil(Double(max(scanImages.count, 1)) / 2.0)))
    let imageGridHeight = CGFloat(rows) * panelHeight + CGFloat(max(0, rows - 1)) * gap
    let summaryRowHeight: CGFloat = 54
    let summaryHeight = max(120, CGFloat(max(detections.count, 1)) * summaryRowHeight + 86)
    let pageHeight = titleHeight + imageGridHeight + summaryHeight + margin * 2

    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true

    let renderer = UIGraphicsImageRenderer(size: CGSize(width: pageWidth, height: pageHeight), format: format)
    return renderer.image { ctx in
        UIColor.systemBackground.setFill()
        UIBezierPath(rect: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)).fill()

        let title = "Damage Summary"
        let subtitle = "\(carType) · \(plate) · \(detections.count) new damage case\(detections.count == 1 ? "" : "s")"
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 44),
            .foregroundColor: UIColor.label
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .medium),
            .foregroundColor: UIColor.secondaryLabel
        ]
        title.draw(at: CGPoint(x: margin, y: margin), withAttributes: titleAttrs)
        subtitle.draw(at: CGPoint(x: margin, y: margin + 56), withAttributes: subtitleAttrs)

        let grouped = Dictionary(grouping: Array(detections.enumerated()), by: { $0.element.angleIndex })
        let safeImages = scanImages.isEmpty ? [UIImage()] : scanImages

        for idx in 0..<safeImages.count {
            let row = idx / 2
            let col = idx % 2
            let panelX = margin + CGFloat(col) * (panelWidth + gap)
            let panelY = margin + titleHeight + CGFloat(row) * (panelHeight + gap)
            let panelRect = CGRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)

            UIColor.secondarySystemBackground.setFill()
            UIBezierPath(roundedRect: panelRect, cornerRadius: 24).fill()

            let angleTitle = idx < angleNames.count ? angleNames[idx] : "Angle \(idx + 1)"
            let angleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 22),
                .foregroundColor: UIColor.label
            ]
            angleTitle.draw(at: CGPoint(x: panelRect.minX + 20, y: panelRect.minY + 16), withAttributes: angleAttrs)

            let imageArea = panelRect.insetBy(dx: 20, dy: 56)
            if idx < scanImages.count {
                let img = normalizedImage(scanImages[idx])
                let fitted = aspectFitRect(imageSize: img.size, in: imageArea)
                img.draw(in: fitted)

                if let items = grouped[idx] {
                    for item in items {
                        let number = item.offset + 1
                        let det = item.element
                        guard let bbox = det.normalizedBBox else { continue }
                        let box = CGRect(
                            x: fitted.minX + bbox.minX * fitted.width,
                            y: fitted.minY + bbox.minY * fitted.height,
                            width: bbox.width * fitted.width,
                            height: bbox.height * fitted.height
                        ).intersection(fitted)

                        UIColor.orange.setStroke()
                        let path = UIBezierPath(rect: box)
                        path.lineWidth = 5
                        path.stroke()

                        let badgeSize: CGFloat = 34
                        let badgeRect = CGRect(
                            x: min(max(box.minX - badgeSize * 0.35, fitted.minX), fitted.maxX - badgeSize),
                            y: min(max(box.minY - badgeSize * 0.35, fitted.minY), fitted.maxY - badgeSize),
                            width: badgeSize,
                            height: badgeSize
                        )
                        UIColor.orange.setFill()
                        UIBezierPath(ovalIn: badgeRect).fill()
                        let n = "\(number)" as NSString
                        let nAttrs: [NSAttributedString.Key: Any] = [
                            .font: UIFont.boldSystemFont(ofSize: 18),
                            .foregroundColor: UIColor.white
                        ]
                        let nSize = n.size(withAttributes: nAttrs)
                        n.draw(
                            at: CGPoint(x: badgeRect.midX - nSize.width / 2, y: badgeRect.midY - nSize.height / 2),
                            withAttributes: nAttrs
                        )
                    }
                }
            } else {
                let msg = "No image" as NSString
                msg.draw(
                    at: CGPoint(x: panelRect.midX - 45, y: panelRect.midY - 10),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor.secondaryLabel]
                )
            }
        }

        let summaryY = margin + titleHeight + imageGridHeight + 38
        let summaryRect = CGRect(x: margin, y: summaryY, width: pageWidth - margin * 2, height: summaryHeight)
        UIColor.secondarySystemBackground.setFill()
        UIBezierPath(roundedRect: summaryRect, cornerRadius: 24).fill()

        let header = "Summary of new scratches and dents" as NSString
        header.draw(
            at: CGPoint(x: summaryRect.minX + 28, y: summaryRect.minY + 24),
            withAttributes: [.font: UIFont.boldSystemFont(ofSize: 26), .foregroundColor: UIColor.label]
        )

        if detections.isEmpty {
            let text = "No new damage identified against the current benchmark." as NSString
            text.draw(
                at: CGPoint(x: summaryRect.minX + 28, y: summaryRect.minY + 72),
                withAttributes: [.font: UIFont.systemFont(ofSize: 22), .foregroundColor: UIColor.secondaryLabel]
            )
        } else {
            for (idx, det) in detections.enumerated() {
                let y = summaryRect.minY + 76 + CGFloat(idx) * summaryRowHeight
                let badgeRect = CGRect(x: summaryRect.minX + 28, y: y - 4, width: 34, height: 34)
                UIColor.orange.setFill()
                UIBezierPath(ovalIn: badgeRect).fill()
                let number = "\(idx + 1)" as NSString
                let numberAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 17), .foregroundColor: UIColor.white]
                let numberSize = number.size(withAttributes: numberAttrs)
                number.draw(at: CGPoint(x: badgeRect.midX - numberSize.width / 2, y: badgeRect.midY - numberSize.height / 2), withAttributes: numberAttrs)

                let line = "\(det.damageType.capitalized) · \(det.angleName)" as NSString
                line.draw(
                    at: CGPoint(x: summaryRect.minX + 78, y: y),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: UIColor.label]
                )
            }
        }
    }
}

private func aspectFitRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
        return bounds
    }
    let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
    let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    return CGRect(
        x: bounds.midX - size.width / 2,
        y: bounds.midY - size.height / 2,
        width: size.width,
        height: size.height
    )
}

// MARK: - PDFKit Wrapper

import PDFKit

/// A SwiftUI wrapper around PDFKit's PDFView, allowing the user to scroll
/// through all pages of a PDF document inline.
struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = PDFDocument(url: url)
    }
}

// MARK: - Full Page Report Generated View

struct ReportWelcomeView: View {
    let plate: String
    let carType: CarType
    let detectionCount: Int
    let pdfURL: URL
    let reportID: String
    let reportNo: String
    let sourceChecklistID: String?
    var onLogout: () -> Void
    var onBackToActivityList: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthViewModel

    /// Controls whether we show the summary tab or the PDF preview tab.
    @State private var showingPreview = false

    var body: some View {
        NavigationStack {
            ZStack {
                SubtleHTXBackground()

                VStack(spacing: 0) {

                // ── Tab picker ───────────────────────────────────────────────
                Picker("View", selection: $showingPreview) {
                    Text("Summary").tag(false)
                    Text("Preview PDF").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)

                Divider()

                if showingPreview {
                    // ── PDF preview ──────────────────────────────────────────
                    PDFKitView(url: pdfURL)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    // ── Summary ──────────────────────────────────────────────
                    ScrollView {
                        VStack(spacing: 32) {
                            Spacer(minLength: 20)

                            Image(systemName: "doc.richtext.fill")
                                .font(.system(size: 64))
                                .foregroundColor(HTXTheme.primaryPurple)

                            VStack(spacing: 8) {
                                Text("Damage Report")
                                    .font(.largeTitle).bold()

                                Text("Vehicle: \(carType.rawValue)")
                                    .font(.headline)
                                    .foregroundColor(.secondary)

                                Text("Plate: \(plate)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            VStack(spacing: 4) {
                                Text("\(detectionCount)")
                                    .font(.system(size: 56, weight: .black))
                                    .foregroundColor(HTXTheme.primaryPurple)
                                Text(detectionCount == 1 ? "damage case recorded" : "damage cases recorded")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 20)
                            .frame(maxWidth: .infinity)
                            .background(HTXTheme.primaryPurple.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .padding(.horizontal, 40)

                            Text("Report successfully generated. Tap \"Preview PDF\" to review the full report before sharing.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)

                            if auth.isAdmin {
                                PostReportVehicleStatusView(
                                    plate: plate,
                                    carType: carType.rawValue,
                                    reportID: reportID,
                                    reportNo: reportNo,
                                    sourceChecklistID: sourceChecklistID
                                )
                                .padding(.horizontal, 40)
                            }

                            Spacer(minLength: 20)

                            VStack(spacing: 14) {

                                // Preview PDF shortcut
                                Button {
                                    showingPreview = true
                                } label: {
                                    HStack {
                                        Image(systemName: "doc.text.magnifyingglass")
                                        Text("Preview PDF")
                                    }
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(HTXTheme.primaryPurple.opacity(0.12))
                                    .foregroundColor(HTXTheme.primaryPurple)
                                    .cornerRadius(14)
                                }

                                // Share button
                                Button {
                                    sharePDF(url: pdfURL)
                                } label: {
                                    HStack {
                                        Image(systemName: "square.and.arrow.up")
                                        Text("Share PDF Report")
                                    }
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(HTXTheme.primaryPurple)
                                    .foregroundColor(.white)
                                    .cornerRadius(14)
                                }

                                Button {
                                    onBackToActivityList()
                                } label: {
                                    HStack {
                                        Image(systemName: "list.bullet.rectangle")
                                        Text("Back to Activity List")
                                    }
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(HTXTheme.primaryPurple.opacity(0.12))
                                    .foregroundColor(HTXTheme.primaryPurple)
                                    .cornerRadius(14)
                                }

                                Button {
                                    onLogout()
                                } label: {
                                    Text("Logout")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.red)
                                        .foregroundColor(.white)
                                        .cornerRadius(14)
                                }
                            }
                            .padding(.horizontal, 40)
                            .padding(.bottom, 40)
                            .padding(.top, 10)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showingPreview {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            sharePDF(url: pdfURL)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .tint(HTXTheme.primaryPurple)
            .navigationBarBackButtonHidden(true)
            .interactiveDismissDisabled(true)
        }
    }

    /// Presents the system share sheet by finding the root view controller and
    /// calling present() directly — this bypasses the SwiftUI .sheet nesting
    /// issue that causes a blank white screen on iPad.
    private func sharePDF(url: URL) {
        let activity = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )

        // iPad requires a source rect for the popover anchor
        if let popover = activity.popoverPresentationController {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
            let window = scene?.windows.first
            popover.sourceView = window
            if let window {
                popover.sourceRect = CGRect(
                    x: window.bounds.midX,
                    y: window.bounds.midY,
                    width: 0,
                    height: 0
                )
            }
            popover.permittedArrowDirections = []
        }

        // Walk up to the topmost presented view controller and present from there
        var topVC = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController

        while let presented = topVC?.presentedViewController {
            topVC = presented
        }

        topVC?.present(activity, animated: true)
    }
}


// MARK: - Police Report Details Flow


// MARK: - Police Station Selection

struct PoliceStationDetails: Identifiable, Hashable {
    let division: String
    let name: String
    let address: String
    let postalCode: String
    let telephone: String

    var id: String { "\(division)-\(name)" }
    var displayName: String { "\(name) N.P.C" }
    var pdfHeaderText: String {
        let telLine = telephone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Tel No:" : "Tel No: \(telephone)"
        return "Police Station Of Origin\n\(displayName)\n\(address) SINGAPORE\n\(postalCode)\n\(telLine)"
    }

    static let defaultStation = PoliceStationDetails(
        division: "Ang Mo Kio Division",
        name: "Ang Mo Kio North",
        address: "51 Ang Mo Kio Avenue 9",
        postalCode: "569784",
        telephone: "1800 484 9999"
    )

    static let all: [PoliceStationDetails] = [
        PoliceStationDetails(division: "Central Division", name: "Bukit Merah East", address: "391 New Bridge Road", postalCode: "088762", telephone: "6236 9999"),
        PoliceStationDetails(division: "Central Division", name: "Marina Bay", address: "6 Bayfront Link", postalCode: "018962", telephone: "1800 222 9999"),
        PoliceStationDetails(division: "Central Division", name: "Rochor", address: "101 Kampong Java Road", postalCode: "228866", telephone: "1800 294 9999"),
        PoliceStationDetails(division: "Tanglin Division", name: "Kampong Java", address: "21 Kampong Java Road", postalCode: "228892", telephone: "6295 9999"),
        PoliceStationDetails(division: "Tanglin Division", name: "Bishan", address: "20 Bishan Street 23", postalCode: "579757", telephone: "1800 552 9999"),
        PoliceStationDetails(division: "Tanglin Division", name: "Orchard", address: "51 Killiney Road", postalCode: "228201", telephone: "1800 735 9999"),
        PoliceStationDetails(division: "Tanglin Division", name: "Toa Payoh", address: "95 Toa Payoh Central, #01-02 Community Building", postalCode: "319194", telephone: "1800 251 9999"),
        PoliceStationDetails(division: "Clementi Division", name: "Bukit Merah West", address: "500 Bukit Merah View #01-01", postalCode: "159682", telephone: "1800 377 9999"),
        PoliceStationDetails(division: "Clementi Division", name: "Clementi", address: "6 Lempeng Drive", postalCode: "128496", telephone: "1800 872 9999"),
        PoliceStationDetails(division: "Clementi Division", name: "Jurong East", address: "92 Boon Lay Way", postalCode: "609962", telephone: "1800 899 9999"),
        PoliceStationDetails(division: "Clementi Division", name: "Queenstown", address: "3 Queensway #01-03", postalCode: "149073", telephone: "1800 471 9999"),
        PoliceStationDetails(division: "Bedok Division", name: "Bedok", address: "30 Bedok North Road", postalCode: "469676", telephone: "1800 244 9999"),
        PoliceStationDetails(division: "Bedok Division", name: "Changi", address: "9 Simei Street 2", postalCode: "529914", telephone: "1800 587 2999"),
        PoliceStationDetails(division: "Bedok Division", name: "Geylang", address: "1 Cassia Link", postalCode: "397618", telephone: "1800 848 6999"),
        PoliceStationDetails(division: "Bedok Division", name: "Marine Parade", address: "300 Marine Parade Road", postalCode: "449296", telephone: "1800 442 8999"),
        PoliceStationDetails(division: "Bedok Division", name: "Pasir Ris", address: "1 Pasir Ris Drive 4", postalCode: "519457", telephone: "6585 2999"),
        PoliceStationDetails(division: "Bedok Division", name: "Tampines", address: "6 Tampines Avenue 4", postalCode: "529682", telephone: "1800 587 1999"),
        PoliceStationDetails(division: "Ang Mo Kio Division", name: "Ang Mo Kio North", address: "51 Ang Mo Kio Avenue 9", postalCode: "569784", telephone: "1800 484 9999"),
        PoliceStationDetails(division: "Ang Mo Kio Division", name: "Ang Mo Kio South", address: "81 Ang Mo Kio Avenue 3", postalCode: "569929", telephone: "1800 451 9999"),
        PoliceStationDetails(division: "Ang Mo Kio Division", name: "Hougang", address: "60 Hougang Avenue 9", postalCode: "538775", telephone: "6489 0999"),
        PoliceStationDetails(division: "Ang Mo Kio Division", name: "Punggol", address: "151 Punggol Central", postalCode: "828727", telephone: "1800 604 9999"),
        PoliceStationDetails(division: "Ang Mo Kio Division", name: "Sengkang", address: "2 Sengkang Square, #01-02", postalCode: "545025", telephone: ""),
        PoliceStationDetails(division: "Ang Mo Kio Division", name: "Serangoon", address: "50 Serangoon Avenue 2 #01-02", postalCode: "556129", telephone: "1800 488 0999"),
        PoliceStationDetails(division: "Ang Mo Kio Division", name: "Woodleigh", address: "501 Upper Aljunied Road", postalCode: "367897", telephone: ""),
        PoliceStationDetails(division: "Jurong Division", name: "Bukit Batok", address: "21 Bukit Batok East Avenue 4", postalCode: "659840", telephone: "1800 665 9999"),
        PoliceStationDetails(division: "Jurong Division", name: "Choa Chu Kang", address: "20 Choa Chu Kang Street 52, #01-02", postalCode: "689286", telephone: "1800 755 9999"),
        PoliceStationDetails(division: "Jurong Division", name: "Jurong West", address: "2 Jurong West Avenue 5", postalCode: "649482", telephone: "1800 792 9999"),
        PoliceStationDetails(division: "Jurong Division", name: "Nanyang", address: "2 Jurong West Avenue 5", postalCode: "649482", telephone: "6792 9999"),
        PoliceStationDetails(division: "Woodlands Police Division", name: "Sembawang", address: "4 Sembawang Crescent", postalCode: "757633", telephone: "1800 554 9999"),
        PoliceStationDetails(division: "Woodlands Police Division", name: "Woodlands East", address: "3 Woodlands Drive 63", postalCode: "737890", telephone: "1800 767 9999"),
        PoliceStationDetails(division: "Woodlands Police Division", name: "Woodlands West", address: "1 Woodlands Street 12", postalCode: "738619", telephone: ""),
        PoliceStationDetails(division: "Woodlands Police Division", name: "Yishun", address: "31 Yishun Central", postalCode: "768827", telephone: "1800 852 9999")
    ]

    static var groupedByDivision: [(String, [PoliceStationDetails])] {
        let order = ["Central Division", "Tanglin Division", "Clementi Division", "Bedok Division", "Ang Mo Kio Division", "Jurong Division", "Woodlands Police Division"]
        return order.compactMap { division in
            let stations = all.filter { $0.division == division }
            return stations.isEmpty ? nil : (division, stations)
        }
    }
}

struct PoliceReportStageZeroView: View {
    let plate: String
    let carType: CarType
    let detections: [MutableDamageDetection]
    let scanImages: [UIImage]
    var onLogout: () -> Void

    @Binding var isGeneratingReport: Bool
    @Binding var pdfURL: URL?
    @Binding var isPresented: Bool

    @State private var selectedStation = PoliceStationDetails.defaultStation
    @State private var useOtherStation = false
    @State private var customDivision = ""
    @State private var customAddress = ""
    @State private var customPostalCode = ""
    @State private var customTelephone = ""
    @State private var showStageOne = false
    @State private var showStationValidationError = false
    @State private var expandedDivisions: Set<String> = [PoliceStationDetails.defaultStation.division]
    @Environment(\.dismiss) private var dismiss

    private var stationForReport: PoliceStationDetails {
        if useOtherStation {
            return PoliceStationDetails(
                division: customDivision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Other" : customDivision,
                name: "Other",
                address: customAddress,
                postalCode: customPostalCode,
                telephone: customTelephone
            )
        }
        return selectedStation
    }

    private var stationValidationIssues: [String] {
        guard useOtherStation else { return [] }
        var issues: [String] = []
        if customDivision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("Division") }
        if customAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("Location") }
        if customPostalCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("Postal Code") }
        return issues
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Police Station of Origin") {
                    ForEach(PoliceStationDetails.groupedByDivision, id: \.0) { division, stations in
                        let isDivisionSelected = !useOtherStation && selectedStation.division == division
                        let isExpanded = expandedDivisions.contains(division)

                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                if isExpanded {
                                    expandedDivisions.remove(division)
                                } else {
                                    expandedDivisions.insert(division)
                                }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Text(division)
                                    .font(.headline.weight(.semibold))
                                    .foregroundColor(isDivisionSelected ? HTXTheme.primaryPurple : .primary)

                                if isDivisionSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(HTXTheme.primaryPurple)
                                }

                                Spacer()

                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(isDivisionSelected ? HTXTheme.primaryPurple : .secondary)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(isDivisionSelected ? HTXTheme.primaryPurple.opacity(0.12) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color(.systemBackground).opacity(0.86))

                        if isExpanded {
                            ForEach(stations) { station in
                                let isSelected = selectedStation.id == station.id && !useOtherStation

                                Button {
                                    selectedStation = station
                                    useOtherStation = false
                                    expandedDivisions.insert(division)
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(isSelected ? HTXTheme.primaryPurple : .secondary)
                                            .font(.system(size: 18, weight: .semibold))

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(station.displayName)
                                                .font(.subheadline.bold())
                                                .foregroundColor(.primary)
                                            Text("\(station.address), Singapore \(station.postalCode)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(station.telephone.isEmpty ? "Tel:" : "Tel: \(station.telephone)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(isSelected ? HTXTheme.primaryPurple.opacity(0.12) : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color(.systemBackground).opacity(0.86))
                            }
                        }
                    }
                }

                Section("Other Station") {
                    Toggle("Use other / manual NPC", isOn: $useOtherStation)
                    if useOtherStation {
                        Text("* Required field")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.red)
                        reportTextField("Division", text: $customDivision, placeholder: "Enter division", required: true)
                        reportTextField("Location", text: $customAddress, placeholder: "Enter station location", axis: .vertical, required: true)
                        reportTextField("Postal Code", text: $customPostalCode, placeholder: "Enter postal code", required: true)
                            .keyboardType(.numberPad)
                        reportTextField("Telephone", text: $customTelephone, placeholder: "Enter telephone, if any")
                            .keyboardType(.phonePad)
                    }
                }

                Section("Selected Station") {
                    let station = stationForReport
                    VStack(alignment: .leading, spacing: 6) {
                        Text(station.displayName).font(.headline)
                        Text(station.division).font(.subheadline).foregroundColor(.secondary)
                        Text(station.address)
                        Text("Singapore \(station.postalCode)")
                        Text(station.telephone.isEmpty ? "Tel:" : "Tel: \(station.telephone)")
                    }
                }

                Section {
                    if showStationValidationError, !stationValidationIssues.isEmpty {
                        validationSummary(stationValidationIssues)
                    }

                    Button {
                        if stationValidationIssues.isEmpty {
                            showStationValidationError = false
                            showStageOne = true
                        } else {
                            showStationValidationError = true
                        }
                    } label: {
                        Text("Proceed to Stage 1")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HTXTheme.primaryPurple)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }
            }
            .navigationTitle("Report Stage 0")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(SubtleHTXBackground())
            .tint(HTXTheme.primaryPurple)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showStageOne) {
                PoliceReportStageOneView(
                    plate: plate,
                    carType: carType,
                    detections: detections,
                    scanImages: scanImages,
                    policeStation: stationForReport,
                    onLogout: onLogout,
                    isGeneratingReport: $isGeneratingReport,
                    pdfURL: $pdfURL,
                    isPresented: $isPresented
                )
            }
        }
    }

    @ViewBuilder
    private func reportTextField(
        _ title: String,
        text: Binding<String>,
        placeholder: String,
        axis: Axis = .horizontal,
        required: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HTXFieldLabel(
                text: title,
                required: required,
                color: HTXTheme.primaryPurple,
                font: .caption.weight(.semibold)
            )
            TextField(placeholder, text: text, axis: axis)
                .lineLimit(axis == .vertical ? 2...4 : 1...1)
        }
    }

    private func validationSummary(_ issues: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Please complete:")
                .font(.footnote.weight(.semibold))
            ForEach(issues, id: \.self) { issue in
                Label(issue, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
            }
        }
        .foregroundColor(.red)
        .padding(.vertical, 4)
    }
}

struct PoliceReportStageOneDetails {
    var stationDiaryNo = ""
    var videReportNo = ""
    var nameOfInformant = ""
    var address = ""
    var idTypeAndNo = ""
    var finNo = ""
    var contactType = "Home"
    var contactNumber = ""
    var emailAddress = ""
    var nationality = ""
    var occupation = ""
    var sex = ""
    var age = ""
    var dateOfBirth = ""
    var race = ""
    var language = ""
    var dateTimeOfIncident = ""
    var locationOfIncident = ""
    var institutionSchoolName = ""

    // Backward-compatible values for older generator references.
    var homeOfficeNo: String { contactType == "Home" || contactType == "Office" ? contactNumber : "" }
    var mobileNo: String { "" }
}

struct PoliceReportStageTwoDetails {
    var officerRecordingName = ""
    var officerSignature: UIImage? = nil
    var interpreterAvailability = ""
    var interpreterSignature: UIImage? = nil
    var interpreterSignatureDateTime = ""
    var informantName = ""
    var informantSignature: UIImage? = nil
    var informantSignatureDateTime = ""
    var officerInCharge = ""
    var classificationOfCase = ""
}

struct PoliceReportStageOneView: View {
    let plate: String
    let carType: CarType
    let detections: [MutableDamageDetection]
    let scanImages: [UIImage]
    let policeStation: PoliceStationDetails
    var onLogout: () -> Void

    @Binding var isGeneratingReport: Bool
    @Binding var pdfURL: URL?
    @Binding var isPresented: Bool

    @State private var details = PoliceReportStageOneDetails()
    @State private var dateOfBirthValue = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var incidentDateTimeValue = Date()
    @State private var showStageTwo = false
    @State private var showRequiredFieldErrors = false
    @State private var expandedDropdown: DropdownField? = nil
    @State private var didApplyEscalationPrefill = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.htxNP299EscalationContext) private var escalationContext

    private let sexOptions = ["", "Male", "Female", "Prefer not to say"]
    private let raceOptions = ["", "Chinese", "Malay", "Indian", "Other"]
    private let contactOptions = ["Home", "Office"]
    
    @FocusState private var focusedField: Field?

    enum Field {
        case id
        case fin
        case contact
        case email
        case age
    }

    enum DropdownField {
        case sex
        case race
    }

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.endEditing()
    }

    // MARK: - Validators

    private func isValidNRIC(_ value: String) -> Bool {
        let regex = "^[ST]\\d{7}[A-Z]$"
        return NSPredicate(format: "SELF MATCHES %@", regex)
            .evaluate(with: value.uppercased())
    }

    private func isValidFIN(_ value: String) -> Bool {
        let regex = "^[FGM]\\d{7}[A-Z]$"
        return NSPredicate(format: "SELF MATCHES %@", regex)
            .evaluate(with: value.uppercased())
    }

    private func isValidSingaporePhone(_ value: String) -> Bool {
        let regex = "^[689]\\d{7}$"
        return NSPredicate(format: "SELF MATCHES %@", regex)
            .evaluate(with: value)
    }

    private func isValidEmail(_ value: String) -> Bool {
        let regex = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return NSPredicate(format: "SELF MATCHES %@", regex)
            .evaluate(with: value)
    }

    private var isNRICValid: Bool {
        let trimmed = details.idTypeAndNo
            .replacingOccurrences(of: "NRIC /", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmed.isEmpty || isValidNRIC(trimmed)
    }

    private var isFINValid: Bool {
        let trimmed = details.finNo.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || isValidFIN(trimmed)
    }

    private var isPhoneValid: Bool {
        let trimmed = details.contactNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || isValidSingaporePhone(trimmed)
    }

    private var isEmailValid: Bool {
        let trimmed = details.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || isValidEmail(trimmed)
    }

    private var isAgeTwoDigits: Bool {
        let trimmed = details.age.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= 2
    }

    private var isAgeValid: Bool {
        let trimmed = details.age.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return Int(trimmed) != nil && Int(trimmed)! >= 0 && Int(trimmed)! <= 130
    }

    private var isDOBValid: Bool {
        isBlank(details.dateOfBirth) || isValidDate(details.dateOfBirth, formats: ["dd/MM/yyyy"])
    }

    private var isIncidentDateTimeValid: Bool {
        isBlank(details.dateTimeOfIncident) || isValidDate(details.dateTimeOfIncident, formats: ["d MMMM yyyy, HH:mm", "dd MMMM yyyy, HH:mm"])
    }

    private var validationIssues: [String] {
        var issues: [String] = []
        if isBlank(details.nameOfInformant) { issues.append("Name of Informant") }
        if isBlank(details.address) { issues.append("Address") }
        if isBlank(details.contactNumber) { issues.append("Contact Number") }
        if isBlank(details.nationality) { issues.append("Nationality") }
        if isBlank(details.sex) { issues.append("Sex") }
        if isBlank(details.age) { issues.append("Age") }
        if isBlank(details.race) { issues.append("Race") }
        if isBlank(details.language) { issues.append("Language") }
        if isBlank(details.locationOfIncident) { issues.append("Location of Incident") }
        if !isNRICValid { issues.append("ID Type / ID No. has an invalid NRIC format") }
        if !isFINValid { issues.append("FIN No. has an invalid format") }
        if !isPhoneValid { issues.append("Contact Number must be 8 digits beginning with 6, 8, or 9") }
        if !isEmailValid { issues.append("Email Address has an invalid format") }
        if !isAgeValid || !isAgeTwoDigits { issues.append("Age must contain one or two valid digits") }
        if !isDOBValid { issues.append("Date of Birth is invalid") }
        if !isIncidentDateTimeValid { issues.append("Date/Time of Incident is invalid") }
        return issues.reduce(into: [String]()) { unique, issue in
            if !unique.contains(issue) { unique.append(issue) }
        }
    }

    var body: some View {
        Form {
            Section("Incident Details") {
                    Text("* Required field")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.red)

                    reportTextField(
                        "Station Diary No.",
                        text: $details.stationDiaryNo,
                        placeholder: "Auto: D/yyyymmdd/1234",
                        required: true
                    )
                    reportTextField("Vide Report No.", text: $details.videReportNo, placeholder: "Leave blank if not available")
                    reportTextField("Name of Informant", text: $details.nameOfInformant, placeholder: "Enter full name", required: true)
                    reportTextField("Address", text: $details.address, placeholder: "Enter address", axis: .vertical, required: true)
                    VStack(alignment: .leading, spacing: 6) {

                        reportTextField(
                            "ID Type / ID No.",
                            text: $details.idTypeAndNo,
                            placeholder: "e.g. NRIC / S1234567A"
                        )
                        .focused($focusedField, equals: .id)
                        .textInputAutocapitalization(.characters)
                        .onChange(of: details.idTypeAndNo) { _, newValue in
                            details.idTypeAndNo = newValue.uppercased()
                        }

                        if !isNRICValid {
                            validationText("Invalid NRIC format. Example: S1234567A")
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {

                        reportTextField(
                            "FIN NO /",
                            text: $details.finNo,
                            placeholder: "Example: F1234567N"
                        )
                        .focused($focusedField, equals: .fin)
                        .textInputAutocapitalization(.characters)
                        .onChange(of: details.finNo) { _, newValue in
                            details.finNo = newValue.uppercased()
                        }

                        if !isFINValid {
                            validationText("Invalid FIN format.")
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HTXFieldLabel(text: "Contact No.", required: true, color: .secondary, font: .caption)
                        Picker("Contact Type", selection: $details.contactType) {
                            ForEach(contactOptions, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .simultaneousGesture(TapGesture().onEnded {
                            dismissKeyboard()
                        })
                        TextField(
                            "Enter \(details.contactType.lowercased()) number",
                            text: $details.contactNumber
                        )
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .contact)
                        .onChange(of: details.contactNumber) { _, newValue in

                            details.contactNumber = String(
                                newValue.filter(\.isNumber).prefix(8)
                            )

                            if details.contactNumber.count == 8 {
                                UIApplication.shared.endEditing()
                            }
                        }

                        if !isPhoneValid {
                            validationText("Must be 8 digits starting with 6, 8, or 9.")
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {

                        reportTextField(
                            "Email Address",
                            text: $details.emailAddress,
                            placeholder: "name@example.com"
                        )
                        .keyboardType(.emailAddress)
                        .focused($focusedField, equals: .email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        if !isEmailValid {
                            validationText("Invalid email address.")
                        }
                    }
                    reportTextField("Nationality", text: $details.nationality, placeholder: "Enter nationality", required: true)
                    reportTextField("Occupation", text: $details.occupation, placeholder: "Enter occupation")

                    dropdownField(
                        "Sex",
                        selection: $details.sex,
                        options: sexOptions,
                        emptyTitle: "Select sex",
                        field: .sex,
                        required: true
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        reportTextField(
                            "Age",
                            text: $details.age,
                            placeholder: "Enter age",
                            required: true
                        )
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .age)
                        .onChange(of: details.age) { _, newValue in

                            details.age = String(
                                newValue.filter(\.isNumber).prefix(2)
                            )

                            if details.age.count == 2 {
                                UIApplication.shared.endEditing()
                            }
                        }

                        if !isAgeValid {
                            validationText("Age must be valid.")
                        }

                        if !isAgeTwoDigits {
                            validationText("Age must be 2 digits only.")
                        }
                    }
                    dateOnlyPickerField(
                        "Date of Birth",
                        date: $dateOfBirthValue,
                        output: $details.dateOfBirth,
                        required: true
                    )

                    dropdownField(
                        "Race",
                        selection: $details.race,
                        options: raceOptions,
                        emptyTitle: "Select race",
                        field: .race,
                        required: true
                    )
                    reportTextField("Institution/School Name", text: $details.institutionSchoolName, placeholder: "Enter institution/school, if any")
                    reportTextField("Language", text: $details.language, placeholder: "Enter language", required: true)
                    dateTimePickerField(
                        "Date/Time of Incident",
                        date: $incidentDateTimeValue,
                        output: $details.dateTimeOfIncident,
                        required: true
                    )
                    reportTextField("Location of Incident", text: $details.locationOfIncident, placeholder: "Enter location", axis: .vertical, required: true)
                }

                Section {
                    if showRequiredFieldErrors, !validationIssues.isEmpty {
                        validationSummary(validationIssues)
                    }

                    Button {
                        if isBlank(details.stationDiaryNo) {
                            details.stationDiaryNo = PoliceReportFormFormatter.stationDiaryNumber()
                        }
                        details.dateOfBirth = PoliceReportFormFormatter.dobDisplay(from: dateOfBirthValue)
                        details.dateTimeOfIncident = PoliceReportFormFormatter.reportDateTimeDisplay(from: incidentDateTimeValue)
                        if validationIssues.isEmpty {
                            showRequiredFieldErrors = false
                            showStageTwo = true
                        } else {
                            showRequiredFieldErrors = true
                        }
                    } label: {
                        Text("Proceed to Stage 2")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HTXTheme.primaryPurple)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }
            }
            .navigationTitle("Report Stage 1")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(SubtleHTXBackground())
            .tint(HTXTheme.primaryPurple)
            .navigationDestination(isPresented: $showStageTwo) {
                PoliceReportStageTwoView(
                    plate: plate,
                    carType: carType,
                    detections: detections,
                    scanImages: scanImages,
                    policeStation: policeStation,
                    stageOne: details,
                    onLogout: onLogout,
                    isGeneratingReport: $isGeneratingReport,
                    pdfURL: $pdfURL,
                    isPresented: $isPresented
                )
            }
            .onAppear(perform: applyInitialValues)
    }

    private func applyInitialValues() {
        if details.stationDiaryNo.isEmpty {
            details.stationDiaryNo = PoliceReportFormFormatter.stationDiaryNumber()
        }

        guard !didApplyEscalationPrefill, let escalationContext else { return }
        didApplyEscalationPrefill = true

        if details.nameOfInformant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            details.nameOfInformant = escalationContext.informantName
        }

        if details.contactNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !escalationContext.workContact.isEmpty {
            details.contactType = "Office"
            details.contactNumber = escalationContext.workContact
        }

        if let incidentDate = escalationContext.incidentDate {
            incidentDateTimeValue = incidentDate
            details.dateTimeOfIncident = PoliceReportFormFormatter.reportDateTimeDisplay(from: incidentDate)
        }
    }

    @ViewBuilder
    private func reportTextField(
        _ title: String,
        text: Binding<String>,
        placeholder: String,
        axis: Axis = .horizontal,
        required: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HTXFieldLabel(
                text: title,
                required: required,
                color: HTXTheme.primaryPurple,
                font: .caption.weight(.semibold)
            )
            TextField(placeholder, text: text, axis: axis)
                .lineLimit(axis == .vertical ? 2...4 : 1...1)
        }
    }

    @ViewBuilder
    private func dropdownField(
        _ title: String,
        selection: Binding<String>,
        options: [String],
        emptyTitle: String,
        field: DropdownField,
        required: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HTXFieldLabel(
                text: title,
                required: required,
                color: HTXTheme.primaryPurple,
                font: .caption.weight(.semibold)
            )

            Button {
                dismissKeyboard()

                withAnimation(.easeInOut(duration: 0.18)) {
                    expandedDropdown = expandedDropdown == field ? nil : field
                }
            } label: {
                HStack {
                    Text(selection.wrappedValue.isEmpty ? emptyTitle : selection.wrappedValue)
                        .foregroundColor(selection.wrappedValue.isEmpty ? .secondary : .primary)

                    Spacer()

                    Image(systemName: expandedDropdown == field ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            if expandedDropdown == field {
                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Button {
                            dismissKeyboard()
                            selection.wrappedValue = option

                            withAnimation(.easeInOut(duration: 0.18)) {
                                expandedDropdown = nil
                            }
                        } label: {
                            HStack {
                                Text(option.isEmpty ? emptyTitle : option)
                                    .foregroundColor(option.isEmpty ? .secondary : .primary)

                                Spacer()

                                if selection.wrappedValue == option {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(HTXTheme.primaryPurple)
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < options.count - 1 {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.separator), lineWidth: 0.5)
                )
            }
        }
    }

    @ViewBuilder
    private func dateOnlyPickerField(
        _ title: String,
        date: Binding<Date>,
        output: Binding<String>,
        required: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HTXFieldLabel(
                text: title,
                required: required,
                color: HTXTheme.primaryPurple,
                font: .caption.weight(.semibold)
            )
            DatePicker("", selection: date, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .simultaneousGesture(TapGesture().onEnded {
                    dismissKeyboard()
                })
                .onAppear { output.wrappedValue = PoliceReportFormFormatter.dobDisplay(from: date.wrappedValue) }
                .onChange(of: date.wrappedValue) { _, newDate in
                    output.wrappedValue = PoliceReportFormFormatter.dobDisplay(from: newDate)
                }
            Text(output.wrappedValue.isEmpty ? "DD/MM/YYYY" : output.wrappedValue)
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func dateTimePickerField(
        _ title: String,
        date: Binding<Date>,
        output: Binding<String>,
        required: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HTXFieldLabel(
                text: title,
                required: required,
                color: HTXTheme.primaryPurple,
                font: .caption.weight(.semibold)
            )
            DatePicker("", selection: date, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.wheel)
                .labelsHidden()
                .simultaneousGesture(TapGesture().onEnded {
                    dismissKeyboard()
                })
                .environment(\.locale, Locale(identifier: "en_GB"))
                .onAppear { output.wrappedValue = PoliceReportFormFormatter.reportDateTimeDisplay(from: date.wrappedValue) }
                .onChange(of: date.wrappedValue) { _, newDate in
                    output.wrappedValue = PoliceReportFormFormatter.reportDateTimeDisplay(from: newDate)
                }
            Text(output.wrappedValue.isEmpty ? "Day Month Year, HH:mm" : output.wrappedValue)
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
    }

    private func validationText(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundColor(.red)
    }

    private func validationSummary(_ issues: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Please complete or correct:")
                .font(.footnote.weight(.semibold))
            ForEach(issues, id: \.self) { issue in
                Label(issue, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
            }
        }
        .foregroundColor(.red)
        .padding(.vertical, 4)
    }

    private func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isValidDate(_ value: String, formats: [String]) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return formats.contains { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            formatter.isLenient = false
            return formatter.date(from: trimmed) != nil
        }
    }
}

struct PoliceReportStageTwoView: View {
    let plate: String
    let carType: CarType
    let detections: [MutableDamageDetection]
    let scanImages: [UIImage]
    let policeStation: PoliceStationDetails
    let stageOne: PoliceReportStageOneDetails
    var onLogout: () -> Void

    @Binding var isGeneratingReport: Bool
    @Binding var pdfURL: URL?
    @Binding var isPresented: Bool

    @Environment(\.htxNP299EscalationContext) private var escalationContext

    @State private var details = PoliceReportStageTwoDetails()
    @State private var officerSignatureTrigger = UUID()
    @State private var interpreterSignatureTrigger = UUID()
    @State private var informantSignatureTrigger = UUID()
    @State private var interpreterDateTimeValue = Date()
    @State private var informantDateTimeValue = Date()
    @State private var officerSignatureImage: UIImage? = nil
    @State private var interpreterSignatureImage: UIImage? = nil
    @State private var informantSignatureImage: UIImage? = nil
    @State private var showReportReview = false
    @State private var showRequiredFieldErrors = false
    @State private var generatedReportID = ""
    @State private var generatedReportNo = ""
    @State private var reportGenerationError: String? = nil

    private var validationIssues: [String] {
        var issues: [String] = []
        if details.officerRecordingName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Name of Officer Recording the Report")
        }
        if officerSignatureImage == nil { issues.append("Signature of Officer Recording the Report") }
        let informantName = details.informantName.trimmingCharacters(in: .whitespacesAndNewlines)
        if informantName.isEmpty && stageOne.nameOfInformant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Name of Informant")
        }
        if informantSignatureImage == nil { issues.append("Signature of Informant") }
        if details.officerInCharge.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Name of Officer In-Charge of Case")
        }
        if details.classificationOfCase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Classification of Case")
        }
        return issues
    }

    var body: some View {
        Form {
            Section("Officer") {
                Text("* Required field")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.red)

                reportTextField("Name of officer recording the report", text: $details.officerRecordingName, placeholder: "Enter officer name", required: true)

                signatureInput(
                    title: "Signature of Officer Recording the Report",
                    image: $officerSignatureImage,
                    clearTrigger: $officerSignatureTrigger,
                    clearTitle: "Clear Officer Signature",
                    required: true
                )
            }

            Section("Interpreter") {
                reportTextField("Name of Interpreter", text: $details.interpreterAvailability, placeholder: "Enter interpreter name")

                signatureInput(
                    title: "Signature of Interpreter",
                    image: $interpreterSignatureImage,
                    clearTrigger: $interpreterSignatureTrigger,
                    clearTitle: "Clear Interpreter Signature"
                )
                dateTimePickerField("Date/Time", date: $interpreterDateTimeValue, output: $details.interpreterSignatureDateTime)
            }

            Section("Informant") {
                reportTextField("Name of Informant", text: $details.informantName, placeholder: stageOne.nameOfInformant.isEmpty ? "Enter informant name" : stageOne.nameOfInformant, required: true)
                signatureInput(
                    title: "Signature of Informant",
                    image: $informantSignatureImage,
                    clearTrigger: $informantSignatureTrigger,
                    clearTitle: "Clear Informant Signature",
                    required: true
                )

                dateTimePickerField("Date/Time", date: $informantDateTimeValue, output: $details.informantSignatureDateTime)
            }

            Section("Case") {
                reportTextField("Name of Officer In-Charge of Case", text: $details.officerInCharge, placeholder: "Enter officer-in-charge", required: true)
                reportTextField("Classification of Case", text: $details.classificationOfCase, placeholder: "Enter classification", axis: .vertical, required: true)
            }

            Section {
                if showRequiredFieldErrors, !validationIssues.isEmpty {
                    validationSummary(validationIssues)
                }

                Button {
                    if validationIssues.isEmpty {
                        showRequiredFieldErrors = false
                        showReportReview = true
                    } else {
                        showRequiredFieldErrors = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                        Text("Confirm Report Details")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(HTXTheme.primaryPurple)
                .disabled(isGeneratingReport)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
        }
        .navigationTitle("Report Stage 2")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(SubtleHTXBackground())
        .tint(HTXTheme.primaryPurple)
        .navigationDestination(isPresented: $showReportReview) {
            PoliceReportReviewView(
                plate: plate,
                carType: carType,
                detections: detections,
                policeStation: policeStation,
                stageOne: stageOne,
                stageTwo: finalizedStageTwoDetails(),
                isGeneratingReport: isGeneratingReport,
                onGenerate: { generateReport() }
            )
        }
        .fullScreenCover(item: $pdfURL) { url in
            ReportWelcomeView(
                plate: plate,
                carType: carType,
                detectionCount: detections.filter { !$0.isBaseline }.count,
                pdfURL: url,
                reportID: generatedReportID,
                reportNo: generatedReportNo,
                sourceChecklistID: escalationContext?.checklistID,
                onLogout: {
                    pdfURL = nil
                    isPresented = false

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        onLogout()
                    }
                },
                onBackToActivityList: {
                    pdfURL = nil
                    isPresented = false

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        HTXNavigationHelper.popToActivityList()
                    }
                }
            )
        }
        .alert(
            "Report Not Generated",
            isPresented: Binding(
                get: { reportGenerationError != nil },
                set: { if !$0 { reportGenerationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { reportGenerationError = nil }
        } message: {
            Text(reportGenerationError ?? "The report could not be completed.")
        }
    }

    @ViewBuilder
    private func reportTextField(
        _ title: String,
        text: Binding<String>,
        placeholder: String,
        axis: Axis = .horizontal,
        required: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HTXFieldLabel(
                text: title,
                required: required,
                color: HTXTheme.primaryPurple,
                font: .caption.weight(.semibold)
            )
            TextField(placeholder, text: text, axis: axis)
                .lineLimit(axis == .vertical ? 2...4 : 1...1)
        }
    }

    @ViewBuilder
    private func dateTimePickerField(
        _ title: String,
        date: Binding<Date>,
        output: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundColor(HTXTheme.primaryPurple)
            DatePicker("", selection: date, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "en_GB"))
                .onAppear { output.wrappedValue = PoliceReportFormFormatter.reportDateTimeDisplay(from: date.wrappedValue) }
                .onChange(of: date.wrappedValue) { _, newDate in
                    output.wrappedValue = PoliceReportFormFormatter.reportDateTimeDisplay(from: newDate)
                }
            Text(output.wrappedValue.isEmpty ? "Day Month Year, HH:mm" : output.wrappedValue)
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func signatureInput(
        title: String,
        image: Binding<UIImage?>,
        clearTrigger: Binding<UUID>,
        clearTitle: String,
        required: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HTXFieldLabel(
                text: title,
                required: required,
                color: HTXTheme.primaryPurple,
                font: .caption.weight(.semibold)
            )

            // Keep the tappable/drawable signature canvas visually and interactively
            // separate from the clear action below.
            SignaturePadView(image: image, clearTrigger: clearTrigger.wrappedValue)
                .frame(height: 150)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.systemGray3), lineWidth: 1)
                )

            HStack {
                Spacer()
                Button {
                    image.wrappedValue = nil
                    clearTrigger.wrappedValue = UUID()
                } label: {
                    Label(clearTitle, systemImage: "trash")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(HTXTheme.primaryPurple.opacity(0.10))
                        .clipShape(Capsule())
                }
                // Important inside Form: without a borderless/plain style, SwiftUI can
                // make the whole row behave like the button. That is why tapping blank
                // space near the signature can accidentally trigger Clear.
                .buttonStyle(.borderless)
                .foregroundColor(HTXTheme.primaryPurple)
            }
        }
        .padding(.vertical, 8)
    }

    private func validationSummary(_ issues: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Please complete:")
                .font(.footnote.weight(.semibold))
            ForEach(issues, id: \.self) { issue in
                Label(issue, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
            }
        }
        .foregroundColor(.red)
        .padding(.vertical, 4)
    }

    private func finalizedStageTwoDetails() -> PoliceReportStageTwoDetails {
        var finalStageTwo = details
        finalStageTwo.officerSignature = officerSignatureImage
        finalStageTwo.interpreterSignature = interpreterSignatureImage
        if finalStageTwo.informantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finalStageTwo.informantName = stageOne.nameOfInformant
        }
        finalStageTwo.informantSignature = informantSignatureImage
        return finalStageTwo
    }

    private func generateReport() {
        guard !isGeneratingReport else { return }
        isGeneratingReport = true
        reportGenerationError = nil
        pdfURL = nil
        generatedReportID = ""
        generatedReportNo = ""

        let finalStageTwo = finalizedStageTwoDetails()

        let plate = plate
        let carTypeValue = carType.rawValue

        // Report must contain NEW damage only. Existing benchmark damage is shown
        // in the app for reference, but it should not be printed into the NP299 PDF.
        let reportDetections = detections.filter { !$0.isBaseline }

        // A normal four-view NP299 review contains the complete edited baseline
        // and can replace the submitted angles. A checklist escalation contains
        // only the driver's newly confirmed areas, so that path must merge with
        // the existing baseline instead of erasing older damage for that angle.
        let baselineAngles = makeBaselineBatchAngles(
            from: detections,
            scanImages: scanImages,
            includeEmptyScanAngles: escalationContext == nil
        )
        let savedRegionCount = baselineAngles.reduce(0) { $0 + $1.regions.count }

        // Never create a report whose visible/confirmed damage cannot also be
        // represented in the comparison baseline. This prevents the PDF and the
        // vehicle baseline from silently disagreeing.
        guard savedRegionCount == detections.count else {
            isGeneratingReport = false
            reportGenerationError = "One or more confirmed damage boxes could not be saved. Return to Damage Analysis, review the affected box, and try again."
            return
        }

        let scanImages = scanImages
        let policeStation = policeStation
        let stageOne = stageOne
        let numericBarcodeId = ReportStore.makeNumericBarcodeId()
        let reportNo = ReportStore.makeReportNo(plate: plate)
        let officerName = finalStageTwo.officerRecordingName.trimmingCharacters(in: .whitespacesAndNewlines)
        let signedInName = Auth.auth().currentUser?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let signedInEmail = Auth.auth().currentUser?.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let generatedBy = !officerName.isEmpty
            ? officerName
            : (!(signedInName ?? "").isEmpty ? signedInName! : (signedInEmail?.isEmpty == false ? signedInEmail! : "Not recorded"))
        let escalationContext = escalationContext

        Task(priority: .userInitiated) {
            let url = await Task(priority: .userInitiated) {
                DamageReportGenerator.generatePDF(
                    plate: plate,
                    carType: carTypeValue,
                    detections: reportDetections,
                    scanImages: scanImages,
                    policeStation: policeStation,
                    stageOne: stageOne,
                    stageTwo: finalStageTwo,
                    numericBarcodeId: numericBarcodeId
                )
            }.value

            guard let url else {
                await MainActor.run {
                    failReportGeneration("The NP299 PDF could not be created. No baseline changes were saved.")
                }
                return
            }

            ReportStore.saveReport(
                reportNo: reportNo,
                plate: plate,
                carType: carTypeValue,
                generatedBy: generatedBy,
                detectionCount: reportDetections.count,
                numericBarcodeId: numericBarcodeId,
                baselineUpdatedAngles: baselineAngles.map(\.angle_index),
                pdfURL: url
            ) { error in
                if let error {
                    DispatchQueue.main.async {
                        failReportGeneration("The NP299 report could not be stored, so the vehicle baseline was left unchanged.\n\n\(error.localizedDescription)")
                    }
                    return
                }

                updateBaselineForStoredReport(
                    url: url,
                    reportID: numericBarcodeId,
                    reportNo: reportNo,
                    plate: plate,
                    escalationContext: escalationContext,
                    baselineAngles: baselineAngles
                )
            }
        }
    }

    private func updateBaselineForStoredReport(
        url: URL,
        reportID: String,
        reportNo: String,
        plate: String,
        escalationContext: NP299EscalationContext?,
        baselineAngles: [ConfirmBaselineBatchAngle]
    ) {
        guard !baselineAngles.isEmpty else {
            finishStoredReport(
                url: url,
                reportID: reportID,
                reportNo: reportNo,
                escalationContext: escalationContext,
                baselineAngles: baselineAngles
            )
            return
        }

        Task(priority: .userInitiated) {
            do {
                if escalationContext == nil {
                    try await DamageAnalysisService.shared.confirmBaselineBatch(
                        plate: plate,
                        angles: baselineAngles
                    )
                } else {
                    try await DamageAnalysisService.shared.mergeConfirmedDamageIntoBaseline(
                        plate: plate,
                        angles: baselineAngles
                    )
                }
                print("Saved updated benchmark for \(plate) after storing NP299 \(reportNo).")
            } catch {
                ReportStore.updateBaselineStatus(
                    reportID: reportID,
                    status: "failed",
                    updatedAngles: baselineAngles.map(\.angle_index),
                    errorMessage: error.localizedDescription
                ) { _ in
                    DispatchQueue.main.async {
                        failReportGeneration(
                            "The NP299 report was stored and will remain visible, but its vehicle baseline could not be updated. Check that the backend is running, then retry from the report.\n\n\(error.localizedDescription)"
                        )
                    }
                }
                return
            }

            ReportStore.updateBaselineStatus(
                reportID: reportID,
                status: "updated",
                updatedAngles: baselineAngles.map(\.angle_index)
            ) { error in
                if let error {
                    DispatchQueue.main.async {
                        failReportGeneration(
                            "The NP299 report and baseline were saved, but the report status could not be finalised. The report remains available in Historical Reports.\n\n\(error.localizedDescription)"
                        )
                    }
                    return
                }

                finishStoredReport(
                    url: url,
                    reportID: reportID,
                    reportNo: reportNo,
                    escalationContext: escalationContext,
                    baselineAngles: baselineAngles
                )
            }
        }
    }

    private func finishStoredReport(
        url: URL,
        reportID: String,
        reportNo: String,
        escalationContext: NP299EscalationContext?,
        baselineAngles: [ConfirmBaselineBatchAngle]
    ) {
        guard let escalationContext else {
            presentGeneratedReport(url: url, reportID: reportID, reportNo: reportNo)
            return
        }

        linkEscalatedChecklist(
            context: escalationContext,
            reportID: reportID,
            reportNo: reportNo,
            baselineAngles: baselineAngles
        ) { error in
            if let error {
                failReportGeneration("The NP299 and baseline were saved, but the SecCom checklist could not be linked. The report remains available in Historical Reports.\n\n\(error.localizedDescription)")
            } else {
                presentGeneratedReport(url: url, reportID: reportID, reportNo: reportNo)
            }
        }
    }

    private func presentGeneratedReport(url: URL, reportID: String, reportNo: String) {
        DispatchQueue.main.async {
            generatedReportID = reportID
            generatedReportNo = reportNo
            isGeneratingReport = false
            pdfURL = url
        }
    }

    private func failReportGeneration(_ message: String) {
        isGeneratingReport = false
        reportGenerationError = message
    }

    private func linkEscalatedChecklist(
        context: NP299EscalationContext,
        reportID: String,
        reportNo: String,
        baselineAngles: [ConfirmBaselineBatchAngle],
        completion: @escaping (Error?) -> Void
    ) {
        let database = Firestore.firestore()
        let reportReference = database.collection("reports").document(reportID)
        let checklistReference = database.collection("seccom_checklists").document(context.checklistID)
        let batch = database.batch()

        var checklistUpdate: [String: Any] = [
            "np299ReportId": reportID,
            "np299ReportNo": reportNo,
            "np299GeneratedAt": FieldValue.serverTimestamp(),
            "adminReviewStatus": ChecklistAdminReviewStatus.np299Filed.rawValue
        ]

        if baselineAngles.isEmpty {
            checklistUpdate["baselineUpdateStatus"] = "not_required"
            checklistUpdate["baselineUpdateError"] = FieldValue.delete()
        } else {
            checklistUpdate["baselineUpdateStatus"] = "updated"
            checklistUpdate["baselineUpdatedAngles"] = baselineAngles.map(\.angle_index)
            checklistUpdate["baselineUpdatedAt"] = FieldValue.serverTimestamp()
            checklistUpdate["baselineUpdateError"] = FieldValue.delete()
        }

        batch.setData(
            [
                "sourceChecklistId": context.checklistID,
                "sourceChecklistReportNo": context.checklistReportNo
            ],
            forDocument: reportReference,
            merge: true
        )
        batch.setData(checklistUpdate, forDocument: checklistReference, merge: true)

        batch.commit { error in
            if let error {
                print("Failed to link NP299 report to checklist:", error.localizedDescription)
                DispatchQueue.main.async { completion(error) }
                return
            }
            DispatchQueue.main.async {
                context.onReportSaved(reportNo)
                completion(nil)
            }
        }
    }

    private func makeBaselineBatchAngles(
        from detections: [MutableDamageDetection],
        scanImages: [UIImage],
        includeEmptyScanAngles: Bool
    ) -> [ConfirmBaselineBatchAngle] {
        var grouped: [Int: [ConfirmBaselineRegion]] = [:]

        for detection in detections {
            guard let region = makeBaselineRegion(from: detection, scanImages: scanImages) else {
                print("Skipping benchmark save for detection with no usable box:", detection.damageType, detection.angleName)
                continue
            }
            grouped[detection.angleIndex, default: []].append(region)
        }

        if includeEmptyScanAngles {
            // A normal NP299 is a complete four-view review. Sending an empty
            // submitted angle is intentional: it records that the user removed
            // the last old baseline case from that side. Checklist escalation
            // does not use this path because its one-sided evidence must merge.
            for angleIndex in scanImages.indices.prefix(4) {
                grouped[angleIndex, default: []] = grouped[angleIndex] ?? []
            }
        }

        return grouped.keys.sorted().map { angleIndex in
            ConfirmBaselineBatchAngle(
                angle_index: angleIndex,
                angle_name: angleName(for: angleIndex),
                regions: grouped[angleIndex] ?? []
            )
        }
    }

    private func makeBaselineRegion(
        from detection: MutableDamageDetection,
        scanImages: [UIImage]
    ) -> ConfirmBaselineRegion? {
        let sourceImage: UIImage? = {
            guard detection.angleIndex >= 0, detection.angleIndex < scanImages.count else {
                return detection.cleanContextImage ?? detection.contextImage ?? detection.cropImage
            }
            return scanImages[detection.angleIndex]
        }()

        guard let sourceImage else { return nil }
        let normalizedSource = sourceImage.htxNormalizedImage()

        let bbox: CGRect? = {
            // This is the same current box used by the NP299 PDF. It changes when
            // the user edits or manually draws the damage area, so it must take
            // priority over the detector's original pixel coordinates.
            if let current = detection.normalizedBBox,
               current.width > 0, current.height > 0 {
                return current
            }

            guard let x1 = detection.x1, let y1 = detection.y1,
                  let x2 = detection.x2, let y2 = detection.y2,
                  x2 > x1, y2 > y1 else { return nil }

            let coordinateWidth = CGFloat(max(1, detection.imageWidth ?? Int(normalizedSource.size.width)))
            let coordinateHeight = CGFloat(max(1, detection.imageHeight ?? Int(normalizedSource.size.height)))
            return CGRect(
                x: CGFloat(x1) / coordinateWidth,
                y: CGFloat(y1) / coordinateHeight,
                width: CGFloat(x2 - x1) / coordinateWidth,
                height: CGFloat(y2 - y1) / coordinateHeight
            )
        }()

        guard let bbox else { return nil }

        // Store a compact clean reference image. The old full-resolution copy
        // was duplicated for every box and could make baseline requests tens of
        // megabytes, causing the silent timeouts seen during report generation.
        let referenceImage = resizedImageForPreview(normalizedSource, maxDimension: 1800)
        return ConfirmBaselineRegion.fromNormalizedBox(
            bbox,
            label: detection.damageType,
            image: referenceImage
        )
    }

    private func angleName(for index: Int) -> String {
        switch index {
        case 0: return "Front"
        case 1: return "Rear"
        case 2: return "Left Side"
        case 3: return "Right Side"
        default: return "Angle \(index)"
        }
    }
}

// MARK: - Report Confirmation Review

struct PoliceReportReviewView: View {
    let plate: String
    let carType: CarType
    let detections: [MutableDamageDetection]
    let policeStation: PoliceStationDetails
    let stageOne: PoliceReportStageOneDetails
    let stageTwo: PoliceReportStageTwoDetails
    let isGeneratingReport: Bool
    var onGenerate: () -> Void

    @State private var showGenerateConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Image(systemName: "checklist.checked")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundColor(HTXTheme.primaryPurple)

                    Text("Confirm Report Details")
                        .font(.title2.weight(.bold))

                    Text("Review all fields before creating the final PDF report.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 18)

                reviewSection("Vehicle") {
                    reviewRow("Plate", plate)
                    reviewRow("Vehicle Type", carType.rawValue)
                    reviewRow("Damage Cases", "\(detections.count)")
                }

                reviewSection("Station") {
                    reviewRow("Division", policeStation.division)
                    reviewRow("NPC", policeStation.displayName)
                    reviewRow("Address", "\(policeStation.address), Singapore \(policeStation.postalCode)")
                    reviewRow("Telephone", policeStation.telephone.isEmpty ? "-" : policeStation.telephone)
                }

                reviewSection("Stage 1 — Informant & Incident") {
                    reviewRow("Name Of Informant", stageOne.nameOfInformant)
                    reviewRow("Address", stageOne.address)
                    reviewRow("ID Type / ID No.", stageOne.idTypeAndNo)
                    reviewRow("FIN No.", stageOne.finNo)
                    reviewRow("Contact", stageOne.contactNumber)
                    reviewRow("Nationality", stageOne.nationality)
                    reviewRow("Email", stageOne.emailAddress)
                    reviewRow("Occupation", stageOne.occupation)
                    reviewRow("Sex", stageOne.sex)
                    reviewRow("Age", stageOne.age)
                    reviewRow("Date of Birth", stageOne.dateOfBirth)
                    reviewRow("Race", stageOne.race)
                    reviewRow("Institution / School", stageOne.institutionSchoolName)
                    reviewRow("Language", stageOne.language)
                    reviewRow("Date/Time Of Incident", stageOne.dateTimeOfIncident)
                    reviewRow("Location Of Incident", stageOne.locationOfIncident)
                    reviewRow("Vide Report No.", stageOne.videReportNo)
                    reviewRow("Station Diary No.", stageOne.stationDiaryNo)
                }

                reviewSection("Stage 2 — Officer & Signatures") {
                    reviewRow("Officer Recording", stageTwo.officerRecordingName)
                    reviewRow("Officer Signature", stageTwo.officerSignature == nil ? "Not provided" : "Provided")
                    reviewRow("Interpreter Name", stageTwo.interpreterAvailability)
                    reviewRow("Interpreter Signature", stageTwo.interpreterSignature == nil ? "Not provided" : "Provided")
                    reviewRow("Interpreter Date/Time", stageTwo.interpreterSignatureDateTime)
                    reviewRow("Informant Name", stageTwo.informantName)
                    reviewRow("Informant Signature", stageTwo.informantSignature == nil ? "Not provided" : "Provided")
                    reviewRow("Informant Date/Time", stageTwo.informantSignatureDateTime)
                    reviewRow("Officer In-Charge", stageTwo.officerInCharge)
                    reviewRow("Classification", stageTwo.classificationOfCase)
                }

                Button {
                    showGenerateConfirmation = true
                } label: {
                    HStack {
                        if isGeneratingReport {
                            ProgressView().tint(.white)
                        }
                        Text(isGeneratingReport ? "Generating Report..." : "Generate Report")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isGeneratingReport ? Color.gray : HTXTheme.primaryPurple)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isGeneratingReport)
                .padding(.horizontal)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("Review Details")
        .navigationBarTitleDisplayMode(.inline)
        .background(SubtleHTXBackground())
        .alert("Are you sure you want to generate the report?", isPresented: $showGenerateConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Yes, Generate Report") {
                onGenerate()
            }
        } message: {
            Text("Make sure that all fields are correct")
        }
    }

    @ViewBuilder
    private func reviewSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundColor(HTXTheme.primaryPurple)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            content()
        }
        .background(Color(.systemBackground).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(HTXTheme.primaryPurple.opacity(0.14), lineWidth: 1)
        )
        .padding(.horizontal)
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 128, alignment: .leading)

                Text(displayValue(value))
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().padding(.leading, 16)
        }
    }

    private func displayValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "-" : trimmed
    }
}

enum PoliceReportFormFormatter {
    static func yyyymmdd(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    static func stationDiaryNumber(date: Date = Date()) -> String {
        let reference = Int.random(in: 0...9999)
        return "D/\(yyyymmdd(date: date))/\(String(format: "%04d", reference))"
    }

    static func dobDisplay(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }

    static func reportDateTimeDisplay(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMMM yyyy, HH:mm"
        return formatter.string(from: date)
    }
}

struct SignaturePadView: UIViewRepresentable {
    @Binding var image: UIImage?
    let clearTrigger: UUID

    func makeUIView(context: Context) -> SignatureCanvasView {
        let view = SignatureCanvasView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 10
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.systemGray3.cgColor
        view.clipsToBounds = true
        view.onImageChanged = { image in
            self.image = image
        }
        view.loadCommittedImageIfNeeded(image)
        return view
    }

    func updateUIView(_ uiView: SignatureCanvasView, context: Context) {
        // Only touch the canvas when the clear button was explicitly pressed.
        // Do NOT call loadCommittedImageIfNeeded here — SwiftUI calls updateUIView
        // immediately after onImageChanged fires (e.g. after a dot/short stroke),
        // and passing the stale `image` binding back into the canvas would wipe
        // the stroke the user just drew.
        if context.coordinator.lastClearTrigger != clearTrigger {
            uiView.clear()
            context.coordinator.lastClearTrigger = clearTrigger
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(clearTrigger: clearTrigger)
    }

    final class Coordinator {
        var lastClearTrigger: UUID
        init(clearTrigger: UUID) {
            self.lastClearTrigger = clearTrigger
        }
    }
}

final class SignatureCanvasView: UIView, UIGestureRecognizerDelegate {
    var onImageChanged: ((UIImage?) -> Void)?

    /// Previously completed strokes are committed into this bitmap.
    /// This prevents the signature from disappearing when SwiftUI redraws
    /// the parent view after the user lifts their finger/stylus.
    private var committedImage: UIImage?
    private var currentLine: [CGPoint] = []
    private var isDrawing = false

    /// A tiny tap / dot should still count as a valid signature stroke.
    /// Previously, a dot could render as a blank white image because a one-point
    /// UIBezierPath has no visible length. We render it as a filled circle instead.
    private let dotRadius: CGFloat = 2.2
    private let tinyStrokeThreshold: CGFloat = 3.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupDrawingGesture()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupDrawingGesture()
    }

    private func setupDrawingGesture() {
        isMultipleTouchEnabled = false
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        pan.delegate = self
        addGestureRecognizer(pan)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    /// Rehydrates the canvas when SwiftUI creates the UIView.
    /// Clearing must only happen through clear(), which is triggered by the Clear button.
    func loadCommittedImageIfNeeded(_ image: UIImage?) {
        guard !isDrawing else { return }
        guard let image else { return }

        if committedImage == nil {
            committedImage = image
            currentLine.removeAll()
            setNeedsDisplay()
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        let clampedPoint = CGPoint(
            x: min(max(point.x, 0), bounds.width),
            y: min(max(point.y, 0), bounds.height)
        )

        switch gesture.state {
        case .began:
            isDrawing = true
            currentLine = [clampedPoint]
            setNeedsDisplay()

        case .changed:
            currentLine.append(clampedPoint)
            setNeedsDisplay()

        case .ended:
            commitCurrentStroke()

        case .cancelled, .failed:
            // Do not treat a cancelled gesture as a clear action.
            // Keep the already-committed signature exactly as it is.
            currentLine.removeAll()
            isDrawing = false
            setNeedsDisplay()

        default:
            break
        }
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        UIColor.white.setFill()
        UIRectFill(rect)

        if let committedImage {
            committedImage.draw(in: bounds)
        }

        drawLine(currentLine)
    }

    func clear() {
        committedImage = nil
        currentLine.removeAll()
        isDrawing = false
        setNeedsDisplay()
        onImageChanged?(nil)
    }

    private func commitCurrentStroke() {
        guard !currentLine.isEmpty else {
            isDrawing = false
            setNeedsDisplay()
            return
        }

        committedImage = renderSignatureImage(includeCurrentLine: true)
        currentLine.removeAll()
        isDrawing = false
        setNeedsDisplay()
        onImageChanged?(committedImage)
    }

    private func drawLine(_ line: [CGPoint]) {
        guard let first = line.first else { return }

        if shouldRenderAsDot(line) {
            drawDot(at: first)
            return
        }

        let path = UIBezierPath()
        path.lineWidth = 2.2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: first)

        for point in line.dropFirst() {
            path.addLine(to: point)
        }

        UIColor.black.setStroke()
        path.stroke()
    }

    private func drawDot(at point: CGPoint) {
        let path = UIBezierPath(
            arcCenter: point,
            radius: dotRadius,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: true
        )
        UIColor.black.setFill()
        path.fill()
    }

    private func shouldRenderAsDot(_ line: [CGPoint]) -> Bool {
        guard let first = line.first else { return false }

        let minX = line.map(\.x).min() ?? first.x
        let maxX = line.map(\.x).max() ?? first.x
        let minY = line.map(\.y).min() ?? first.y
        let maxY = line.map(\.y).max() ?? first.y

        return line.count == 1 ||
            (maxX - minX <= tinyStrokeThreshold && maxY - minY <= tinyStrokeThreshold)
    }

    private func renderSignatureImage(includeCurrentLine: Bool) -> UIImage? {
        guard bounds.width > 0, bounds.height > 0 else { return committedImage }
        guard committedImage != nil || !currentLine.isEmpty else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = window?.screen.scale ?? traitCollection.displayScale
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)

        return renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(bounds)

            if let committedImage {
                committedImage.draw(in: bounds)
            }

            if includeCurrentLine {
                drawLine(currentLine)
            }
        }
    }
}
