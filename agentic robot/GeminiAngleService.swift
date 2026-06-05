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
    private static let maxRetries = 3
    private static let retryDelays: [Double] = [0, 1.5, 3.0]
    // ──────────────────────────────────────────────────────────────────────

    // MARK: - App slot names (what the UI shows)
    // Left  = the LEFT SIDE slot  → camera stands on the LEFT  of the car → car's RIGHT side faces camera
    // Right = the RIGHT SIDE slot → camera stands on the RIGHT of the car → car's LEFT  side faces camera
    //
    // In plain English:
    //   "Left Side"  photo: you walk to the LEFT of the car and shoot across. BMW badge on right of frame.
    //   "Right Side" photo: you walk to the RIGHT of the car and shoot across. BMW badge on left of frame.
    //
    // We tell Gemini EXACTLY what physical orientation to expect for each slot.
    // No swapping, no mapping — Gemini's answer is used directly.

    enum DetectedAngle: String {
        case front   = "Front"
        case rear    = "Rear"
        case left    = "Left"
        case right   = "Right"
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
            matchesExpectedAngle && confidence >= 0.50 && detectedAngle != .unknown
        }

        var debugSummary: String {
            "Expected=\(expectedAngle.rawValue), Detected=\(detectedAngle.rawValue), Match=\(matchesExpectedAngle), Confidence=\(confidence), Reason=\(reason)"
        }
    }

    private struct ModelAngleResponse: Decodable {
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

    // MARK: - Public API

    static func detectAngle(
        image: UIImage,
        completion: @escaping (DetectedAngle) -> Void
    ) {
        detectAngleDetailed(image: image) { result in
            completion(result.angle)
        }
    }

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
        debugLog("Sending angle request. Expected slot: \(expectedAngle?.rawValue ?? "None")\nPrompt:\n\(prompt)")

        attemptRequest(base64: base64, prompt: prompt, expectedAngle: expectedAngle, attempt: 0, completion: completion)
    }

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
                completion(failureResult(expectedAngle: expectedAngle, reason: "Could not build request."))
                return
            }

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    DispatchQueue.main.async {
                        completion(failureResult(expectedAngle: expectedAngle, reason: error.localizedDescription))
                    }
                    return
                }

                guard let data = data else {
                    DispatchQueue.main.async {
                        completion(failureResult(expectedAngle: expectedAngle, reason: "No data received."))
                    }
                    return
                }

                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorObj = json["error"] as? [String: Any],
                   let code = errorObj["code"] as? Int,
                   code == 503 {
                    let nextAttempt = attempt + 1
                    if nextAttempt < maxRetries {
                        debugLog("503 on attempt \(attempt + 1). Retrying in \(retryDelays[min(nextAttempt, retryDelays.count - 1)])s…")
                        attemptRequest(base64: base64, prompt: prompt, expectedAngle: expectedAngle,
                                       attempt: nextAttempt, completion: completion)
                    } else {
                        DispatchQueue.main.async {
                            completion(failureResult(expectedAngle: expectedAngle,
                                                     reason: "Gemini is temporarily unavailable. Please try again."))
                        }
                    }
                    return
                }

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
                    ["inline_data": ["mime_type": "image/jpeg", "data": base64]],
                    ["text": prompt]
                ]
            ]],
            "generationConfig": [
                "maxOutputTokens": 256,
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
        request.timeoutInterval = 20
        return request
    }

    // MARK: - Response handling

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
            debugLog("Unusable response:\n\(raw)")
            DispatchQueue.main.async {
                completion(failureResult(expectedAngle: expectedAngle, reason: "Gemini did not return a usable response."))
            }
            return
        }

        let text = parts
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            DispatchQueue.main.async {
                completion(failureResult(expectedAngle: expectedAngle, reason: "Gemini returned an empty response."))
            }
            return
        }

        let result = parseValidationResponse(from: text, expectedAngle: expectedAngle)
        debugLog("Raw Gemini text:\n\(text)\n\nParsed: \(result.debugSummary)")
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
    //
    // Rule: bonnet on LEFT side of image = "Left" slot. Bonnet on RIGHT = "Right" slot.
    // No driver-side / vehicle-side reasoning. Pure image-frame position of the bonnet.

    private static func buildPrompt(expectedAngle: DetectedAngle?) -> String {

        let coreRule = """
        You are inspecting a car photo. Your only job is to classify which angle was captured.

        HOW TO CLASSIFY SIDE SHOTS — one simple rule:
        Look at the bonnet (the front hood of the car).
        • If the bonnet is on the LEFT side of the image  → classify as "Left"
        • If the bonnet is on the RIGHT side of the image → classify as "Right"

        HOW TO CLASSIFY FRONT / REAR:
        • You can see the headlights and grille straight-on → classify as "Front"
        • You can see the tail-lights and boot straight-on  → classify as "Rear"

        Do NOT think about which side of the car the driver sits on.
        Do NOT think about physical left/right of the vehicle.
        ONLY look at where the bonnet appears in the image frame.
        """

        if let expectedAngle, expectedAngle != .unknown {

            let check: String
            switch expectedAngle {
            case .left:
                check = """
                EXPECTED SLOT: "Left"
                ACCEPT this photo only if the bonnet is clearly on the LEFT side of the image.
                REJECT if the bonnet is on the right side, or if this is a front/rear shot.
                """
            case .right:
                check = """
                EXPECTED SLOT: "Right"
                ACCEPT this photo only if the bonnet is clearly on the RIGHT side of the image.
                REJECT if the bonnet is on the left side, or if this is a front/rear shot.
                """
            case .front:
                check = """
                EXPECTED SLOT: "Front"
                ACCEPT this photo only if it shows the front grille and headlights straight-on.
                REJECT if it is a side shot or rear shot.
                """
            case .rear:
                check = """
                EXPECTED SLOT: "Rear"
                ACCEPT this photo only if it shows the rear boot and tail-lights straight-on.
                REJECT if it is a side shot or front shot.
                """
            case .unknown:
                check = ""
            }

            return """
            \(coreRule)

            \(check)

            Respond with ONLY this JSON on a single line, no markdown, no explanation:
            {"detectedAngle":"Left","matchesExpectedAngle":true,"confidence":0.95,"reason":"bonnet is on the left side of the image"}
            """
        } else {
            return """
            \(coreRule)

            Classify this image into exactly one of: Front, Rear, Left, Right, Unknown.

            Respond with ONLY this JSON on a single line, no markdown, no explanation:
            {"detectedAngle":"Left","matchesExpectedAngle":true,"confidence":0.95,"reason":"bonnet is on the left side of the image"}
            """
        }
    }

    // MARK: - JSON parsing
    //
    // NO angle mapping/swapping here. Gemini's detectedAngle is the app slot name directly.

    private static func parseValidationResponse(
        from text: String,
        expectedAngle: DetectedAngle?
    ) -> AngleValidationResult {
        let jsonText = extractJSONObject(from: text)
        let expected = expectedAngle ?? .unknown

        if let jsonData = jsonText.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(ModelAngleResponse.self, from: jsonData) {

            let detected = parseDetectedAngle(from: decoded.detectedAngle ?? "")
            let reason = decoded.reason ?? ""
            let rawConfidence = decoded.confidence ?? (detected == .unknown ? 0.0 : 0.60)
            let confidence = min(max(rawConfidence, 0.0), 1.0)

            // Trust Gemini's matchesExpectedAngle, but also do our own direct check.
            // Both must agree for acceptance — this prevents false positives.
            let directMatch = expected != .unknown && detected == expected
            let geminiSaysMatch = decoded.matchesExpectedAngle == true
            // Accept only if BOTH the direct label match AND Gemini's own verdict agree.
            // This catches cases where Gemini's label and its verdict contradict each other.
            let matches: Bool
            if expected == .unknown {
                matches = false
            } else if directMatch && geminiSaysMatch {
                matches = true   // both agree: accept
            } else if !directMatch && !geminiSaysMatch {
                matches = false  // both agree: reject
            } else {
                // They disagree — be conservative and reject
                debugLog("⚠️ Conflict: directMatch=\(directMatch), geminiSaysMatch=\(geminiSaysMatch), detected=\(detected.rawValue), expected=\(expected.rawValue). Rejecting.")
                matches = false
            }

            return AngleValidationResult(expectedAngle: expected,
                                         detectedAngle: detected,
                                         matchesExpectedAngle: matches,
                                         confidence: confidence,
                                         reason: reason,
                                         rawText: text)
        }

        // Fallback: plain text parse
        let detected = parseDetectedAngle(from: text)
        let confidence = detected == .unknown ? 0.0 : 0.60
        let matches = expected != .unknown && detected == expected
        return AngleValidationResult(expectedAngle: expected,
                                     detectedAngle: detected,
                                     matchesExpectedAngle: matches,
                                     confidence: confidence,
                                     reason: "Recovered from non-JSON response.",
                                     rawText: text)
    }

    // MARK: - Helpers

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
