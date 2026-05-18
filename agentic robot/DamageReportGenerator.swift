import UIKit

struct DamageReportGenerator {

    static func generatePDF(
        plate: String,
        carType: String,
        detections: [MutableDamageDetection],
        scanImages: [UIImage]
    ) -> URL? {

        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        let url = documents.appendingPathComponent("DamageReport.pdf")

        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        do {

            try renderer.writePDF(to: url) { context in

                var y: CGFloat = 40

                // ─────────────────────────────────────────────
                // Helpers
                // ─────────────────────────────────────────────

                func newPageIfNeeded(_ requiredHeight: CGFloat) {
                    if y + requiredHeight > 780 {
                        context.beginPage()
                        y = 40
                    }
                }

                func drawText(
                    _ text: String,
                    x: CGFloat = 40,
                    font: UIFont = .systemFont(ofSize: 14),
                    bold: Bool = false,
                    color: UIColor = .black
                ) {
                    let actualFont = bold
                        ? UIFont.boldSystemFont(ofSize: font.pointSize)
                        : font

                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: actualFont,
                        .foregroundColor: color
                    ]

                    let rect = CGRect(
                        x: x,
                        y: y,
                        width: 515,
                        height: 100
                    )

                    text.draw(in: rect, withAttributes: attrs)

                    y += 24
                }

                /// Draws multi-line text that wraps properly and triggers page breaks.
                func drawWrappedText(
                    _ text: String,
                    x: CGFloat = 40,
                    font: UIFont = .systemFont(ofSize: 13),
                    color: UIColor = .darkGray
                ) {
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: color
                    ]

                    let maxWidth: CGFloat = 515

                    let boundingRect = (text as NSString).boundingRect(
                        with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: attrs,
                        context: nil
                    )

                    let textHeight = ceil(boundingRect.height) + 8

                    newPageIfNeeded(textHeight + 12)

                    let rect = CGRect(x: x, y: y, width: maxWidth, height: textHeight)
                    text.draw(in: rect, withAttributes: attrs)

                    y += textHeight + 4
                }

                func drawImage(
                    _ image: UIImage,
                    maxHeight: CGFloat = 220
                ) {
                    let availableWidth: CGFloat = 515
                    let aspectRatio = image.size.width > 0
                        ? image.size.height / image.size.width
                        : 1
                    let naturalHeight = availableWidth * aspectRatio
                    let drawHeight = min(naturalHeight, maxHeight)
                    let drawWidth  = drawHeight / aspectRatio

                    newPageIfNeeded(drawHeight + 20)

                    let xOffset: CGFloat = 40 + (availableWidth - drawWidth) / 2
                    let rect = CGRect(x: xOffset, y: y, width: drawWidth, height: drawHeight)
                    image.draw(in: rect)

                    y += drawHeight + 12
                }

                // ─────────────────────────────────────────────
                // FIRST PAGE — Header
                // ─────────────────────────────────────────────

                context.beginPage()

                drawText(
                    "VEHICLE DAMAGE ANALYSIS REPORT",
                    font: .systemFont(ofSize: 24),
                    bold: true
                )

                y += 10

                drawText("Plate: \(plate)")
                drawText("Vehicle: \(carType)")

                let formatter = DateFormatter()
                formatter.dateFormat = "dd MMM yyyy"
                drawText("Date: \(formatter.string(from: Date()))")

                y += 10

                // ─────────────────────────────────────────────
                // SUMMARY
                // ─────────────────────────────────────────────

                drawText(
                    "SUMMARY",
                    font: .systemFont(ofSize: 20),
                    bold: true
                )

                let scratches = detections.filter {
                    $0.damageType.lowercased().contains("scratch")
                }.count

                let dents = detections.filter {
                    $0.damageType.lowercased().contains("dent")
                }.count

                let overallSeverity: String

                switch detections.count {
                case 0:        overallSeverity = "None"
                case 1...2:    overallSeverity = "Minor"
                case 3...5:    overallSeverity = "Moderate"
                default:       overallSeverity = "Severe"
                }

                drawText("- \(scratches) scratches detected")
                drawText("- \(dents) dents detected")
                drawText("- Overall Severity: \(overallSeverity)")

                y += 20

                // ─────────────────────────────────────────────
                // DAMAGE CASES
                // ─────────────────────────────────────────────

                drawText(
                    "DAMAGE CASES",
                    font: .systemFont(ofSize: 20),
                    bold: true
                )

                for (index, detection) in detections.enumerated() {

                    newPageIfNeeded(420)

                    // ── Case header ──
                    drawText(
                        "Case #\(index + 1)",
                        font: .systemFont(ofSize: 18),
                        bold: true
                    )

                    // ── Detection metadata ──
                    drawText("Damage Type: \(detection.damageType.capitalized)")
                    drawText("Vehicle Angle: \(detection.angleName)")
                    drawText("Confidence: \(Int(detection.confidence * 100))%")

                    // ── VLM fields ──
                    if !detection.severity.isEmpty {
                        drawText("Severity: \(detection.severity.capitalized)")
                    }

                    if !detection.repairComplexity.isEmpty {
                        drawText("Repair Complexity: \(detection.repairComplexity.capitalized)")
                    }

                    if !detection.repairRecommendation.isEmpty {
                        newPageIfNeeded(60)
                        drawText("Repair Recommendation:", bold: true)
                        drawWrappedText(detection.repairRecommendation)
                    }

                    if !detection.explanation.isEmpty {
                        newPageIfNeeded(60)
                        drawText("AI Analysis:", bold: true)
                        drawWrappedText(detection.explanation)
                    }

                    y += 8

                    // ── Context image ──
                    if let contextImage = detection.contextImage {
                        drawText("Vehicle Location", bold: true)
                        drawImage(contextImage)
                    }

                    // ── Crop image ──
                    if let cropImage = detection.cropImage {
                        drawText("Damage Close-Up", bold: true)
                        drawImage(cropImage)
                    }

                    y += 20
                }

                // ─────────────────────────────────────────────
                // FOOTER
                // ─────────────────────────────────────────────

                newPageIfNeeded(80)
                y += 20

                drawText(
                    "Generated by Agentic Robot AI",
                    font: .systemFont(ofSize: 14),
                    bold: true
                )
            }

            print("PDF CREATED:", url)
            return url

        } catch {
            print("PDF ERROR:", error)
            return nil
        }
    }
}
