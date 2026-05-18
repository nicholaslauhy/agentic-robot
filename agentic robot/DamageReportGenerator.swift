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

                    let rect = CGRect(
                        x: x,
                        y: y,
                        width: maxWidth,
                        height: textHeight
                    )

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
                    let drawWidth = drawHeight / aspectRatio

                    newPageIfNeeded(drawHeight + 20)

                    let xOffset: CGFloat = 40 + (availableWidth - drawWidth) / 2

                    let rect = CGRect(
                        x: xOffset,
                        y: y,
                        width: drawWidth,
                        height: drawHeight
                    )

                    image.draw(in: rect)
                    y += drawHeight + 12
                }

                func cleanDamageType(_ damageType: String) -> String {
                    let lower = damageType.lowercased()

                    if lower.contains("scratch") {
                        return "Scratch"
                    }

                    if lower.contains("dent") {
                        return "Dent"
                    }

                    if lower.contains("crack") {
                        return "Crack"
                    }

                    if lower.contains("paint") {
                        return "Paint damage"
                    }

                    if lower.contains("scuff") {
                        return "Scuff"
                    }

                    return damageType
                        .replacingOccurrences(of: "_", with: " ")
                        .capitalized
                }

                func cleanAngleName(_ angleName: String) -> String {
                    let lower = angleName.lowercased()

                    if lower.contains("front") {
                        return "Front"
                    }

                    if lower.contains("rear") || lower.contains("back") {
                        return "Rear"
                    }

                    if lower.contains("left") {
                        return "Left Side"
                    }

                    if lower.contains("right") {
                        return "Right Side"
                    }

                    return angleName
                }

                func pluralize(_ word: String, count: Int) -> String {
                    if count == 1 {
                        return word
                    }

                    switch word.lowercased() {
                    case "scratch":
                        return "scratches"
                    case "dent":
                        return "dents"
                    case "crack":
                        return "cracks"
                    case "scuff":
                        return "scuffs"
                    case "paint damage":
                        return "paint damage areas"
                    default:
                        return "\(word.lowercased())s"
                    }
                }

                func buildOverallSummary(
                    detections: [MutableDamageDetection]
                ) -> String {
                    if detections.isEmpty {
                        return "No visible damage was detected in the submitted vehicle images."
                    }

                    let angleOrder = [
                        "Front",
                        "Rear",
                        "Left Side",
                        "Right Side"
                    ]

                    var angleDamageCounts: [String: [String: Int]] = [:]

                    for angle in angleOrder {
                        angleDamageCounts[angle] = [:]
                    }

                    for detection in detections {
                        let angle = cleanAngleName(detection.angleName)
                        let damage = cleanDamageType(detection.damageType)

                        if angleDamageCounts[angle] == nil {
                            angleDamageCounts[angle] = [:]
                        }

                        angleDamageCounts[angle]?[damage, default: 0] += 1
                    }

                    var affectedAngleParts: [String] = []

                    for angle in angleOrder {
                        guard let damageCounts = angleDamageCounts[angle],
                              !damageCounts.isEmpty else {
                            continue
                        }

                        let damageParts = damageCounts
                            .sorted { $0.key < $1.key }
                            .map { damageType, count in
                                "\(count) \(pluralize(damageType, count: count))"
                            }
                            .joined(separator: " and ")

                        affectedAngleParts.append("\(damageParts) on the \(angle)")
                    }

                    let affectedAngles = affectedAngleParts.joined(separator: ", ")

                    let damagedAngles = Set(
                        detections.map {
                            cleanAngleName($0.angleName)
                        }
                    )

                    let clearAngles = angleOrder.filter {
                        !damagedAngles.contains($0)
                    }

                    let totalCases = detections.count

                    var summary = "Across the submitted vehicle images, \(totalCases) possible damage area\(totalCases == 1 ? "" : "s") were recorded: \(affectedAngles)."

                    if !clearAngles.isEmpty {
                        summary += " No detected damage cases were recorded for the \(clearAngles.joined(separator: ", "))."
                    }

                    return summary
                }

                func countDamageType(
                    _ target: String,
                    in detections: [MutableDamageDetection]
                ) -> Int {
                    detections.filter {
                        cleanDamageType($0.damageType).lowercased().contains(target.lowercased())
                    }.count
                }

                func overallSeverity(
                    detectionCount: Int
                ) -> String {
                    switch detectionCount {
                    case 0:
                        return "None"
                    case 1...2:
                        return "Minor"
                    case 3...5:
                        return "Moderate"
                    default:
                        return "Severe"
                    }
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

                let scratches = countDamageType("scratch", in: detections)
                let dents = countDamageType("dent", in: detections)
                let cracks = countDamageType("crack", in: detections)
                let paintDamage = countDamageType("paint", in: detections)

                drawText("- \(detections.count) possible damage area\(detections.count == 1 ? "" : "s") recorded")
                drawText("- \(scratches) \(pluralize("Scratch", count: scratches)) detected")
                drawText("- \(dents) \(pluralize("Dent", count: dents)) detected")

                if cracks > 0 {
                    drawText("- \(cracks) \(pluralize("Crack", count: cracks)) detected")
                }

                if paintDamage > 0 {
                    drawText("- \(paintDamage) \(pluralize("Paint damage", count: paintDamage)) detected")
                }

                drawText("- Overall Severity: \(overallSeverity(detectionCount: detections.count))")

                y += 8

                drawText(
                    "Overall Image Summary",
                    font: .systemFont(ofSize: 16),
                    bold: true
                )

                drawWrappedText(
                    buildOverallSummary(detections: detections),
                    font: .systemFont(ofSize: 13),
                    color: .darkGray
                )

                y += 20

                // ─────────────────────────────────────────────
                // DAMAGE CASES
                // ─────────────────────────────────────────────

                drawText(
                    "DAMAGE CASES",
                    font: .systemFont(ofSize: 20),
                    bold: true
                )

                if detections.isEmpty {
                    drawWrappedText(
                        "No damage cases were detected from the submitted vehicle images.",
                        font: .systemFont(ofSize: 13),
                        color: .darkGray
                    )
                }

                for (index, detection) in detections.enumerated() {

                    newPageIfNeeded(420)

                    let damageType = cleanDamageType(detection.damageType)
                    let angleName = cleanAngleName(detection.angleName)

                    // ── Case header ──
                    drawText(
                        "Case #\(index + 1)",
                        font: .systemFont(ofSize: 18),
                        bold: true
                    )

                    // ── Detection metadata ──
                    drawText("Damage Type: \(damageType)")
                    drawText("Vehicle Angle: \(angleName)")
                    drawText("Confidence: \(Int(detection.confidence * 100))%")

                    // ── Short AI analysis only, no repair advice ──
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
