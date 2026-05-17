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
    let contextBase64: String       // annotated: mask overlay + bbox rectangle burned in
    let cleanContextBase64: String  // pristine: no annotations — used as base for user bbox editing

    enum CodingKeys: String, CodingKey {
        case angleIndex
        case angleName
        case damageType
        case confidence
        case cropBase64
        case contextBase64
        case cleanContextBase64
    }

    var cropImage: UIImage? {
        guard let data = Data(base64Encoded: cropBase64) else { return nil }
        return UIImage(data: data)
    }

    /// Annotated image shown in the read-only detail view.
    var contextImage: UIImage? {
        guard !contextBase64.isEmpty,
              let data = Data(base64Encoded: contextBase64) else { return nil }
        return UIImage(data: data)
    }

    /// Clean image used as the base when the user draws their own bounding box.
    var cleanContextImage: UIImage? {
        guard !cleanContextBase64.isEmpty,
              let data = Data(base64Encoded: cleanContextBase64) else { return nil }
        return UIImage(data: data)
    }
}

final class DamageAnalysisService {
    static let shared = DamageAnalysisService()

    private init() {}

    func analyze(images: [UIImage]) async throws -> [DamageDetection] {
        // REPLACE THIS IP ADDRESS
        guard let url = URL(string: "http://192.168.86.176:8000/analyze-damage") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        for (index, image) in images.enumerated() {
            guard let imageData = image.jpegData(compressionQuality: 0.75) else { continue }

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
