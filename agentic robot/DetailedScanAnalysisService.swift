import SwiftUI
import UIKit

struct DetailedPanelAnalysisResponse: Decodable {
    let panelId: String
    let processedFrames: Int
    let analysisPerformed: Bool
    let analysisRequestId: String
    let results: [DetailedPanelDamageFinding]
}

struct DetailedPanelAnalysisReceipt: Identifiable {
    let panel: DetailedVehiclePanel
    let submittedFrames: Int
    let processedFrames: Int
    let findingCount: Int
    let requestId: String

    var id: String { panel.id }
}

enum DetailedPanelAnalysisRunState: Equatable {
    case waiting
    case current
    case completed
    case failed
}

enum DetailedPanelAnalysisStatusResolver {
    static func state(
        for panel: DetailedVehiclePanel,
        currentPanel: DetailedVehiclePanel?,
        failedPanel: DetailedVehiclePanel?,
        receipts: [DetailedPanelAnalysisReceipt]
    ) -> DetailedPanelAnalysisRunState {
        if receipts.contains(where: { $0.panel == panel }) {
            return .completed
        }
        if failedPanel == panel {
            return .failed
        }
        if currentPanel == panel {
            return .current
        }
        return .waiting
    }
}

struct DetailedScanAnalysisBatchResult {
    let findings: [DetailedProjectedDamageFinding]
    let receipts: [DetailedPanelAnalysisReceipt]

    var processedFrameCount: Int {
        receipts.reduce(0) { $0 + $1.processedFrames }
    }
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
    case noCaptures
    case incompleteCaptureSet(missing: [DetailedVehiclePanel], unexpectedCount: Int)
    case duplicatePanel(DetailedVehiclePanel)
    case incompletePanelFrames(panel: DetailedVehiclePanel, expected: Int, actual: Int)
    case panelQualityFailed(DetailedVehiclePanel)
    case frameEncodingFailed(DetailedVehiclePanel)
    case incompleteOverviewImages(expected: Int, actual: Int)
    case mismatchedPanelResponse(expected: DetailedVehiclePanel, actual: String)
    case mismatchedProcessedFrameCount(panel: DetailedVehiclePanel, expected: Int, actual: Int)
    case backendAnalysisNotConfirmed(DetailedVehiclePanel)
    case invalidFindingReference(panel: String)
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .backendNotConfigured:
            return "The damage-analysis backend address is not configured."
        case .noCaptures:
            return "Detailed analysis did not start because no panel recordings were received. Return to the scan and record all 12 panels."
        case .incompleteCaptureSet(let missing, let unexpectedCount):
            let names = missing.map(\.displayName).joined(separator: ", ")
            if !names.isEmpty {
                return "Detailed analysis did not start. Missing panel recordings: \(names)."
            }
            return "Detailed analysis did not start because the submission contained \(unexpectedCount) unexpected panel recording(s)."
        case .duplicatePanel(let panel):
            return "Detailed analysis did not start because \(panel.displayName) was submitted more than once."
        case .incompletePanelFrames(let panel, let expected, let actual):
            return "Detailed analysis did not start because \(panel.displayName) has \(actual) usable viewpoints instead of \(expected). Record that panel again."
        case .panelQualityFailed(let panel):
            return "Detailed analysis did not start because the quality check for \(panel.displayName) did not pass. Record that panel again."
        case .frameEncodingFailed(let panel):
            return "The viewpoints for \(panel.displayName) could not be prepared for upload. Record that panel again."
        case .incompleteOverviewImages(let expected, let actual):
            return "Detailed analysis cannot map its findings because only \(actual) of \(expected) overview images are available."
        case .mismatchedPanelResponse(let expected, let actual):
            return "The backend returned results for \(actual) while \(expected.displayName) was being checked. No result was accepted."
        case .mismatchedProcessedFrameCount(let panel, let expected, let actual):
            return "The backend processed only \(actual) of \(expected) viewpoints for \(panel.displayName). No result was accepted."
        case .backendAnalysisNotConfirmed(let panel):
            return "The backend did not confirm that damage analysis ran for \(panel.displayName). No result was accepted."
        case .invalidFindingReference(let panel):
            return "A detailed finding for \(panel) could not be mapped back to its source image. No incomplete result was accepted."
        case .invalidResponse:
            return "The detailed damage-analysis response could not be read."
        case .server(let message):
            return message
        }
    }
}

enum DetailedScanSubmissionValidator {
    static let requiredPanelCount = DetailedVehicleScanSpecification.panels.count
    static let requiredFramesPerPanel = DetailedScanFrameProcessor.representativeFrameCount

    static func validate(_ captures: [DetailedPanelCapture]) throws -> [DetailedPanelCapture] {
        guard !captures.isEmpty else {
            throw DetailedScanAnalysisError.noCaptures
        }

        var capturesByPanel: [DetailedVehiclePanel: DetailedPanelCapture] = [:]
        for capture in captures {
            guard capturesByPanel[capture.panel] == nil else {
                throw DetailedScanAnalysisError.duplicatePanel(capture.panel)
            }
            capturesByPanel[capture.panel] = capture
        }

        let expectedPanels = DetailedVehicleScanSpecification.panels
        let missing = expectedPanels.filter { capturesByPanel[$0] == nil }
        let unexpectedCount = max(0, capturesByPanel.count - expectedPanels.count)
        guard missing.isEmpty, capturesByPanel.count == expectedPanels.count else {
            throw DetailedScanAnalysisError.incompleteCaptureSet(
                missing: missing,
                unexpectedCount: unexpectedCount
            )
        }

        return try expectedPanels.map { panel in
            guard let capture = capturesByPanel[panel] else {
                throw DetailedScanAnalysisError.incompleteCaptureSet(
                    missing: [panel],
                    unexpectedCount: 0
                )
            }
            let frameCount = capture.representativeFrames.count
            guard frameCount == requiredFramesPerPanel else {
                throw DetailedScanAnalysisError.incompletePanelFrames(
                    panel: panel,
                    expected: requiredFramesPerPanel,
                    actual: frameCount
                )
            }
            guard capture.qualityAssessment.passed else {
                throw DetailedScanAnalysisError.panelQualityFailed(panel)
            }
            return capture
        }
    }

    static func validate(
        response: DetailedPanelAnalysisResponse,
        for capture: DetailedPanelCapture,
        submittedFrameCount: Int
    ) throws {
        guard response.panelId == capture.panel.rawValue else {
            throw DetailedScanAnalysisError.mismatchedPanelResponse(
                expected: capture.panel,
                actual: response.panelId
            )
        }
        guard response.processedFrames == submittedFrameCount else {
            throw DetailedScanAnalysisError.mismatchedProcessedFrameCount(
                panel: capture.panel,
                expected: submittedFrameCount,
                actual: response.processedFrames
            )
        }
        guard response.analysisPerformed,
              !response.analysisRequestId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DetailedScanAnalysisError.backendAnalysisNotConfirmed(capture.panel)
        }
        guard response.results.allSatisfy({ finding in
            finding.panelId == capture.panel.rawValue
                && finding.frameIndex >= 0
                && finding.frameIndex < submittedFrameCount
                && finding.totalFrames == response.processedFrames
        }) else {
            throw DetailedScanAnalysisError.invalidResponse
        }
    }
}

final class DetailedScanAnalysisService {
    static let shared = DetailedScanAnalysisService()

    private init() {}

    func analyze(
        captures: [DetailedPanelCapture],
        progress: @MainActor @escaping (
            _ completed: Int,
            _ total: Int,
            _ panel: DetailedVehiclePanel,
            _ receipt: DetailedPanelAnalysisReceipt?
        ) -> Void
    ) async throws -> (findings: [DetailedPanelDamageFinding], receipts: [DetailedPanelAnalysisReceipt]) {
        let validatedCaptures = try DetailedScanSubmissionValidator.validate(captures)
        var findings: [DetailedPanelDamageFinding] = []
        var receipts: [DetailedPanelAnalysisReceipt] = []
        for (index, capture) in validatedCaptures.enumerated() {
            try Task.checkCancellation()
            progress(index, validatedCaptures.count, capture.panel, nil)
            let response = try await analyze(capture: capture)
            findings.append(contentsOf: response.results)
            let receipt = DetailedPanelAnalysisReceipt(
                panel: capture.panel,
                submittedFrames: capture.representativeFrames.count,
                processedFrames: response.processedFrames,
                findingCount: response.results.count,
                requestId: response.analysisRequestId
            )
            receipts.append(receipt)
            progress(index + 1, validatedCaptures.count, capture.panel, receipt)
        }
        guard receipts.count == DetailedScanSubmissionValidator.requiredPanelCount else {
            throw DetailedScanAnalysisError.invalidResponse
        }
        return (findings, receipts)
    }

    func projectToOverview(
        findings: [DetailedPanelDamageFinding],
        captures: [DetailedPanelCapture],
        overviewImages: [UIImage],
        progress: @MainActor @escaping (_ completed: Int, _ total: Int, _ finding: DetailedPanelDamageFinding) -> Void
    ) async throws -> [DetailedProjectedDamageFinding] {
        let expectedOverviewCount = DetailedVehicleScanSpecification.requiredOverviewCaptureCount
        guard overviewImages.count >= expectedOverviewCount else {
            throw DetailedScanAnalysisError.incompleteOverviewImages(
                expected: expectedOverviewCount,
                actual: overviewImages.count
            )
        }
        let capturesByPanel = Dictionary(uniqueKeysWithValues: captures.map { ($0.panel.rawValue, $0) })
        var projected: [DetailedProjectedDamageFinding] = []

        for (index, finding) in findings.enumerated() {
            try Task.checkCancellation()
            progress(index, findings.count, finding)
            guard let capture = capturesByPanel[finding.panelId],
                  capture.representativeFrames.indices.contains(finding.frameIndex),
                  overviewImages.indices.contains(finding.damage.angleIndex) else {
                throw DetailedScanAnalysisError.invalidFindingReference(panel: finding.panelId)
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

        let encodedFrames = try capture.representativeFrames.enumerated().map { index, frame in
            guard let imageData = frame.image.htxNormalizedImage().jpegData(compressionQuality: 0.82) else {
                throw DetailedScanAnalysisError.frameEncodingFailed(capture.panel)
            }
            return (index, imageData)
        }
        guard encodedFrames.count == DetailedScanSubmissionValidator.requiredFramesPerPanel else {
            throw DetailedScanAnalysisError.incompletePanelFrames(
                panel: capture.panel,
                expected: DetailedScanSubmissionValidator.requiredFramesPerPanel,
                actual: encodedFrames.count
            )
        }

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

        for (index, imageData) in encodedFrames {
            try Task.checkCancellation()
            body.appendFile(
                fieldName: "files",
                filename: "\(capture.panel.rawValue)-view-\(index + 1).jpg",
                mimeType: "image/jpeg",
                data: imageData,
                boundary: boundary
            )
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        print("[Detailed Scan] Uploading \(capture.panel.rawValue) with \(encodedFrames.count) viewpoints")

        let (data, httpResponse) = try await uploadWithRetry(request: request, body: body)
        try Task.checkCancellation()
        guard (200...299).contains(httpResponse.statusCode) else {
            let detail = (try? JSONDecoder().decode(ServerDetail.self, from: data).detail)
                ?? "Detailed scan analysis failed with status \(httpResponse.statusCode)."
            throw DetailedScanAnalysisError.server(detail)
        }

        do {
            let response = try JSONDecoder().decode(DetailedPanelAnalysisResponse.self, from: data)
            try DetailedScanSubmissionValidator.validate(
                response: response,
                for: capture,
                submittedFrameCount: encodedFrames.count
            )
            print(
                "[Detailed Scan] Backend acknowledged \(response.panelId): "
                    + "\(response.processedFrames)/\(encodedFrames.count) viewpoints, "
                    + "\(response.results.count) finding(s)"
            )
            return response
        } catch {
            if error is DetailedScanAnalysisError {
                throw error
            }
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

        let (data, httpResponse) = try await uploadWithRetry(request: request, body: body)
        try Task.checkCancellation()
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

    private func uploadWithRetry(
        request: URLRequest,
        body: Data,
        maximumAttempts: Int = 2
    ) async throws -> (Data, HTTPURLResponse) {
        var lastError: Error?

        for attempt in 1...maximumAttempts {
            try Task.checkCancellation()
            do {
                let (data, response) = try await URLSession.shared.upload(for: request, from: body)
                try Task.checkCancellation()
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw DetailedScanAnalysisError.invalidResponse
                }

                let retryableStatus = httpResponse.statusCode == 408
                    || httpResponse.statusCode == 429
                    || (500...599).contains(httpResponse.statusCode)
                if retryableStatus, attempt < maximumAttempts {
                    try await Task.sleep(for: .seconds(1))
                    continue
                }
                return (data, httpResponse)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                guard attempt < maximumAttempts, isRetryableTransportError(error) else {
                    throw error
                }
                try await Task.sleep(for: .seconds(1))
            }
        }

        throw lastError ?? DetailedScanAnalysisError.invalidResponse
    }

    private func isRetryableTransportError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return [
            .timedOut,
            .networkConnectionLost,
            .notConnectedToInternet,
            .cannotConnectToHost,
            .cannotFindHost,
            .dnsLookupFailed,
        ].contains(urlError.code)
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

private enum DetailedScanWorkflowStage {
    case capture
    case analysis([DetailedPanelCapture])
    case review(DetailedScanAnalysisBatchResult)
}

/// Keeps capture, backend analysis and user review inside one presentation.
/// Passing the captures as an associated value prevents a second screen from
/// observing an empty @State array during a dismiss/present transition.
struct DetailedScanWorkflowView: View {
    let plate: String
    let carType: CarType
    let overviewImages: [UIImage]
    let onCancel: () -> Void
    let onContinueWithoutResults: () -> Void
    let onComplete: (DetailedScanReviewOutcome) -> Void

    @State private var stage: DetailedScanWorkflowStage = .capture

    var body: some View {
        Group {
            switch stage {
            case .capture:
                DetailedVehicleScanView(
                    plate: plate,
                    carType: carType,
                    onCancel: onCancel,
                    onComplete: { captures in
                        stage = .analysis(captures)
                    }
                )

            case .analysis(let captures):
                DetailedScanAnalysisProgressView(
                    captures: captures,
                    overviewImages: overviewImages,
                    onComplete: { result in
                        removeTemporaryVideos(in: captures)
                        stage = .review(result)
                    },
                    onRetake: {
                        removeTemporaryVideos(in: captures)
                        stage = .capture
                    },
                    onSkip: {
                        removeTemporaryVideos(in: captures)
                        onContinueWithoutResults()
                    }
                )

            case .review(let result):
                DetailedScanFindingsReviewView(
                    findings: result.findings,
                    analysisResult: result,
                    scanImages: overviewImages,
                    onComplete: onComplete,
                    onBack: { stage = .capture }
                )
            }
        }
    }

    private func removeTemporaryVideos(in captures: [DetailedPanelCapture]) {
        captures.forEach { $0.removeTemporaryVideo() }
    }
}

struct DetailedScanAnalysisProgressView: View {
    let captures: [DetailedPanelCapture]
    let overviewImages: [UIImage]
    let onComplete: (DetailedScanAnalysisBatchResult) -> Void
    let onRetake: () -> Void
    let onSkip: () -> Void

    @State private var progressValue = 0.0
    @State private var stageLabel = "Step 1 of 2 · Multi-frame damage check"
    @State private var currentPanel: DetailedVehiclePanel?
    @State private var analysisTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var receipts: [DetailedPanelAnalysisReceipt] = []
    @State private var failedPanel: DetailedVehiclePanel?

    private var processedFrameCount: Int {
        receipts.reduce(0) { $0 + $1.processedFrames }
    }

    private var expectedFrameCount: Int {
        DetailedScanSubmissionValidator.requiredPanelCount
            * DetailedScanSubmissionValidator.requiredFramesPerPanel
    }

    var body: some View {
        ZStack {
            SubtleHTXBackground()
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "waveform.and.magnifyingglass")
                        .font(.system(size: 48))
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

                    panelStatusCard

                    if let errorMessage {
                        VStack(spacing: 12) {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                            Button("Try Again") { startAnalysis() }
                                .buttonStyle(.borderedProminent)
                                .tint(HTXTheme.primaryPurple)
                            Button("Return to Detailed Scan") { onRetake() }
                                .buttonStyle(.bordered)
                                .tint(HTXTheme.primaryPurple)
                            Button("Continue Without Detailed Results") { onSkip() }
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Button("Cancel and Return to Detailed Scan") {
                            analysisTask?.cancel()
                            onRetake()
                        }
                        .foregroundColor(.red)
                    }
                }
                .frame(maxWidth: 760)
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .task { startAnalysis() }
        .onDisappear { analysisTask?.cancel() }
    }

    private var panelStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("All panel requests", systemImage: "server.rack")
                    .font(.headline)
                Spacer()
                Text("\(receipts.count)/\(DetailedScanSubmissionValidator.requiredPanelCount) completed")
                    .font(.subheadline.bold())
                    .foregroundColor(
                        receipts.count == DetailedScanSubmissionValidator.requiredPanelCount
                            ? .green
                            : HTXTheme.primaryPurple
                    )
            }

            Text("\(processedFrameCount)/\(expectedFrameCount) viewpoints processed")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()

            LazyVStack(spacing: 0) {
                ForEach(DetailedVehicleScanSpecification.panels) { panel in
                    panelStatusRow(panel)
                    if panel != DetailedVehicleScanSpecification.panels.last {
                        Divider().padding(.leading, 42)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func panelStatusRow(_ panel: DetailedVehiclePanel) -> some View {
        let receipt = receipts.first(where: { $0.panel == panel })
        let state = DetailedPanelAnalysisStatusResolver.state(
            for: panel,
            currentPanel: currentPanel,
            failedPanel: failedPanel,
            receipts: receipts
        )
        let presentation = panelStatusPresentation(state)

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: presentation.icon)
                .foregroundColor(presentation.color)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(panel.sequenceNumber). \(panel.displayName)")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(presentation.label)
                        .font(.caption.bold())
                        .foregroundColor(presentation.color)
                }

                if let receipt {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(receipt.processedFrames)/\(receipt.submittedFrames) frames processed")
                        Text("Receipt #\(receipt.requestId.prefix(8))")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                } else {
                    Text(panelStatusDetail(state))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func panelStatusPresentation(
        _ state: DetailedPanelAnalysisRunState
    ) -> (icon: String, label: String, color: Color) {
        switch state {
        case .waiting:
            return ("clock", "Waiting", .secondary)
        case .current:
            return ("arrow.triangle.2.circlepath.circle.fill", "Analysing", HTXTheme.primaryPurple)
        case .completed:
            return ("checkmark.circle.fill", "Completed", .green)
        case .failed:
            return ("exclamationmark.triangle.fill", "Failed", .red)
        }
    }

    private func panelStatusDetail(_ state: DetailedPanelAnalysisRunState) -> String {
        switch state {
        case .waiting:
            return "Waiting to send 5 representative frames"
        case .current:
            return "Uploading and running the damage detector on 5 frames"
        case .completed:
            return "Backend processing completed"
        case .failed:
            return "No verified backend receipt was returned"
        }
    }

    private func startAnalysis() {
        analysisTask?.cancel()
        progressValue = 0
        stageLabel = "Step 1 of 2 · Multi-frame damage check"
        currentPanel = nil
        failedPanel = nil
        errorMessage = nil
        receipts = []
        analysisTask = Task {
            do {
                let analysis = try await DetailedScanAnalysisService.shared.analyze(
                    captures: captures
                ) { completed, total, panel, receipt in
                    progressValue = 0.72 * Double(completed) / Double(max(1, total))
                    currentPanel = panel
                    if let receipt,
                       !receipts.contains(where: { $0.panel == receipt.panel }) {
                        receipts.append(receipt)
                    }
                }
                guard !Task.isCancelled else { return }
                stageLabel = "Step 2 of 2 · Mapping to overview images"
                progressValue = 0.72
                if analysis.findings.isEmpty {
                    stageLabel = "Analysis complete · 12 panels checked"
                    progressValue = 1
                    try? await Task.sleep(for: .milliseconds(650))
                    guard !Task.isCancelled else { return }
                    onComplete(
                        DetailedScanAnalysisBatchResult(
                            findings: [],
                            receipts: analysis.receipts
                        )
                    )
                    return
                }

                let projected = try await DetailedScanAnalysisService.shared.projectToOverview(
                    findings: analysis.findings,
                    captures: captures,
                    overviewImages: overviewImages
                ) { completed, total, finding in
                    progressValue = 0.72 + 0.28 * Double(completed) / Double(max(1, total))
                    currentPanel = DetailedVehiclePanel(rawValue: finding.panelId)
                }
                stageLabel = "Analysis complete · 12 panels checked"
                progressValue = 1
                try? await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled else { return }
                onComplete(
                    DetailedScanAnalysisBatchResult(
                        findings: projected,
                        receipts: analysis.receipts
                    )
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                if let currentPanel,
                   !receipts.contains(where: { $0.panel == currentPanel }) {
                    failedPanel = currentPanel
                    stageLabel = "Analysis stopped · \(currentPanel.displayName) failed"
                } else {
                    stageLabel = "Detailed analysis stopped"
                }
                errorMessage = error.localizedDescription
            }
        }
    }
}
