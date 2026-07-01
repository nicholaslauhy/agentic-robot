import SwiftUI

struct DamageAnalysisResponse: Codable {
    let results: [DamageDetection]
}

struct DamageAnalysisComparedResponse: Codable {
    let results: [DamageDetection]
    let baseline: [DamageDetection]
}

struct BaselineLookupResponse: Codable {
    let plate: String
    let baselines: [String: [BaselineRegion]]

    var hasExistingBaseline: Bool {
        baselines.values.contains { !$0.isEmpty }
    }
}



struct ConfirmBaselineRegion: Codable {
    let x1: Int
    let y1: Int
    let x2: Int
    let y2: Int
    let label: String
    let imageWidth: Int?   // original image width when this region was saved
    let imageHeight: Int?  // original image height when this region was saved

    // Full clean benchmark image. Backend uses this to estimate zoom/rotation/
    // translation from old report image -> new scan image, then projects this
    // region into the new image.
    let referenceImageBase64: String?

    // Small visual reference crop. Backend only uses this as a fallback if
    // full-image alignment cannot find enough matching features.
    let referenceCropBase64: String?
    let templateX1: Int?
    let templateY1: Int?
    let templateX2: Int?
    let templateY2: Int?

    func rescaled(to image: UIImage?) -> ConfirmBaselineRegion {
        guard let image else { return self }
        let normalized = image.htxNormalizedImage()
        let targetWidth = max(1, Int(normalized.size.width.rounded()))
        let targetHeight = max(1, Int(normalized.size.height.rounded()))

        guard let savedWidth = imageWidth,
              let savedHeight = imageHeight,
              savedWidth > 0,
              savedHeight > 0,
              (savedWidth != targetWidth || savedHeight != targetHeight) else {
            return ConfirmBaselineRegion(
                x1: min(max(0, x1), targetWidth),
                y1: min(max(0, y1), targetHeight),
                x2: min(max(0, x2), targetWidth),
                y2: min(max(0, y2), targetHeight),
                label: label,
                imageWidth: imageWidth ?? targetWidth,
                imageHeight: imageHeight ?? targetHeight,
                referenceImageBase64: referenceImageBase64,
                referenceCropBase64: referenceCropBase64,
                templateX1: templateX1,
                templateY1: templateY1,
                templateX2: templateX2,
                templateY2: templateY2
            )
        }

        let scaleX = Double(targetWidth) / Double(savedWidth)
        let scaleY = Double(targetHeight) / Double(savedHeight)

        return ConfirmBaselineRegion(
            x1: min(max(0, Int((Double(x1) * scaleX).rounded())), targetWidth),
            y1: min(max(0, Int((Double(y1) * scaleY).rounded())), targetHeight),
            x2: min(max(0, Int((Double(x2) * scaleX).rounded())), targetWidth),
            y2: min(max(0, Int((Double(y2) * scaleY).rounded())), targetHeight),
            label: label,
            imageWidth: targetWidth,
            imageHeight: targetHeight,
            referenceImageBase64: referenceImageBase64,
            referenceCropBase64: referenceCropBase64,
            templateX1: templateX1,
            templateY1: templateY1,
            templateX2: templateX2,
            templateY2: templateY2
        )
    }
}

struct ConfirmBaselineBatchAngle: Codable {
    let angle_index: Int
    let angle_name: String
    let regions: [ConfirmBaselineRegion]
}

struct ConfirmBaselineBatchRequest: Codable {
    let plate: String
    let angles: [ConfirmBaselineBatchAngle]
}

struct ConfirmBaselineBatchResponse: Codable {
    let status: String?
}

struct BaselineRegion: Codable {
    let x1: Int?
    let y1: Int?
    let x2: Int?
    let y2: Int?
    let label: String?
    let imageWidth: Int?
    let imageHeight: Int?
    let referenceImageBase64: String?
    let referenceCropBase64: String?
    let templateX1: Int?
    let templateY1: Int?
    let templateX2: Int?
    let templateY2: Int?
}


private enum PlateNormalizer {
    static func normalize(_ plate: String) -> String {
        plate.replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }
}


private enum DamageAngleMetadata {
    static let names = ["Front", "Rear", "Left Side", "Right Side"]

    static func name(for index: Int) -> String {
        if index >= 0 && index < names.count { return names[index] }
        return "Angle \(index)"
    }
}

private enum LocalBaselineCache {
    private static func key(for plate: String) -> String {
        "np299.localBaseline." + PlateNormalizer.normalize(plate)
    }

    static func save(plate: String, angles: [ConfirmBaselineBatchAngle]) {
        // Disabled on purpose. Keeping a second local copy caused old benchmark
        // boxes to reappear even after baselines.db was deleted on the backend.
        UserDefaults.standard.removeObject(forKey: key(for: plate))
    }

    static func load(plate: String) -> [ConfirmBaselineBatchAngle] {
        // Backend database is the single source of truth.
        UserDefaults.standard.removeObject(forKey: key(for: plate))
        return []
    }
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

    // Backend comparison / baseline fields
    let isBaseline: Bool?
    let x1: Int?
    let y1: Int?
    let x2: Int?
    let y2: Int?

    // Original backend image size. Coordinates x1/y1/x2/y2 are based on
    // this size, while cleanContextBase64 may be downscaled for UI display.
    let imageWidth: Int?
    let imageHeight: Int?

    // ── VLM fields ──
    let isVerifiedDamage: Bool
    let vlmDamageType: String
    let severity: String
    let repairRecommendation: String
    let repairComplexity: String
    let likelyFalsePositive: Bool
    let explanation: String

    enum CodingKeys: String, CodingKey {
        case angleIndex
        case angleName
        case damageType
        case confidence
        case cropBase64
        case contextBase64
        case cleanContextBase64
        case isBaseline
        case x1
        case y1
        case x2
        case y2
        case imageWidth
        case imageHeight
        case isVerifiedDamage
        case vlmDamageType
        case severity
        case repairRecommendation
        case repairComplexity
        case likelyFalsePositive
        case explanation
    }


    init(
        angleIndex: Int,
        angleName: String,
        damageType: String,
        confidence: Double = 1.0,
        cropBase64: String = "",
        contextBase64: String = "",
        cleanContextBase64: String = "",
        isBaseline: Bool? = nil,
        x1: Int? = nil,
        y1: Int? = nil,
        x2: Int? = nil,
        y2: Int? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        isVerifiedDamage: Bool = true,
        vlmDamageType: String? = nil,
        severity: String = "",
        repairRecommendation: String = "",
        repairComplexity: String = "",
        likelyFalsePositive: Bool = false,
        explanation: String = ""
    ) {
        self.angleIndex = angleIndex
        self.angleName = angleName
        self.damageType = damageType
        self.confidence = confidence
        self.cropBase64 = cropBase64
        self.contextBase64 = contextBase64
        self.cleanContextBase64 = cleanContextBase64
        self.isBaseline = isBaseline
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.isVerifiedDamage = isVerifiedDamage
        self.vlmDamageType = vlmDamageType ?? damageType
        self.severity = severity
        self.repairRecommendation = repairRecommendation
        self.repairComplexity = repairComplexity
        self.likelyFalsePositive = likelyFalsePositive
        self.explanation = explanation.isEmpty
            ? "\(damageType.capitalized) detected on the \(angleName)."
            : explanation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        angleIndex = try c.decodeIfPresent(Int.self, forKey: .angleIndex) ?? 0
        angleName = try c.decodeIfPresent(String.self, forKey: .angleName) ?? "Vehicle"
        damageType = try c.decodeIfPresent(String.self, forKey: .damageType) ?? "damage"
        confidence = try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 1.0
        cropBase64 = try c.decodeIfPresent(String.self, forKey: .cropBase64) ?? ""
        contextBase64 = try c.decodeIfPresent(String.self, forKey: .contextBase64) ?? ""
        cleanContextBase64 = try c.decodeIfPresent(String.self, forKey: .cleanContextBase64) ?? ""

        isBaseline = try c.decodeIfPresent(Bool.self, forKey: .isBaseline)
        x1 = try c.decodeIfPresent(Int.self, forKey: .x1)
        y1 = try c.decodeIfPresent(Int.self, forKey: .y1)
        x2 = try c.decodeIfPresent(Int.self, forKey: .x2)
        y2 = try c.decodeIfPresent(Int.self, forKey: .y2)
        imageWidth = try c.decodeIfPresent(Int.self, forKey: .imageWidth)
        imageHeight = try c.decodeIfPresent(Int.self, forKey: .imageHeight)

        isVerifiedDamage = try c.decodeIfPresent(Bool.self, forKey: .isVerifiedDamage) ?? true
        vlmDamageType = try c.decodeIfPresent(String.self, forKey: .vlmDamageType) ?? damageType
        severity = try c.decodeIfPresent(String.self, forKey: .severity) ?? ""
        repairRecommendation = try c.decodeIfPresent(String.self, forKey: .repairRecommendation) ?? ""
        repairComplexity = try c.decodeIfPresent(String.self, forKey: .repairComplexity) ?? ""
        likelyFalsePositive = try c.decodeIfPresent(Bool.self, forKey: .likelyFalsePositive) ?? false
        explanation = try c.decodeIfPresent(String.self, forKey: .explanation)
            ?? "\(damageType.capitalized) detected on the \(angleName)."
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(angleIndex, forKey: .angleIndex)
        try c.encode(angleName, forKey: .angleName)
        try c.encode(damageType, forKey: .damageType)
        try c.encode(confidence, forKey: .confidence)
        try c.encode(cropBase64, forKey: .cropBase64)
        try c.encode(contextBase64, forKey: .contextBase64)
        try c.encode(cleanContextBase64, forKey: .cleanContextBase64)
        try c.encodeIfPresent(isBaseline, forKey: .isBaseline)
        try c.encodeIfPresent(x1, forKey: .x1)
        try c.encodeIfPresent(y1, forKey: .y1)
        try c.encodeIfPresent(x2, forKey: .x2)
        try c.encodeIfPresent(y2, forKey: .y2)
        try c.encodeIfPresent(imageWidth, forKey: .imageWidth)
        try c.encodeIfPresent(imageHeight, forKey: .imageHeight)
        try c.encode(isVerifiedDamage, forKey: .isVerifiedDamage)
        try c.encode(vlmDamageType, forKey: .vlmDamageType)
        try c.encode(severity, forKey: .severity)
        try c.encode(repairRecommendation, forKey: .repairRecommendation)
        try c.encode(repairComplexity, forKey: .repairComplexity)
        try c.encode(likelyFalsePositive, forKey: .likelyFalsePositive)
        try c.encode(explanation, forKey: .explanation)
    }

    var cropImage: UIImage? {
        guard let data = Data(base64Encoded: cropBase64) else { return nil }
        return UIImage(data: data)
    }

    var contextImage: UIImage? {
        guard !contextBase64.isEmpty,
              let data = Data(base64Encoded: contextBase64) else { return nil }
        return UIImage(data: data)
    }

    var cleanContextImage: UIImage? {
        guard !cleanContextBase64.isEmpty,
              let data = Data(base64Encoded: cleanContextBase64) else { return nil }
        return UIImage(data: data)
    }
}



extension UIImage {
    func htxNormalizedImage() -> UIImage {
        if imageOrientation == .up { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func htxJPEGBase64(compressionQuality: CGFloat = 0.75) -> String {
        jpegData(compressionQuality: compressionQuality)?.base64EncodedString() ?? ""
    }

    func htxCropBase64(region: ConfirmBaselineRegion) -> String {
        let normalized = htxNormalizedImage()
        let scale = normalized.scale
        let imageSize = normalized.size
        let imageRect = CGRect(origin: .zero, size: imageSize)

        // Same pixel->point conversion as htxReferenceTemplateBase64.
        let coordScale: CGFloat = {
            if let iw = region.imageWidth, iw > 0 { return imageSize.width / CGFloat(iw) }
            return 1.0 / scale
        }()
        let coordScaleY: CGFloat = {
            if let ih = region.imageHeight, ih > 0 { return imageSize.height / CGFloat(ih) }
            return 1.0 / scale
        }()

        let rect = CGRect(
            x: max(0, CGFloat(region.x1) * coordScale),
            y: max(0, CGFloat(region.y1) * coordScaleY),
            width: max(1, CGFloat(region.x2 - region.x1) * coordScale),
            height: max(1, CGFloat(region.y2 - region.y1) * coordScaleY)
        ).intersection(imageRect)

        guard rect.width > 0, rect.height > 0,
              let cgImage = normalized.cgImage?.cropping(to: CGRect(
                x: rect.minX * scale,
                y: rect.minY * scale,
                width: rect.width * scale,
                height: rect.height * scale
              )) else {
            return ""
        }

        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
            .jpegData(compressionQuality: 0.75)?
            .base64EncodedString() ?? ""
    }

    func htxReferenceTemplateBase64(region: ConfirmBaselineRegion) -> (base64: String, templateX1: Int, templateY1: Int, templateX2: Int, templateY2: Int)? {
        let normalized = htxNormalizedImage()
        let scale = normalized.scale
        let imageSize = normalized.size          // UIKit POINTS (pixels / scale)
        let imageRect = CGRect(origin: .zero, size: imageSize)

        // region.x1/y1/x2/y2 come from the backend in full-res PIXEL space.
        // region.imageWidth/imageHeight are also in pixels.
        // imageSize is in UIKit POINTS. We must convert coords to points before
        // doing any CGRect geometry, otherwise the damageRect sits outside
        // imageRect and the intersection returns an empty rect -> nil return ->
        // no reference crop saved -> template matching always fails.
        let coordScale: CGFloat = {
            if let iw = region.imageWidth, iw > 0 {
                // Backend pixel width -> point width conversion factor
                return imageSize.width / CGFloat(iw)
            }
            // If imageWidth is missing, try the scale factor directly.
            return 1.0 / scale
        }()
        let coordScaleY: CGFloat = {
            if let ih = region.imageHeight, ih > 0 {
                return imageSize.height / CGFloat(ih)
            }
            return 1.0 / scale
        }()

        let damageRect = CGRect(
            x: max(0, CGFloat(region.x1) * coordScale),
            y: max(0, CGFloat(region.y1) * coordScaleY),
            width: max(1, CGFloat(region.x2 - region.x1) * coordScale),
            height: max(1, CGFloat(region.y2 - region.y1) * coordScaleY)
        ).intersection(imageRect)

        guard damageRect.width > 0, damageRect.height > 0 else { return nil }

        // Save context around the damage, not only the tiny box. This gives the
        // backend more pixels/features to match when future photos are nearer,
        // further, or taken in a different environment.
        let padX = max(damageRect.width * 1.25, imageSize.width * 0.035, 40)
        let padY = max(damageRect.height * 1.25, imageSize.height * 0.035, 40)

        let templateRect = damageRect.insetBy(dx: -padX, dy: -padY).intersection(imageRect)
        guard templateRect.width > 8, templateRect.height > 8 else { return nil }

        // Convert back to device pixels for the actual cgImage crop.
        let cropRectInPixels = CGRect(
            x: templateRect.minX * scale,
            y: templateRect.minY * scale,
            width: templateRect.width * scale,
            height: templateRect.height * scale
        )

        guard let cgImage = normalized.cgImage?.cropping(to: cropRectInPixels) else { return nil }

        let templateImage = UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        guard let data = templateImage.jpegData(compressionQuality: 0.82) else { return nil }

        // templateX/Y are in the coordinate space of the saved JPEG image
        // (templateRect * scale = device pixels, then rendered as a 1x UIImage).
        let tx1 = Int((damageRect.minX - templateRect.minX).rounded() * scale)
        let ty1 = Int((damageRect.minY - templateRect.minY).rounded() * scale)
        let tx2 = Int((damageRect.maxX - templateRect.minX).rounded() * scale)
        let ty2 = Int((damageRect.maxY - templateRect.minY).rounded() * scale)

        return (
            data.base64EncodedString(),
            max(0, tx1),
            max(0, ty1),
            max(1, tx2),
            max(1, ty2)
        )
    }

    func htxContextBase64(region: ConfirmBaselineRegion) -> String {
        let normalized = htxNormalizedImage()
        let renderer = UIGraphicsImageRenderer(size: normalized.size)
        let rendered = renderer.image { context in
            normalized.draw(in: CGRect(origin: .zero, size: normalized.size))

            let rect = CGRect(
                x: CGFloat(region.x1),
                y: CGFloat(region.y1),
                width: CGFloat(max(1, region.x2 - region.x1)),
                height: CGFloat(max(1, region.y2 - region.y1))
            )

            UIColor.systemGray.setStroke()
            context.cgContext.setLineWidth(max(3, normalized.size.width * 0.003))
            context.cgContext.stroke(rect)
        }

        return rendered.jpegData(compressionQuality: 0.70)?.base64EncodedString() ?? ""
    }
}

final class DamageAnalysisService {
    static let shared = DamageAnalysisService()

    private init() {}

    private let baseURLString = "http://192.168.86.229:8000"

    /// Smart NP299 analysis.
    /// Always asks the backend comparison endpoint first. If the backend has no
    /// benchmark rows yet, the endpoint still returns the normal YOLO detections
    /// as new damage. This avoids a stale/failed GET /baseline check hiding old
    /// benchmark damage from the result screen.
    ///
    /// There is also a same-device fallback cache. Whenever a report is generated,
    /// the confirmed benchmark is saved locally as well as sent to the backend.
    /// If the backend database was restarted/deleted or the app is pointed at a
    /// different backend folder, the app can still show the existing benchmark
    /// from the last generated report on this device.
    func analyzeForPlate(plate: String, images: [UIImage], angleIndices: [Int]? = nil) async throws -> [DamageDetection] {
        let localBaseline = LocalBaselineCache.load(plate: plate)

        do {
            let compared = try await analyzeCompared(plate: plate, images: images, angleIndices: angleIndices)

            if !compared.baseline.isEmpty {
                print("Backend benchmark found. New: \(compared.results.count), existing: \(compared.baseline.count)")
                return compared.results + compared.baseline
            }

            if !localBaseline.isEmpty {
                print("Backend benchmark empty. Using local benchmark fallback for \(plate).")
                let localExisting = makeLocalBaselineDetections(
                    from: localBaseline,
                    images: images
                )
                let filteredNew = filterDetections(
                    compared.results,
                    excluding: localBaseline,
                    images: images
                )
                return filteredNew + localExisting
            }

            print("No backend or local benchmark found. Treating this as first scan.")
            return compared.results
        } catch {
            if Task.isCancelled ||
                error is CancellationError ||
                (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }

            if !localBaseline.isEmpty {
                print("Compared analysis failed, but local benchmark exists. Falling back to normal analysis + local benchmark:", error)
                let normalResults = try await analyze(images: images, angleIndices: angleIndices)
                let localExisting = makeLocalBaselineDetections(
                    from: localBaseline,
                    images: images
                )
                let filteredNew = filterDetections(
                    normalResults,
                    excluding: localBaseline,
                    images: images
                )
                return filteredNew + localExisting
            }

            throw error
        }
    }


    private func filterDetections(
        _ detections: [DamageDetection],
        excluding baselineAngles: [ConfirmBaselineBatchAngle],
        images: [UIImage] = []
    ) -> [DamageDetection] {
        detections.filter { detection in
            guard let dx1 = detection.x1,
                  let dy1 = detection.y1,
                  let dx2 = detection.x2,
                  let dy2 = detection.y2 else {
                return true
            }

            let currentImage = (detection.angleIndex >= 0 && detection.angleIndex < images.count)
                ? images[detection.angleIndex]
                : nil

            let overlapsExisting = baselineAngles.contains { angle in
                guard angle.angle_index == detection.angleIndex else { return false }
                return angle.regions.contains { storedRegion in
                    let region = storedRegion.rescaled(to: currentImage)
                    return Self.iou(
                        ax1: dx1, ay1: dy1, ax2: dx2, ay2: dy2,
                        bx1: region.x1, by1: region.y1, bx2: region.x2, by2: region.y2
                    ) >= 0.40
                }
            }

            return !overlapsExisting
        }
    }

    private func makeLocalBaselineDetections(
        from baselineAngles: [ConfirmBaselineBatchAngle],
        images: [UIImage]
    ) -> [DamageDetection] {
        baselineAngles.flatMap { angle in
            angle.regions.map { storedRegion in
                let image = (angle.angle_index >= 0 && angle.angle_index < images.count)
                    ? images[angle.angle_index].htxNormalizedImage()
                    : nil
                let region = storedRegion.rescaled(to: image)

                let cropBase64 = image?.htxCropBase64(region: region) ?? ""
                let contextBase64 = image?.htxContextBase64(region: region) ?? cropBase64
                let cleanContextBase64 = image?.htxJPEGBase64(compressionQuality: 0.70) ?? ""

                return DamageDetection(
                    angleIndex: angle.angle_index,
                    angleName: angle.angle_name,
                    damageType: region.label,
                    confidence: 1.0,
                    cropBase64: cropBase64,
                    contextBase64: contextBase64,
                    cleanContextBase64: cleanContextBase64,
                    isBaseline: true,
                    x1: region.x1,
                    y1: region.y1,
                    x2: region.x2,
                    y2: region.y2,
                    imageWidth: region.imageWidth,
                    imageHeight: region.imageHeight,
                    explanation: "Pre-existing benchmark damage saved from a previous report."
                )
            }
        }
    }

    private static func iou(
        ax1: Int, ay1: Int, ax2: Int, ay2: Int,
        bx1: Int, by1: Int, bx2: Int, by2: Int
    ) -> Double {
        let ix1 = max(ax1, bx1)
        let iy1 = max(ay1, by1)
        let ix2 = min(ax2, bx2)
        let iy2 = min(ay2, by2)
        let inter = max(0, ix2 - ix1) * max(0, iy2 - iy1)
        if inter <= 0 { return 0 }
        let areaA = max(0, ax2 - ax1) * max(0, ay2 - ay1)
        let areaB = max(0, bx2 - bx1) * max(0, by2 - by1)
        let union = areaA + areaB - inter
        guard union > 0 else { return 0 }
        return Double(inter) / Double(union)
    }

    func getBaseline(plate: String) async throws -> BaselineLookupResponse {
        let encodedPlate = plate.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? plate
        guard let url = URL(string: "\(baseURLString)/baseline/\(encodedPlate)") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        if let httpResponse = response as? HTTPURLResponse {
            print("Baseline API status:", httpResponse.statusCode)
        }

        return try JSONDecoder().decode(BaselineLookupResponse.self, from: data)
    }

    func analyzeCompared(plate: String, images: [UIImage], angleIndices: [Int]? = nil) async throws -> DamageAnalysisComparedResponse {
        let encodedPlate = plate.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? plate
        guard let url = URL(string: "\(baseURLString)/analyze-damage-compared?plate=\(encodedPlate)") else {
            throw URLError(.badURL)
        }

        let data = try await uploadImages(images, to: url, angleIndices: angleIndices)

        if let raw = String(data: data, encoding: .utf8) {
            print("Compared damage API raw response:", raw)
        }

        return try JSONDecoder().decode(DamageAnalysisComparedResponse.self, from: data)
    }

    func analyze(images: [UIImage], angleIndices: [Int]? = nil) async throws -> [DamageDetection] {
        guard let url = URL(string: "\(baseURLString)/analyze-damage") else {
            throw URLError(.badURL)
        }

        let data = try await uploadImages(images, to: url, angleIndices: angleIndices)

        if let raw = String(data: data, encoding: .utf8) {
            print("Damage API raw response:", raw)
        }

        do {
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(DamageAnalysisResponse.self, from: data)
            print("Decoded damage result count:", decoded.results.count)
            return decoded.results
        } catch {
            print("JSON decode error:", error)
            if let raw = String(data: data, encoding: .utf8) {
                print("Raw JSON that failed to decode:", raw.prefix(2000))
            }
            throw error
        }
    }


    func confirmBaselineBatch(
        plate: String,
        angles: [ConfirmBaselineBatchAngle]
    ) async throws {
        guard let url = URL(string: "\(baseURLString)/confirm-baseline-batch") else {
            throw URLError(.badURL)
        }

        let payload = ConfirmBaselineBatchRequest(
            plate: plate,
            angles: angles
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            print("Confirm baseline batch API status:", httpResponse.statusCode)
            if !(200...299).contains(httpResponse.statusCode) {
                let raw = String(data: data, encoding: .utf8) ?? ""
                print("Confirm baseline batch API failed:", raw)
                throw URLError(.badServerResponse)
            }
        }

        if let raw = String(data: data, encoding: .utf8) {
            print("Confirm baseline batch API raw response:", raw)
        }

        LocalBaselineCache.save(plate: plate, angles: angles)
        print("Backend benchmark saved for \(PlateNormalizer.normalize(plate)); local fallback cache cleared.")
    }

    private func uploadImages(
        _ images: [UIImage],
        to url: URL,
        angleIndices: [Int]? = nil
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Send the real scan slot for every file. The backend must not infer
        // left/right/front/rear purely from multipart order, because replacing
        // or cropping images can change upload order in some SwiftUI flows.
        let indices = angleIndices ?? Array(images.indices)
        let names = indices.map { DamageAngleMetadata.name(for: $0) }

        let encoder = JSONEncoder()
        if let indicesData = try? encoder.encode(indices),
           let indicesJSON = String(data: indicesData, encoding: .utf8) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"angle_indices\"\r\n\r\n".data(using: .utf8)!)
            body.append(indicesJSON.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }

        if let namesData = try? encoder.encode(names),
           let namesJSON = String(data: namesData, encoding: .utf8) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"angle_names\"\r\n\r\n".data(using: .utf8)!)
            body.append(namesJSON.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }

        for (uploadPosition, image) in images.enumerated() {
            let angleIndex = uploadPosition < indices.count ? indices[uploadPosition] : uploadPosition
            guard let imageData = image.jpegData(compressionQuality: 0.75) else { continue }

            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"files\"; filename=\"damage_angle_\(angleIndex).jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)

        if let httpResponse = response as? HTTPURLResponse {
            print("Damage API status:", httpResponse.statusCode)
        }

        return data
    }
}
