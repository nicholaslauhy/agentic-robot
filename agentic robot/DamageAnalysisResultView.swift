import SwiftUI
import UIKit
import Combine

// Make URL usable as a sheet item
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}


// MARK: - Damage Analysis HTX Styling
private enum DamageHTX {
    static let cyan = Color(red: 0.00, green: 0.78, blue: 1.00)
    static let violet = Color(red: 0.88, green: 0.25, blue: 0.98)
    static let panel = Color(red: 0.16, green: 0.02, blue: 0.30).opacity(0.86)
    static let panelSoft = Color.white.opacity(0.12)
    static let panelStrong = Color(red: 0.10, green: 0.00, blue: 0.22).opacity(0.92)
    static let border = Color.white.opacity(0.24)
    static let titleText = Color.white
    static let bodyText = Color.white.opacity(0.92)
    static let mutedText = Color.white.opacity(0.76)
}

private struct DamageHTXMiniButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    init(title: String, systemImage: String, tint: Color = DamageHTX.cyan, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundColor(tint)
            .background(tint.opacity(0.14))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}


private struct DamageReportSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption.weight(.heavy))
                .tracking(1.1)
                .foregroundColor(DamageHTX.cyan)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(DamageHTX.mutedText)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DamageReportPrimaryButton: View {
    let title: String
    let systemImage: String
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .font(.headline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundColor(.white)
            .background(
                LinearGradient(
                    colors: isDisabled
                        ? [Color.gray.opacity(0.65), Color.gray.opacity(0.45)]
                        : [DamageHTX.cyan, DamageHTX.violet],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
            .shadow(color: DamageHTX.violet.opacity(isDisabled ? 0 : 0.25), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private extension View {
    func damageReportFormStyle() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(HTXBackground())
            .tint(DamageHTX.cyan)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(DamageHTX.panelStrong, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    func damageReportRowStyle() -> some View {
        self
            .listRowBackground(DamageHTX.panel)
            .listRowSeparatorTint(Color.white.opacity(0.12))
    }

    func damageReportInputStyle() -> some View {
        self
            .padding(12)
            .foregroundColor(.black)
            .background(Color.white.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.88), lineWidth: 1.2)
            )
    }
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
    @State private var showIncidentStageOne = false

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
        ZStack {
            HTXBackground()

            ScrollView {
                VStack(spacing: 20) {
                    // ── Header ────────────────────────────────────────────────────
                    HStack(alignment: .center) {
                        DamageHTXMiniButton(title: "Back", systemImage: "chevron.left") {
                            onBackToScratchScan()
                        }

                        Spacer()

                        VStack(spacing: 4) {
                            Text("Damage Analysis")
                                .font(.system(size: 24, weight: .semibold, design: .default))
                                .foregroundColor(DamageHTX.titleText)

                            Text("\(carType.rawValue) · \(plate)")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(DamageHTX.mutedText)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 8) {
                            DamageHTXMiniButton(title: "Add", systemImage: "plus.circle.fill") {
                                showAddCase = true
                            }

                            Button("Logout") { onLogout() }
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(DamageHTX.titleText)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.18))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.red.opacity(0.38), lineWidth: 1))
                        }
                        .frame(width: 92, alignment: .trailing)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                    if mutableDetections.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 48))
                                .foregroundColor(Color(red: 0.41, green: 0.94, blue: 0.68))

                            Text("No damage cases")
                                .font(.title3.weight(.semibold))
                                .foregroundColor(DamageHTX.titleText)

                            Text("All cases have been removed, or none were detected.")
                                .font(.subheadline)
                                .foregroundColor(DamageHTX.mutedText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .background(DamageHTX.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(DamageHTX.border, lineWidth: 1))
                        .padding(.horizontal, 20)
                        .padding(.top, 30)
                    } else {
                        Text("Found \(mutableDetections.count) possible damage area\(mutableDetections.count == 1 ? "" : "s"). Tap a card for detail, edit, or delete.")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(DamageHTX.bodyText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)

                        LazyVStack(spacing: 18) {
                            ForEach(mutableDetections) { detection in
                                DamageDetectionCard(
                                    detection: detection,
                                    accentColor: DamageHTX.cyan,
                                    onEdit: { detectionToEdit = detection },
                                    onDelete: { remove(detection) }
                                )
                                .onTapGesture { selectedDetection = detection }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // ── Next: collect police-report details ─────────────────────────
                    Button {
                        showIncidentStageOne = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Continue to Report Details")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [DamageHTX.cyan, DamageHTX.violet],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(color: DamageHTX.violet.opacity(0.32), radius: 14, y: 6)
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
            }
        }
        .overlay {
            if isGeneratingReport {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()

                    VStack(spacing: 14) {
                        ProgressView()
                            .scaleEffect(1.3)
                            .tint(.white)

                        Text("Generating your report…")
                            .font(.headline)
                            .foregroundColor(DamageHTX.titleText)

                        Text("This may take a few seconds.")
                            .font(.subheadline)
                            .foregroundColor(DamageHTX.mutedText)
                    }
                    .padding(28)
                    .background(DamageHTX.panelStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(DamageHTX.border, lineWidth: 1))
                    .shadow(radius: 18)
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
}

// MARK: - Card

struct DamageDetectionCard: View {
    @ObservedObject var detection: MutableDamageDetection
    let accentColor: Color
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if let cropImage = detection.cropImage {
                    Image(uiImage: cropImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                } else {
                    ZStack {
                        DamageHTX.panelStrong
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundColor(DamageHTX.mutedText)
                            Text("Could not load image")
                                .font(.footnote)
                                .foregroundColor(DamageHTX.mutedText)
                        }
                    }
                    .frame(height: 200)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(accentColor.opacity(0.38), lineWidth: 1)
            )

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(detection.damageType.capitalized)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(DamageHTX.cyan)

                    Text(detection.angleName)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(DamageHTX.bodyText)
                }

                Spacer()

                HStack(spacing: 8) {
                    Text("\(Int(detection.confidence * 100))%")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(DamageHTX.violet.opacity(0.18))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(DamageHTX.violet.opacity(0.35), lineWidth: 1))

                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "pencil.and.outline")
                            .font(.subheadline)
                            .foregroundColor(DamageHTX.cyan)
                            .padding(8)
                            .background(DamageHTX.cyan.opacity(0.14))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline)
                            .foregroundColor(Color(red: 1, green: 0.48, blue: 0.48))
                            .padding(8)
                            .background(Color.red.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(DamageHTX.panel)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [DamageHTX.cyan.opacity(0.38), DamageHTX.violet.opacity(0.28)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.20), radius: 14, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - Detail Sheet

struct DamageDetailSheet: View {
    @ObservedObject var detection: MutableDamageDetection
    let accentColor: Color
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                HTXBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Location on car", systemImage: "viewfinder")
                                .font(.headline)
                                .foregroundColor(DamageHTX.cyan)

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
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            } else {
                                Text("Context image not available")
                                    .font(.footnote)
                                    .foregroundColor(DamageHTX.mutedText)
                            }
                        }
                        .padding()
                        .background(DamageHTX.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(DamageHTX.border, lineWidth: 1))
                        .padding(.horizontal, 20)

                        VStack(alignment: .leading, spacing: 10) {
                            Label("Damage close-up", systemImage: "magnifyingglass")
                                .font(.headline)
                                .foregroundColor(DamageHTX.cyan)

                            if let cropImage = detection.cropImage {
                                Image(uiImage: cropImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(accentColor.opacity(0.42), lineWidth: 1))
                            }
                        }
                        .padding()
                        .background(DamageHTX.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(DamageHTX.border, lineWidth: 1))
                        .padding(.horizontal, 20)

                        VStack(spacing: 0) {
                            metaRow(label: "Type",       value: detection.damageType.capitalized)
                            Divider().overlay(DamageHTX.border)
                            metaRow(label: "Angle",      value: detection.angleName)
                            Divider().overlay(DamageHTX.border)
                            metaRow(label: "Confidence", value: "\(Int(detection.confidence * 100))%")
                            if !detection.severity.isEmpty {
                                Divider().overlay(DamageHTX.border)
                                metaRow(label: "Severity", value: detection.severity.capitalized)
                            }
                            if !detection.repairComplexity.isEmpty {
                                Divider().overlay(DamageHTX.border)
                                metaRow(label: "Repair Complexity", value: detection.repairComplexity.capitalized)
                            }
                        }
                        .background(DamageHTX.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(DamageHTX.border, lineWidth: 1))
                        .padding(.horizontal, 20)

                        if !detection.repairRecommendation.isEmpty {
                            infoBlock(title: "Repair Recommendation", systemImage: "wrench.and.screwdriver", text: detection.repairRecommendation)
                        }

                        if !detection.explanation.isEmpty {
                            infoBlock(title: "AI Analysis", systemImage: "sparkles", text: detection.explanation)
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Damage Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(DamageHTX.cyan)
                }
            }
        }
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(DamageHTX.cyan)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(DamageHTX.titleText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private func infoBlock(title: String, systemImage: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundColor(DamageHTX.cyan)
            Text(text)
                .font(.subheadline)
                .foregroundColor(DamageHTX.bodyText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(DamageHTX.panel)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(DamageHTX.border, lineWidth: 1))
        .padding(.horizontal, 20)
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
                                    .background(pendingDamageType == type ? DamageHTX.violet : DamageHTX.panel)
                                    .foregroundColor(pendingDamageType == type ? .white : DamageHTX.titleText)
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
                            .foregroundColor(DamageHTX.mutedText)
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
                                    .foregroundColor(DamageHTX.mutedText)
                                    .padding(.horizontal)
                            } else {
                                Text("No boundary drawn yet.")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding(.horizontal)
                            }
                        } else {
                            Text("No image available for this detection.")
                                .foregroundColor(DamageHTX.mutedText)
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
                                                .foregroundColor(DamageHTX.mutedText)
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
                                .background(selectedDamageType == type ? DamageHTX.violet : DamageHTX.panel)
                                .foregroundColor(selectedDamageType == type ? .white : DamageHTX.titleText)
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
                .foregroundColor(DamageHTX.mutedText)
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
                        .foregroundColor(DamageHTX.mutedText)
                } else {
                    Text("No boundary drawn yet — you can still add the case without one.")
                        .font(.caption)
                        .foregroundColor(DamageHTX.mutedText)
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
            ZStack {
                HTXBackground()

                VStack(spacing: 0) {

                    // ── Tab picker ───────────────────────────────────────────────
                    Picker("View", selection: $showingPreview) {
                    Text("Summary").tag(false)
                    Text("Preview PDF").tag(true)
                }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .tint(DamageHTX.cyan)

                    Rectangle()
                        .fill(Color.white.opacity(0.16))
                        .frame(height: 1)

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
                                .foregroundColor(DamageHTX.cyan)

                            VStack(spacing: 8) {
                                Text("Damage Report")
                                    .font(.largeTitle.weight(.semibold))
                                    .foregroundColor(.white)

                                Text("Vehicle: \(carType.rawValue)")
                                    .font(.headline)
                                    .foregroundColor(DamageHTX.bodyText)

                                Text("Plate: \(plate)")
                                    .font(.subheadline)
                                    .foregroundColor(DamageHTX.mutedText)
                            }

                            VStack(spacing: 4) {
                                Text("\(detectionCount)")
                                    .font(.system(size: 56, weight: .black))
                                    .foregroundColor(DamageHTX.cyan)
                                Text(detectionCount == 1 ? "damage case recorded" : "damage cases recorded")
                                    .font(.subheadline)
                                    .foregroundColor(DamageHTX.mutedText)
                            }
                            .padding(.vertical, 20)
                            .frame(maxWidth: .infinity)
                            .background(DamageHTX.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .padding(.horizontal, 40)

                            Text("Report successfully generated. Tap \"Preview PDF\" to review the full report before sharing.")
                                .font(.subheadline)
                                .foregroundColor(DamageHTX.mutedText)
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
                                    .background(DamageHTX.cyan.opacity(0.16))
                                    .foregroundColor(DamageHTX.cyan)
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
                                    .background(LinearGradient(colors: [DamageHTX.cyan, DamageHTX.violet], startPoint: .leading, endPoint: .trailing))
                                    .foregroundColor(.white)
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    if showingPreview {
                        Button {
                            sharePDF(url: pdfURL)
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }

                    Button(role: .destructive) {
                        onLogout()
                    } label: {
                        Text("Logout")
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DamageReportSectionHeader(title: "Police Station of Origin", subtitle: "Choose the NPC/station that will appear in the report")
                    ForEach(PoliceStationDetails.groupedByDivision, id: \.0) { division, stations in
                        DisclosureGroup {

                            ForEach(stations) { station in
                                Button {
                                    selectedStation = station
                                    useOtherStation = false
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: selectedStation == station ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedStation == station ? DamageHTX.cyan : Color.white.opacity(0.65))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(station.displayName).font(.subheadline.bold()).foregroundColor(.white)
                                            Text("\(station.address), Singapore \(station.postalCode)")
                                                .font(.caption)
                                                .foregroundColor(DamageHTX.mutedText)
                                            Text("Tel: \(station.telephone)")
                                                .font(.caption)
                                                .foregroundColor(DamageHTX.mutedText)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 4)
                            }
                        } label: {
                            Text(division)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .damageReportRowStyle()

                Section {
                    DamageReportSectionHeader(title: "Other Station", subtitle: "Use this only if the station is not listed above")
                    Toggle("Use other / manual NPC", isOn: $useOtherStation)
                        .foregroundColor(.white)
                    if useOtherStation {
                        reportTextField("Division", text: $customDivision, placeholder: "Enter division")
                        reportTextField("Location", text: $customAddress, placeholder: "Enter station location", axis: .vertical)
                        reportTextField("Postal Code", text: $customPostalCode, placeholder: "Enter postal code")
                            .keyboardType(.numberPad)
                        reportTextField("Telephone", text: $customTelephone, placeholder: "Enter telephone, if any")
                            .keyboardType(.phonePad)
                    }
                }
                .damageReportRowStyle()

                Section {
                    DamageReportSectionHeader(title: "Selected Station")
                    VStack(alignment: .leading, spacing: 7) {
                        Text(stationForReport.displayName)
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.white)
                        Text(stationForReport.division)
                            .font(.subheadline)
                            .foregroundColor(DamageHTX.bodyText)
                        Text(stationForReport.address)
                            .foregroundColor(DamageHTX.bodyText)
                        Text("Singapore \(stationForReport.postalCode)")
                            .foregroundColor(DamageHTX.bodyText)
                        Text(stationForReport.telephone.isEmpty ? "Tel:" : "Tel: \(stationForReport.telephone)")
                            .foregroundColor(DamageHTX.bodyText)
                    }
                }
                .damageReportRowStyle()

                Section {
                    DamageReportPrimaryButton(title: "Proceed to Stage 1", systemImage: "arrow.right.circle.fill") {
                        showStageOne = true
                    }
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                }
                .damageReportRowStyle()
            }
            .damageReportFormStyle()
            .navigationTitle("Report Stage 0")
            .navigationBarTitleDisplayMode(.inline)
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
        axis: Axis = .horizontal
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.bold)).foregroundColor(.white)
            TextField(placeholder, text: text, axis: axis)
                .lineLimit(axis == .vertical ? 2...4 : 1...1)
                .damageReportInputStyle()
        }
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
    var interpreterAvailability = "Not available"
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
    @Environment(\.dismiss) private var dismiss

    private let sexOptions = ["", "Male", "Female", "Prefer not to say"]
    private let raceOptions = ["", "Chinese", "Malay", "Indian", "Other"]
    private let contactOptions = ["Home", "Office"]

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

    private var canProceed: Bool {
        isAgeValid && isDOBValid && isIncidentDateTimeValid
    }

    var body: some View {
        Form {
            Section {
                DamageReportSectionHeader(title: "Incident Details", subtitle: "Fill in the informant and incident information")
                    reportTextField(
                        "Station Diary No.",
                        text: $details.stationDiaryNo,
                        placeholder: "Auto: D/yyyymmdd/1234"
                    )
                    reportTextField("Vide Report No.", text: $details.videReportNo, placeholder: "Leave blank if not available")
                    reportTextField("Name of Informant", text: $details.nameOfInformant, placeholder: "Enter full name")
                    reportTextField("Address", text: $details.address, placeholder: "Enter address", axis: .vertical)
                    reportTextField("ID Type / ID No.", text: $details.idTypeAndNo, placeholder: "e.g. NRIC / S1234567A")
                    reportTextField("FIN NO /", text: $details.finNo, placeholder: "Enter FIN, if any")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Contact No.").font(.caption.weight(.bold)).foregroundColor(.white)
                        Picker("Contact Type", selection: $details.contactType) {
                            ForEach(contactOptions, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        TextField("Enter \(details.contactType.lowercased()) number", text: $details.contactNumber)
                            .keyboardType(.phonePad)
                            .damageReportInputStyle()
                    }

                    reportTextField("Email Address", text: $details.emailAddress, placeholder: "name@example.com")
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    reportTextField("Nationality", text: $details.nationality, placeholder: "Enter nationality")
                    reportTextField("Occupation", text: $details.occupation, placeholder: "Enter occupation")

                    dropdownField("Sex", selection: $details.sex, options: sexOptions, emptyTitle: "Select sex")
                    reportTextField("Age", text: $details.age, placeholder: "Enter age")
                        .keyboardType(.numberPad)
                    if !isAgeValid {
                        validationText("Age must be a valid number between 0 and 130.")
                    }

                    dateOnlyPickerField(
                        "Date of Birth",
                        date: $dateOfBirthValue,
                        output: $details.dateOfBirth
                    )

                    dropdownField("Race", selection: $details.race, options: raceOptions, emptyTitle: "Select race")
                    reportTextField("Institution/School Name", text: $details.institutionSchoolName, placeholder: "Enter institution/school, if any")
                    reportTextField("Language", text: $details.language, placeholder: "Enter language")
                    dateTimePickerField(
                        "Date/Time of Incident",
                        date: $incidentDateTimeValue,
                        output: $details.dateTimeOfIncident
                    )
                    reportTextField("Location of Incident", text: $details.locationOfIncident, placeholder: "Enter location", axis: .vertical)
                }
                .damageReportRowStyle()

                Section {
                    Button {
                        if isBlank(details.stationDiaryNo) {
                            details.stationDiaryNo = PoliceReportFormFormatter.stationDiaryNumber()
                        }
                        details.dateOfBirth = PoliceReportFormFormatter.dobDisplay(from: dateOfBirthValue)
                        details.dateTimeOfIncident = PoliceReportFormFormatter.reportDateTimeDisplay(from: incidentDateTimeValue)
                        showStageTwo = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Proceed to Stage 2")
                                .font(.headline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .foregroundColor(.white)
                        .background(
                            LinearGradient(
                                colors: canProceed ? [DamageHTX.cyan, DamageHTX.violet] : [Color.gray.opacity(0.65), Color.gray.opacity(0.45)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canProceed)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                }
                .damageReportRowStyle()
            }
            .damageReportFormStyle()
            .navigationTitle("Report Stage 1")
            .navigationBarTitleDisplayMode(.inline)
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
            .onAppear {
                if details.stationDiaryNo.isEmpty {
                    details.stationDiaryNo = PoliceReportFormFormatter.stationDiaryNumber()
                }
            }
    }

    @ViewBuilder
    private func reportTextField(
        _ title: String,
        text: Binding<String>,
        placeholder: String,
        axis: Axis = .horizontal
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.bold)).foregroundColor(.white)
            TextField(placeholder, text: text, axis: axis)
                .lineLimit(axis == .vertical ? 2...4 : 1...1)
                .damageReportInputStyle()
        }
    }

    @ViewBuilder
    private func dropdownField(
        _ title: String,
        selection: Binding<String>,
        options: [String],
        emptyTitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.bold)).foregroundColor(.white)
            Picker(emptyTitle, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option.isEmpty ? emptyTitle : option).tag(option)
                }
            }
            .pickerStyle(.menu)
            .damageReportInputStyle()
        }
    }

    @ViewBuilder
    private func dateOnlyPickerField(
        _ title: String,
        date: Binding<Date>,
        output: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.bold)).foregroundColor(.white)
            DatePicker("", selection: date, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .damageReportInputStyle()
                .onAppear { output.wrappedValue = PoliceReportFormFormatter.dobDisplay(from: date.wrappedValue) }
                .onChange(of: date.wrappedValue) { _, newDate in
                    output.wrappedValue = PoliceReportFormFormatter.dobDisplay(from: newDate)
                }
            Text(output.wrappedValue.isEmpty ? "DD/MM/YYYY" : output.wrappedValue)
                .font(.caption.monospacedDigit())
                .foregroundColor(DamageHTX.mutedText)
        }
    }

    @ViewBuilder
    private func dateTimePickerField(
        _ title: String,
        date: Binding<Date>,
        output: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.bold)).foregroundColor(.white)
            DatePicker("", selection: date, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.wheel)
                .labelsHidden()
                .damageReportInputStyle()
                .environment(\.locale, Locale(identifier: "en_GB"))
                .onAppear { output.wrappedValue = PoliceReportFormFormatter.reportDateTimeDisplay(from: date.wrappedValue) }
                .onChange(of: date.wrappedValue) { _, newDate in
                    output.wrappedValue = PoliceReportFormFormatter.reportDateTimeDisplay(from: newDate)
                }
            Text(output.wrappedValue.isEmpty ? "Day Month Year, HH:mm" : output.wrappedValue)
                .font(.caption.monospacedDigit())
                .foregroundColor(DamageHTX.mutedText)
        }
    }

    private func validationText(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundColor(.red)
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

    @State private var details = PoliceReportStageTwoDetails()
    @State private var officerSignatureTrigger = UUID()
    @State private var interpreterSignatureTrigger = UUID()
    @State private var informantSignatureTrigger = UUID()
    @State private var interpreterDateTimeValue = Date()
    @State private var informantDateTimeValue = Date()
    @State private var officerSignatureImage: UIImage? = nil
    @State private var interpreterSignatureImage: UIImage? = nil
    @State private var informantSignatureImage: UIImage? = nil

    var body: some View {
        Form {
            Section {
                DamageReportSectionHeader(title: "Enter your details")
                reportTextField("Name of officer recording the report", text: $details.officerRecordingName, placeholder: "Enter officer name")

                signatureInput(
                    title: "Signature of Officer Recording the Report",
                    image: $officerSignatureImage,
                    clearTrigger: $officerSignatureTrigger,
                    clearTitle: "Clear Officer Signature"
                )
            }
            .damageReportRowStyle()

            Section {
                DamageReportSectionHeader(title: "Interpreter")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Interpreter status").font(.caption.weight(.bold)).foregroundColor(.white)
                    TextField("Not available", text: $details.interpreterAvailability)
                        .damageReportInputStyle()
                }
                signatureInput(
                    title: "Signature of Interpreter",
                    image: $interpreterSignatureImage,
                    clearTrigger: $interpreterSignatureTrigger,
                    clearTitle: "Clear Interpreter Signature"
                )
                dateTimePickerField("Date/Time", date: $interpreterDateTimeValue, output: $details.interpreterSignatureDateTime)
            }
            .damageReportRowStyle()

            Section {
                DamageReportSectionHeader(title: "Informant")
                reportTextField("Name of Informant", text: $details.informantName, placeholder: stageOne.nameOfInformant.isEmpty ? "Enter informant name" : stageOne.nameOfInformant)
                signatureInput(
                    title: "Signature of Informant",
                    image: $informantSignatureImage,
                    clearTrigger: $informantSignatureTrigger,
                    clearTitle: "Clear Informant Signature"
                )

                dateTimePickerField("Date/Time", date: $informantDateTimeValue, output: $details.informantSignatureDateTime)
            }
            .damageReportRowStyle()

            Section {
                DamageReportSectionHeader(title: "Case")
                reportTextField("Name of Officer In-Charge of Case", text: $details.officerInCharge, placeholder: "Enter officer-in-charge")
                reportTextField("Classification of Case", text: $details.classificationOfCase, placeholder: "Enter classification", axis: .vertical)
            }
            .damageReportRowStyle()

            Section {
                DamageReportPrimaryButton(
                    title: isGeneratingReport ? "Generating Report..." : "Generate Report",
                    systemImage: "doc.richtext.fill",
                    isLoading: isGeneratingReport,
                    isDisabled: isGeneratingReport
                ) {
                    generateReport()
                }
                .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            }
            .damageReportRowStyle()
        }
        .damageReportFormStyle()
        .navigationTitle("Report Stage 2")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pdfURL) { url in
            ReportWelcomeView(
                plate: plate,
                carType: carType,
                detectionCount: detections.count,
                pdfURL: url,
                onLogout: {
                    pdfURL = nil
                    isPresented = false

                    // Wait for the PDF sheet/full-screen report flow to dismiss,
                    // then trigger the app-level logout from DamageAnalysisResultView.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        onLogout()
                    }
                }
            )
        }
    }

    @ViewBuilder
    private func reportTextField(
        _ title: String,
        text: Binding<String>,
        placeholder: String,
        axis: Axis = .horizontal
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.bold)).foregroundColor(.white)
            TextField(placeholder, text: text, axis: axis)
                .lineLimit(axis == .vertical ? 2...4 : 1...1)
                .damageReportInputStyle()
        }
    }

    @ViewBuilder
    private func dateTimePickerField(
        _ title: String,
        date: Binding<Date>,
        output: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.bold)).foregroundColor(.white)
            DatePicker("", selection: date, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.wheel)
                .labelsHidden()
                .damageReportInputStyle()
                .environment(\.locale, Locale(identifier: "en_GB"))
                .onAppear { output.wrappedValue = PoliceReportFormFormatter.reportDateTimeDisplay(from: date.wrappedValue) }
                .onChange(of: date.wrappedValue) { _, newDate in
                    output.wrappedValue = PoliceReportFormFormatter.reportDateTimeDisplay(from: newDate)
                }
            Text(output.wrappedValue.isEmpty ? "Day Month Year, HH:mm" : output.wrappedValue)
                .font(.caption.monospacedDigit())
                .foregroundColor(DamageHTX.mutedText)
        }
    }

    @ViewBuilder
    private func signatureInput(
        title: String,
        image: Binding<UIImage?>,
        clearTrigger: Binding<UUID>,
        clearTitle: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
            SignaturePadView(image: image, clearTrigger: clearTrigger.wrappedValue)
                .frame(height: 150)
                .background(Color.white.opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.88), lineWidth: 1.2))
            Button(clearTitle) {
                image.wrappedValue = nil
                clearTrigger.wrappedValue = UUID()
            }
            .font(.caption)
        }
        .padding(.vertical, 6)
    }

    private func generateReport() {
        guard !isGeneratingReport else { return }
        isGeneratingReport = true
        pdfURL = nil

        var finalStageTwo = details
        finalStageTwo.officerSignature = officerSignatureImage
        finalStageTwo.interpreterSignature = interpreterSignatureImage
        if finalStageTwo.interpreterAvailability.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && interpreterSignatureImage == nil {
            finalStageTwo.interpreterAvailability = "Not available"
        }
        if finalStageTwo.informantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            finalStageTwo.informantName = stageOne.nameOfInformant
        }
        finalStageTwo.informantSignature = informantSignatureImage

        let plate = plate
        let carTypeValue = carType.rawValue
        let detections = detections
        let scanImages = scanImages
        let policeStation = policeStation
        let stageOne = stageOne

        Task(priority: .userInitiated) {
            let url = await Task(priority: .userInitiated) {
                DamageReportGenerator.generatePDF(
                    plate: plate,
                    carType: carTypeValue,
                    detections: detections,
                    scanImages: scanImages,
                    policeStation: policeStation,
                    stageOne: stageOne,
                    stageTwo: finalStageTwo
                )
            }.value

            await MainActor.run {
                isGeneratingReport = false
                pdfURL = url
            }
        }
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
        return view
    }

    func updateUIView(_ uiView: SignatureCanvasView, context: Context) {
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
    private var lines: [[CGPoint]] = []
    private var currentLine: [CGPoint] = []

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

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        let clampedPoint = CGPoint(
            x: min(max(point.x, 0), bounds.width),
            y: min(max(point.y, 0), bounds.height)
        )

        switch gesture.state {
        case .began:
            currentLine = [clampedPoint]
            setNeedsDisplay()
        case .changed:
            currentLine.append(clampedPoint)
            setNeedsDisplay()
        case .ended, .cancelled, .failed:
            if !currentLine.isEmpty {
                lines.append(currentLine)
                currentLine = []
                onImageChanged?(renderSignatureImage())
            }
            setNeedsDisplay()
        default:
            break
        }
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        UIColor.white.setFill()
        UIRectFill(rect)

        let path = UIBezierPath()
        path.lineWidth = 2.2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        for line in lines + (currentLine.isEmpty ? [] : [currentLine]) {
            guard let first = line.first else { continue }
            path.move(to: first)
            for point in line.dropFirst() {
                path.addLine(to: point)
            }
        }

        UIColor.black.setStroke()
        path.stroke()
    }

    func clear() {
        lines.removeAll()
        currentLine.removeAll()
        setNeedsDisplay()
        onImageChanged?(nil)
    }

    private func renderSignatureImage() -> UIImage? {
        guard !lines.isEmpty else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { context in
            UIColor.white.setFill()
            UIRectFill(bounds)
            layer.render(in: context.cgContext)
        }
    }
}

