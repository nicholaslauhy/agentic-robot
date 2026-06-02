//
//  GeminiAngleService.swift
//  agentic robot
//
//  Perspective-aware angle validator for Scratch Scan.
//

import UIKit

struct GeminiAngleService {

    // ── Paste your key here ────────────────────────────────────────────────
    private static let apiKey = "AQ.Ab8RN6Lq982WOxRGQffyhjC--Lk9e_WJWr_yBH1IzVw44B4hSw"
    // ──────────────────────────────────────────────────────────────────────

    private static let modelName = "gemini-2.5-flash"

    private static let endpoint =
        "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent"

    // ── Retry configuration ────────────────────────────────────────────────
    // 3 attempts total, backoff: 0s → 1.5s → 3s = max ~4.5s extra wait
    // Combined with a 20s per-attempt timeout, worst case ≈ 20+1.5+20+3+20 = ~64s
    // but in practice 503s resolve after the first retry delay.
    private static let maxRetries = 3
    private static let retryDelays: [Double] = [0, 1.5, 3.0] // seconds before each attempt
    // ──────────────────────────────────────────────────────────────────────

    enum DetectedAngle: String {
        case front = "Front"
        case rear  = "Rear"
        case left  = "Left"
        case right = "Right"
        case unknown = "Unknown"
    }

    struct AngleDetectionResult {
        let angle: DetectedAngle
        let confidence: Double
        let reason: String
        let rawText: String

        var isConfident: Bool {
            confidence >= 0.60 && angle != .unknown
        }
    }

    struct AngleValidationResult {
        let expectedAngle: DetectedAngle
        let detectedAngle: DetectedAngle
        let matchesExpectedAngle: Bool
        let confidence: Double
        let reason: String
        let rawText: String

        var isAccepted: Bool {
            matchesExpectedAngle && confidence >= 0.40 && detectedAngle != .unknown
        }

        var debugSummary: String {
            "Expected=\(expectedAngle.rawValue), Detected=\(detectedAngle.rawValue), Match=\(matchesExpectedAngle), Confidence=\(confidence), Reason=\(reason), Raw=\(rawText)"
        }
    }

    private struct ModelAngleResponse: Decodable {
        let angle: String?
        let detectedAngle: String?
        let matchesExpectedAngle: Bool?
        let confidence: Double?
        let reason: String?
    }

    private static let debugLoggingEnabled = true

    private static func debugLog(_ message: String) {
        guard debugLoggingEnabled else { return }
        print("\n========== GEMINI ANGLE DEBUG ==========")
        print(message)
        print("========================================\n")
    }

    /// Backwards-compatible simple API.
    static func detectAngle(
        image: UIImage,
        completion: @escaping (DetectedAngle) -> Void
    ) {
        detectAngleDetailed(image: image) { result in
            completion(result.angle)
        }
    }

    /// General classifier. Prefer validateExpectedAngle(image:expectedAngle:) for upload validation.
    static func detectAngleDetailed(
        image: UIImage,
        completion: @escaping (AngleDetectionResult) -> Void
    ) {
        sendAngleRequest(image: image, expectedAngle: nil) { result in
            completion(AngleDetectionResult(angle: result.detectedAngle,
                                            confidence: result.confidence,
                                            reason: result.reason,
                                            rawText: result.rawText))
        }
    }

    /// Best API for the app flow.
    static func validateExpectedAngle(
        image: UIImage,
        expectedAngle: DetectedAngle,
        completion: @escaping (AngleValidationResult) -> Void
    ) {
        sendAngleRequest(image: image, expectedAngle: expectedAngle, completion: completion)
    }

    // MARK: - Core request with retry

    private static func sendAngleRequest(
        image: UIImage,
        expectedAngle: DetectedAngle?,
        completion: @escaping (AngleValidationResult) -> Void
    ) {
        let resized = image.resized(toMaxDimension: 1600)
        guard let jpeg = resized.jpegData(compressionQuality: 0.90) else {
            completion(failureResult(expectedAngle: expectedAngle, reason: "Could not convert image to JPEG."))
            return
        }

        let base64 = jpeg.base64EncodedString()
        let prompt = buildPrompt(expectedAngle: expectedAngle)
        debugLog("Sending angle request. Model: \(modelName). Expected slot: \(expectedAngle?.rawValue ?? "None")")

        attemptRequest(base64: base64,
                       prompt: prompt,
                       expectedAngle: expectedAngle,
                       attempt: 0,
                       completion: completion)
    }

    /// Recursive retry with delay. Retries only on 503 (UNAVAILABLE) responses.
    private static func attemptRequest(
        base64: String,
        prompt: String,
        expectedAngle: DetectedAngle?,
        attempt: Int,
        completion: @escaping (AngleValidationResult) -> Void
    ) {
        let delay = retryDelays[min(attempt, retryDelays.count - 1)]

        let execute = {
            guard let request = buildURLRequest(base64: base64, prompt: prompt) else {
                completion(failureResult(expectedAngle: expectedAngle, reason: "Could not build Gemini request."))
                return
            }

            URLSession.shared.dataTask(with: request) { data, response, error in
                // Network-level error — no retry (likely a timeout or connectivity issue)
                if let error = error {
                    DispatchQueue.main.async {
                        completion(failureResult(expectedAngle: expectedAngle,
                                                 reason: error.localizedDescription))
                    }
                    return
                }

                guard let data = data else {
                    DispatchQueue.main.async {
                        completion(failureResult(expectedAngle: expectedAngle, reason: "No data received."))
                    }
                    return
                }

                // Check for a retryable 503 error in the JSON body
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorObj = json["error"] as? [String: Any],
                   let code = errorObj["code"] as? Int,
                   code == 503 {

                    let nextAttempt = attempt + 1
                    if nextAttempt < maxRetries {
                        debugLog("Attempt \(attempt + 1)/\(maxRetries) got 503. Retrying in \(retryDelays[min(nextAttempt, retryDelays.count - 1)])s…")
                        attemptRequest(base64: base64,
                                       prompt: prompt,
                                       expectedAngle: expectedAngle,
                                       attempt: nextAttempt,
                                       completion: completion)
                    } else {
                        let raw = String(data: data, encoding: .utf8) ?? ""
                        debugLog("All \(maxRetries) attempts exhausted. Last error:\n\(raw)")
                        DispatchQueue.main.async {
                            completion(failureResult(expectedAngle: expectedAngle,
                                                     reason: "Gemini is temporarily unavailable. Please try again shortly."))
                        }
                    }
                    return
                }

                // Normal parse path
                handleResponse(data: data, expectedAngle: expectedAngle, completion: completion)

            }.resume()
        }

        if delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: execute)
        } else {
            execute()
        }
    }

    // MARK: - Request builder

    private static func buildURLRequest(base64: String, prompt: String) -> URLRequest? {
        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    [
                        "inline_data": [
                            "mime_type": "image/jpeg",
                            "data": base64
                        ]
                    ],
                    ["text": prompt]
                ]
            ]],
            "generationConfig": [
                "maxOutputTokens": 2048,
                "temperature": 0.0,
                "topP": 0.1,
                "topK": 1
            ]
        ]

        guard
            let url = URL(string: endpoint),
            let bodyData = try? JSONSerialization.data(withJSONObject: body)
        else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = bodyData
        request.timeoutInterval = 20   // Shorter per-attempt timeout (was 40s)
        return request
    }

    // MARK: - Response parsing

    private static func handleResponse(
        data: Data,
        expectedAngle: DetectedAngle?,
        completion: @escaping (AngleValidationResult) -> Void
    ) {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]]
        else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            debugLog("Gemini returned unusable response:\n\(raw)")
            DispatchQueue.main.async {
                completion(failureResult(expectedAngle: expectedAngle,
                                         reason: "Gemini did not return a usable response."))
            }
            return
        }

        let finishReason = candidates.first?["finishReason"] as? String ?? "unknown"
        let text = parts
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            debugLog("Gemini returned parts but no text:\n\(raw)")
            DispatchQueue.main.async {
                completion(failureResult(expectedAngle: expectedAngle,
                                         reason: "Gemini returned an empty text response."))
            }
            return
        }

        let result = parseValidationResponse(from: text, expectedAngle: expectedAngle)
        let fullRawResponse = String(data: data, encoding: .utf8) ?? ""
        debugLog("Finish reason: \(finishReason)\nRaw Gemini text:\n\(text)\n\nParsed result:\n\(result.debugSummary)\n\nFull API response:\n\(fullRawResponse)")
        DispatchQueue.main.async { completion(result) }
    }

    private static func failureResult(expectedAngle: DetectedAngle?, reason: String) -> AngleValidationResult {
        AngleValidationResult(expectedAngle: expectedAngle ?? .unknown,
                              detectedAngle: .unknown,
                              matchesExpectedAngle: false,
                              confidence: 0.0,
                              reason: reason,
                              rawText: "")
    }

    // MARK: - Prompt

    private static func buildPrompt(expectedAngle: DetectedAngle?) -> String {
        let expectedLine: String
        if let expectedAngle, expectedAngle != .unknown {
            expectedLine = "Expected upload slot: \(expectedAngle.rawValue). Decide whether the image is valid for this expected slot."
        } else {
            expectedLine = "No expected slot was provided. Classify the uploaded car photo."
        }

        return """
        You are validating a car inspection photo. Look only at the main car.

        \(expectedLine)

        Classify the visible view as exactly one of:
        Front, Rear, Left, Right, Unknown.

        App convention:
        Front = front grille/headlights/bonnet view.
        Rear = rear boot/tail lights view.
        Left = the app's Left Side slot.
        Right = the app's Right Side slot.

        Important side rule:
        The app's side convention is opposite of the vehicle's physical left/right.
        So if normal vehicle-side reasoning says Right, the app wants Left.
        If normal vehicle-side reasoning says Left, the app wants Right.

        Be lenient. Slight diagonal/3-quarter views are okay.
        Never include Markdown fences or explanations.
        Return only this JSON, one line:
        {"detectedAngle":"Front","matchesExpectedAngle":true,"confidence":0.9,"reason":"front view"}
        """
    }

    // MARK: - JSON parsing

    private static func parseValidationResponse(
        from text: String,
        expectedAngle: DetectedAngle?
    ) -> AngleValidationResult {
        let jsonText = extractJSONObject(from: text)
        let expected = expectedAngle ?? .unknown

        if let jsonData = jsonText.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(ModelAngleResponse.self, from: jsonData) {
            let geminiDetected = parseDetectedAngle(from: decoded.detectedAngle ?? decoded.angle ?? "")
            let detected = mapGeminiAngleToAppAngle(geminiDetected)
            let reason = decoded.reason ?? ""

            let directMatch = expected != .unknown && detected == expected
            let modelSaidMatch = expected != .unknown && decoded.matchesExpectedAngle == true && detected != .unknown
            let matches = directMatch || modelSaidMatch

            let rawConfidence = decoded.confidence ?? (detected == .unknown ? 0.0 : 0.60)
            let adjustedConfidence = matches ? max(rawConfidence, 0.60) : rawConfidence
            let confidence = min(max(adjustedConfidence, 0.0), 1.0)

            return AngleValidationResult(expectedAngle: expected,
                                         detectedAngle: detected,
                                         matchesExpectedAngle: matches,
                                         confidence: confidence,
                                         reason: appendSideMappingNote(reason, geminiDetected: geminiDetected, appDetected: detected),
                                         rawText: text)
        }

        let geminiDetected = parseDetectedAngle(from: text)
        let detected = mapGeminiAngleToAppAngle(geminiDetected)
        let confidence = detected == .unknown ? 0.0 : 0.60
        let matches = expected != .unknown && detected == expected
        return AngleValidationResult(expectedAngle: expected,
                                     detectedAngle: detected,
                                     matchesExpectedAngle: matches,
                                     confidence: confidence,
                                     reason: appendSideMappingNote("Recovered from partial Gemini JSON.",
                                                                   geminiDetected: geminiDetected,
                                                                   appDetected: detected),
                                     rawText: text)
    }

    private static func extractJSONObject(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fenced = extractFencedJSON(from: trimmed) { return fenced }
        if let balanced = extractFirstBalancedJSONObject(from: trimmed) { return balanced }
        return trimmed
    }

    private static func extractFencedJSON(from text: String) -> String? {
        let pattern = #"```(?:json)?\s*([\s\S]*?)\s*```"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let insideFence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return extractFirstBalancedJSONObject(from: insideFence) ?? insideFence
    }

    private static func extractFirstBalancedJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var isInsideString = false
        var previousWasEscape = false
        var index = start
        while index < text.endIndex {
            let char = text[index]
            if isInsideString {
                if previousWasEscape { previousWasEscape = false }
                else if char == "\\" { previousWasEscape = true }
                else if char == "\"" { isInsideString = false }
            } else {
                if char == "\"" { isInsideString = true }
                else if char == "{" { depth += 1 }
                else if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(text[start...index]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func mapGeminiAngleToAppAngle(_ angle: DetectedAngle) -> DetectedAngle {
        switch angle {
        case .left:  return .right
        case .right: return .left
        default:     return angle
        }
    }

    private static func appendSideMappingNote(
        _ reason: String,
        geminiDetected: DetectedAngle,
        appDetected: DetectedAngle
    ) -> String {
        guard geminiDetected != appDetected else { return reason }
        let base = reason.isEmpty ? "Side mapped to app convention." : reason
        return "\(base) Gemini=\(geminiDetected.rawValue), App=\(appDetected.rawValue)."
    }

    private static func parseDetectedAngle(from text: String) -> DetectedAngle {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.contains("front") { return .front }
        if clean.contains("rear") || clean.contains("back") { return .rear }
        if clean.contains("left") { return .left }
        if clean.contains("right") { return .right }
        return .unknown
    }
}

private extension UIImage {
    func resized(toMaxDimension maxDim: CGFloat) -> UIImage {
        let scale = maxDim / max(size.width, size.height)
        guard scale < 1 else { return self }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
