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

    private struct ServerDetail: Decodable {
        let detail: String
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
    let onComplete: ([DetailedPanelDamageFinding]) -> Void
    let onSkip: () -> Void

    @State private var completedPanels = 0
    @State private var currentPanel: DetailedVehiclePanel?
    @State private var analysisTask: Task<Void, Never>?
    @State private var errorMessage: String?

    private var progress: Double {
        Double(completedPanels) / Double(max(1, captures.count))
    }

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
                    ProgressView(value: progress)
                        .tint(HTXTheme.primaryPurple)
                    HStack {
                        Text("Multi-frame damage check")
                        Spacer()
                        Text("\(Int((progress * 100).rounded()))%")
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
        completedPanels = 0
        currentPanel = nil
        errorMessage = nil
        analysisTask = Task {
            do {
                let findings = try await DetailedScanAnalysisService.shared.analyze(
                    captures: captures
                ) { completed, _, panel in
                    completedPanels = completed
                    currentPanel = panel
                }
                guard !Task.isCancelled else { return }
                completedPanels = captures.count
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                onComplete(findings)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
