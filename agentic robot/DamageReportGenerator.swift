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
                    bold: Bool = false
                ) {

                    let actualFont = bold
                    ? UIFont.boldSystemFont(ofSize: font.pointSize)
                    : font

                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: actualFont,
                        .foregroundColor: UIColor.black
                    ]

                    let rect = CGRect(
                        x: x,
                        y: y,
                        width: 520,
                        height: 100
                    )

                    text.draw(
                        in: rect,
                        withAttributes: attrs
                    )

                    y += 24
                }

                func drawImage(
                    _ image: UIImage,
                    height: CGFloat = 180
                ) {

                    newPageIfNeeded(height + 20)

                    let width = 515.0

                    let rect = CGRect(
                        x: 40,
                        y: y,
                        width: width,
                        height: height
                    )

                    image.draw(in: rect)

                    y += height + 12
                }

                // FIRST PAGE

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

                drawText(
                    "Date: \(formatter.string(from: Date()))"
                )

                y += 10

                // SUMMARY

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

                let severity: String

                switch detections.count {
                case 0:
                    severity = "None"
                case 1...2:
                    severity = "Minor"
                case 3...5:
                    severity = "Moderate"
                default:
                    severity = "Severe"
                }

                drawText("- \(scratches) scratches detected")
                drawText("- \(dents) dents detected")
                drawText("- Severity: \(severity)")

                y += 20

                // DAMAGE CASES

                drawText(
                    "DAMAGE CASES",
                    font: .systemFont(ofSize: 20),
                    bold: true
                )

                for (index, detection) in detections.enumerated() {

                    newPageIfNeeded(420)

                    drawText(
                        "Case #\(index + 1)",
                        font: .systemFont(ofSize: 18),
                        bold: true
                    )

                    drawText(
                        "Damage Type: \(detection.damageType.capitalized)"
                    )

                    drawText(
                        "Vehicle Angle: \(detection.angleName)"
                    )

                    drawText(
                        "Confidence: \(Int(detection.confidence * 100))%"
                    )

                    y += 8

                    // CONTEXT IMAGE

                    if let context = detection.contextImage {

                        drawText(
                            "Vehicle Location",
                            bold: true
                        )

                        drawImage(context, height: 180)
                    }

                    // CROP IMAGE

                    if let crop = detection.cropImage {

                        drawText(
                            "Damage Close-Up",
                            bold: true
                        )

                        drawImage(crop, height: 160)
                    }

                    y += 20
                }

                // FINAL FOOTER

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
