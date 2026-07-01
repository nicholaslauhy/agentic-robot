//
//  GeminiAngleService.swift
//  agentic robot
//
//  OpenAI-powered vehicle photo validator for Scratch Scan.
//  Class name kept as GeminiAngleService so existing ScratchScanView calls do not change.
//

import UIKit

struct GeminiAngleService {

    // IMPORTANT:
    // Do NOT ship a real API key inside an iOS app for production.
    // For testing only, paste your NEW key here.
    // Production: iOS app -> your backend -> OpenAI.
    private static let apiKey = "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"

    // User requested gpt-4o, not 4o-mini.
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
                // Rear should not fail just because the model says "not a side view".
                return visibilityScore >= 0.35 && (isStraightEnough || straightnessScore >= 0.35)

            case .front:
                return wholeVehicleVisible &&
                       confidence >= 0.45 &&
                       visibilityScore >= 0.55 &&
                       isStraightEnough &&
                       straightnessScore >= 0.58

            case .left, .right:
                // Side views must be strict about orientation and perspective.
                // Orientation is enforced locally from image coordinates/votes, not from the model's vague Left/Right label.
                return wholeVehicleVisible &&
                       confidence >= 0.45 &&
                       visibilityScore >= 0.55 &&
                       isStraightEnough &&
                       straightnessScore >= 0.70

            case .unknown:
                return detectedAngle != .unknown &&
                       wholeVehicleVisible &&
                       confidence >= 0.45 &&
                       visibilityScore >= 0.55 &&
                       isStraightEnough
            }
        }

        var debugSummary: String {
            "Expected=\(expectedAngle.rawValue), Detected=\(detectedAngle.rawValue), Match=\(matchesExpectedAngle), Confidence=\(confidence), CarPresent=\(carPresent), Visible=\(wholeVehicleVisible), VisibilityScore=\(visibilityScore), Straight=\(isStraightEnough), StraightnessScore=\(straightnessScore), Perspective=\(perspectiveIssue), Reason=\(reason)"
        }
    }

    private struct ModelAngleResponse: Decodable {
        let carPresent: Bool?
        let wholeVehicleVisible: Bool?
        let visibilityScore: Double?
        let detectedAngle: String?
        let confidence: Double?
        let isStraightEnough: Bool?
        let straightnessScore: Double?
        let perspectiveIssue: String?

        // Objective side-orientation evidence. These must describe IMAGE coordinates only.
        let sideFrontPosition: String?
        let cameraSideDirection: String?
        let frontIsOnImageLeft: Bool?
        let frontIsOnImageRight: Bool?
        let frontEndX: Double?
        let rearEndX: Double?
        let bonnetEndX: Double?
        let bootEndX: Double?

        // Straight side-profile evidence.
        let sideProfileScore: Double?
        let isThreeQuarterSideView: Bool?
        let nearEndSizePercent: Double?
        let farEndSizePercent: Double?
        let wheelsAppearSimilarSize: Bool?
        let cameraPerpendicularToSide: Bool?

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
        guard apiKey != "PASTE_YOUR_NEW_OPENAI_API_KEY_HERE",
              apiKey != "PASTE_YOUR_OPENAI_API_KEY_HERE",
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
        let prompt = buildPrompt()
        debugLog("Expected slot: \(expectedAngle?.rawValue ?? "None")\nPrompt is OBJECTIVE; expected slot is NOT sent to the model. Local code enforces expected slot after parsing.")

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
            "max_tokens": 700,
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

    private static func buildPrompt() -> String {
        """
        You are objectively describing ONE vehicle inspection photo for an iOS app.

        Return ONLY valid JSON. No markdown. No extra text.
        You are NOT told the expected slot. Do NOT try to satisfy any expected answer.
        Describe exactly what is visible in the image.

        IMAGE COORDINATES:
        - Left edge of photo is x=0.
        - Right edge of photo is x=100.
        - All left/right decisions refer ONLY to photo coordinates.
        - Ignore driver side, passenger side, steering wheel side, road side, and real-world vehicle left/right.

        ABSOLUTE APP SIDE DEFINITIONS:
        - LEFT SIDE = the bonnet/hood/nose/front end of the car is on IMAGE-LEFT.
        - RIGHT SIDE = the bonnet/hood/nose/front end of the car is on IMAGE-RIGHT.
        - If the bonnet/front is on image-left, detectedAngle must be "Left".
        - If the bonnet/front is on image-right, detectedAngle must be "Right".
        - A side photo can NEVER be both Left and Right.

        HOW TO FIND THE BONNET/FRONT END:
        - Bonnet/front end = hood/bonnet, headlights, grille/front bumper, front wheel arch, windscreen sloping back from the bonnet.
        - Boot/rear end = trunk/boot, tail-lights, rear bumper, rear windscreen/C-pillar.
        - frontEndX and bonnetEndX are approximate x-coordinates of the front/bonnet end center, from 0 to 100.
        - rearEndX and bootEndX are approximate x-coordinates of the rear/boot end center, from 0 to 100.
        - For LEFT SIDE: bonnetEndX < bootEndX, frontEndX < rearEndX, sideFrontPosition="left", frontIsOnImageLeft=true, frontIsOnImageRight=false.
        - For RIGHT SIDE: bonnetEndX > bootEndX, frontEndX > rearEndX, sideFrontPosition="right", frontIsOnImageLeft=false, frontIsOnImageRight=true.
        - If you cannot clearly locate both ends, use detectedAngle="Unknown" and sideFrontPosition="unknown".

        STRICT SIDE STRAIGHTNESS RULE:
        - The side photo must be a straight side profile, not a 3/4 angled view.
        - Reject angled/corner side photos even if the bonnet side is known.
        - Set isThreeQuarterSideView=true if one end of the car is visibly closer/larger, both front and side faces are visible, both rear and side faces are visible, or body lines strongly converge.
        - Set cameraPerpendicularToSide=false for diagonal side/corner shots.
        - For a correct straight side photo, sideProfileScore and straightnessScore should usually be at least 0.75.

        FRONT / REAR RULES:
        - Front means grille/headlights/front bumper face the camera.
        - Rear means tail-lights/boot/rear bumper face the camera.
        - For front/rear, do not apply side bonnet-left/bonnet-right rules.

        CAR PRESENCE / VISIBILITY:
        - carPresent=false if there is no real car/vehicle.
        - Reject empty carparks, walls, pillars, people, motorcycles only, close-up parts only, drawings, screenshots, or toys.
        - For side photos, wholeVehicleVisible=true only if both bonnet/front end and boot/rear end are visible enough for calibration.
        - For front/rear, wholeVehicleVisible=true if the required face is sufficiently visible.

        Required JSON schema:
        {
          "carPresent": true,
          "wholeVehicleVisible": true,
          "visibilityScore": 0.0,
          "detectedAngle": "Unknown",
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
          "nearEndSizePercent": 0.0,
          "farEndSizePercent": 0.0,
          "wheelsAppearSimilarSize": true,
          "cameraPerpendicularToSide": true,
          "reason": "short reason"
        }

        Allowed detectedAngle values: "Front", "Rear", "Left", "Right", "Unknown".
        Allowed sideFrontPosition values: "left", "right", "unknown".
        Allowed cameraSideDirection values: "bonnet_on_image_left", "bonnet_on_image_right", "unknown".
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
        let rawStraightnessScore = clamp01(decoded.straightnessScore ?? 0.0)
        let sideProfileScore = clamp01(decoded.sideProfileScore ?? 0.0)
        let perspectiveIssue = decoded.perspectiveIssue ?? "None"
        let modelReason = decoded.reason ?? ""
        let rawDetected = parseDetectedAngle(from: decoded.detectedAngle ?? "")

        let finalSide = decideFinalSideStrict(
            coordinateSide: inferSideFromCoordinates(frontEndX: decoded.frontEndX,
                                                     rearEndX: decoded.rearEndX,
                                                     bonnetEndX: decoded.bonnetEndX,
                                                     bootEndX: decoded.bootEndX),
            textSide: normalizeSideFrontPosition(decoded.sideFrontPosition),
            cameraSide: normalizeCameraSideDirection(decoded.cameraSideDirection),
            boolSide: inferSideFromBooleans(left: decoded.frontIsOnImageLeft,
                                            right: decoded.frontIsOnImageRight),
            angleSide: sideFromDetectedAngle(rawDetected)
        )

        var detected = rawDetected
        if finalSide == "left" {
            detected = .left
        } else if finalSide == "right" {
            detected = .right
        } else if expected == .left || expected == .right {
            // Never let a weak model label alone make a side image pass.
            // If the objective side evidence is unknown/conflicting, show Unknown.
            detected = .unknown
        }

        // Rear images often get low generic scores because the model thinks it needs side length.
        if expected == .rear && detected == .rear && carPresent {
            confidence = max(confidence, 0.75)
            visibilityScore = max(visibilityScore, 0.70)
        }

        let matches: Bool
        switch expected {
        case .left:
            matches = finalSide == "left" && detected == .left
        case .right:
            matches = finalSide == "right" && detected == .right
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
            wholeVisible = carPresent && (detected == .rear || decoded.wholeVehicleVisible == true || visibilityScore >= 0.35)
        case .front:
            wholeVisible = carPresent && (decoded.wholeVehicleVisible == true || visibilityScore >= 0.55)
        case .left, .right:
            wholeVisible = carPresent && (decoded.wholeVehicleVisible == true || visibilityScore >= 0.55) && finalSide != "unknown"
        case .unknown:
            wholeVisible = carPresent && (decoded.wholeVehicleVisible == true || visibilityScore >= 0.55)
        }

        let endSizeMismatch = hasEndSizeMismatch(near: decoded.nearEndSizePercent, far: decoded.farEndSizePercent)
        let wheelsMismatch = decoded.wheelsAppearSimilarSize == false
        let notPerpendicular = decoded.cameraPerpendicularToSide == false
        let threeQuarter = decoded.isThreeQuarterSideView == true

        let hardPerspectiveReject: Bool
        if expected == .rear {
            hardPerspectiveReject = containsHardRearPerspectiveReject(reason: modelReason, perspectiveIssue: perspectiveIssue)
        } else if expected == .left || expected == .right {
            hardPerspectiveReject = threeQuarter || endSizeMismatch || wheelsMismatch || notPerpendicular || containsHardPerspectiveReject(reason: modelReason, perspectiveIssue: perspectiveIssue)
        } else {
            hardPerspectiveReject = containsHardPerspectiveReject(reason: modelReason, perspectiveIssue: perspectiveIssue)
        }

        let straightnessScore: Double
        let isStraight: Bool
        switch expected {
        case .left, .right:
            // Keep angled-car catching strict.
            // Correct side must still fail if it is diagonal/3-quarter.
            straightnessScore = sideProfileScore > 0 ? min(rawStraightnessScore, sideProfileScore) : rawStraightnessScore
            isStraight = !hardPerspectiveReject &&
                         (decoded.isStraightEnough == true || rawStraightnessScore >= 0.72) &&
                         rawStraightnessScore >= 0.66 &&
                         (sideProfileScore == 0 || sideProfileScore >= 0.62)
        case .rear:
            straightnessScore = rawStraightnessScore
            isStraight = !hardPerspectiveReject && (decoded.isStraightEnough == true || rawStraightnessScore >= 0.35)
        case .front:
            straightnessScore = rawStraightnessScore
            isStraight = !hardPerspectiveReject && (decoded.isStraightEnough == true || rawStraightnessScore >= 0.58)
        case .unknown:
            straightnessScore = rawStraightnessScore
            isStraight = !hardPerspectiveReject && (decoded.isStraightEnough == true || rawStraightnessScore >= 0.58)
        }

        let reason = buildFinalReason(expected: expected,
                                      detected: detected,
                                      carPresent: carPresent,
                                      wholeVisible: wholeVisible,
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
                return "Wrong side. This is Right Side because the bonnet/front is on the right side of the image. Left Side requires the bonnet/front on the left."
            }
            return "Could not confirm Left Side. Left Side requires a clear side profile with the bonnet/front on the left side of the image."
        }

        if expected == .right && !matches {
            if finalSide == "left" {
                return "Wrong side. This is Left Side because the bonnet/front is on the left side of the image. Right Side requires the bonnet/front on the right."
            }
            return "Could not confirm Right Side. Right Side requires a clear side profile with the bonnet/front on the right side of the image."
        }

        if !wholeVisible {
            switch expected {
            case .rear:
                return "The rear face is not visible enough. Please make sure the tail-lights, boot and rear bumper can be seen."
            case .front:
                return "The front face is not visible enough. Please make sure the headlights, grille and front bumper can be seen."
            case .left, .right:
                return "The side profile is not visible enough. Please include the car from bonnet/front end to boot/rear end."
            case .unknown:
                return "The vehicle is not visible enough for inspection."
            }
        }

        if !matches {
            return "Wrong angle. Expected \(expected.rawValue), but detected \(detected.rawValue)."
        }

        if !isStraight {
            if expected == .left || expected == .right {
                return "This photo is taken at an angle, not straight-on. Stand directly beside the middle of the car so both ends and wheels look similar in size."
            }
            return "The vehicle is too angled or slanted for calibration. Please retake it more straight-on."
        }

        if !modelReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return modelReason
        }

        return "Photo accepted. Straightness \(Int(straightnessScore * 100))%."
    }

    // MARK: - Side decision helpers

    private static func decideFinalSideStrict(
        coordinateSide: String,
        textSide: String,
        cameraSide: String,
        boolSide: String,
        angleSide: String
    ) -> String {
        // Coordinates are strongest: bonnetEndX/bootEndX or frontEndX/rearEndX.
        if coordinateSide == "left" || coordinateSide == "right" {
            return coordinateSide
        }

        // Vote only from explicit image-coordinate fields.
        // Do NOT let expected slot bias this. Do NOT pass if left and right conflict.
        let signals = [textSide, cameraSide, boolSide].filter { $0 == "left" || $0 == "right" }
        let leftCount = signals.filter { $0 == "left" }.count
        let rightCount = signals.filter { $0 == "right" }.count

        if leftCount >= 2 && rightCount == 0 { return "left" }
        if rightCount >= 2 && leftCount == 0 { return "right" }

        // Last fallback: detectedAngle only if at least one explicit field agrees.
        // This prevents Left slot from accepting right-side images just because the model said "matchesExpectedAngle".
        if angleSide == "left" && leftCount == 1 && rightCount == 0 { return "left" }
        if angleSide == "right" && rightCount == 1 && leftCount == 0 { return "right" }

        return "unknown"
    }

    private static func inferSideFromCoordinates(
        frontEndX: Double?,
        rearEndX: Double?,
        bonnetEndX: Double?,
        bootEndX: Double?
    ) -> String {
        // Prefer bonnet/boot wording because "front" can be ambiguous.
        if let bonnetEndX, let bootEndX {
            let bonnet = clamp100(bonnetEndX)
            let boot = clamp100(bootEndX)
            guard abs(bonnet - boot) >= 12 else { return "unknown" }
            return bonnet < boot ? "left" : "right"
        }

        if let frontEndX, let rearEndX {
            let front = clamp100(frontEndX)
            let rear = clamp100(rearEndX)
            guard abs(front - rear) >= 12 else { return "unknown" }
            return front < rear ? "left" : "right"
        }

        return "unknown"
    }

    private static func normalizeSideFrontPosition(_ value: String?) -> String {
        let clean = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if clean == "left" ||
            clean == "image_left" ||
            clean == "bonnet_left" ||
            clean == "bonnet_on_image_left" ||
            clean == "hood_on_image_left" ||
            clean == "nose_on_image_left" ||
            clean.contains("bonnet on image left") ||
            clean.contains("hood on image left") ||
            clean.contains("nose on image left") ||
            clean.contains("front on image left") ||
            clean.contains("front is on image left") ||
            clean.contains("front on left") ||
            clean.contains("front is on the left") {
            return "left"
        }

        if clean == "right" ||
            clean == "image_right" ||
            clean == "bonnet_right" ||
            clean == "bonnet_on_image_right" ||
            clean == "hood_on_image_right" ||
            clean == "nose_on_image_right" ||
            clean.contains("bonnet on image right") ||
            clean.contains("hood on image right") ||
            clean.contains("nose on image right") ||
            clean.contains("front on image right") ||
            clean.contains("front is on image right") ||
            clean.contains("front on right") ||
            clean.contains("front is on the right") {
            return "right"
        }

        return "unknown"
    }

    private static func normalizeCameraSideDirection(_ value: String?) -> String {
        let clean = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.contains("bonnet_on_image_left") || clean.contains("front_on_image_left") || clean.contains("bonnet on image left") || clean.contains("front on image left") {
            return "left"
        }
        if clean.contains("bonnet_on_image_right") || clean.contains("front_on_image_right") || clean.contains("bonnet on image right") || clean.contains("front on image right") {
            return "right"
        }
        return "unknown"
    }

    private static func inferSideFromBooleans(left: Bool?, right: Bool?) -> String {
        if left == true && right != true { return "left" }
        if right == true && left != true { return "right" }
        return "unknown"
    }

    private static func sideFromDetectedAngle(_ angle: DetectedAngle) -> String {
        switch angle {
        case .left: return "left"
        case .right: return "right"
        default: return "unknown"
        }
    }

    // MARK: - Perspective helpers

    private static func hasEndSizeMismatch(near: Double?, far: Double?) -> Bool {
        guard let near, let far else { return false }
        return abs(near - far) > 12.0
    }

    private static func containsHardRearPerspectiveReject(reason: String, perspectiveIssue: String) -> Bool {
        let combined = "\(reason) \(perspectiveIssue)".lowercased()
        let hardTerms = [
            "obvious 3/4", "clear 3/4", "three-quarter rear", "three quarter rear",
            "rear-corner", "rear corner", "strong diagonal", "strong perspective",
            "severe perspective", "keystone", "heavily slanted", "very slanted", "too slanted"
        ]
        return hardTerms.contains { combined.contains($0) }
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
            if mildTerms.contains(where: { combined.contains($0) }) &&
                !combined.contains("obvious") &&
                !combined.contains("strong") &&
                !combined.contains("severe") &&
                !combined.contains("too") {
                return false
            }
            return true
        }

        return false
    }

    // MARK: - General helpers

    private static func parseDetectedAngle(from text: String) -> DetectedAngle {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Check Left/Right before Front because model explanations sometimes say "front on image right".
        if clean == "left" || clean.contains("left side") { return .left }
        if clean == "right" || clean.contains("right side") { return .right }
        if clean.contains("rear") || clean.contains("back") { return .rear }
        if clean.contains("front") { return .front }
        return .unknown
    }

    private static func clamp01(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }

    private static func clamp100(_ value: Double) -> Double {
        min(max(value, 0.0), 100.0)
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
