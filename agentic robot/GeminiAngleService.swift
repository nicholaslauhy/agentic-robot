//
//  GeminiAngleService.swift
//  agentic robot
//
//  OpenAI-powered vehicle photo validator for Scratch Scan.
//  The class name is kept as GeminiAngleService so existing app calls do not need to change.
//

import UIKit

struct GeminiAngleService {

    // IMPORTANT:
    // Do NOT ship a real API key inside an iOS app for production.
    // For testing only, paste your new OpenAI key here.
    // Production: iOS app -> your backend -> OpenAI.
    private static let apiKey = "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"

    private static let modelName = "gpt-4o"
    private static let endpoint = "https://api.openai.com/v1/chat/completions"

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

        let carPresent: Bool
        let wholeVehicleVisible: Bool
        let visibilityScore: Double

        let isStraightEnough: Bool
        let straightnessScore: Double
        let perspectiveIssue: String
        let reason: String
        let rawText: String

        var isAccepted: Bool {
            guard carPresent else { return false }
            guard matchesExpectedAngle else { return false }

            switch expectedAngle {
            case .rear:
                // Rear is intentionally lenient: if the rear face is detected and straight enough,
                // do not fail just because the model gave low generic confidence/visibility scores.
                return isStraightEnough || straightnessScore >= 0.40
            case .front:
                guard confidence >= requiredConfidence(for: expectedAngle) else { return false }
                guard visibilityScore >= requiredVisibility(for: expectedAngle) else { return false }
                guard straightnessScore >= requiredStraightness(for: expectedAngle) else { return false }
                return wholeVehicleVisible && isStraightEnough
            case .left, .right:
                guard confidence >= requiredConfidence(for: expectedAngle) else { return false }
                guard visibilityScore >= requiredVisibility(for: expectedAngle) else { return false }
                guard straightnessScore >= requiredStraightness(for: expectedAngle) else { return false }
                // Side slots must show enough of the whole side profile for later bbox calibration.
                return wholeVehicleVisible && isStraightEnough
            case .unknown:
                guard confidence >= requiredConfidence(for: expectedAngle) else { return false }
                guard visibilityScore >= requiredVisibility(for: expectedAngle) else { return false }
                guard straightnessScore >= requiredStraightness(for: expectedAngle) else { return false }
                return wholeVehicleVisible && isStraightEnough && detectedAngle != .unknown
            }
        }

        var debugSummary: String {
            "Expected=\(expectedAngle.rawValue), Detected=\(detectedAngle.rawValue), Match=\(matchesExpectedAngle), Confidence=\(confidence), CarPresent=\(carPresent), Visible=\(wholeVehicleVisible), VisibilityScore=\(visibilityScore), Straight=\(isStraightEnough), StraightnessScore=\(straightnessScore), Perspective=\(perspectiveIssue), Reason=\(reason)"
        }

        private func requiredConfidence(for angle: DetectedAngle) -> Double {
            switch angle {
            case .rear: return 0.35
            case .front: return 0.50
            case .left, .right: return 0.50
            case .unknown: return 0.50
            }
        }

        private func requiredVisibility(for angle: DetectedAngle) -> Double {
            switch angle {
            case .rear:
                // Accept rear photos where the rear face is clearly visible even if the model complains
                // that the whole car length is not visible.
                return 0.35
            case .front:
                return 0.60
            case .left, .right:
                return 0.68
            case .unknown:
                return 0.65
            }
        }

        private func requiredStraightness(for angle: DetectedAngle) -> Double {
            switch angle {
            case .rear:
                return 0.35
            case .front:
                return 0.62
            case .left, .right:
                return 0.72
            case .unknown:
                return 0.62
            }
        }
    }

    private struct ModelAngleResponse: Decodable {
        let carPresent: Bool?
        let wholeVehicleVisible: Bool?
        let visibilityScore: Double?
        let detectedAngle: String?
        let matchesExpectedAngle: Bool?
        let confidence: Double?
        let isStraightEnough: Bool?
        let straightnessScore: Double?
        let perspectiveIssue: String?
        let sideFrontPosition: String?
        let cameraSideDirection: String?
        let frontIsOnImageLeft: Bool?
        let frontIsOnImageRight: Bool?
        let frontEndX: Double?
        let rearEndX: Double?
        let bonnetEndX: Double?
        let bootEndX: Double?
        let sideProfileScore: Double?
        let isThreeQuarterSideView: Bool?
        let reason: String?
    }

    private static let debugLoggingEnabled = true

    private static func debugLog(_ message: String) {
        guard debugLoggingEnabled else { return }
        print("\n========== VEHICLE PHOTO VALIDATION DEBUG ==========")
        print(message)
        print("===================================================\n")
    }

    // MARK: - Public API

    static func detectAngle(image: UIImage, completion: @escaping (DetectedAngle) -> Void) {
        detectAngleDetailed(image: image) { result in
            completion(result.angle)
        }
    }

    static func detectAngleDetailed(image: UIImage, completion: @escaping (AngleDetectionResult) -> Void) {
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

    // MARK: - Request

    private static func sendAngleRequest(
        image: UIImage,
        expectedAngle: DetectedAngle?,
        completion: @escaping (AngleValidationResult) -> Void
    ) {
        guard apiKey != "PASTE_YOUR_OPENAI_API_KEY_HERE",
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(failureResult(expectedAngle: expectedAngle,
                                     reason: "OpenAI API key is missing. Paste your new key into GeminiAngleService.swift or call your backend proxy."))
            return
        }

        let resized = image.resized(toMaxDimension: 1600)
        guard let jpeg = resized.jpegData(compressionQuality: 0.90) else {
            completion(failureResult(expectedAngle: expectedAngle, reason: "Could not convert image to JPEG."))
            return
        }

        let base64 = jpeg.base64EncodedString()
        let prompt = buildPrompt(expectedAngle: expectedAngle)
        debugLog("Expected slot: \(expectedAngle?.rawValue ?? "None")\nPrompt:\n\(prompt)")

        guard let request = buildURLRequest(base64: base64, prompt: prompt) else {
            completion(failureResult(expectedAngle: expectedAngle, reason: "Could not build OpenAI request."))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(failureResult(expectedAngle: expectedAngle, reason: error.localizedDescription))
                }
                return
            }

            guard let data else {
                DispatchQueue.main.async {
                    completion(failureResult(expectedAngle: expectedAngle, reason: "No data received from OpenAI."))
                }
                return
            }

            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                let raw = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    completion(failureResult(expectedAngle: expectedAngle, reason: "OpenAI HTTP \(http.statusCode): \(raw)"))
                }
                return
            }

            handleResponse(data: data, expectedAngle: expectedAngle, completion: completion)
        }.resume()
    }

    private static func buildURLRequest(base64: String, prompt: String) -> URLRequest? {
        let body: [String: Any] = [
            "model": modelName,
            "temperature": 0,
            "max_tokens": 800,
            "response_format": ["type": "json_object"],
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    [
                        "type": "image_url",
                        "image_url": [
                            "url": "data:image/jpeg;base64,\(base64)",
                            "detail": "high"
                        ]
                    ]
                ]
            ]]
        ]

        guard let url = URL(string: endpoint),
              let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        request.timeoutInterval = 18
        return request
    }

    // MARK: - Response handling

    private static func handleResponse(
        data: Data,
        expectedAngle: DetectedAngle?,
        completion: @escaping (AngleValidationResult) -> Void
    ) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            debugLog("Unexpected API response:\n\(raw)")
            DispatchQueue.main.async {
                completion(failureResult(expectedAngle: expectedAngle, reason: "OpenAI returned an unexpected response format."))
            }
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = parseValidationResponse(from: trimmed, expectedAngle: expectedAngle)
        debugLog("Raw OpenAI text:\n\(trimmed)\n\nParsed: \(result.debugSummary)")
        DispatchQueue.main.async { completion(result) }
    }

    private static func failureResult(expectedAngle: DetectedAngle?, reason: String) -> AngleValidationResult {
        AngleValidationResult(expectedAngle: expectedAngle ?? .unknown,
                              detectedAngle: .unknown,
                              matchesExpectedAngle: false,
                              confidence: 0.0,
                              carPresent: false,
                              wholeVehicleVisible: false,
                              visibilityScore: 0.0,
                              isStraightEnough: false,
                              straightnessScore: 0.0,
                              perspectiveIssue: reason,
                              reason: reason,
                              rawText: "")
    }

    // MARK: - Prompt

    private static func buildPrompt(expectedAngle: DetectedAngle?) -> String {
        return """
        You are objectively describing ONE vehicle inspection photo for an iOS app.

        CRITICAL RULE: You are NOT told what angle is expected. Describe exactly what
        you see in the photo, with no bias toward any particular answer. There is no
        "correct" answer to satisfy — just report what is actually in the image.
        Return ONLY valid JSON. No markdown. No extra text.

        IMAGE COORDINATES:
        - The left edge of the photo is x=0.
        - The right edge of the photo is x=100.
        - All left/right decisions refer ONLY to the photo coordinates.
        - Do NOT use driver side, passenger side, Singapore road side, steering wheel side, or the real-world left/right side of the vehicle.

        IMPORTANT WORDING:
        - For side photos, DO NOT think about "front side" of the vehicle.
        - Use the word BONNET/HOOD/NOSE END instead.
        - The BONNET END means the end with bonnet/hood, headlights, grille, front bumper, front wheel arch, and windscreen sloping back from the bonnet.
        - The BOOT END means the end with boot/trunk, tail-lights, rear bumper, rear windscreen/C-pillar.

        SIDE SLOT DEFINITIONS FOR THIS APP:
        - LEFT SIDE photo = the BONNET END is on the LEFT side of the IMAGE.
          This must mean bonnetEndX < bootEndX, frontEndX < rearEndX, sideFrontPosition="left".
        - RIGHT SIDE photo = the BONNET END is on the RIGHT side of the IMAGE.
          This must mean bonnetEndX > bootEndX, frontEndX > rearEndX, sideFrontPosition="right".
        - A side photo can NEVER be both left and right.
        - If the bonnet/hood/headlights are on image-right, it is RIGHT SIDE for this app, even if you think it is the car's real-world left side.
        - If the bonnet/hood/headlights are on image-left, it is LEFT SIDE for this app, even if you think it is the car's real-world right side.
        - If you cannot clearly locate the bonnet end and boot end, return detectedAngle="Unknown" and sideFrontPosition="unknown".

        SIDE STRAIGHTNESS / CALIBRATION RULE:
        - For side photos, be strict. A valid photo must be a mostly straight side profile.
        - Reject diagonal side-corner / 3-quarter / perspective views.
        - If one end is much closer/larger than the other, set isThreeQuarterSideView=true, isStraightEnough=false, straightnessScore below 0.70, sideProfileScore below 0.70.
        - A valid side profile should show both bonnet end and boot end, with the car side nearly parallel to the image plane.

        FRONT / REAR RULES:
        - Front means grille/headlights/front bumper face the camera.
        - Rear means tail-lights/boot/rear bumper face the camera.
        - For rear, DO NOT require a side view and DO NOT require the full car length.
        - For rear, wholeVehicleVisible=true when the rear face is visible enough: tail-lights, boot and rear bumper can be seen.
        - For rear, do NOT mark cropped simply because only the rear face is shown. That is correct for Rear.
        - For rear, allow slight off-centre or handheld framing. Only reject obvious rear-corner 3-quarter views, heavy slant, or strong perspective.
        - The phrase "not a side view" is NOT a problem for a Rear image.

        CAR PRESENCE / VISIBILITY:
        - carPresent=false if there is no real car/vehicle in frame.
        - Reject empty carparks, walls, pillars, random objects, people, motorcycles only, close-up parts only, drawings, screenshots, or toys.
        - For side photos, wholeVehicleVisible=true only if both bonnet end and boot end are visible enough for calibration. Small margins cut off are okay.
        - For front/rear, wholeVehicleVisible=true if the respective face is sufficiently visible.

        Required JSON schema:
        {
          "carPresent": true,
          "wholeVehicleVisible": true,
          "visibilityScore": 0.0,
          "detectedAngle": "Unknown",
          "matchesExpectedAngle": false,
          "confidence": 0.0,
          "isStraightEnough": true,
          "straightnessScore": 0.0,
          "perspectiveIssue": "None",
          "sideFrontPosition": "unknown",
          "cameraSideDirection": "unknown",
          "frontIsOnImageLeft": false,
          "frontIsOnImageRight": false,
          "frontEndX": null,
          "rearEndX": null,
          "bonnetEndX": null,
          "bootEndX": null,
          "sideProfileScore": 0.0,
          "isThreeQuarterSideView": false,
          "reason": "short reason"
        }

        Allowed detectedAngle values: "Front", "Rear", "Left", "Right", "Unknown".
        Allowed sideFrontPosition values: "left", "right", "unknown".
        Allowed cameraSideDirection values: "bonnet_on_image_left", "bonnet_on_image_right", "unknown".

        Examples:
        - Bonnet/headlights on image-left and boot/tail-lights on image-right: detectedAngle="Left", sideFrontPosition="left", cameraSideDirection="bonnet_on_image_left", frontIsOnImageLeft=true, frontIsOnImageRight=false, bonnetEndX < bootEndX, frontEndX < rearEndX.
        - Bonnet/headlights on image-right and boot/tail-lights on image-left: detectedAngle="Right", sideFrontPosition="right", cameraSideDirection="bonnet_on_image_right", frontIsOnImageLeft=false, frontIsOnImageRight=true, bonnetEndX > bootEndX, frontEndX > rearEndX.
        - Clear rear face with tail-lights/boot/rear bumper: detectedAngle="Rear", wholeVehicleVisible=true, visibilityScore at least 0.70, confidence at least 0.70. Do not complain that it is not a side view.
        """
    }

    // MARK: - JSON parsing and final enforcement

    private static func parseValidationResponse(from text: String, expectedAngle: DetectedAngle?) -> AngleValidationResult {
        let jsonText = extractJSONObject(from: text)
        let expected = expectedAngle ?? .unknown

        guard let jsonData = jsonText.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ModelAngleResponse.self, from: jsonData) else {
            return failureResult(expectedAngle: expectedAngle, reason: "Could not parse validation JSON. Please retake or use Override if needed. Raw: \(text)")
        }

        let carPresent = decoded.carPresent == true
        var visibilityScore = clamp01(decoded.visibilityScore ?? 0.0)
        var confidence = clamp01(decoded.confidence ?? 0.0)
        var rawStraightnessScore = clamp01(decoded.straightnessScore ?? 0.0)
        let sideProfileScore = clamp01(decoded.sideProfileScore ?? 0.0)
        let isThreeQuarterSideView = decoded.isThreeQuarterSideView == true
        let perspectiveIssue = decoded.perspectiveIssue ?? "None"
        let modelReason = decoded.reason ?? ""

        let coordinateSide = inferSideFrontPosition(frontEndX: decoded.frontEndX, rearEndX: decoded.rearEndX, bonnetEndX: decoded.bonnetEndX, bootEndX: decoded.bootEndX)
        let textSide = normalizeSideFrontPosition(decoded.sideFrontPosition)
        let cameraDirectionSide = normalizeCameraSideDirection(decoded.cameraSideDirection)
        let booleanSide = inferSideFromBooleans(left: decoded.frontIsOnImageLeft, right: decoded.frontIsOnImageRight)
        let rawDetected = parseDetectedAngle(from: decoded.detectedAngle ?? "")

        // Rear images were being rejected when the model correctly said "Rear" but gave
        // confidence/visibility 0 because it was thinking about side-view requirements.
        // For the Rear slot, a clear rear face is enough.
        if expected == .rear && rawDetected == .rear && carPresent {
            confidence = max(confidence, 0.75)
            visibilityScore = max(visibilityScore, 0.75)
            rawStraightnessScore = max(rawStraightnessScore, 0.55)
        }

        let angleSide: String
        if rawDetected == .left {
            angleSide = "left"
        } else if rawDetected == .right {
            angleSide = "right"
        } else {
            angleSide = "unknown"
        }

        let finalSide = consensusSide(
            coordinateSide: coordinateSide,
            textSide: textSide,
            cameraDirectionSide: cameraDirectionSide,
            booleanSide: booleanSide,
            angleSide: angleSide,
            sideProfileScore: sideProfileScore,
            frontEndX: decoded.frontEndX,
            rearEndX: decoded.rearEndX,
            bonnetEndX: decoded.bonnetEndX,
            bootEndX: decoded.bootEndX
        )

        var detected = rawDetected
        if finalSide == "left" {
            detected = .left
        } else if finalSide == "right" {
            detected = .right
        }

        let matches: Bool
        switch expected {
        case .left:
            matches = finalSide == "left" && detected == .left && sideProfileScore >= 0.70
        case .right:
            matches = finalSide == "right" && detected == .right && sideProfileScore >= 0.70
        case .front:
            matches = detected == .front
        case .rear:
            matches = detected == .rear
        case .unknown:
            matches = detected != .unknown
        }

        let wholeVisible: Bool
        switch expected {
        case .rear:
            // Do not let the model reject a rear photo as "cropped" when it can clearly see the rear face.
            // The rear slot only needs the rear face; it does not need the full side length of the car.
            wholeVisible = carPresent && (detected == .rear || decoded.wholeVehicleVisible == true || visibilityScore >= 0.35)
        case .front:
            wholeVisible = carPresent && (decoded.wholeVehicleVisible == true || visibilityScore >= 0.60)
        case .left, .right:
            wholeVisible = carPresent && decoded.wholeVehicleVisible == true && visibilityScore >= 0.68 && sideProfileScore >= 0.70
        case .unknown:
            wholeVisible = carPresent && (decoded.wholeVehicleVisible == true || visibilityScore >= 0.65)
        }

        var hardPerspectiveReject = isThreeQuarterSideView || containsHardPerspectiveReject(reason: modelReason, perspectiveIssue: perspectiveIssue)
        if expected == .rear {
            // "not a side view" is correct for rear. Do not use that phrase to reject rear images.
            hardPerspectiveReject = containsHardRearPerspectiveReject(reason: modelReason, perspectiveIssue: perspectiveIssue)
        }
        let straightnessScore: Double
        let isStraight: Bool

        switch expected {
        case .rear:
            straightnessScore = rawStraightnessScore
            // Rear is allowed to be slightly off-centre. Only reject obvious 3/4 rear-corner / strong slant.
            isStraight = !hardPerspectiveReject && (decoded.isStraightEnough == true || rawStraightnessScore >= 0.35)
        case .front:
            straightnessScore = rawStraightnessScore
            isStraight = !hardPerspectiveReject && (decoded.isStraightEnough == true || rawStraightnessScore >= 0.62)
        case .left, .right:
            straightnessScore = min(rawStraightnessScore, sideProfileScore)
            // Strict for calibration: a very angled side/corner shot must not pass.
            isStraight = !hardPerspectiveReject && decoded.isStraightEnough == true && rawStraightnessScore >= 0.78 && sideProfileScore >= 0.75
        case .unknown:
            straightnessScore = rawStraightnessScore
            isStraight = !hardPerspectiveReject && (decoded.isStraightEnough == true || rawStraightnessScore >= 0.62)
        }

        let reason = buildFinalReason(expected: expected,
                                      detected: detected,
                                      carPresent: carPresent,
                                      wholeVisible: wholeVisible,
                                      visibilityScore: visibilityScore,
                                      matches: matches,
                                      finalSide: finalSide,
                                      isStraight: isStraight,
                                      straightnessScore: straightnessScore,
                                      modelReason: modelReason)

        return AngleValidationResult(expectedAngle: expected,
                                     detectedAngle: detected,
                                     matchesExpectedAngle: matches,
                                     confidence: confidence,
                                     carPresent: carPresent,
                                     wholeVehicleVisible: wholeVisible,
                                     visibilityScore: visibilityScore,
                                     isStraightEnough: isStraight,
                                     straightnessScore: straightnessScore,
                                     perspectiveIssue: perspectiveIssue,
                                     reason: reason,
                                     rawText: text)
    }

    private static func buildFinalReason(
        expected: DetectedAngle,
        detected: DetectedAngle,
        carPresent: Bool,
        wholeVisible: Bool,
        visibilityScore: Double,
        matches: Bool,
        finalSide: String,
        isStraight: Bool,
        straightnessScore: Double,
        modelReason: String
    ) -> String {
        if !carPresent {
            return "No car was detected in the photo. Please retake or choose another photo."
        }

        if expected == .left && !matches {
            if finalSide == "right" {
                return "Wrong side. This photo is Right Side because the car front is on the right side of the image. Left Side requires the car front on the left."
            }
            return "Could not confirm Left Side. Left Side requires a clear side profile with the car front on the left side of the image."
        }

        if expected == .right && !matches {
            if finalSide == "left" {
                return "Wrong side. This photo is Left Side because the car front is on the left side of the image. Right Side requires the car front on the right."
            }
            return "Could not confirm Right Side. Right Side requires a clear side profile with the car front on the right side of the image."
        }

        if !wholeVisible {
            switch expected {
            case .rear:
                return "The rear face is not visible enough. Please make sure the tail-lights, boot and rear bumper can be seen."
            case .front:
                return "The front face is not visible enough. Please make sure the headlights, grille and front bumper can be seen."
            case .left, .right:
                return "The side profile is not visible enough. Please include the car from front end to rear end."
            case .unknown:
                return "The vehicle is not visible enough for inspection."
            }
        }

        if !matches {
            return "Wrong angle. Expected \(expected.rawValue), but detected \(detected.rawValue)."
        }

        if !isStraight {
            return "The vehicle is too angled/slanted for calibration. Please retake it more straight-on."
        }

        if !modelReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return modelReason
        }

        return "Photo accepted. Visibility \(Int(visibilityScore * 100))%, straightness \(Int(straightnessScore * 100))%."
    }

    private static func consensusSide(
        coordinateSide: String,
        textSide: String,
        cameraDirectionSide: String,
        booleanSide: String,
        angleSide: String,
        sideProfileScore: Double,
        frontEndX: Double?,
        rearEndX: Double?,
        bonnetEndX: Double?,
        bootEndX: Double?
    ) -> String {
        guard sideProfileScore >= 0.70 else { return "unknown" }

        // Most important fix: do NOT let a vague text label make Left pass.
        // The final side is based primarily on bonnet/boot or front/rear x-coordinates.
        if coordinateSide != "unknown" {
            return coordinateSide
        }

        // Fallback only when coordinates are missing: require all non-coordinate text signals to agree.
        let signals = [textSide, cameraDirectionSide, booleanSide, angleSide]
            .filter { $0 == "left" || $0 == "right" }

        let leftCount = signals.filter { $0 == "left" }.count
        let rightCount = signals.filter { $0 == "right" }.count

        if leftCount >= 3 && rightCount == 0 { return "left" }
        if rightCount >= 3 && leftCount == 0 { return "right" }

        return "unknown"
    }

    private static func normalizeCameraSideDirection(_ value: String?) -> String {
        let clean = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.contains("bonnet_on_image_left") || clean.contains("bonnet on image left") || clean.contains("front_on_image_left") || clean.contains("front on image left") || clean.contains("front is on image left") { return "left" }
        if clean.contains("bonnet_on_image_right") || clean.contains("bonnet on image right") || clean.contains("front_on_image_right") || clean.contains("front on image right") || clean.contains("front is on image right") { return "right" }
        return "unknown"
    }

    private static func inferSideFromBooleans(left: Bool?, right: Bool?) -> String {
        if left == true && right != true { return "left" }
        if right == true && left != true { return "right" }
        return "unknown"
    }

    private static func normalizeSideFrontPosition(_ value: String?) -> String {
        let clean = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean == "left" || clean == "image_left" || clean.contains("front on left") || clean.contains("front is on the left") { return "left" }
        if clean == "right" || clean == "image_right" || clean.contains("front on right") || clean.contains("front is on the right") { return "right" }
        return "unknown"
    }

    private static func inferSideFrontPosition(frontEndX: Double?, rearEndX: Double?, bonnetEndX: Double?, bootEndX: Double?) -> String {
        // Prefer bonnet/boot coordinates because the word "front" caused ambiguous model answers.
        if let bonnetEndX, let bootEndX {
            let bonnet = max(0.0, min(100.0, bonnetEndX))
            let boot = max(0.0, min(100.0, bootEndX))
            let gap = abs(bonnet - boot)
            guard gap >= 25 else { return "unknown" }
            return bonnet < boot ? "left" : "right"
        }

        guard let frontEndX, let rearEndX else { return "unknown" }

        let front = max(0.0, min(100.0, frontEndX))
        let rear = max(0.0, min(100.0, rearEndX))
        let gap = abs(front - rear)

        guard gap >= 25 else { return "unknown" }

        return front < rear ? "left" : "right"
    }

    private static func parseDetectedAngle(from text: String) -> DetectedAngle {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.contains("front") { return .front }
        if clean.contains("rear") || clean.contains("back") { return .rear }
        if clean.contains("left") { return .left }
        if clean.contains("right") { return .right }
        return .unknown
    }

    private static func containsHardRearPerspectiveReject(reason: String, perspectiveIssue: String) -> Bool {
        let combined = "\(reason) \(perspectiveIssue)".lowercased()
        let hardTerms = [
            "obvious 3/4", "clear 3/4", "three-quarter rear", "three quarter rear",
            "rear-corner", "rear corner", "strong diagonal", "strong perspective",
            "severe perspective", "keystone", "heavily slanted", "very slanted", "too slanted"
        ]
        return hardTerms.contains(where: { combined.contains($0) })
    }

    private static func containsHardPerspectiveReject(reason: String, perspectiveIssue: String) -> Bool {
        let combined = "\(reason) \(perspectiveIssue)".lowercased()

        let mildTerms = [
            "none", "slight", "slightly", "minor", "small", "off-centre", "off center", "hand-held", "handheld"
        ]
        let hardTerms = [
            "obvious 3/4", "clear 3/4", "three-quarter", "three quarter",
            "strong diagonal", "strongly diagonal", "severe perspective", "strong perspective",
            "keystone", "one end much larger", "heavily slanted", "very slanted",
            "too slanted", "corner view", "corner perspective", "not a side profile",
            "angled", "diagonal", "3/4", "three-quarter view", "three quarter view"
        ]

        if hardTerms.contains(where: { combined.contains($0) }) {
            if mildTerms.contains(where: { combined.contains($0) }) && !combined.contains("obvious") && !combined.contains("strong") && !combined.contains("severe") && !combined.contains("too") {
                return false
            }
            return true
        }

        return false
    }

    private static func clamp01(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    private static func extractJSONObject(from text: String) -> String {
        if let balanced = extractFirstBalancedJSONObject(from: text) { return balanced }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
                        return String(text[start...index]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
            index = text.index(after: index)
        }

        return nil
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
