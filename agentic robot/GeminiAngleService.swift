//
//  GeminiAngleService.swift
//  agentic robot
//
//  OpenAI-powered vehicle photo validator for Scratch Scan.
//  Class name kept as GeminiAngleService so existing ScratchScanView calls do not change.
//

import UIKit

struct GeminiAngleService {

    // The OpenAI key must stay on the server. This endpoint belongs to the same
    // private backend used by licence-plate and damage analysis.
    private static let endpoint = "http://192.168.86.241:8000/validate-vehicle-angle"

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
                // Confidence bar raised from 0.45 -> 0.62: side orientation is the
                // hardest judgment call for the model, so a lukewarm confidence
                // score is itself a signal the photo (or the model's read of it)
                // is questionable and should go to Override rather than auto-pass.
                return wholeVehicleVisible &&
                       confidence >= 0.62 &&
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
        let originalBonnetPosition: String?
        let mirrorBonnetPosition: String?
        let mirrorCheckPasses: Bool?
        let frontCues: String?
        let rearCues: String?
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
        let visibleEndFace: String?
        let estimatedSideYawDegrees: Double?

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
        _ = sendAngleRequest(image: image, expectedAngle: nil) { result in
            completion(AngleDetectionResult(angle: result.detectedAngle,
                                            confidence: result.confidence,
                                            reason: result.reason,
                                            rawText: result.rawText))
        }
    }

    @discardableResult
    static func validateExpectedAngle(
        image: UIImage,
        expectedAngle: DetectedAngle,
        completion: @escaping (AngleValidationResult) -> Void
    ) -> URLSessionDataTask? {
        sendAngleRequest(image: image, expectedAngle: expectedAngle, completion: completion)
    }

    // MARK: - Request

    private static func sendAngleRequest(
        image: UIImage,
        expectedAngle: DetectedAngle?,
        completion: @escaping (AngleValidationResult) -> Void
    ) -> URLSessionDataTask? {
        // Normalize first so the JPEG pixels match what the user sees in SwiftUI.
        // Send one image only: including a mirrored duplicate gives the model two
        // contradictory vehicle orientations and makes every classification less reliable.
        let normalized = image.normalizedForAngleValidation()
        let resized = normalized.resized(toMaxDimension: 1600)

        guard let jpeg = resized.jpegData(compressionQuality: 0.90) else {
            completion(failureResult(expectedAngle: expectedAngle, reason: "Could not convert image to JPEG."))
            return nil
        }

        let originalBase64 = jpeg.base64EncodedString()
        debugLog("Expected slot: \(expectedAngle?.rawValue ?? "Unknown")\nSending one normalized image to the private validation backend.")

        guard let request = buildURLRequest(
            originalBase64: originalBase64,
            expectedAngle: expectedAngle ?? .unknown
        ) else {
            completion(failureResult(expectedAngle: expectedAngle, reason: "Could not build the vehicle validation request."))
            return nil
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(failureResult(expectedAngle: expectedAngle, reason: error.localizedDescription))
                }
                return
            }

            guard let data else {
                DispatchQueue.main.async {
                    completion(failureResult(expectedAngle: expectedAngle, reason: "No data received from the vehicle validation server."))
                }
                return
            }

            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                let serverMessage = backendErrorMessage(from: data)
                DispatchQueue.main.async {
                    completion(failureResult(expectedAngle: expectedAngle, reason: "Vehicle validation failed (HTTP \(http.statusCode)): \(serverMessage)"))
                }
                return
            }

            handleResponse(data: data, expectedAngle: expectedAngle, completion: completion)
        }
        task.resume()
        return task
    }

    private static func buildURLRequest(originalBase64: String, expectedAngle: DetectedAngle) -> URLRequest? {
        let body: [String: Any] = [
            "originalImageBase64": originalBase64,
            "expectedAngle": expectedAngle.rawValue
        ]

        guard let url = URL(string: endpoint),
              let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = bodyData
        request.timeoutInterval = 30
        return request
    }

    // MARK: - Response handling

    private static func handleResponse(
        data: Data,
        expectedAngle: DetectedAngle?,
        completion: @escaping (AngleValidationResult) -> Void
    ) {
        guard let text = String(data: data, encoding: .utf8),
              (try? JSONDecoder().decode(ModelAngleResponse.self, from: data)) != nil else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            debugLog("Unexpected API response:\n\(raw)")
            DispatchQueue.main.async {
                completion(failureResult(expectedAngle: expectedAngle, reason: "The vehicle validation server returned an unexpected response."))
            }
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = parseValidationResponse(from: trimmed, expectedAngle: expectedAngle)
        debugLog("Raw OpenAI text:\n\(trimmed)\n\nParsed: \(result.debugSummary)")
        DispatchQueue.main.async { completion(result) }
    }

    private static func backendErrorMessage(from data: Data) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = object["detail"] as? String,
           !detail.isEmpty {
            return detail
        }
        return "Please check that the backend is running and has OpenAI API credit."
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

        You receive TWO images:
        - IMAGE A is the ORIGINAL photo. Every JSON field must describe IMAGE A.
        - IMAGE B is IMAGE A mirrored horizontally. Use it only to check whether your left/right judgement for IMAGE A is consistent.

        CRITICAL LEFT/RIGHT RULE:
        - All left/right answers are IMAGE COORDINATES, not real vehicle side names.
        - Left edge of IMAGE A is x=0. Right edge of IMAGE A is x=100.
        - Ignore driver side, passenger side, steering wheel side, road side, and physical left/right side of the car.
        - You are deciding where the BONNET/HOOD/NOSE/FRONT END appears inside IMAGE A.

        APP SIDE CODES FOR SIDE PHOTOS:
        - If the bonnet/hood/nose/front end is closer to the LEFT EDGE of IMAGE A, output detectedAngle="Left".
        - If the bonnet/hood/nose/front end is closer to the RIGHT EDGE of IMAGE A, output detectedAngle="Right".
        - These are app codes only. They do NOT mean the car's real-world left or right side.
        - Example: if headlights/grille/bonnet are at the RIGHT edge of IMAGE A and tail-lights/boot are at the LEFT edge, output originalBonnetPosition="image_right", sideFrontPosition="right", detectedAngle="Right".
        - Example: if headlights/grille/bonnet are at the LEFT edge of IMAGE A and tail-lights/boot are at the RIGHT edge, output originalBonnetPosition="image_left", sideFrontPosition="left", detectedAngle="Left".

        HOW TO FIND THE BONNET/FRONT END:
        - Front cues: bonnet/hood, headlights, grille/front bumper, front wheel arch, side mirror near front door, windscreen sloping back from bonnet.
        - Rear cues: boot/trunk, tail-lights, rear bumper, fuel door, rear windscreen/C-pillar.
        - frontEndX and bonnetEndX are approximate x-coordinates of the front/bonnet end center in IMAGE A, from 0 to 100.
        - rearEndX and bootEndX are approximate x-coordinates of the rear/boot end center in IMAGE A, from 0 to 100.
        - For IMAGE A front-on-left: bonnetEndX < bootEndX, frontEndX < rearEndX, originalBonnetPosition="image_left", sideFrontPosition="left", frontIsOnImageLeft=true, frontIsOnImageRight=false.
        - For IMAGE A front-on-right: bonnetEndX > bootEndX, frontEndX > rearEndX, originalBonnetPosition="image_right", sideFrontPosition="right", frontIsOnImageLeft=false, frontIsOnImageRight=true.
        - mirrorBonnetPosition must describe IMAGE B. It should be the opposite of originalBonnetPosition when the side is clear.
        - mirrorCheckPasses=true only if IMAGE B confirms the opposite left/right position.
        - If you cannot clearly locate both front and rear ends, use detectedAngle="Unknown" and originalBonnetPosition="unknown".

        STRICT SIDE STRAIGHTNESS RULE:
        - A side photo must be a straight side profile, not a 3/4 angled view.
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
          "originalBonnetPosition": "unknown",
          "mirrorBonnetPosition": "unknown",
          "mirrorCheckPasses": false,
          "frontCues": "short visual evidence for the front end in IMAGE A",
          "rearCues": "short visual evidence for the rear end in IMAGE A",
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
          "reason": "short reason using IMAGE A coordinates only"
        }

        Allowed detectedAngle values: "Front", "Rear", "Left", "Right", "Unknown".
        Allowed sideFrontPosition values: "left", "right", "unknown".
        Allowed cameraSideDirection values: "bonnet_on_image_left", "bonnet_on_image_right", "unknown".
        Allowed originalBonnetPosition and mirrorBonnetPosition values: "image_left", "image_right", "unknown".
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

        let coordinateSide = inferSideFromCoordinates(frontEndX: decoded.frontEndX,
                                                       rearEndX: decoded.rearEndX,
                                                       bonnetEndX: decoded.bonnetEndX,
                                                       bootEndX: decoded.bootEndX)
        let textSide = normalizeSideFrontPosition(decoded.sideFrontPosition)
        let cameraSide = normalizeCameraSideDirection(decoded.cameraSideDirection)
        let originalBonnetSide = normalizeBonnetPosition(decoded.originalBonnetPosition)
        let boolSide = inferSideFromBooleans(left: decoded.frontIsOnImageLeft,
                                             right: decoded.frontIsOnImageRight)
        let angleSide = sideFromDetectedAngle(rawDetected)

        let finalSide = decideFinalSideStrict(
            coordinateSide: coordinateSide,
            originalBonnetSide: originalBonnetSide,
            textSide: textSide,
            cameraSide: cameraSide,
            boolSide: boolSide,
            angleSide: angleSide
        )

        debugLog("""
            Side vote breakdown -> coordinate=\(coordinateSide) originalBonnet=\(originalBonnetSide) text=\(textSide) camera=\(cameraSide) bool=\(boolSide) angle=\(angleSide) => final=\(finalSide)
            frontEndX=\(decoded.frontEndX?.description ?? "nil") rearEndX=\(decoded.rearEndX?.description ?? "nil") bonnetEndX=\(decoded.bonnetEndX?.description ?? "nil") bootEndX=\(decoded.bootEndX?.description ?? "nil")
            sideFrontPosition=\(decoded.sideFrontPosition ?? "nil") cameraSideDirection=\(decoded.cameraSideDirection ?? "nil") originalBonnetPosition=\(decoded.originalBonnetPosition ?? "nil") mirrorBonnetPosition=\(decoded.mirrorBonnetPosition ?? "nil") frontIsOnImageLeft=\(decoded.frontIsOnImageLeft?.description ?? "nil") frontIsOnImageRight=\(decoded.frontIsOnImageRight?.description ?? "nil")
            frontCues=\(decoded.frontCues ?? "nil") rearCues=\(decoded.rearCues ?? "nil")
            """)

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

        // For side photos, once objective bonnet-position evidence resolves the side,
        // do not let a low generic confidence score reject an otherwise clear photo.
        // Wrong-side photos still fail below because matchesExpectedAngle will be false.
        if (expected == .left || expected == .right || expected == .unknown),
           (detected == .left || detected == .right),
           finalSide != "unknown",
           carPresent {
            confidence = max(confidence, 0.78)
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
        let threeQuarter = decoded.isThreeQuarterSideView == true
        let visibleEndFace = (decoded.visibleEndFace ?? "none")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let endFaceVisible = visibleEndFace == "front" ||
                             visibleEndFace == "rear" ||
                             visibleEndFace == "both"
        let sideYaw = abs(decoded.estimatedSideYawDegrees ?? 0)
        let excessiveSideYaw = sideYaw > 22
        let clearThreeQuarter = threeQuarter &&
                                (endFaceVisible || sideYaw > 16 || endSizeMismatch)
        let clearCornerView = endFaceVisible && sideYaw > 16

        let hardPerspectiveReject: Bool
        if expected == .rear {
            hardPerspectiveReject = containsHardRearPerspectiveReject(reason: modelReason, perspectiveIssue: perspectiveIssue)
        } else if expected == .left || expected == .right {
            hardPerspectiveReject = clearThreeQuarter ||
                                    clearCornerView ||
                                    excessiveSideYaw ||
                                    containsHardPerspectiveReject(reason: modelReason, perspectiveIssue: perspectiveIssue)
        } else {
            hardPerspectiveReject = containsHardPerspectiveReject(reason: modelReason, perspectiveIssue: perspectiveIssue)
        }

        let straightnessScore: Double
        let isStraight: Bool
        switch expected {
        case .left, .right:
            // Allow small hand-held perspective differences, but still reject
            // a clear corner/three-quarter view.
            straightnessScore = sideProfileScore > 0 ? min(rawStraightnessScore, sideProfileScore) : rawStraightnessScore
            isStraight = !hardPerspectiveReject &&
                         (decoded.isStraightEnough == true || rawStraightnessScore >= 0.55) &&
                         rawStraightnessScore >= 0.50 &&
                         (sideProfileScore == 0 || sideProfileScore >= 0.52)
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
        originalBonnetSide: String,
        textSide: String,
        cameraSide: String,
        boolSide: String,
        angleSide: String
    ) -> String {
        // Side identity and camera straightness are separate questions. The
        // side code is determined only by where the bonnet sits in the image:
        // bonnet-left = Left, bonnet-right = Right. Perspective must never flip it.
        if coordinateSide == "left" || coordinateSide == "right" {
            return coordinateSide
        }
        if originalBonnetSide == "left" || originalBonnetSide == "right" {
            return originalBonnetSide
        }

        // Fall back to redundant image-coordinate fields only when at least two
        // agree. Never use a lone generic detectedAngle label as authority.
        let signals = [textSide, cameraSide, boolSide, angleSide]
        let leftVotes = signals.filter { $0 == "left" }.count
        let rightVotes = signals.filter { $0 == "right" }.count
        if leftVotes >= 2 && leftVotes > rightVotes { return "left" }
        if rightVotes >= 2 && rightVotes > leftVotes { return "right" }

        return "unknown"
    }

    private static func inferSideFromCoordinates(
        frontEndX: Double?,
        rearEndX: Double?,
        bonnetEndX: Double?,
        bootEndX: Double?
    ) -> String {
        // Prefer bonnet/boot wording because "front" can be ambiguous.
        // If bonnet/boot are too close to call, don't give up yet — try front/rear too.
        if let bonnetEndX, let bootEndX {
            let bonnet = clamp100(bonnetEndX)
            let boot = clamp100(bootEndX)
            if abs(bonnet - boot) >= 12 {
                return bonnet < boot ? "left" : "right"
            }
        }

        if let frontEndX, let rearEndX {
            let front = clamp100(frontEndX)
            let rear = clamp100(rearEndX)
            if abs(front - rear) >= 12 {
                return front < rear ? "left" : "right"
            }
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

    private static func normalizeBonnetPosition(_ value: String?) -> String {
        let clean = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if clean == "image_left" ||
            clean == "left" ||
            clean == "bonnet_left" ||
            clean == "hood_left" ||
            clean == "front_left" ||
            clean == "bonnet_on_image_left" ||
            clean == "hood_on_image_left" ||
            clean == "front_on_image_left" ||
            clean.contains("image left") ||
            clean.contains("bonnet left") ||
            clean.contains("hood left") ||
            clean.contains("front left") ||
            clean.contains("bonnet on the left") ||
            clean.contains("hood on the left") ||
            clean.contains("front on the left") {
            return "left"
        }

        if clean == "image_right" ||
            clean == "right" ||
            clean == "bonnet_right" ||
            clean == "hood_right" ||
            clean == "front_right" ||
            clean == "bonnet_on_image_right" ||
            clean == "hood_on_image_right" ||
            clean == "front_on_image_right" ||
            clean.contains("image right") ||
            clean.contains("bonnet right") ||
            clean.contains("hood right") ||
            clean.contains("front right") ||
            clean.contains("bonnet on the right") ||
            clean.contains("hood on the right") ||
            clean.contains("front on the right") {
            return "right"
        }

        return "unknown"
    }

    private static func inferOriginalSideFromMirrorBonnetPosition(_ mirrorBonnetSide: String) -> String {
        // IMAGE B is a horizontal mirror of IMAGE A, so its bonnet position must be opposite.
        if mirrorBonnetSide == "left" { return "right" }
        if mirrorBonnetSide == "right" { return "left" }
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
        return abs(near - far) > 20.0
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
            "none", "slight", "slightly", "minor", "small", "moderate", "moderately",
            "off-centre", "off center", "hand-held", "handheld"
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
    func normalizedForAngleValidation() -> UIImage {
        // Force the pixels to match the visual orientation shown in the app.
        // This avoids EXIF orientation metadata causing the model to see a
        // different left/right layout from what the user sees.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func resized(toMaxDimension maxDim: CGFloat) -> UIImage {
        let scale = maxDim / max(size.width, size.height)
        guard scale < 1 else { return self }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    func horizontallyMirroredForAngleValidation() -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: size.width, y: 0)
            context.cgContext.scaleBy(x: -1, y: 1)
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
