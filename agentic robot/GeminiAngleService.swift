//
//  GeminiAngleService.swift
//  agentic robot
//
//  Created by q2 on 30/5/26.
//

import UIKit

struct GeminiAngleService {

    // ── Paste your key here ────────────────────────────────────────────────
    private static let apiKey = "AQ.Ab8RN6Lq982WOxRGQffyhjC--Lk9e_WJWr_yBH1IzVw44B4hSw"
    // ──────────────────────────────────────────────────────────────────────

    private static let endpoint =
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\(apiKey)"

    enum DetectedAngle: String {
        case front = "Front"
        case rear  = "Rear"
        case left  = "Left"
        case right = "Right"
        case unknown = "Unknown"
    }

    /// Returns the angle Gemini sees in the image.
    static func detectAngle(
        image: UIImage,
        completion: @escaping (DetectedAngle) -> Void
    ) {
        // Downscale to 512px — Gemini Flash doesn't need full res for this task
        let resized = image.resized(toMaxDimension: 512)
        guard let jpeg = resized.jpegData(compressionQuality: 0.7) else {
            completion(.unknown); return
        }
        let base64 = jpeg.base64EncodedString()

        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    [
                        "inlineData": [
                            "mimeType": "image/jpeg",
                            "data": base64
                        ]
                    ],
                    [
                        "text": """
                        You are a vehicle angle classifier for a car inspection app.
                        Look at this photo and determine which side of the car is shown.
                        Reply with EXACTLY one word only — no punctuation, no explanation:
                        Front
                        Rear
                        Left
                        Right
                        If you cannot determine the angle or no car is visible, reply: Unknown
                        """
                    ]
                ]
            ]],
            "generationConfig": [
                "maxOutputTokens": 5,
                "temperature": 0.0
            ]
        ]

        guard
            let url = URL(string: endpoint),
            let bodyData = try? JSONSerialization.data(withJSONObject: body)
        else { completion(.unknown); return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard
                let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let candidates = json["candidates"] as? [[String: Any]],
                let content = candidates.first?["content"] as? [String: Any],
                let parts = content["parts"] as? [[String: Any]],
                let text = parts.first?["text"] as? String
            else {
                DispatchQueue.main.async { completion(.unknown) }
                return
            }

            let angle = parseDetectedAngle(from: text)
            DispatchQueue.main.async { completion(angle) }
        }.resume()
    }
    private static func parseDetectedAngle(from text: String) -> DetectedAngle {
        let clean = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        // Accept common Gemini variations such as "front view", "Front.",
        // or short replies that contain the required word.
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
