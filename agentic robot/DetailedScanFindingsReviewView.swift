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

struct DetailedScanFindingsReviewView: View {
    let scanImages: [UIImage]
    let onComplete: (DetailedScanReviewOutcome) -> Void
    let onBack: () -> Void

    @State private var candidates: [DetailedReviewCandidate]
    @State private var decisions: [UUID: Bool] = [:]
    @State private var manualDetections: [MutableDamageDetection] = []
    @State private var detectionToEdit: MutableDamageDetection?
    @State private var zoomedImage: DetailedScanZoomItem?
    @State private var showManualAdd = false

    init(
        findings: [DetailedProjectedDamageFinding],
        scanImages: [UIImage],
        onComplete: @escaping (DetailedScanReviewOutcome) -> Void,
        onBack: @escaping () -> Void
    ) {
        self.scanImages = scanImages
        self.onComplete = onComplete
        self.onBack = onBack
        _candidates = State(initialValue: findings.map { finding in
            let detection = MutableDamageDetection(from: finding.damage)
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

                        if candidates.isEmpty {
                            noFindingsCard
                        } else {
                            ForEach(candidates) { candidate in
                                DetailedFindingReviewCard(
                                    finding: candidate.finding,
                                    detection: candidate.detection,
                                    decision: decisions[candidate.id],
                                    onDecision: { decisions[candidate.id] = $0 },
                                    onZoom: {
                                        if let image = candidate.detection.contextImage
                                            ?? candidate.detection.cleanContextImage
                                            ?? candidate.detection.cropImage {
                                            zoomedImage = DetailedScanZoomItem(image: image)
                                        }
                                    },
                                    onEdit: { detectionToEdit = candidate.detection }
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
        .fullScreenCover(item: $detectionToEdit) { detection in
            BoundingBoxEditorSheet(
                detection: detection,
                accentColor: HTXTheme.primaryPurple,
                scanImage: scanImages.indices.contains(detection.angleIndex)
                    ? scanImages[detection.angleIndex]
                    : nil
            )
        }
        .fullScreenCover(item: $zoomedImage) { item in
            DetailedScanZoomViewer(image: item.image)
        }
        .fullScreenCover(isPresented: $showManualAdd) {
            AddCaseSheet(scanImages: scanImages, accentColor: HTXTheme.primaryPurple) { detection in
                manualDetections.append(detection)
            }
        }
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
            Text("If you can see damage that the scan missed, draw its location manually below. Otherwise, continue without adding damage.")
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
                        onZoom: {
                            if let image = detection.contextImage ?? detection.cleanContextImage ?? detection.cropImage {
                                zoomedImage = DetailedScanZoomItem(image: image)
                            }
                        },
                        onEdit: { detectionToEdit = detection },
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
    let decision: Bool?
    let onDecision: (Bool) -> Void
    let onZoom: () -> Void
    let onEdit: () -> Void

    private var needsLocationReview: Bool {
        finding.projectionMethod == "panel_zone_fallback"
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

            if let image = detection.contextImage ?? detection.cleanContextImage ?? detection.cropImage {
                Button(action: onZoom) {
                    ZStack(alignment: .bottomTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 220, maxHeight: 430)
                            .background(Color.black.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 14))

                        Label("Tap to zoom", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.bold())
                            .padding(8)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(10)
                    }
                }
                .buttonStyle(.plain)
            }

            if needsLocationReview {
                Label("The scan used an approximate panel location. Check the box and adjust it before accepting.", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundColor(.orange)
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
}

private struct DetailedManualFindingRow: View {
    @ObservedObject var detection: MutableDamageDetection
    let onZoom: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            if let image = detection.cropImage ?? detection.contextImage {
                Button(action: onZoom) {
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

private struct DetailedScanZoomItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct DetailedScanZoomViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in scale = min(max(lastScale * value, 1), 6) }
                            .onEnded { _ in
                                lastScale = scale
                                if scale == 1 { resetZoom() }
                            },
                        DragGesture()
                            .onChanged { value in
                                guard scale > 1 else { return }
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in lastOffset = offset }
                    )
                )
                .onTapGesture(count: 2) {
                    if scale > 1 { resetZoom() } else { scale = 2; lastScale = 2 }
                }

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .padding(20)
            }
        }
    }

    private func resetZoom() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
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
