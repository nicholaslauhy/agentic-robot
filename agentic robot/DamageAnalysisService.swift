//
//  DamageAnalysisService.swift
//  agentic robot
//
//  Created by q2 on 14/5/26.
//

import SwiftUI

struct DamageAnalysisResponse: Codable {
    let results: [DamageDetection]
}

struct DamageDetection: Codable, Identifiable {
    let id = UUID()

    let angleIndex: Int
    let angleName: String
    let damageType: String
    let confidence: Double
    let cropBase64: String

    enum CodingKeys: String, CodingKey {
        case angleIndex
        case angleName
        case damageType
        case confidence
        case cropBase64
    }

    var cropImage: UIImage? {
        guard let data = Data(base64Encoded: cropBase64) else {
            return nil
        }
        return UIImage(data: data)
    }
}

final class DamageAnalysisService {
    static let shared = DamageAnalysisService()

    private init() {}

    func analyze(images: [UIImage]) async throws -> [DamageDetection] {
        guard let url = URL(string: "http://127.0.0.1:8000/analyze-damage") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        for (index, image) in images.enumerated() {
            guard let imageData = image.jpegData(compressionQuality: 0.75) else {
                continue
            }

            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"files\"; filename=\"damage_\(index).jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)

        if let httpResponse = response as? HTTPURLResponse {
            print("Damage API status:", httpResponse.statusCode)
        }

        if let raw = String(data: data, encoding: .utf8) {
            print("Damage API raw response:", raw)
        }

        let decoded = try JSONDecoder().decode(DamageAnalysisResponse.self, from: data)

        print("Decoded damage result count:", decoded.results.count)

        return decoded.results
    }
}
