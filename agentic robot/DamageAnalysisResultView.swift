import SwiftUI
import UIKit
import Combine

// Make URL usable as a sheet item
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - Mutable Detection Model

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

    // ── VLM fields ──
    @Published var isVerifiedDamage: Bool
    @Published var vlmDamageType: String
    @Published var severity: String
    @Published var repairRecommendation: String
    @Published var repairComplexity: String
    @Published var likelyFalsePositive: Bool
    @Published var explanation: String

    init(from detection: DamageDetection) {
        self.id                    = detection.id
        self.angleIndex            = detection.angleIndex
        self.angleName             = detection.angleName
        self.damageType            = detection.damageType
        self.confidence            = detection.confidence
        self.cropImage             = detection.cropImage
        self.contextImage          = detection.contextImage
        self.cleanContextImage     = detection.cleanContextImage
        self.normalizedBBox        = nil
        self.isVerifiedDamage      = detection.isVerifiedDamage
        self.vlmDamageType         = detection.vlmDamageType
        self.severity              = detection.severity
        self.repairRecommendation  = detection.repairRecommendation
        self.repairComplexity      = detection.repairComplexity
        self.likelyFalsePositive   = detection.likelyFalsePositive
        self.explanation           = detection.explanation
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
        explanation: String = ""
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
        self.isVerifiedDamage      = true
        self.vlmDamageType         = damageType
        self.severity              = ""
        self.repairRecommendation  = ""
        self.repairComplexity      = ""
        self.likelyFalsePositive   = false
        self.explanation           = explanation
    }
}

// MARK: - Result List View

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

    // The 4 angle images passed from ScratchScanView
    // We re-use the scanned images stored in the detections; if none exist we show placeholders.
    // For "Add Case", the user picks which of the 4 slots they want.
    let scanImages: [UIImage]   // front, back, left, right  (may have fewer)

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
                        .foregroundColor(carType.accentColor)
                    }

                    Spacer()

                    VStack(alignment: .center, spacing: 4) {
                        Text("Damage Analysis")
                            .font(.title2).bold()
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
                            .foregroundColor(carType.accentColor)
                        }

                        Button("Logout") { onLogout() }
                            .foregroundColor(.red)
                    }
                    .frame(width: 130, alignment: .trailing)
                }
                .padding(.horizontal)
                .padding(.top)

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
                    Text("Found \(mutableDetections.count) possible damage area\(mutableDetections.count == 1 ? "" : "s"). Tap a card for detail or swipe left to delete.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    LazyVStack(spacing: 20) {
                        ForEach(mutableDetections) { detection in
                            DamageDetectionCard(
                                detection: detection,
                                accentColor: carType.accentColor,
                                onEdit: { detectionToEdit = detection },
                                onDelete: { remove(detection) }
                            )
                            .onTapGesture { selectedDetection = detection }
                        }
                    }
                    .padding(.horizontal)
                }

                // ── Generate Report ───────────────────────────────────────────
                Button {
                    guard !isGeneratingReport else { return }
                    isGeneratingReport = true
                    let plate = plate
                    let carType = carType
                    let detections = mutableDetections
                    let scanImages = scanImages
                    Task(priority: .userInitiated) {
                        let url = await Task(priority: .userInitiated) {
                            DamageReportGenerator.generatePDF(
                                plate: plate,
                                carType: carType.rawValue,
                                detections: detections,
                                scanImages: scanImages
                            )
                        }.value
                        isGeneratingReport = false
                        pdfURL = url
                    }
                } label: {
                    HStack {
                        Image(systemName: "doc.text.fill")
                        Text("Generate Report")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isGeneratingReport ? Color.gray : carType.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(14)
                    .padding(.horizontal)
                }
                .disabled(isGeneratingReport)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
        }
        .overlay {
            if isGeneratingReport {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.4)
                            .tint(.white)
                        Text("Generating your report…")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("This may take a few seconds.")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.75))
                    }
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.systemGray2).opacity(0.95))
                    )
                    .shadow(radius: 16)
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
                accentColor: carType.accentColor
            )
        }
        // ── Edit bounding-box sheet ───────────────────────────────────────────
        .sheet(item: $detectionToEdit) { detection in
            BoundingBoxEditorSheet(
                detection: detection,
                accentColor: carType.accentColor,
                scanImage: detection.angleIndex < scanImages.count ? scanImages[detection.angleIndex] : nil
            )
        }
        // ── Add Case sheet ────────────────────────────────────────────────────
        .sheet(isPresented: $showAddCase) {
            AddCaseSheet(
                scanImages: scanImages,
                accentColor: carType.accentColor
            ) { newDetection in
                mutableDetections.insert(newDetection, at: 0)
            }
        }
        // ── Report sheet ──────────────────────────────────────────────────────
        .sheet(item: $pdfURL) { url in
            ReportWelcomeView(
                plate: plate,
                carType: carType,
                detectionCount: mutableDetections.count,
                pdfURL: url,
                onLogout: {
                    pdfURL = nil
                    onLogout()
                }
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
                if let cropImage = detection.cropImage {
                    Image(uiImage: cropImage)
                        .resizable()
                        .scaledToFit()
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
                    Text(detection.damageType.capitalized).font(.headline)
                    Text(detection.angleName).font(.subheadline).foregroundColor(.secondary)
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
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
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
                        if let ctxImage = detection.normalizedBBox == nil
                            ? detection.contextImage
                            : (detection.cleanContextImage ?? detection.contextImage) {
                            BoundingBoxOverlayView(
                                image: ctxImage,
                                normalizedBBox: .constant(detection.normalizedBBox),
                                accentColor: accentColor,
                                isInteractive: false
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

                        if let cropImage = detection.cropImage {
                            Image(uiImage: cropImage)
                                .resizable().scaledToFit().frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(accentColor.opacity(0.4), lineWidth: 1))
                                .padding(.horizontal)
                        }
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
                    .frame(width: geo.size.width)

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
                            .padding(.horizontal)

                            if let bbox = pendingBBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Close-up Preview", systemImage: "magnifyingglass")
                                        .font(.subheadline.bold())
                                        .padding(.horizontal)

                                    Image(uiImage: renderCrop(image: img, bbox: bbox))
                                        .resizable()
                                        .scaledToFit()
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                        .padding(.horizontal)
                                }
                                .padding(.top, 6)

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
                        detection.normalizedBBox  = bbox
                        // contextImage = full car photo with orange box burned in
                        detection.contextImage    = renderContext(image: baseImg, bbox: bbox)
                        // cleanContextImage = full car photo with no annotations (for future edits)
                        detection.cleanContextImage = normalizedImage(baseImg)
                        // cropImage = padded crop from the full photo
                        detection.cropImage       = renderAnnotatedCrop(image: baseImg, bbox: bbox)

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
                            let detection  = MutableDamageDetection(
                                angleIndex:        selectedAngleIndex,
                                angleName:         angleName,
                                damageType:        selectedDamageType,
                                confidence:        1.0,
                                cropImage:         croppedImage(),
                                contextImage:      selectedImage.map { renderContext(image: $0, bbox: normalizedBBox) },
                                cleanContextImage: selectedImage.map { normalizedImage($0) },
                                normalizedBBox:    normalizedBBox,
                                explanation:       explanation
                            )
                            onAdd(detection)
                            dismiss()
                        }
                        .bold()
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
        VStack(spacing: 12) {
            Text("Drag on the image to draw the orange boundary around the damage.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let img = selectedImage {
                BoundingBoxOverlayView(
                    image: img,
                    normalizedBBox: $normalizedBBox,
                    accentColor: .orange,
                    isInteractive: true
                )
                .padding(.horizontal)

                if let bbox = normalizedBBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Close-up Preview", systemImage: "magnifyingglass")
                            .font(.subheadline.bold())
                            .padding(.horizontal)

                        Image(uiImage: renderCrop(image: img, bbox: bbox))
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .padding(.horizontal)
                    }
                    .padding(.top, 8)

                    Text("Boundary set. Drag again to adjust.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("No boundary drawn yet — you can still add the case without one.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
            }

            Spacer()
        }
        .padding(.top)
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /// Crop with surrounding context padding, matching renderCrop behaviour.
    private func croppedImage() -> UIImage? {
        guard let img = selectedImage, let bbox = normalizedBBox else { return selectedImage }
        return renderAnnotatedCrop(image: img, bbox: bbox)
    }
}

/// Renders the full image with an orange bounding box drawn on it.
/// Used as contextImage — both for user-added cases and after the user edits a bbox.
private func renderContext(image: UIImage, bbox: CGRect?) -> UIImage {
    // Normalize first so image.size and the drawn rect are in the same coordinate space
    let img = normalizedImage(image)
    let renderer = UIGraphicsImageRenderer(size: img.size)
    return renderer.image { _ in
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
private func renderAnnotatedCrop(image: UIImage, bbox: CGRect?, padding: CGFloat = 0.35) -> UIImage {
    guard let bbox else { return normalizedImage(image) }

    let contextImage = renderContext(image: image, bbox: bbox)
    guard let cgImage = contextImage.cgImage else { return contextImage }

    let geometry = cropGeometry(
        for: bbox,
        imageWidth: CGFloat(cgImage.width),
        imageHeight: CGFloat(cgImage.height),
        padding: padding
    )

    guard let cropped = cgImage.cropping(to: geometry.cropRect) else { return contextImage }
    return UIImage(cgImage: cropped, scale: 1, orientation: .up)
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

// MARK: - Report Welcome View

struct ReportWelcomeView: View {
    let plate: String
    let carType: CarType
    let detectionCount: Int
    let pdfURL: URL
    var onLogout: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// Controls whether we show the summary tab or the PDF preview tab.
    @State private var showingPreview = false

    var body: some View {
        NavigationStack {
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
                                .foregroundColor(carType.accentColor)

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
                                    .foregroundColor(carType.accentColor)
                                Text(detectionCount == 1 ? "damage case recorded" : "damage cases recorded")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 20)
                            .frame(maxWidth: .infinity)
                            .background(carType.accentColor.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .padding(.horizontal, 40)

                            Text("Report successfully generated. Tap \"Preview PDF\" to review the full report before sharing.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)

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
                                    .background(carType.accentColor.opacity(0.12))
                                    .foregroundColor(carType.accentColor)
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
                                    .background(carType.accentColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(14)
                                }

                                Button {
                                    dismiss()
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                // Share button also pinned in toolbar when on preview tab for easy access
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
