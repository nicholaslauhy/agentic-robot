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

                let casesPerDamagePage = 3
                let damagePageCount = max(1, Int(ceil(Double(max(detections.count, 1)) / Double(casesPerDamagePage))))
                let totalPageCount = 2 + damagePageCount
                var currentPageNumber = 0

                func beginReportPage() {
                    currentPageNumber += 1
                    context.beginPage()
                    drawHeader(pageText: "\(currentPageNumber) of \(totalPageCount)")
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
                    beginReportPage()

                    let tableTop: CGFloat = 215
                    drawLine(x1: left, y1: tableTop, x2: right, y2: tableTop, width: 1)
                    drawLine(x1: left, y1: tableTop + 34, x2: right, y2: tableTop + 34, width: 3)

                    let col1: CGFloat = left
                    let col2: CGFloat = 270
                    let col3: CGFloat = 450
                    drawLine(x1: col2, y1: tableTop, x2: col2, y2: tableTop + 287)
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
                    let idRowH: CGFloat = 56
                    drawField(label: "ID Type / ID No.", value: stageOne.idTypeAndNo, rect: CGRect(x: left, y: y, width: col2 - left, height: idRowH / 2), labelHeight: 13, valueFontSize: 9)
                    drawField(label: "FIN NO /", value: stageOne.finNo, rect: CGRect(x: left, y: y + idRowH / 2, width: col2 - left, height: idRowH / 2), labelHeight: 13, valueFontSize: 9)
                    drawField(label: "Contact No.\n\(stageOne.contactType)", value: stageOne.contactNumber, rect: CGRect(x: col2, y: y, width: right - col2, height: idRowH))
                    y += idRowH
                    drawLine(x1: left, y1: y, x2: right, y2: y)
                    drawField(label: "Nationality", value: stageOne.nationality, rect: CGRect(x: left, y: y, width: col2 - left, height: 34))
                    drawField(label: "Email Address", value: stageOne.emailAddress, rect: CGRect(x: col2, y: y, width: right - col2, height: 34))
                    y += 34
                    drawLine(x1: left, y1: y, x2: right, y2: y)
                    drawLine(x1: 325, y1: y, x2: 325, y2: y + 34)
                    drawLine(x1: 380, y1: y, x2: 380, y2: y + 34)
                    drawLine(x1: 450, y1: y, x2: 450, y2: y + 34)
                    drawField(label: "Occupation", value: stageOne.occupation, rect: CGRect(x: left, y: y, width: col2 - left, height: 34))
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
                    drawLine(x1: left + 2, y1: y + 15, x2: left + 70, y2: y + 15, width: 0.7)
                    y += 18
                    drawString(buildOverallSummary(), in: CGRect(x: left, y: y, width: pageWidth, height: 38), font: .systemFont(ofSize: 8.3))
                    y += 45

                    fillRect(CGRect(x: left, y: y, width: pageWidth, height: 16), color: UIColor(white: 0.78, alpha: 1))
                    drawRect(CGRect(x: left, y: y, width: pageWidth, height: 16))
                    drawString("Property Information", in: CGRect(x: left + 2, y: y + 2, width: pageWidth - 4, height: 12), font: .systemFont(ofSize: 10))
                    y += 52
                    drawLine(x1: left, y1: y, x2: right, y2: y)
                    y += 20
                    drawLine(x1: left, y1: y, x2: right, y2: y)
                    // Signature/case boxes can overflow this page because the Stage 1 table is tall.
                    // Keep the Property Information area on page 1, then continue the exact
                    // NP299-style signature block on the next page.
                }

                func drawSignatureContinuationPage() {
                    beginReportPage()
                    drawBottomSignatureBlock(y: 215)
                }

                func drawBottomSignatureBlock(y: CGFloat) {
                    let colGap: CGFloat = 25
                    let colWidth = (pageWidth - colGap) / 2
                    let leftCol = left
                    let rightCol = left + colWidth + colGap
                    let row1H: CGFloat = 55
                    let row2H: CGFloat = 55
                    let row3H: CGFloat = 70
                    let totalH = row1H + row2H + row3H

                    // Outer boxes for the two columns, matching the reference layout.
                    drawRect(CGRect(x: leftCol, y: y, width: colWidth, height: totalH))
                    drawRect(CGRect(x: rightCol, y: y, width: colWidth, height: totalH))

                    // Row separators.
                    drawLine(x1: leftCol, y1: y + row1H, x2: leftCol + colWidth, y2: y + row1H)
                    drawLine(x1: leftCol, y1: y + row1H + row2H, x2: leftCol + colWidth, y2: y + row1H + row2H)
                    drawLine(x1: rightCol, y1: y + row1H, x2: rightCol + colWidth, y2: y + row1H)
                    drawLine(x1: rightCol, y1: y + row1H + row2H, x2: rightCol + colWidth, y2: y + row1H + row2H)

                    // Left column: officer signature + name.
                    drawString("Signature of Officer Recording the Report:", in: CGRect(x: leftCol + 5, y: y + 6, width: colWidth - 86, height: 13), font: .boldSystemFont(ofSize: 8.5))
                    drawString(valueOrBlank(stageTwo.officerRecordingName), in: CGRect(x: leftCol + 5, y: y + 22, width: colWidth - 100, height: 34), font: .boldSystemFont(ofSize: 8.5))
                    if let signature = stageTwo.officerSignature {
                        signature.draw(in: CGRect(x: leftCol + colWidth - 72, y: y + 9, width: 50, height: 40))
                    }

                    // Right column: informant signature.
                    drawString("Signature Of Informant:", in: CGRect(x: rightCol + 5, y: y + 6, width: colWidth - 86, height: 13), font: .boldSystemFont(ofSize: 8.5))
                    if let signature = stageTwo.informantSignature {
                        signature.draw(in: CGRect(x: rightCol + colWidth - 72, y: y + 9, width: 50, height: 40))
                    }

                    // Left row 2: interpreter signature / default text.
                    let interpreterY = y + row1H
                    drawString("Signature Of Interpreter:", in: CGRect(x: leftCol + 5, y: interpreterY + 7, width: colWidth - 10, height: 13), font: .boldSystemFont(ofSize: 8.5))
                    if let interpreterSignature = stageTwo.interpreterSignature {
                        interpreterSignature.draw(in: CGRect(x: leftCol + 8, y: interpreterY + 23, width: colWidth - 16, height: 26))
                    } else {
                        drawString(valueOrBlank(stageTwo.interpreterAvailability, fallback: "Not applicable"), in: CGRect(x: leftCol + 5, y: interpreterY + 22, width: colWidth - 10, height: 14), font: .boldSystemFont(ofSize: 8.5))
                    }

                    // Right row 2: date/time.
                    let dateY = y + row1H
                    drawString("Date/Time:", in: CGRect(x: rightCol + 5, y: dateY + 8, width: 80, height: 13), font: .boldSystemFont(ofSize: 8.5))
                    drawString(valueOrBlank(stageTwo.informantSignatureDateTime, fallback: dateReportMade), in: CGRect(x: rightCol + 5, y: dateY + 24, width: colWidth - 10, height: 18), font: .systemFont(ofSize: 8.5))

                    // Bottom row.
                    let bottomY = y + row1H + row2H
                    drawString("Officer In-Charge Of Case:", in: CGRect(x: leftCol + 5, y: bottomY + 8, width: colWidth - 10, height: 13), font: .boldSystemFont(ofSize: 8.5))
                    drawString(valueOrBlank(stageTwo.officerInCharge), in: CGRect(x: leftCol + 5, y: bottomY + 26, width: colWidth - 10, height: row3H - 34), font: .systemFont(ofSize: 8.5))
                    drawString("Classification Of Case:", in: CGRect(x: rightCol + 5, y: bottomY + 8, width: colWidth - 10, height: 13), font: .boldSystemFont(ofSize: 8.5))
                    drawString(valueOrBlank(stageTwo.classificationOfCase), in: CGRect(x: rightCol + 5, y: bottomY + 26, width: colWidth - 10, height: row3H - 34), font: .systemFont(ofSize: 8.5))
                }

                func drawSignaturePage() {
                    beginReportPage()

                    // Signature/case section — intentionally drawn without a grey/black
                    // title row, matching the requested NP299-style bottom layout.
                    let y: CGFloat = 215
                    let gap: CGFloat = 24
                    let colWidth = (pageWidth - gap) / 2
                    let leftCol = left
                    let rightCol = left + colWidth + gap
                    let topRowH: CGFloat = 100
                    let middleRowH: CGFloat = 90
                    let bottomRowH: CGFloat = 130
                    let totalH = topRowH + middleRowH + bottomRowH

                    let leftBox = CGRect(x: leftCol, y: y, width: colWidth, height: totalH)
                    let rightBox = CGRect(x: rightCol, y: y, width: colWidth, height: totalH)

                    drawRect(leftBox)
                    drawRect(rightBox)

                    // Row separators inside both columns
                    drawLine(x1: leftCol, y1: y + topRowH, x2: leftCol + colWidth, y2: y + topRowH)
                    drawLine(x1: leftCol, y1: y + topRowH + middleRowH, x2: leftCol + colWidth, y2: y + topRowH + middleRowH)
                    drawLine(x1: rightCol, y1: y + topRowH, x2: rightCol + colWidth, y2: y + topRowH)
                    drawLine(x1: rightCol, y1: y + topRowH + middleRowH, x2: rightCol + colWidth, y2: y + topRowH + middleRowH)

                    // Left column, first row: officer signature + name inside the same row.
                    drawString(
                        "Signature of Officer Recording the Report:",
                        in: CGRect(x: leftCol + 6, y: y + 8, width: colWidth - 100, height: 14),
                        font: .boldSystemFont(ofSize: 9.5)
                    )
                    drawString(
                        valueOrBlank(stageTwo.officerRecordingName),
                        in: CGRect(x: leftCol + 6, y: y + 26, width: colWidth - 105, height: 48),
                        font: .boldSystemFont(ofSize: 9)
                    )
                    let officerSigBox = CGRect(x: leftCol + colWidth - 86, y: y + 24, width: 66, height: 58)
                    if let officerSignature = stageTwo.officerSignature {
                        officerSignature.draw(in: officerSigBox)
                    }

                    // Left column, second row: interpreter signature/default text.
                    let interpreterY = y + topRowH
                    drawString(
                        "Signature Of Interpreter:",
                        in: CGRect(x: leftCol + 6, y: interpreterY + 8, width: colWidth - 12, height: 14),
                        font: .boldSystemFont(ofSize: 9.5)
                    )
                    let interpreterBox = CGRect(x: leftCol + 6, y: interpreterY + 28, width: colWidth - 12, height: 50)
                    if let interpreterSignature = stageTwo.interpreterSignature {
                        interpreterSignature.draw(in: interpreterBox.insetBy(dx: 6, dy: 4))
                    } else {
                        drawString(
                            valueOrBlank(stageTwo.interpreterAvailability, fallback: "Not applicable"),
                            in: CGRect(x: leftCol + 6, y: interpreterY + 25, width: colWidth - 12, height: 18),
                            font: .systemFont(ofSize: 9)
                        )
                    }

                    // Left column, third row: officer in-charge.
                    let officerCaseY = y + topRowH + middleRowH
                    drawString(
                        "Officer In-Charge Of Case:",
                        in: CGRect(x: leftCol + 6, y: officerCaseY + 8, width: colWidth - 12, height: 14),
                        font: .boldSystemFont(ofSize: 9.5)
                    )
                    drawString(
                        valueOrBlank(stageTwo.officerInCharge),
                        in: CGRect(x: leftCol + 6, y: officerCaseY + 30, width: colWidth - 12, height: bottomRowH - 38),
                        font: .systemFont(ofSize: 9)
                    )

                    // Right column, first row: informant signature.
                    drawString(
                        "Signature Of Informant:",
                        in: CGRect(x: rightCol + 6, y: y + 8, width: colWidth - 12, height: 14),
                        font: .boldSystemFont(ofSize: 9.5)
                    )
                    let informantSigBox = CGRect(x: rightCol + colWidth - 112, y: y + 24, width: 82, height: 58)
                    if let informantSignature = stageTwo.informantSignature {
                        informantSignature.draw(in: informantSigBox)
                    }

                    // Right column, second row: date/time.
                    let dateY = y + topRowH
                    drawString(
                        "Date/Time:",
                        in: CGRect(x: rightCol + 6, y: dateY + 8, width: colWidth - 12, height: 14),
                        font: .boldSystemFont(ofSize: 9.5)
                    )
                    drawString(
                        valueOrBlank(stageTwo.informantSignatureDateTime),
                        in: CGRect(x: rightCol + 6, y: dateY + 30, width: colWidth - 12, height: 40),
                        font: .systemFont(ofSize: 9)
                    )

                    // Right column, third row: classification.
                    let classificationY = y + topRowH + middleRowH
                    drawString(
                        "Classification Of Case:",
                        in: CGRect(x: rightCol + 6, y: classificationY + 8, width: colWidth - 12, height: 14),
                        font: .boldSystemFont(ofSize: 9.5)
                    )
                    drawString(
                        valueOrBlank(stageTwo.classificationOfCase),
                        in: CGRect(x: rightCol + 6, y: classificationY + 30, width: colWidth - 12, height: bottomRowH - 38),
                        font: .systemFont(ofSize: 9)
                    )
                }

                @discardableResult
                func drawImageFit(_ image: UIImage, in rect: CGRect) -> CGRect {
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
                    return drawRect
                }

                func drawImageFit(_ image: UIImage, in rect: CGRect, normalizedBBox: CGRect?) {
                    let fittedRect = drawImageFit(image, in: rect)
                    guard let bbox = normalizedBBox else { return }

                    let boxRect = CGRect(
                        x: fittedRect.minX + bbox.minX * fittedRect.width,
                        y: fittedRect.minY + bbox.minY * fittedRect.height,
                        width: bbox.width * fittedRect.width,
                        height: bbox.height * fittedRect.height
                    )

                    let cg = UIGraphicsGetCurrentContext()
                    cg?.saveGState()
                    cg?.setStrokeColor(UIColor.orange.cgColor)
                    cg?.setLineWidth(2.2)
                    cg?.stroke(boxRect)
                    cg?.restoreGState()
                }

                func drawPageTwo() {
                    beginReportPage()

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
                            beginReportPage()
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
                            if detection.normalizedBBox == nil {
                                drawImageFit(contextImage, in: CGRect(x: 315, y: y + 38, width: 95, height: 90))
                            } else {
                                drawImageFit(contextImage, in: CGRect(x: 315, y: y + 38, width: 95, height: 90), normalizedBBox: detection.normalizedBBox)
                            }
                        }
                        if let cropImage = detection.cropImage {
                            drawString("Damage Close-Up", in: CGRect(x: 430, y: y + 24, width: 95, height: 12), font: .boldSystemFont(ofSize: 8))
                            drawImageFit(cropImage, in: CGRect(x: 430, y: y + 38, width: 95, height: 90))
                        }

                        y += boxHeight + 14
                    }
                }

                drawPageOne()
                drawSignatureContinuationPage()
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
