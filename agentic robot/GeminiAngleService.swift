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

    private static let modelName = "gemini-3.5-flash"

    private static let endpoint =
        "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent"

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
            // Gemini's confidence value is self-reported and can be oddly low even
            // when the detected angle is correct. The important part is whether
            // Gemini detected a real angle and whether that angle matches the slot.
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
    /// Instead of asking Gemini to classify blindly, we tell it which slot the user is uploading for.
    /// This is more reliable because Gemini only needs to answer: "is this a valid Front/Rear/Left/Right view?"
    static func validateExpectedAngle(
        image: UIImage,
        expectedAngle: DetectedAngle,
        completion: @escaping (AngleValidationResult) -> Void
    ) {
        sendAngleRequest(image: image, expectedAngle: expectedAngle, completion: completion)
    }

    private static func sendAngleRequest(
        image: UIImage,
        expectedAngle: DetectedAngle?,
        completion: @escaping (AngleValidationResult) -> Void
    ) {
        // Use a larger image and less compression because side/front cues can be small.
        let resized = image.resized(toMaxDimension: 1600)
        guard let jpeg = resized.jpegData(compressionQuality: 0.90) else {
            completion(AngleValidationResult(expectedAngle: expectedAngle ?? .unknown,
                                             detectedAngle: .unknown,
                                             matchesExpectedAngle: false,
                                             confidence: 0.0,
                                             reason: "Could not convert image to JPEG.",
                                             rawText: ""))
            return
        }

        let base64 = jpeg.base64EncodedString()
        let prompt = buildPrompt(expectedAngle: expectedAngle)
        debugLog("Sending angle request. Model: \(modelName). Expected slot: \(expectedAngle?.rawValue ?? "None")")

        // REST request shape follows Google's image-understanding quickstart:
        // - API key is passed through x-goog-api-key header
        // - image part uses inline_data / mime_type
        //
        // Important: do NOT use generationConfig.responseFormat here. On some
        // Gemini API projects/models it rejects application/json with INVALID_ARGUMENT.
        // Instead, we force JSON through a very short prompt and then parse the
        // returned text robustly, even if Gemini adds a prefix or Markdown fence.
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
                // Gemini 3.5 can spend hidden tokens before writing the answer.
                // 256 was too small and caused MAX_TOKENS after only partial JSON,
                // e.g. {"detectedAngle":"Right","matches...
                "maxOutputTokens": 2048,
                "temperature": 0.0,
                "topP": 0.1,
                "topK": 1
            ]
        ]

        guard
            let url = URL(string: endpoint),
            let bodyData = try? JSONSerialization.data(withJSONObject: body)
        else {
            completion(AngleValidationResult(expectedAngle: expectedAngle ?? .unknown,
                                             detectedAngle: .unknown,
                                             matchesExpectedAngle: false,
                                             confidence: 0.0,
                                             reason: "Could not build Gemini request.",
                                             rawText: ""))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = bodyData
        request.timeoutInterval = 40

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard error == nil else {
                DispatchQueue.main.async {
                    completion(AngleValidationResult(expectedAngle: expectedAngle ?? .unknown,
                                                     detectedAngle: .unknown,
                                                     matchesExpectedAngle: false,
                                                     confidence: 0.0,
                                                     reason: error?.localizedDescription ?? "Network error.",
                                                     rawText: ""))
                }
                return
            }

            guard
                let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let candidates = json["candidates"] as? [[String: Any]],
                let content = candidates.first?["content"] as? [String: Any],
                let parts = content["parts"] as? [[String: Any]]
            else {
                let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                debugLog("Gemini returned unusable response:\n\(raw)")
                DispatchQueue.main.async {
                    completion(AngleValidationResult(expectedAngle: expectedAngle ?? .unknown,
                                                     detectedAngle: .unknown,
                                                     matchesExpectedAngle: false,
                                                     confidence: 0.0,
                                                     reason: "Gemini did not return a usable response.",
                                                     rawText: raw))
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
                    completion(AngleValidationResult(expectedAngle: expectedAngle ?? .unknown,
                                                     detectedAngle: .unknown,
                                                     matchesExpectedAngle: false,
                                                     confidence: 0.0,
                                                     reason: "Gemini returned an empty text response.",
                                                     rawText: raw))
                }
                return
            }

            let result = parseValidationResponse(from: text, expectedAngle: expectedAngle)
            let fullRawResponse = String(data: data, encoding: .utf8) ?? ""
            debugLog("Finish reason: \(finishReason)\nRaw Gemini text:\n\(text)\n\nParsed result:\n\(result.debugSummary)\n\nFull API response:\n\(fullRawResponse)")
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

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

            // If Gemini says the angle matches but reports a low/empty confidence,
            // bump the effective confidence enough for the app to accept. This avoids
            // false rejects from Gemini being overly cautious with self-confidence.
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

        // Fallback for malformed/partial JSON. Example:
        // ```json
        // {"detectedAngle":"Right","matches
        // Even though JSON parsing fails, we can still recover the detected angle.
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

        // Handles responses like:
        // ```json
        // { ... }
        // ```
        if let fenced = extractFencedJSON(from: trimmed) {
            return fenced
        }

        // Handles responses like:
        // Here is the JSON requested:
        // { ... }
        if let balanced = extractFirstBalancedJSONObject(from: trimmed) {
            return balanced
        }

        return trimmed
    }

    private static func extractFencedJSON(from text: String) -> String? {
        let pattern = #"```(?:json)?\s*([\s\S]*?)\s*```"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }

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
                if previousWasEscape {
                    previousWasEscape = false
                } else if char == "\\" {
                    previousWasEscape = true
                } else if char == "\"" {
                    isInsideString = false
                }
            } else {
                if char == "\"" {
                    isInsideString = true
                } else if char == "{" {
                    depth += 1
                } else if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(text[start...index])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }

            index = text.index(after: index)
        }

        return nil
    }

    /// Gemini tends to describe Left/Right using the vehicle's physical side.
    /// The app's capture slots use the opposite convention for side photos.
    /// So we flip only side detections; Front/Rear stay unchanged.
    private static func mapGeminiAngleToAppAngle(_ angle: DetectedAngle) -> DetectedAngle {
        switch angle {
        case .left:
            return .right
        case .right:
            return .left
        default:
            return angle
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
        let clean = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

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
