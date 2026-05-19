import UIKit

struct DamageReportGenerator {

    static func generatePDF(
        plate: String,
        carType: String,
        detections: [MutableDamageDetection],
        scanImages: [UIImage]
    ) -> URL? {
        generatePDF(
            plate: plate,
            carType: carType,
            detections: detections,
            scanImages: scanImages,
            policeStation: PoliceStationDetails.defaultStation,
            stageOne: PoliceReportStageOneDetails(),
            stageTwo: PoliceReportStageTwoDetails()
        )
    }

    static func generatePDF(
        plate: String,
        carType: String,
        detections: [MutableDamageDetection],
        scanImages: [UIImage],
        policeStation: PoliceStationDetails = .defaultStation,
        stageOne: PoliceReportStageOneDetails,
        stageTwo: PoliceReportStageTwoDetails
    ) -> URL? {

        let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        let url = documents.appendingPathComponent("PoliceDamageReport.pdf")
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        do {
            try renderer.writePDF(to: url) { context in

                let left: CGFloat = 50
                let right: CGFloat = 545
                let top: CGFloat = 36
                let pageWidth = right - left

                let displayDateFormatter = DateFormatter()
                displayDateFormatter.locale = Locale(identifier: "en_US_POSIX")
                displayDateFormatter.dateFormat = "d MMMM yyyy, HH:mm"
                let generatedDateTime = displayDateFormatter.string(from: Date())

                let compactDateFormatter = DateFormatter()
                compactDateFormatter.locale = Locale(identifier: "en_US_POSIX")
                compactDateFormatter.dateFormat = "yyyyMMdd"
                let compactDate = compactDateFormatter.string(from: Date())
                let cleanedPlate = plate.replacingOccurrences(of: " ", with: "").uppercased()
                let reportNo = "F/\(compactDate)/\(cleanedPlate)"
                let dateReportMade = generatedDateTime
                let videReportNo = stageOne.videReportNo
                let stageOneDiaryNo = stageOne.stationDiaryNo.trimmingCharacters(in: .whitespacesAndNewlines)
                let stationDiaryNo = stageOneDiaryNo.isEmpty
                    ? "D/\(compactDate)/\(String(format: "%04d", Int.random(in: 0...9999)))"
                    : stageOne.stationDiaryNo

                func isBlank(_ value: String) -> Bool {
                    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }

                func valueOrBlank(_ text: String, fallback: String = "") -> String {
                    isBlank(text) ? fallback : text
                }

                func drawString(
                    _ text: String,
                    in rect: CGRect,
                    font: UIFont = .systemFont(ofSize: 9),
                    color: UIColor = .black,
                    alignment: NSTextAlignment = .left
                ) {
                    let paragraph = NSMutableParagraphStyle()
                    paragraph.alignment = alignment
                    paragraph.lineBreakMode = .byWordWrapping
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: color,
                        .paragraphStyle: paragraph
                    ]
                    (text as NSString).draw(in: rect, withAttributes: attrs)
                }

                func drawLine(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat, width: CGFloat = 0.8) {
                    let cg = UIGraphicsGetCurrentContext()
                    cg?.saveGState()
                    cg?.setStrokeColor(UIColor.black.cgColor)
                    cg?.setLineWidth(width)
                    cg?.move(to: CGPoint(x: x1, y: y1))
                    cg?.addLine(to: CGPoint(x: x2, y: y2))
                    cg?.strokePath()
                    cg?.restoreGState()
                }

                func drawRect(_ rect: CGRect, width: CGFloat = 0.8) {
                    let cg = UIGraphicsGetCurrentContext()
                    cg?.saveGState()
                    cg?.setStrokeColor(UIColor.black.cgColor)
                    cg?.setLineWidth(width)
                    cg?.stroke(rect)
                    cg?.restoreGState()
                }

                func fillRect(_ rect: CGRect, color: UIColor) {
                    let cg = UIGraphicsGetCurrentContext()
                    cg?.saveGState()
                    cg?.setFillColor(color.cgColor)
                    cg?.fill(rect)
                    cg?.restoreGState()
                }

                func drawBarcode(in rect: CGRect) {
                    let cg = UIGraphicsGetCurrentContext()
                    cg?.saveGState()
                    cg?.setFillColor(UIColor.black.cgColor)

                    // Fill the full barcode width using a deterministic pseudo-barcode
                    // based on the report number. This keeps the visible barcode long
                    // while ensuring the text underneath matches Report No.
                    let seedBytes = Array(reportNo.utf8)
                    let modules = max(96, seedBytes.count * 8)
                    let moduleWidth = rect.width / CGFloat(modules)

                    for i in 0..<modules {
                        let byte = Int(seedBytes[i % seedBytes.count])
                        let shouldDraw = ((byte + i * 31 + (i / 3)) % 5) != 0
                        if shouldDraw {
                            let barWidth = moduleWidth * CGFloat(((byte + i) % 3) + 1)
                            let x = rect.minX + CGFloat(i) * moduleWidth
                            cg?.fill(CGRect(x: x, y: rect.minY, width: min(barWidth, rect.maxX - x), height: rect.height))
                        }
                    }
                    cg?.restoreGState()
                }

                func drawCrest(at origin: CGPoint) {
                    let crestRect = CGRect(x: origin.x, y: origin.y, width: 52, height: 52)
                    let cg = UIGraphicsGetCurrentContext()
                    cg?.saveGState()
                    cg?.setStrokeColor(UIColor(red: 0.15, green: 0.24, blue: 0.43, alpha: 1).cgColor)
                    cg?.setFillColor(UIColor(red: 0.92, green: 0.95, blue: 1, alpha: 1).cgColor)
                    cg?.setLineWidth(2)
                    cg?.fillEllipse(in: crestRect)
                    cg?.strokeEllipse(in: crestRect)
                    let shield = CGRect(x: crestRect.midX - 12, y: crestRect.minY + 12, width: 24, height: 28)
                    cg?.setFillColor(UIColor(red: 0.88, green: 0.12, blue: 0.14, alpha: 1).cgColor)
                    cg?.fill(shield)
                    cg?.restoreGState()
                    drawString("POLIS", in: CGRect(x: crestRect.minX, y: crestRect.maxY - 12, width: 52, height: 10), font: .boldSystemFont(ofSize: 6), color: .white, alignment: .center)
                }

                func drawField(label: String, value: String, rect: CGRect, labelHeight: CGFloat = 17, valueFontSize: CGFloat = 9.5) {
                    drawString(label, in: CGRect(x: rect.minX + 2, y: rect.minY + 2, width: rect.width - 4, height: labelHeight), font: .boldSystemFont(ofSize: 9.5))
                    let text = valueOrBlank(value)
                    drawString(text, in: CGRect(x: rect.minX + 2, y: rect.minY + labelHeight, width: rect.width - 4, height: rect.height - labelHeight - 2), font: .systemFont(ofSize: valueFontSize))
                }

                func cleanDamageType(_ damageType: String) -> String {
                    let lower = damageType.lowercased()
                    if lower.contains("scratch") { return "Scratch" }
                    if lower.contains("dent") { return "Dent" }
                    if lower.contains("crack") { return "Crack" }
                    if lower.contains("paint") { return "Paint damage" }
                    if lower.contains("scuff") { return "Scuff" }
                    return damageType.replacingOccurrences(of: "_", with: " ").capitalized
                }

                func cleanAngleName(_ angleName: String) -> String {
                    let lower = angleName.lowercased()
                    if lower.contains("front") { return "Front" }
                    if lower.contains("rear") || lower.contains("back") { return "Rear" }
                    if lower.contains("left") { return "Left Side" }
                    if lower.contains("right") { return "Right Side" }
                    return angleName
                }

                func pluralize(_ word: String, count: Int) -> String {
                    if count == 1 { return word.lowercased() }
                    switch word.lowercased() {
                    case "scratch": return "scratches"
                    case "dent": return "dents"
                    case "crack": return "cracks"
                    case "scuff": return "scuffs"
                    case "paint damage": return "paint damage areas"
                    default: return "\(word.lowercased())s"
                    }
                }

                func buildOverallSummary() -> String {
                    if detections.isEmpty {
                        return "No visible damage was detected in the submitted vehicle images for vehicle \(plate) (\(carType))."
                    }

                    let angleOrder = ["Front", "Rear", "Left Side", "Right Side"]
                    var angleDamageCounts: [String: [String: Int]] = [:]
                    for angle in angleOrder { angleDamageCounts[angle] = [:] }

                    for detection in detections {
                        let angle = cleanAngleName(detection.angleName)
                        let damage = cleanDamageType(detection.damageType)
                        angleDamageCounts[angle, default: [:]][damage, default: 0] += 1
                    }

                    let affectedAngleParts = angleOrder.compactMap { angle -> String? in
                        guard let damageCounts = angleDamageCounts[angle], !damageCounts.isEmpty else { return nil }
                        let damageParts = damageCounts
                            .sorted { $0.key < $1.key }
                            .map { damageType, count in "\(count) \(pluralize(damageType, count: count))" }
                            .joined(separator: " and ")
                        return "\(damageParts) on the \(angle)"
                    }

                    var summary = "Vehicle \(plate) (\(carType)) was assessed from submitted images. Across the submitted vehicle images, \(detections.count) possible damage area\(detections.count == 1 ? "" : "s") were recorded: \(affectedAngleParts.joined(separator: ", "))."

                    let damagedAngles = Set(detections.map { cleanAngleName($0.angleName) })
                    let clearAngles = angleOrder.filter { !damagedAngles.contains($0) }
                    if !clearAngles.isEmpty {
                        summary += " No detected damage cases were recorded for the \(clearAngles.joined(separator: ", "))."
                    }
                    return summary
                }

                func drawHeader(pageText: String) {
                    drawCrest(at: CGPoint(x: left, y: top - 2))
                    drawString("SINGAPORE\nPOLICE FORCE", in: CGRect(x: left + 68, y: top + 4, width: 190, height: 42), font: .boldSystemFont(ofSize: 16), color: UIColor(red: 0.08, green: 0.13, blue: 0.35, alpha: 1))
                    drawString("POLICE REPORT (NP299)", in: CGRect(x: left, y: 112, width: 190, height: 16), font: .boldSystemFont(ofSize: 10))
                    drawString(policeStation.pdfHeaderText, in: CGRect(x: left, y: 135, width: 270, height: 70), font: .boldSystemFont(ofSize: 9))

                    let barcodeRect = CGRect(x: 315, y: 42, width: right - 315, height: 24)
                    drawBarcode(in: barcodeRect)
                    drawString(reportNo, in: CGRect(x: barcodeRect.minX, y: barcodeRect.maxY + 3, width: barcodeRect.width, height: 11), font: .boldSystemFont(ofSize: 7), alignment: .center)
                    drawString(pageText, in: CGRect(x: 510, y: 88, width: 35, height: 13), font: .boldSystemFont(ofSize: 10), alignment: .right)
                    drawString("Report No. \(reportNo)", in: CGRect(x: 315, y: 118, width: right - 315, height: 16), font: .boldSystemFont(ofSize: 10), alignment: .right)
                }

                func drawPageOne() {
                    context.beginPage()
                    drawHeader(pageText: "1 of 3")

                    let tableTop: CGFloat = 215
                    drawLine(x1: left, y1: tableTop, x2: right, y2: tableTop, width: 1)
                    drawLine(x1: left, y1: tableTop + 34, x2: right, y2: tableTop + 34, width: 3)

                    let col1: CGFloat = left
                    let col2: CGFloat = 270
                    let col3: CGFloat = 450
                    drawLine(x1: col2, y1: tableTop, x2: col2, y2: 515)
                    drawLine(x1: col3, y1: tableTop, x2: col3, y2: tableTop + 34)

                    drawField(label: "Date/Time Report Made", value: dateReportMade, rect: CGRect(x: col1, y: tableTop, width: col2 - col1, height: 34))
                    drawField(label: "Vide Report No.", value: videReportNo, rect: CGRect(x: col2, y: tableTop, width: col3 - col2, height: 34))
                    drawField(label: "Station Diary No.", value: stationDiaryNo, rect: CGRect(x: col3, y: tableTop, width: right - col3, height: 34))

                    var y: CGFloat = tableTop + 38
                    let rowH: CGFloat = 43
                    drawLine(x1: left, y1: y, x2: right, y2: y)
                    drawField(label: "Name Of Informant", value: stageOne.nameOfInformant, rect: CGRect(x: left, y: y, width: col2 - left, height: rowH))
                    drawField(label: "Address", value: stageOne.address, rect: CGRect(x: col2, y: y, width: right - col2, height: rowH))
                    y += rowH
                    drawLine(x1: left, y1: y, x2: right, y2: y)
                    drawField(label: "ID Type / ID No.", value: stageOne.idTypeAndNo, rect: CGRect(x: left, y: y, width: col2 - left, height: rowH))
                    drawField(label: "Contact No.\nHome/Office: \(stageOne.contactType)", value: stageOne.contactNumber, rect: CGRect(x: col2, y: y, width: right - col2, height: rowH))
                    y += rowH
                    drawLine(x1: left, y1: y, x2: right, y2: y)
                    drawField(label: "FIN NO /", value: stageOne.finNo, rect: CGRect(x: left, y: y, width: col2 - left, height: 34))
                    drawField(label: "Email Address", value: stageOne.emailAddress, rect: CGRect(x: col2, y: y, width: right - col2, height: 34))
                    y += 34
                    drawLine(x1: left, y1: y, x2: right, y2: y)
                    drawField(label: "Nationality", value: stageOne.nationality, rect: CGRect(x: left, y: y, width: col2 - left, height: 34))
                    drawField(label: "Occupation", value: stageOne.occupation, rect: CGRect(x: col2, y: y, width: right - col2, height: 34))
                    y += 34
                    drawLine(x1: left, y1: y, x2: right, y2: y)
                    drawLine(x1: 325, y1: y, x2: 325, y2: y + 34)
                    drawLine(x1: 380, y1: y, x2: 380, y2: y + 34)
                    drawLine(x1: 450, y1: y, x2: 450, y2: y + 34)
                    drawField(label: "Sex", value: stageOne.sex, rect: CGRect(x: col2, y: y, width: 55, height: 34))
                    drawField(label: "Age", value: stageOne.age, rect: CGRect(x: 325, y: y, width: 55, height: 34))
                    drawField(label: "Date of Birth", value: stageOne.dateOfBirth, rect: CGRect(x: 380, y: y, width: 70, height: 34))
                    drawField(label: "Race", value: stageOne.race, rect: CGRect(x: 450, y: y, width: right - 450, height: 34))
                    y += 34
                    drawLine(x1: left, y1: y, x2: right, y2: y)
                    drawField(label: "Institution/School Name", value: stageOne.institutionSchoolName, rect: CGRect(x: left, y: y, width: col2 - left, height: 34))
                    drawField(label: "Language", value: stageOne.language, rect: CGRect(x: col2, y: y, width: right - col2, height: 34))
                    y += 34
                    drawLine(x1: left, y1: y, x2: right, y2: y)
                    drawField(label: "Date/Time Of Incident", value: stageOne.dateTimeOfIncident, rect: CGRect(x: left, y: y, width: col2 - left, height: 48))
                    drawField(label: "Location Of Incident", value: stageOne.locationOfIncident, rect: CGRect(x: col2, y: y, width: right - col2, height: 48))
                    y += 48
                    drawLine(x1: left, y1: y, x2: right, y2: y)

                    y += 5
                    drawString("Brief details.", in: CGRect(x: left + 2, y: y, width: 120, height: 16), font: .boldSystemFont(ofSize: 10))
                    y += 30
                    drawString(buildOverallSummary(), in: CGRect(x: left, y: y, width: pageWidth, height: 58), font: .systemFont(ofSize: 8.8))
                    y += 78

                    fillRect(CGRect(x: left, y: y, width: pageWidth, height: 16), color: UIColor(white: 0.78, alpha: 1))
                    drawRect(CGRect(x: left, y: y, width: pageWidth, height: 16))
                    drawString("Property Information", in: CGRect(x: left + 2, y: y + 2, width: pageWidth - 4, height: 12), font: .systemFont(ofSize: 10))
                    y += 72
                    drawLine(x1: left, y1: y, x2: right, y2: y)
                    y += 30
                    drawLine(x1: left, y1: y, x2: right, y2: y)

                    // Signature and case officer details are drawn on their own page so the
                    // first page fields stay readable and the damage section remains unchanged.
                }

                func drawSignaturePage() {
                    context.beginPage()
                    drawHeader(pageText: "2 of 3")

                    var y: CGFloat = 210
                    fillRect(CGRect(x: left, y: y, width: pageWidth, height: 18), color: UIColor(white: 0.78, alpha: 1))
                    drawRect(CGRect(x: left, y: y, width: pageWidth, height: 18))
                    drawString("Report Signatures", in: CGRect(x: left + 3, y: y + 3, width: pageWidth - 6, height: 13), font: .boldSystemFont(ofSize: 10))
                    y += 28

                    let colGap: CGFloat = 20
                    let colWidth = (pageWidth - colGap) / 2
                    let leftCol = left
                    let rightCol = left + colWidth + colGap

                    func drawSignaturePanel(title: String, value: String, signature: UIImage?, dateTime: String, rect: CGRect) {
                        drawRect(rect)
                        drawString(title, in: CGRect(x: rect.minX + 8, y: rect.minY + 8, width: rect.width - 16, height: 14), font: .boldSystemFont(ofSize: 9.5))
                        drawString(valueOrBlank(value), in: CGRect(x: rect.minX + 8, y: rect.minY + 28, width: rect.width - 16, height: 24), font: .systemFont(ofSize: 9))
                        drawRect(CGRect(x: rect.minX + 8, y: rect.minY + 58, width: rect.width - 16, height: 70))
                        if let signature {
                            signature.draw(in: CGRect(x: rect.minX + 14, y: rect.minY + 64, width: rect.width - 28, height: 58))
                        }
                        drawString("Date/Time", in: CGRect(x: rect.minX + 8, y: rect.minY + 136, width: 80, height: 12), font: .boldSystemFont(ofSize: 8.5))
                        drawString(valueOrBlank(dateTime), in: CGRect(x: rect.minX + 8, y: rect.minY + 150, width: rect.width - 16, height: 20), font: .systemFont(ofSize: 9))
                    }

                    drawSignaturePanel(
                        title: "Signature Of Officer Recording The Report",
                        value: stageTwo.officerRecordingName,
                        signature: stageTwo.officerSignature,
                        dateTime: dateReportMade,
                        rect: CGRect(x: leftCol, y: y, width: colWidth, height: 178)
                    )

                    drawSignaturePanel(
                        title: "Signature Of Informant",
                        value: valueOrBlank(stageTwo.informantName, fallback: stageOne.nameOfInformant),
                        signature: stageTwo.informantSignature,
                        dateTime: stageTwo.informantSignatureDateTime,
                        rect: CGRect(x: rightCol, y: y, width: colWidth, height: 178)
                    )

                    y += 198

                    drawRect(CGRect(x: leftCol, y: y, width: colWidth, height: 130))
                    drawString("Signature Of Interpreter", in: CGRect(x: leftCol + 6, y: y + 6, width: colWidth - 12, height: 14), font: .boldSystemFont(ofSize: 9.5))
                    let interpreterBox = CGRect(x: leftCol + 6, y: y + 25, width: colWidth - 12, height: 62)
                    drawRect(interpreterBox)
                    if let interpreterSignature = stageTwo.interpreterSignature {
                        interpreterSignature.draw(in: interpreterBox.insetBy(dx: 6, dy: 6))
                    } else {
                        drawString(valueOrBlank(stageTwo.interpreterAvailability, fallback: "Not available"), in: interpreterBox.insetBy(dx: 6, dy: 20), font: .systemFont(ofSize: 9))
                    }
                    drawField(label: "Date/Time", value: stageTwo.interpreterSignatureDateTime, rect: CGRect(x: leftCol + 6, y: y + 92, width: colWidth - 12, height: 32))

                    drawRect(CGRect(x: rightCol, y: y, width: colWidth, height: 130))
                    drawField(label: "Name Of Officer In-Charge Of Case", value: stageTwo.officerInCharge, rect: CGRect(x: rightCol + 6, y: y + 6, width: colWidth - 12, height: 38))
                    drawField(label: "Classification Of Case", value: stageTwo.classificationOfCase, rect: CGRect(x: rightCol + 6, y: y + 46, width: colWidth - 12, height: 36))
                }

                func drawImageFit(_ image: UIImage, in rect: CGRect) {
                    let imageRatio = image.size.width / max(image.size.height, 1)
                    let rectRatio = rect.width / rect.height
                    var drawRect = rect
                    if imageRatio > rectRatio {
                        let height = rect.width / imageRatio
                        drawRect = CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
                    } else {
                        let width = rect.height * imageRatio
                        drawRect = CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: rect.height)
                    }
                    image.draw(in: drawRect)
                }

                func drawPageTwo() {
                    context.beginPage()
                    drawHeader(pageText: "3 of 3")

                    var y: CGFloat = 210
                    fillRect(CGRect(x: left, y: y, width: pageWidth, height: 18), color: UIColor(white: 0.78, alpha: 1))
                    drawRect(CGRect(x: left, y: y, width: pageWidth, height: 18))
                    drawString("Damage Case Information", in: CGRect(x: left + 3, y: y + 3, width: pageWidth - 6, height: 13), font: .boldSystemFont(ofSize: 10))
                    y += 28

                    if detections.isEmpty {
                        drawString("No damage cases were detected from the submitted vehicle images.", in: CGRect(x: left, y: y, width: pageWidth, height: 40), font: .systemFont(ofSize: 9))
                        return
                    }

                    for (index, detection) in detections.enumerated() {
                        if y > 700 {
                            context.beginPage()
                            drawHeader(pageText: "3 of 3")
                            y = 210
                        }

                        let boxHeight: CGFloat = 155
                        drawRect(CGRect(x: left, y: y, width: pageWidth, height: boxHeight))
                        fillRect(CGRect(x: left, y: y, width: pageWidth, height: 18), color: UIColor(white: 0.90, alpha: 1))
                        drawString("Case #\(index + 1)", in: CGRect(x: left + 4, y: y + 3, width: 120, height: 13), font: .boldSystemFont(ofSize: 10))

                        let damageType = cleanDamageType(detection.damageType)
                        let angleName = cleanAngleName(detection.angleName)
                        let confidence = "\(Int(detection.confidence * 100))%"
                        let caseText = "Damage Type: \(damageType)\nVehicle Angle: \(angleName)\nConfidence: \(confidence)\nAI Analysis: \(valueOrBlank(detection.explanation, fallback: "No extra AI explanation provided."))"
                        drawString(caseText, in: CGRect(x: left + 8, y: y + 26, width: 250, height: 118), font: .systemFont(ofSize: 8.6))

                        if let contextImage = detection.normalizedBBox == nil ? detection.contextImage : (detection.cleanContextImage ?? detection.contextImage) {
                            drawString("Vehicle Location", in: CGRect(x: 315, y: y + 24, width: 95, height: 12), font: .boldSystemFont(ofSize: 8))
                            drawImageFit(contextImage, in: CGRect(x: 315, y: y + 38, width: 95, height: 90))
                        }
                        if let cropImage = detection.cropImage {
                            drawString("Damage Close-Up", in: CGRect(x: 430, y: y + 24, width: 95, height: 12), font: .boldSystemFont(ofSize: 8))
                            drawImageFit(cropImage, in: CGRect(x: 430, y: y + 38, width: 95, height: 90))
                        }

                        y += boxHeight + 14
                    }
                }

                drawPageOne()
                drawSignaturePage()
                drawPageTwo()
            }

            print("PDF CREATED:", url)
            return url

        } catch {
            print("PDF ERROR:", error)
            return nil
        }
    }
}
