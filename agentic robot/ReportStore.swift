import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage

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
    let pdfBase64: String?        // Legacy fallback for older reports only
    let pdfStoragePath: String?   // New Firebase Storage path

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
        if let pdfStoragePath, !pdfStoragePath.isEmpty { return true }
        if let pdfFileName, !pdfFileName.isEmpty { return true }
        if let pdfBase64, !pdfBase64.isEmpty { return true }
        return false
    }
}

struct ReportDeletionResult {
    let storagePathsNotDeleted: [String]
}

struct ReportStore {

    static func makeNumericBarcodeId(date: Date = Date()) -> String {
        // Always produce a positive, digits-only barcode.
        // Format: YYYYMMDD + 4 random digits = 12 digits.
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

    static func uploadDataToStorage(
        _ data: Data,
        path: String,
        contentType: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let metadata = StorageMetadata()
        metadata.contentType = contentType

        Storage.storage().reference().child(path).putData(data, metadata: metadata) { _, error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(path))
            }
        }
    }

    static func downloadDataFromStorage(
        path: String,
        maxSize: Int64 = 50 * 1024 * 1024,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        Storage.storage().reference().child(path).getData(maxSize: maxSize) { data, error in
            if let error {
                completion(.failure(error))
            } else if let data {
                completion(.success(data))
            } else {
                let error = NSError(
                    domain: "ReportStore",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "File data was empty."]
                )
                completion(.failure(error))
            }
        }
    }

    static func deleteReport(
        collection: String,
        documentID: String,
        storagePaths: [String],
        localBarcodeId: String? = nil,
        completion: @escaping (Result<ReportDeletionResult, Error>) -> Void
    ) {
        let uniquePaths = Array(Set(storagePaths.filter { !$0.isEmpty }))

        func deleteNextFile(index: Int, failedPaths: [String]) {
            guard index < uniquePaths.count else {
                Firestore.firestore()
                    .collection(collection)
                    .document(documentID)
                    .delete { error in
                        if let error {
                            completion(.failure(error))
                            return
                        }

                        if let localBarcodeId, !localBarcodeId.isEmpty {
                            let localURL = localPDFURL(for: localBarcodeId)
                            try? FileManager.default.removeItem(at: localURL)
                        }

                        completion(.success(ReportDeletionResult(storagePathsNotDeleted: failedPaths)))
                    }
                return
            }

            let path = uniquePaths[index]
            Storage.storage().reference().child(path).delete { error in
                deleteNextFile(
                    index: index + 1,
                    failedPaths: error == nil ? failedPaths : failedPaths + [path]
                )
            }
        }

        deleteNextFile(index: 0, failedPaths: [])
    }

    /// Synchronous legacy resolver. It only works for PDFs already on this device
    /// or older reports that still have pdfBase64 in Firestore.
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

    /// New resolver. It first checks the local file, then Firebase Storage,
    /// then legacy Firestore base64.
    static func resolvePDFURL(for report: ReportEntry, completion: @escaping (URL?) -> Void) {
        let localURL = localPDFURL(for: report.barcodeId)
        if FileManager.default.fileExists(atPath: localURL.path) {
            completion(localURL)
            return
        }

        if let pdfStoragePath = report.pdfStoragePath, !pdfStoragePath.isEmpty {
            downloadDataFromStorage(path: pdfStoragePath) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let data):
                        do {
                            try data.write(to: localURL, options: [.atomic])
                            completion(localURL)
                        } catch {
                            print("Failed to save downloaded PDF locally: \(error.localizedDescription)")
                            completion(nil)
                        }
                    case .failure(let error):
                        print("Failed to download PDF from Firebase Storage: \(error.localizedDescription)")
                        completion(nil)
                    }
                }
            }
            return
        }

        completion(resolvedPDFURL(for: report))
    }

    static func saveReport(
        reportNo: String,
        plate: String,
        carType: String,
        generatedBy: String,
        detectionCount: Int,
        numericBarcodeId: String,
        pdfURL: URL? = nil,
        completion: ((Error?) -> Void)? = nil
    ) {
        var data: [String: Any] = [
            "reportNo": reportNo,
            "barcodeId": numericBarcodeId,
            "plate": plate,
            "carType": carType,
            "generatedBy": generatedBy,
            "createdByUid": Auth.auth().currentUser?.uid ?? "",
            "createdByName": generatedBy,
            "createdByEmail": Auth.auth().currentUser?.email ?? "",
            "detectionCount": detectionCount,
            "createdAt": FieldValue.serverTimestamp(),
            "pdfStoredInFirestore": false
        ]

        guard let pdfURL else {
            Firestore.firestore()
                .collection("reports")
                .document(numericBarcodeId)
                .setData(data, merge: true) { completion?($0) }
            return
        }

        let localURL = copyPDFToLocalStore(from: pdfURL, barcodeId: numericBarcodeId)
        let fileName = localURL?.lastPathComponent ?? "\(numericBarcodeId).pdf"
        let storagePath = "reports/\(numericBarcodeId)/\(fileName)"

        data["pdfFileName"] = fileName
        data["pdfStoragePath"] = storagePath

        guard let pdfData = try? Data(contentsOf: pdfURL) else {
            data["pdfUploadError"] = "Could not read generated PDF data before upload."
            Firestore.firestore()
                .collection("reports")
                .document(numericBarcodeId)
                .setData(data, merge: true) { completion?($0) }
            return
        }

        uploadDataToStorage(pdfData, path: storagePath, contentType: "application/pdf") { result in
            var finalData = data

            switch result {
            case .success(let path):
                finalData["pdfStoragePath"] = path
                finalData["pdfStoredInStorage"] = true
                finalData["pdfUploadError"] = FieldValue.delete()
            case .failure(let error):
                finalData["pdfStoredInStorage"] = false
                finalData["pdfUploadError"] = error.localizedDescription
            }

            Firestore.firestore()
                .collection("reports")
                .document(numericBarcodeId)
                .setData(finalData, merge: true) { completion?($0) }
        }
    }
}
