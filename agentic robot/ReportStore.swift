import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Shared Report Model
struct ReportEntry: Identifiable {
    let id: String          // Firestore document ID (the barcode number)
    let reportNo: String
    let plate: String
    let carType: String
    let generatedBy: String
    let detectionCount: Int
    let createdAt: Date?
    let barcodeId: String
    let pdfFileName: String?
    let pdfBase64: String?

    var dateString: String {
        guard let date = createdAt else { return "Unknown date" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        return formatter.string(from: date)
    }

    var shortDate: String {
        guard let date = createdAt else { return "-" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yy"
        return formatter.string(from: date)
    }

    var hasPDF: Bool {
        if let pdfFileName, !pdfFileName.isEmpty { return true }
        if let pdfBase64, !pdfBase64.isEmpty { return true }
        return false
    }
}

struct ReportStore {

    // Keep this under Firestore's 1 MiB document limit.
    // Larger PDFs will still be saved locally on the generating device via pdfFileName.
    private static let maxFirestorePDFBytes = 850_000

    static func makeNumericBarcodeId(date: Date = Date()) -> String {
        // Always produce a positive, digits-only barcode.
        // Format: YYYYMMDD + 4 random digits = 12 digits.
        // This avoids negative IDs caused by signed integer overflow / hashing.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        let compactDate = formatter.string(from: date)
        let suffix = String(format: "%04d", Int.random(in: 0...9999))
        return "\(compactDate)\(suffix)"
    }

    static func makeReportNo(plate: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        let compactDate = formatter.string(from: date)
        let cleanedPlate = plate.replacingOccurrences(of: " ", with: "").uppercased()
        return "F/\(compactDate)/\(cleanedPlate)"
    }

    static func reportsDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("GeneratedReports", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func localPDFURL(for barcodeId: String) -> URL {
        reportsDirectory().appendingPathComponent("\(barcodeId).pdf")
    }

    @discardableResult
    static func copyPDFToLocalStore(from sourceURL: URL, barcodeId: String) -> URL? {
        let destination = localPDFURL(for: barcodeId)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination
        } catch {
            print("Failed to copy PDF into local report store: \(error.localizedDescription)")
            return nil
        }
    }

    static func resolvedPDFURL(for report: ReportEntry) -> URL? {
        let localURL = localPDFURL(for: report.barcodeId)
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }

        guard let pdfBase64 = report.pdfBase64,
              let data = Data(base64Encoded: pdfBase64) else {
            return nil
        }

        do {
            try data.write(to: localURL, options: [.atomic])
            return localURL
        } catch {
            print("Failed to recreate PDF from Firestore base64: \(error.localizedDescription)")
            return nil
        }
    }

    static func saveReport(
        reportNo: String,
        plate: String,
        carType: String,
        generatedBy: String,
        detectionCount: Int,
        numericBarcodeId: String,
        pdfURL: URL? = nil
    ) {
        var data: [String: Any] = [
            "reportNo": reportNo,
            "barcodeId": numericBarcodeId,
            "plate": plate,
            "carType": carType,
            "generatedBy": generatedBy,
            "detectionCount": detectionCount,
            "createdAt": FieldValue.serverTimestamp()
        ]

        if let pdfURL {
            let localURL = copyPDFToLocalStore(from: pdfURL, barcodeId: numericBarcodeId)
            data["pdfFileName"] = localURL?.lastPathComponent ?? "\(numericBarcodeId).pdf"

            if let pdfData = try? Data(contentsOf: pdfURL), pdfData.count <= maxFirestorePDFBytes {
                data["pdfBase64"] = pdfData.base64EncodedString()
                data["pdfStoredInFirestore"] = true
            } else {
                data["pdfStoredInFirestore"] = false
                data["pdfStorageNote"] = "PDF was larger than the safe Firestore document limit and was stored locally on the generating device."
            }
        }

        Firestore.firestore()
            .collection("reports")
            .document(numericBarcodeId)
            .setData(data, merge: true)
    }
}
