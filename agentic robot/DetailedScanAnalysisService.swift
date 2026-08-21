import SwiftUI
import UIKit

struct DetailedPanelAnalysisResponse: Decodable {
    let panelId: String
    let processedFrames: Int
    let results: [DetailedPanelDamageFinding]
}

struct DetailedPanelDamageFinding: Decodable, Identifiable {
    let id = UUID()
    let panelId: String
    let frameIndex: Int
    let observedFrames: Int
    let totalFrames: Int
    let persistence: Double
    let multiFrameStatus: String
    let normalisedTrackBox: [Double]
    let damage: DamageDetection

    enum CodingKeys: String, CodingKey {
        case panelId
        case frameIndex
        case observedFrames
        case totalFrames
        case persistence
        case multiFrameStatus
        case normalisedTrackBox
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        panelId = try container.decode(String.self, forKey: .panelId)
        frameIndex = try container.decode(Int.self, forKey: .frameIndex)
        observedFrames = try container.decode(Int.self, forKey: .observedFrames)
        totalFrames = try container.decode(Int.self, forKey: .totalFrames)
        persistence = try container.decode(Double.self, forKey: .persistence)
        multiFrameStatus = try container.decode(String.self, forKey: .multiFrameStatus)
        normalisedTrackBox = try container.decodeIfPresent([Double].self, forKey: .normalisedTrackBox) ?? []
        damage = try DamageDetection(from: decoder)
    }
}

struct DetailedProjectedDamageFinding: Decodable, Identifiable {
    let id: UUID
    let panelIds: [String]
    let observedFrames: Int
    let totalFrames: Int
    let persistence: Double
    let multiFrameStatus: String
    let projectionMethod: String
    let projectionConfidence: Double
    let projectionInliers: Int
    let projectionInlierRatio: Double
    let damage: DamageDetection

    enum CodingKeys: String, CodingKey {
        case panelId
        case observedFrames
        case totalFrames
        case persistence
        case multiFrameStatus
        case projectionMethod
        case projectionConfidence
        case projectionInliers
        case projectionInlierRatio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        panelIds = [try container.decode(String.self, forKey: .panelId)]
        observedFrames = try container.decode(Int.self, forKey: .observedFrames)
        totalFrames = try container.decode(Int.self, forKey: .totalFrames)
        persistence = try container.decode(Double.self, forKey: .persistence)
        multiFrameStatus = try container.decode(String.self, forKey: .multiFrameStatus)
        projectionMethod = try container.decode(String.self, forKey: .projectionMethod)
        projectionConfidence = try container.decode(Double.self, forKey: .projectionConfidence)
        projectionInliers = try container.decodeIfPresent(Int.self, forKey: .projectionInliers) ?? 0
        projectionInlierRatio = try container.decodeIfPresent(Double.self, forKey: .projectionInlierRatio) ?? 0
        damage = try DamageDetection(from: decoder)
    }

    init(
        id: UUID = UUID(),
        panelIds: [String],
        observedFrames: Int,
        totalFrames: Int,
        persistence: Double,
        multiFrameStatus: String,
        projectionMethod: String,
        projectionConfidence: Double,
        projectionInliers: Int,
        projectionInlierRatio: Double,
        damage: DamageDetection
    ) {
        self.id = id
        self.panelIds = panelIds
        self.observedFrames = observedFrames
        self.totalFrames = totalFrames
        self.persistence = persistence
        self.multiFrameStatus = multiFrameStatus
        self.projectionMethod = projectionMethod
        self.projectionConfidence = projectionConfidence
        self.projectionInliers = projectionInliers
        self.projectionInlierRatio = projectionInlierRatio
        self.damage = damage
    }
}

enum DetailedScanAnalysisError: LocalizedError {
    case backendNotConfigured
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .backendNotConfigured:
            return "The damage-analysis backend address is not configured."
        case .invalidResponse:
            return "The detailed damage-analysis response could not be read."
        case .server(let message):
            return message
        }
    }
}

final class DetailedScanAnalysisService {
    static let shared = DetailedScanAnalysisService()

    private init() {}

    func analyze(
        captures: [DetailedPanelCapture],
        progress: @MainActor @escaping (_ completed: Int, _ total: Int, _ panel: DetailedVehiclePanel) -> Void
    ) async throws -> [DetailedPanelDamageFinding] {
        var findings: [DetailedPanelDamageFinding] = []
        for (index, capture) in captures.enumerated() {
            try Task.checkCancellation()
            progress(index, captures.count, capture.panel)
            let response = try await analyze(capture: capture)
            findings.append(contentsOf: response.results)
            progress(index + 1, captures.count, capture.panel)
        }
        return findings
    }

    func projectToOverview(
        findings: [DetailedPanelDamageFinding],
        captures: [DetailedPanelCapture],
        overviewImages: [UIImage],
        progress: @MainActor @escaping (_ completed: Int, _ total: Int, _ finding: DetailedPanelDamageFinding) -> Void
    ) async throws -> [DetailedProjectedDamageFinding] {
        let capturesByPanel = Dictionary(uniqueKeysWithValues: captures.map { ($0.panel.rawValue, $0) })
        var projected: [DetailedProjectedDamageFinding] = []

        for (index, finding) in findings.enumerated() {
            try Task.checkCancellation()
            progress(index, findings.count, finding)
            guard let capture = capturesByPanel[finding.panelId],
                  capture.representativeFrames.indices.contains(finding.frameIndex),
                  overviewImages.indices.contains(finding.damage.angleIndex) else {
                continue
            }
            let result = try await project(
                finding: finding,
                sourceImage: capture.representativeFrames[finding.frameIndex].image,
                overviewImage: overviewImages[finding.damage.angleIndex]
            )
            projected.append(result)
            progress(index + 1, findings.count, finding)
        }

        return DetailedScanDuplicateMerger.merge(projected)
    }

    private func analyze(capture: DetailedPanelCapture) async throws -> DetailedPanelAnalysisResponse {
        guard let url = BackendConfiguration.endpointURL(path: "analyze-detailed-panel") else {
            throw DetailedScanAnalysisError.backendNotConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        let boundary = "DetailedScan-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendFormField(name: "panel_id", value: capture.panel.rawValue, boundary: boundary)
        body.appendFormField(
            name: "angle_index",
            value: String(capture.panel.overviewAngle.rawValue),
            boundary: boundary
        )
        body.appendFormField(
            name: "angle_name",
            value: capture.panel.overviewAngle.label,
            boundary: boundary
        )

        for (index, frame) in capture.representativeFrames.enumerated() {
            try Task.checkCancellation()
            guard let imageData = frame.image.htxNormalizedImage().jpegData(compressionQuality: 0.82) else {
                continue
            }
            body.appendFile(
                fieldName: "files",
                filename: "\(capture.panel.rawValue)-view-\(index + 1).jpg",
                mimeType: "image/jpeg",
                data: imageData,
                boundary: boundary
            )
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        try Task.checkCancellation()
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DetailedScanAnalysisError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let detail = (try? JSONDecoder().decode(ServerDetail.self, from: data).detail)
                ?? "Detailed scan analysis failed with status \(httpResponse.statusCode)."
            throw DetailedScanAnalysisError.server(detail)
        }

        do {
            return try JSONDecoder().decode(DetailedPanelAnalysisResponse.self, from: data)
        } catch {
            throw DetailedScanAnalysisError.invalidResponse
        }
    }

    private func project(
        finding: DetailedPanelDamageFinding,
        sourceImage: UIImage,
        overviewImage: UIImage
    ) async throws -> DetailedProjectedDamageFinding {
        guard let url = BackendConfiguration.endpointURL(path: "project-detailed-damage"),
              let x1 = finding.damage.x1,
              let y1 = finding.damage.y1,
              let x2 = finding.damage.x2,
              let y2 = finding.damage.y2 else {
            throw DetailedScanAnalysisError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        let boundary = "DetailedProjection-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let fields = [
            "panel_id": finding.panelId,
            "angle_index": String(finding.damage.angleIndex),
            "angle_name": finding.damage.angleName,
            "x1": String(x1),
            "y1": String(y1),
            "x2": String(x2),
            "y2": String(y2),
            "damage_type": finding.damage.damageType,
            "confidence": String(finding.damage.confidence),
            "explanation": finding.damage.explanation,
            "severity": finding.damage.severity.isEmpty ? "unassessed" : finding.damage.severity,
            "verification_status": finding.damage.likelyFalsePositive
                ? "likely_false_positive"
                : (finding.damage.isVerifiedDamage ? "verified_damage" : "possible_damage"),
            "observed_frames": String(finding.observedFrames),
            "total_frames": String(finding.totalFrames),
            "persistence": String(finding.persistence),
            "multi_frame_status": finding.multiFrameStatus,
        ]
        for (name, value) in fields {
            body.appendFormField(name: name, value: value, boundary: boundary)
        }

        guard let sourceData = sourceImage.htxNormalizedImage().jpegData(compressionQuality: 0.86),
              let overviewData = overviewImage.htxNormalizedImage().jpegData(compressionQuality: 0.86) else {
            throw DetailedScanAnalysisError.invalidResponse
        }
        body.appendFile(
            fieldName: "source_file",
            filename: "detailed-source.jpg",
            mimeType: "image/jpeg",
            data: sourceData,
            boundary: boundary
        )
        body.appendFile(
            fieldName: "overview_file",
            filename: "vehicle-overview.jpg",
            mimeType: "image/jpeg",
            data: overviewData,
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        try Task.checkCancellation()
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DetailedScanAnalysisError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let detail = (try? JSONDecoder().decode(ServerDetail.self, from: data).detail)
                ?? "Detailed damage mapping failed with status \(httpResponse.statusCode)."
            throw DetailedScanAnalysisError.server(detail)
        }

        struct ProjectionResponse: Decodable {
            let result: DetailedProjectedDamageFinding
        }
        return try JSONDecoder().decode(ProjectionResponse.self, from: data).result
    }

    private struct ServerDetail: Decodable {
        let detail: String
    }
}

enum DetailedScanDuplicateMerger {
    private static let scratchFamily = [
        "scratch", "scuff", "crack", "paint damage", "paint chip",
        "paint chipping", "paint peel", "paint peeling", "peeling",
    ]

    static func merge(_ findings: [DetailedProjectedDamageFinding]) -> [DetailedProjectedDamageFinding] {
        var merged: [DetailedProjectedDamageFinding] = []
        for finding in findings.sorted(by: { qualityScore($0) > qualityScore($1) }) {
            guard let duplicateIndex = merged.firstIndex(where: { isDuplicate($0, finding) }) else {
                merged.append(finding)
                continue
            }

            let existing = merged[duplicateIndex]
            let best = qualityScore(finding) > qualityScore(existing) ? finding : existing
            let panelIds = Array(Set(existing.panelIds + finding.panelIds)).sorted()
            let observedFrames = existing.observedFrames + finding.observedFrames
            let totalFrames = existing.totalFrames + finding.totalFrames
            merged[duplicateIndex] = DetailedProjectedDamageFinding(
                panelIds: panelIds,
                observedFrames: observedFrames,
                totalFrames: totalFrames,
                persistence: Double(observedFrames) / Double(max(1, totalFrames)),
                multiFrameStatus: observedFrames >= 3 ? "corroborated" : best.multiFrameStatus,
                projectionMethod: best.projectionMethod,
                projectionConfidence: best.projectionConfidence,
                projectionInliers: best.projectionInliers,
                projectionInlierRatio: best.projectionInlierRatio,
                damage: best.damage
            )
        }
        return merged
    }

    private static func qualityScore(_ finding: DetailedProjectedDamageFinding) -> Double {
        finding.projectionConfidence * 0.50
            + finding.persistence * 0.30
            + finding.damage.confidence * 0.20
    }

    private static func canonicalLabel(_ label: String) -> String {
        let normalised = label.lowercased().replacingOccurrences(of: "_", with: " ")
        return scratchFamily.contains(normalised) ? "scratch" : normalised
    }

    private static func normalisedBox(_ finding: DetailedProjectedDamageFinding) -> CGRect? {
        guard let x1 = finding.damage.x1,
              let y1 = finding.damage.y1,
              let x2 = finding.damage.x2,
              let y2 = finding.damage.y2,
              let width = finding.damage.imageWidth,
              let height = finding.damage.imageHeight,
              width > 0,
              height > 0,
              x2 > x1,
              y2 > y1 else { return nil }
        return CGRect(
            x: Double(x1) / Double(width),
            y: Double(y1) / Double(height),
            width: Double(x2 - x1) / Double(width),
            height: Double(y2 - y1) / Double(height)
        )
    }

    private static func isDuplicate(
        _ first: DetailedProjectedDamageFinding,
        _ second: DetailedProjectedDamageFinding
    ) -> Bool {
        guard first.damage.angleIndex == second.damage.angleIndex,
              canonicalLabel(first.damage.damageType) == canonicalLabel(second.damage.damageType),
              let firstBox = normalisedBox(first),
              let secondBox = normalisedBox(second) else { return false }

        let intersection = firstBox.intersection(secondBox)
        if !intersection.isNull {
            let intersectionArea = intersection.width * intersection.height
            let unionArea = firstBox.width * firstBox.height
                + secondBox.width * secondBox.height
                - intersectionArea
            if unionArea > 0, intersectionArea / unionArea >= 0.15 {
                return true
            }
        }

        guard canonicalLabel(first.damage.damageType) == "scratch" else { return false }
        let horizontalGap = max(0, max(firstBox.minX, secondBox.minX) - min(firstBox.maxX, secondBox.maxX))
        let verticalOverlap = max(0, min(firstBox.maxY, secondBox.maxY) - max(firstBox.minY, secondBox.minY))
        let smallerHeight = max(0.0001, min(firstBox.height, secondBox.height))
        return horizontalGap <= 0.015 && verticalOverlap / smallerHeight >= 0.35
    }
}

private extension Data {
    mutating func appendFormField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append(value.data(using: .utf8)!)
        append("\r\n".data(using: .utf8)!)
    }

    mutating func appendFile(
        fieldName: String,
        filename: String,
        mimeType: String,
        data: Data,
        boundary: String
    ) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}

struct DetailedScanAnalysisProgressView: View {
    let captures: [DetailedPanelCapture]
    let overviewImages: [UIImage]
    let onComplete: ([DetailedProjectedDamageFinding]) -> Void
    let onSkip: () -> Void

    @State private var progressValue = 0.0
    @State private var stageLabel = "Step 1 of 2 · Multi-frame damage check"
    @State private var currentPanel: DetailedVehiclePanel?
    @State private var analysisTask: Task<Void, Never>?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            SubtleHTXBackground()
            VStack(spacing: 24) {
                Image(systemName: "waveform.and.magnifyingglass")
                    .font(.system(size: 56))
                    .foregroundColor(HTXTheme.primaryPurple)

                Text("Analysing Detailed Scan")
                    .font(.largeTitle.bold())
                    .foregroundColor(HTXTheme.primaryPurple)

                Text(currentPanel.map { "Checking \($0.displayName) from several viewpoints" }
                    ?? "Preparing panel recordings")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    ProgressView(value: progressValue)
                        .tint(HTXTheme.primaryPurple)
                    HStack {
                        Text(stageLabel)
                        Spacer()
                        Text("\(Int((progressValue * 100).rounded()))%")
                            .fontWeight(.bold)
                    }
                    .font(.subheadline)
                }
                .padding()
                .background(Color(.systemBackground).opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Text("A mark must remain visible from more than one camera position. Moving reflections are less likely to be returned as damage.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                if let errorMessage {
                    VStack(spacing: 12) {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                        Button("Try Again") { startAnalysis() }
                            .buttonStyle(.borderedProminent)
                            .tint(HTXTheme.primaryPurple)
                        Button("Continue Without Detailed Results") { onSkip() }
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button("Cancel Detailed Analysis") {
                        analysisTask?.cancel()
                        onSkip()
                    }
                    .foregroundColor(.red)
                }
            }
            .frame(maxWidth: 680)
            .padding(30)
        }
        .task { startAnalysis() }
        .onDisappear { analysisTask?.cancel() }
    }

    private func startAnalysis() {
        analysisTask?.cancel()
        progressValue = 0
        stageLabel = "Step 1 of 2 · Multi-frame damage check"
        currentPanel = nil
        errorMessage = nil
        analysisTask = Task {
            do {
                let findings = try await DetailedScanAnalysisService.shared.analyze(
                    captures: captures
                ) { completed, total, panel in
                    progressValue = 0.72 * Double(completed) / Double(max(1, total))
                    currentPanel = panel
                }
                guard !Task.isCancelled else { return }
                stageLabel = "Step 2 of 2 · Mapping to overview images"
                progressValue = 0.72
                if findings.isEmpty {
                    progressValue = 1
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    onComplete([])
                    return
                }

                let projected = try await DetailedScanAnalysisService.shared.projectToOverview(
                    findings: findings,
                    captures: captures,
                    overviewImages: overviewImages
                ) { completed, total, finding in
                    progressValue = 0.72 + 0.28 * Double(completed) / Double(max(1, total))
                    currentPanel = DetailedVehiclePanel(rawValue: finding.panelId)
                }
                progressValue = 1
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                onComplete(projected)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
