import AVFoundation
import CoreGraphics
import UIKit

struct DetailedScanFrame: Identifiable, @unchecked Sendable {
    let id: UUID
    let timestampSeconds: Double
    let image: UIImage
    let brightness: Double
    let sharpness: Double
    let clippedPixelRatio: Double

    nonisolated init(
        id: UUID = UUID(),
        timestampSeconds: Double,
        image: UIImage,
        brightness: Double,
        sharpness: Double,
        clippedPixelRatio: Double
    ) {
        self.id = id
        self.timestampSeconds = timestampSeconds
        self.image = image
        self.brightness = brightness
        self.sharpness = sharpness
        self.clippedPixelRatio = clippedPixelRatio
    }

    nonisolated var isUsable: Bool {
        Self.isUsable(
            brightness: brightness,
            sharpness: sharpness,
            clippedPixelRatio: clippedPixelRatio
        )
    }

    nonisolated static func isUsable(
        brightness: Double,
        sharpness: Double,
        clippedPixelRatio: Double
    ) -> Bool {
        (0.12...0.92).contains(brightness) &&
            sharpness >= 0.012 &&
            clippedPixelRatio <= 0.55
    }
}

struct DetailedScanQualityAssessment: Sendable {
    let passed: Bool
    let usableFrameCount: Int
    let totalFrameCount: Int
    let issues: [String]

    nonisolated init(
        passed: Bool,
        usableFrameCount: Int,
        totalFrameCount: Int,
        issues: [String]
    ) {
        self.passed = passed
        self.usableFrameCount = usableFrameCount
        self.totalFrameCount = totalFrameCount
        self.issues = issues
    }

    var summary: String {
        if passed {
            return "Quality passed · \(usableFrameCount) clear viewpoints"
        }
        return issues.joined(separator: " ")
    }
}

enum DetailedScanFrameProcessingError: LocalizedError {
    case frameExtractionFailed
    case insufficientQuality([String])

    var errorDescription: String? {
        switch self {
        case .frameExtractionFailed:
            return "Stable viewpoints could not be extracted from this recording. Please record the panel again."
        case .insufficientQuality(let issues):
            return "This sweep needs to be retaken. \(issues.joined(separator: " "))"
        }
    }
}

enum DetailedScanFrameProcessor {
    nonisolated static let representativeFrameCount = 5
    nonisolated static let sampleFractions: [Double] = [0.12, 0.31, 0.50, 0.69, 0.88]

    nonisolated static func process(
        videoURL: URL,
        durationSeconds: Double
    ) async throws -> (frames: [DetailedScanFrame], assessment: DetailedScanQualityAssessment) {
        try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1600, height: 1600)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.08, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.08, preferredTimescale: 600)

            var frames: [DetailedScanFrame] = []
            for fraction in sampleFractions {
                try Task.checkCancellation()
                let timestamp = min(
                    max(0.05, durationSeconds * fraction),
                    max(0.05, durationSeconds - 0.05)
                )
                let time = CMTime(seconds: timestamp, preferredTimescale: 600)
                guard let generated = try? await generator.image(at: time) else {
                    continue
                }
                let cgImage = generated.image
                let image = UIImage(cgImage: cgImage)
                let metrics = pixelMetrics(for: image)
                frames.append(
                    DetailedScanFrame(
                        timestampSeconds: timestamp,
                        image: image,
                        brightness: metrics.brightness,
                        sharpness: metrics.sharpness,
                        clippedPixelRatio: metrics.clippedPixelRatio
                    )
                )
            }

            guard frames.count >= 3 else {
                throw DetailedScanFrameProcessingError.frameExtractionFailed
            }

            let assessment = assess(frames)
            guard assessment.passed else {
                throw DetailedScanFrameProcessingError.insufficientQuality(assessment.issues)
            }
            return (frames, assessment)
        }.value
    }

    nonisolated static func assess(_ frames: [DetailedScanFrame]) -> DetailedScanQualityAssessment {
        let usableCount = frames.filter(\.isUsable).count
        let darkCount = frames.filter { $0.brightness < 0.12 }.count
        let brightCount = frames.filter { $0.brightness > 0.92 || $0.clippedPixelRatio > 0.55 }.count
        let blurryCount = frames.filter { $0.sharpness < 0.012 }.count
        let requiredUsable = max(3, Int(ceil(Double(frames.count) * 0.60)))

        var issues: [String] = []
        if darkCount >= 2 {
            issues.append("The panel is too dark; move to even lighting or enable more ambient light.")
        }
        if brightCount >= 2 {
            issues.append("Strong glare or overexposure hides the paint surface; change your position slightly.")
        }
        if blurryCount >= 2 {
            issues.append("The movement is too fast or shaky; walk more slowly and keep the iPad steady.")
        }
        if issues.isEmpty, usableCount < requiredUsable {
            issues.append("Keep the highlighted panel filling most of the frame throughout the sweep.")
        }

        return DetailedScanQualityAssessment(
            passed: frames.count >= 3 && usableCount >= requiredUsable,
            usableFrameCount: usableCount,
            totalFrameCount: frames.count,
            issues: issues
        )
    }

    nonisolated private static func pixelMetrics(for image: UIImage) -> (
        brightness: Double,
        sharpness: Double,
        clippedPixelRatio: Double
    ) {
        guard let cgImage = image.cgImage else {
            return (0, 0, 1)
        }

        let longestEdge = max(cgImage.width, cgImage.height)
        let scale = min(1.0, 320.0 / Double(max(1, longestEdge)))
        let width = max(2, Int(Double(cgImage.width) * scale))
        let height = max(2, Int(Double(cgImage.height) * scale))
        var pixels = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return (0, 0, 1)
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var brightnessSum = 0.0
        var clippedCount = 0
        var gradientSum = 0.0
        var gradientSamples = 0

        for y in 0..<height {
            for x in 0..<width {
                let value = Int(pixels[y * width + x])
                brightnessSum += Double(value) / 255.0
                if value <= 10 || value >= 245 {
                    clippedCount += 1
                }

                if x > 0, y > 0 {
                    let left = Int(pixels[y * width + x - 1])
                    let above = Int(pixels[(y - 1) * width + x])
                    gradientSum += Double(abs(value - left) + abs(value - above)) / 510.0
                    gradientSamples += 1
                }
            }
        }

        let pixelCount = max(1, width * height)
        return (
            brightness: brightnessSum / Double(pixelCount),
            sharpness: gradientSum / Double(max(1, gradientSamples)),
            clippedPixelRatio: Double(clippedCount) / Double(pixelCount)
        )
    }
}
