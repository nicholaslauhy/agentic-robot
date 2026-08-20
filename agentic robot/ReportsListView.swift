import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Report Category Enum
enum ReportCategory: String, CaseIterable, Identifiable {
    case np299    = "NP299"
    case secCom   = "SecCom"
    case fuel     = "Fuel"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .np299:  return "doc.text.magnifyingglass"
        case .secCom: return "checklist"
        case .fuel:   return "fuelpump.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .np299:  return HTXTheme.primaryPurple
        case .secCom: return Color(red: 0.08, green: 0.50, blue: 0.30)
        case .fuel:   return HTXTheme.fuelOrange
        }
    }

    var firestoreCollection: String {
        switch self {
        case .np299:  return "reports"
        case .secCom: return "seccom_checklists"
        case .fuel:   return "fuel_refuel_reports"
        }
    }

    var emptyLabel: String {
        switch self {
        case .np299:  return "No police reports yet."
        case .secCom: return "No pre-driving checklists yet."
        case .fuel:   return "No fuel refuel reports yet."
        }
    }
}

// MARK: - Raw report document (carries full Firestore data)
struct RawReportDocument: Identifiable {
    let id: String           // Firestore document ID
    let entry: ReportEntry   // shared display fields
    let raw: [String: Any]   // full document for type-specific detail views
}

private struct PendingReportDeletion: Identifiable {
    let document: RawReportDocument
    let category: ReportCategory
    var id: String { "\(category.rawValue)-\(document.id)" }
}

// MARK: - Reports List View
struct ReportsListView: View {
    private let initialReportID: String?

    @State private var selectedCategory: ReportCategory = .np299

    @State private var np299Docs:  [RawReportDocument] = []
    @State private var secComDocs: [RawReportDocument] = []
    @State private var fuelDocs:   [RawReportDocument] = []

    @State private var isLoading    = false
    @State private var errorMessage: String? = nil
    @State private var searchText   = ""

    @State private var selectedDoc: RawReportDocument? = nil
    @State private var selectedPDFURL: URL? = nil
    @State private var pendingDeletion: PendingReportDeletion? = nil
    @State private var isDeleting = false
    @State private var deletionFeedbackTitle = ""
    @State private var deletionFeedbackMessage: String? = nil
    @State private var didHandleInitialReport = false

    init(initialReportID: String? = nil) {
        self.initialReportID = initialReportID
    }

    private var activeDocs: [RawReportDocument] {
        switch selectedCategory {
        case .np299:  return np299Docs
        case .secCom: return secComDocs
        case .fuel:   return fuelDocs
        }
    }

    private var filteredDocs: [RawReportDocument] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return activeDocs }
        return activeDocs.filter {
            $0.entry.plate.lowercased().contains(q) ||
            $0.entry.reportNo.lowercased().contains(q) ||
            $0.entry.carType.lowercased().contains(q) ||
            $0.entry.generatedBy.lowercased().contains(q) ||
            $0.entry.barcodeId.contains(q)
        }
    }

    var body: some View {
        ZStack {
            SubtleHTXBackground().ignoresSafeArea()

            VStack(spacing: 0) {

                // MARK: Category Tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(ReportCategory.allCases) { cat in
                            categoryTab(cat)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }

                // MARK: Search Bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search by vehicle number, officer, report no…", text: $searchText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.systemBackground).opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedCategory.accentColor.opacity(0.25), lineWidth: 1))
                .padding(.horizontal)
                .padding(.bottom, 8)

                // MARK: Content
                if isLoading {
                    Spacer()
                    ProgressView("Loading reports…").tint(selectedCategory.accentColor)
                    Spacer()
                } else if let errorMessage {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle).foregroundColor(.orange)
                        Text(errorMessage).multilineTextAlignment(.center).foregroundColor(.secondary)
                        Button("Retry") { fetchAll() }
                            .buttonStyle(.borderedProminent).tint(selectedCategory.accentColor)
                    }
                    .padding()
                    Spacer()
                } else if filteredDocs.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: searchText.isEmpty ? "folder.badge.questionmark" : "magnifyingglass")
                            .font(.system(size: 44))
                            .foregroundColor(selectedCategory.accentColor.opacity(0.5))
                        Text(searchText.isEmpty
                             ? selectedCategory.emptyLabel
                             : "No reports match \"\(searchText)\".")
                            .foregroundColor(.secondary).multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else {
                    HStack {
                        Text("\(filteredDocs.count) report\(filteredDocs.count == 1 ? "" : "s")")
                            .font(.caption.weight(.semibold)).foregroundColor(.secondary)
                        Spacer()
                        Button { fetchAll() } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.subheadline).foregroundColor(selectedCategory.accentColor)
                        }
                    }
                    .padding(.horizontal).padding(.bottom, 4)

                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredDocs) { doc in
                                HStack(spacing: 9) {
                                    Button {
                                        selectedDoc = doc
                                    } label: {
                                        ReportRowCard(
                                            report: doc.entry,
                                            category: selectedCategory,
                                            accent: selectedCategory.accentColor
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        pendingDeletion = PendingReportDeletion(
                                            document: doc,
                                            category: selectedCategory
                                        )
                                    } label: {
                                        Image(systemName: "trash.fill")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(.red)
                                            .frame(width: 44, height: 44)
                                            .background(Color.red.opacity(0.09))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Delete \(doc.entry.reportNo)")
                                }
                            }
                        }
                        .padding(.horizontal).padding(.bottom, 24)
                    }
                }
            }

            if isDeleting {
                Color.black.opacity(0.32).ignoresSafeArea()
                ProgressView("Deleting report…")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .navigationTitle("Existing Reports")
        .navigationBarTitleDisplayMode(.inline)
        .tint(selectedCategory.accentColor)
        .onAppear { fetchAll() }
        .onChange(of: selectedCategory) { _, _ in searchText = "" }
        // Route to the right detail sheet depending on category
        .sheet(item: $selectedDoc) { doc in
            switch selectedCategory {
            case .np299:
                ReportDetailSheet(
                    document: doc,
                    onViewPDF: { url in
                        selectedDoc = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { selectedPDFURL = url }
                    },
                    onVehicleStatusFollowUpResolved: fetchAll
                )
            case .secCom:
                SecComDetailSheet(doc: doc)
            case .fuel:
                FuelDetailSheet(doc: doc)
            }
        }
        .sheet(item: $selectedPDFURL) { url in
            ReportPDFPreviewView(url: url)
        }
        .alert(
            "Delete Report?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { deletion in
            Button("Delete Permanently", role: .destructive) {
                deleteReport(deletion)
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { deletion in
            Text("\(deletion.document.entry.reportNo) and its stored files will be permanently deleted. This cannot be undone.")
        }
        .alert(
            deletionFeedbackTitle,
            isPresented: Binding(
                get: { deletionFeedbackMessage != nil },
                set: { if !$0 { deletionFeedbackMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { deletionFeedbackMessage = nil }
        } message: {
            Text(deletionFeedbackMessage ?? "")
        }
        .requiresRole(.admin)
    }

    // MARK: - Category Tab Button
    @ViewBuilder
    private func categoryTab(_ cat: ReportCategory) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) { selectedCategory = cat }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: cat.icon).font(.subheadline)
                Text(cat.rawValue).font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(selectedCategory == cat ? cat.accentColor : Color(.secondarySystemBackground))
            .foregroundColor(selectedCategory == cat ? .white : .secondary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(
                selectedCategory == cat ? cat.accentColor : HTXTheme.softPurpleBorder,
                lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Fetch All Collections
    private func fetchAll() {
        isLoading = true
        errorMessage = nil
        let group = DispatchGroup()

        group.enter()
        fetchCollection("reports") { np299Docs = $0; group.leave() }
        group.enter()
        fetchCollection("seccom_checklists") { secComDocs = $0; group.leave() }
        group.enter()
        fetchCollection("fuel_refuel_reports") { fuelDocs = $0; group.leave() }

        group.notify(queue: .main) {
            isLoading = false
            openInitialReportIfNeeded()
        }
    }

    private func openInitialReportIfNeeded() {
        guard !didHandleInitialReport,
              let initialReportID,
              !initialReportID.isEmpty else { return }

        didHandleInitialReport = true
        selectedCategory = .np299
        if let report = np299Docs.first(where: { $0.id == initialReportID }) {
            selectedDoc = report
        } else {
            deletionFeedbackTitle = "Report Unavailable"
            deletionFeedbackMessage = "This NP299 report may have been deleted or is no longer available."
        }
    }

    private func fetchCollection(_ collection: String, completion: @escaping ([RawReportDocument]) -> Void) {
        Firestore.firestore()
            .collection(collection)
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    if let error {
                        self.errorMessage = error.localizedDescription
                        completion([]); return
                    }
                    let docs = (snapshot?.documents ?? []).compactMap { doc -> RawReportDocument? in
                        let data = doc.data()
                        guard let reportNo = data["reportNo"] as? String else { return nil }

                        let displayVehicle = collection == "fuel_refuel_reports"
                            ? (data["vehicleNumber"] as? String ?? data["plate"] as? String)
                            : (data["plate"] as? String)

                        guard let plate = displayVehicle else { return nil }

                        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
                        let entry = ReportEntry(
                            id:             doc.documentID,
                            reportNo:       reportNo,
                            plate:          plate,
                            carType:        data["carType"]        as? String ?? "-",
                            generatedBy:    data["generatedBy"]    as? String ?? "-",
                            detectionCount: data["detectionCount"] as? Int    ?? 0,
                            createdAt:      createdAt,
                            barcodeId:      data["barcodeId"]      as? String ?? doc.documentID,
                            pdfFileName:    data["pdfFileName"]    as? String,
                            pdfBase64:      data["pdfBase64"]      as? String,
                            pdfStoragePath: data["pdfStoragePath"] as? String
                        )
                        return RawReportDocument(id: doc.documentID, entry: entry, raw: data)
                    }
                    completion(docs)
                }
            }
    }

    private func deleteReport(_ deletion: PendingReportDeletion) {
        pendingDeletion = nil
        isDeleting = true
        let paths = storagePaths(for: deletion.document, category: deletion.category)

        ReportStore.deleteReport(
            collection: deletion.category.firestoreCollection,
            documentID: deletion.document.id,
            storagePaths: paths,
            localBarcodeId: deletion.document.entry.barcodeId
        ) { result in
            DispatchQueue.main.async {
                isDeleting = false
                switch result {
                case .success(let deletionResult):
                    removeFromLoadedReports(deletion.document.id, category: deletion.category)
                    if !deletionResult.storagePathsNotDeleted.isEmpty {
                        deletionFeedbackTitle = "Report Deleted with Warning"
                        deletionFeedbackMessage = "The report was deleted, but \(deletionResult.storagePathsNotDeleted.count) stored file\(deletionResult.storagePathsNotDeleted.count == 1 ? "" : "s") could not be removed. Check Firebase Storage permissions."
                    }
                case .failure(let error):
                    deletionFeedbackTitle = "Could Not Delete Report"
                    deletionFeedbackMessage = error.localizedDescription
                }
            }
        }
    }

    private func storagePaths(for document: RawReportDocument, category: ReportCategory) -> [String] {
        switch category {
        case .np299:
            return [document.entry.pdfStoragePath].compactMap { $0 }
        case .fuel:
            return [document.raw["receiptStoragePath"] as? String].compactMap { $0 }
        case .secCom:
            var paths = document.raw["damageImageStoragePaths"] as? [String] ?? []
            let photos = document.raw["damagePhotos"] as? [[String: Any]] ?? []
            paths.append(contentsOf: photos.compactMap { $0["storagePath"] as? String })
            return paths
        }
    }

    private func removeFromLoadedReports(_ documentID: String, category: ReportCategory) {
        switch category {
        case .np299:
            np299Docs.removeAll { $0.id == documentID }
        case .secCom:
            secComDocs.removeAll { $0.id == documentID }
        case .fuel:
            fuelDocs.removeAll { $0.id == documentID }
        }
    }
}

// MARK: - Report Row Card
private struct ReportRowCard: View {
    let report: ReportEntry
    let category: ReportCategory
    let accent: Color

    private var generatedByText: String {
        let t = report.generatedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t == "-" ? "Not recorded" : t
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack {
                Image(systemName: "doc.text.fill").font(.title3).foregroundColor(.white)
            }
            .frame(width: 44, height: 44)
            .background(LinearGradient(colors: [accent, accent.opacity(0.7)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 4) {
                Text(report.plate).font(.headline).foregroundColor(.primary)
                Text(report.reportNo).font(.caption.weight(.semibold)).foregroundColor(accent)
                HStack(spacing: 6) {
                    Text(report.carType)
                    if category != .fuel {
                        Text("·")
                        Text("\(report.detectionCount) case\(report.detectionCount == 1 ? "" : "s")")
                    }
                }
                .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(report.shortDate).font(.caption2).foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundColor(accent.opacity(0.6))
            }
        }
        .padding(14)
        .background(Color(.systemBackground).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
}

// MARK: - NP299 Detail Sheet (PDF-based, unchanged)
struct ReportDetailSheet: View {
    let document: RawReportDocument
    var onViewPDF: (URL) -> Void
    var onVehicleStatusFollowUpResolved: () -> Void = {}
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var auth: AuthViewModel
    @State private var pdfErrorMessage: String? = nil
    @State private var isLoadingPDF = false

    private var report: ReportEntry { document.entry }

    private var hasVehicleStatusFollowUp: Bool {
        guard let status = document.raw["vehicleStatusFollowUpStatus"] as? String else {
            return false
        }
        return status == "pending" || status == "completed"
    }

    private var generatedByText: String {
        let t = report.generatedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t == "-" ? "Not recorded" : t
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SubtleHTXBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 6) {
                            Image(systemName: "doc.text.fill").font(.system(size: 40))
                                .foregroundColor(HTXTheme.primaryPurple)
                            Text(report.plate).font(.largeTitle.weight(.black))
                            Text(report.reportNo).font(.subheadline.weight(.semibold))
                                .foregroundColor(HTXTheme.primaryPurple)
                            Label("Generated by \(generatedByText)", systemImage: "person.fill")
                                .font(.caption.weight(.semibold)).foregroundColor(.secondary)
                                .padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                        .background(Color(.systemBackground).opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 18)).padding(.horizontal)

                        // Details
                        detailCard {
                            DetailRow(label: "Report No.",   value: report.reportNo)
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Plate",        value: report.plate)
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Vehicle Type", value: report.carType)
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Damage Cases", value: "\(report.detectionCount)")
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Generated By", value: generatedByText)
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Date & Time",  value: report.dateString)
                        }

                        // A report in this collection has already been filed. This lets an
                        // administrator who opens a member's completed NP299 submission
                        // perform the same vehicle follow-up as an administrator who filed
                        // the report directly. It is intentionally not shown at the earlier
                        // "NP299 Required" escalation stage.
                        if auth.isAdmin, hasVehicleStatusFollowUp {
                            PostReportVehicleStatusView(
                                plate: report.plate,
                                carType: report.carType,
                                reportID: report.id,
                                reportNo: report.reportNo,
                                sourceChecklistID: document.raw["sourceChecklistId"] as? String,
                                onResolved: onVehicleStatusFollowUpResolved
                            )
                            .padding(.horizontal)
                        }

                        // Barcode
                        barcodeBlock(report.barcodeId, accent: HTXTheme.primaryPurple)

                        if let pdfErrorMessage {
                            Text(pdfErrorMessage).font(.footnote.weight(.semibold))
                                .foregroundColor(.red).multilineTextAlignment(.center).padding(.horizontal)
                        }

                        Button {
                            isLoadingPDF = true
                            pdfErrorMessage = nil

                            ReportStore.resolvePDFURL(for: report) { url in
                                isLoadingPDF = false
                                guard let url else {
                                    pdfErrorMessage = "PDF not available. Make sure Firebase Storage is enabled and this report has pdfStoragePath."
                                    return
                                }
                                onViewPDF(url)
                            }
                        } label: {
                            HStack {
                                if isLoadingPDF {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "doc.richtext.fill")
                                }
                                Text(isLoadingPDF ? "Loading PDF…" : (report.hasPDF ? "View PDF Report" : "PDF Not Saved"))
                            }
                            .font(.headline).frame(maxWidth: .infinity).padding()
                            .background(report.hasPDF ? HTXTheme.primaryPurple : Color.gray)
                            .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(isLoadingPDF || !report.hasPDF)
                        .padding(.horizontal)
                        Spacer().frame(height: 10)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Report Detail").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(HTXTheme.primaryPurple).fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - SecCom Detail Sheet
private struct ChecklistHistoryDamageRegion {
    let damageType: String
    let normalizedBox: CGRect?
}

private struct ChecklistHistoryDamagePhoto {
    let storagePath: String
    let angle: String
    let regions: [ChecklistHistoryDamageRegion]
}

private struct ChecklistHistoryDamageImage: Identifiable {
    let id = UUID()
    let image: UIImage
    let angle: String
    let regionCount: Int
}

struct SecComDetailSheet: View {
    let doc: RawReportDocument
    @Environment(\.dismiss) var dismiss
    private let accent = Color(red: 0.08, green: 0.50, blue: 0.30)

    private var d: [String: Any] { doc.raw }

    @State private var damageImages: [ChecklistHistoryDamageImage] = []
    @State private var isLoadingDamageImages = false
    @State private var damageImageError: String? = nil
    @State private var selectedDamageImage: ZoomableImageItem? = nil

    private var equipment: [String] { d["equipment"] as? [String] ?? [] }
    private var selectedEquipmentSet: Set<String> {
        Set(equipment.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    }
    private var legacyDamageImages: [UIImage] {
        guard let b64Array = d["damageImagesBase64"] as? [String] else { return [] }
        return b64Array.compactMap { b64 in
            guard let data = Data(base64Encoded: b64) else { return nil }
            return UIImage(data: data)
        }
    }
    private var damageImageStoragePaths: [String] {
        d["damageImageStoragePaths"] as? [String] ?? []
    }
    private var damagePhotoMetadata: [ChecklistHistoryDamagePhoto] {
        if let rawPhotos = d["damagePhotos"] as? [[String: Any]], !rawPhotos.isEmpty {
            return rawPhotos.compactMap { rawPhoto in
                guard let path = rawPhoto["storagePath"] as? String, !path.isEmpty else {
                    return nil
                }
                let rawRegions = rawPhoto["confirmedDamage"] as? [[String: Any]] ?? []
                return ChecklistHistoryDamagePhoto(
                    storagePath: path,
                    angle: rawPhoto["angle"] as? String ?? "Vehicle Image",
                    regions: rawRegions.map(checklistHistoryRegion)
                )
            }
        }

        return damageImageStoragePaths.enumerated().map { index, path in
            ChecklistHistoryDamagePhoto(
                storagePath: path,
                angle: "Damage Photo \(index + 1)",
                regions: []
            )
        }
    }
    private var bodyworkAllInOrder: Bool { d["bodyworkAllInOrder"] as? Bool ?? true }
    private var bodyworkDetails: String { d["bodyworkDetails"] as? String ?? "" }
    private var adminReviewStatus: ChecklistAdminReviewStatus {
        ChecklistAdminReviewStatus(firestoreData: d)
    }
    private var adminReviewedByName: String {
        d["adminReviewedByName"] as? String ?? ""
    }
    private var adminReviewedAt: Date? {
        (d["adminReviewedAt"] as? Timestamp)?.dateValue()
    }
    private var adminReviewNotes: String {
        d["adminReviewNotes"] as? String ?? ""
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SubtleHTXBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {

                        // Header
                        headerBlock(
                            icon: "checklist",
                            title: doc.entry.plate,
                            subtitle: doc.entry.reportNo,
                            accent: accent
                        )

                        sectionCard(
                            title: "Officer Review",
                            icon: adminReviewStatus.icon,
                            accent: adminReviewStatus.color
                        ) {
                            StatusDetailRow(
                                label: "Decision",
                                value: adminReviewStatus.title,
                                systemImage: adminReviewStatus.icon,
                                tint: adminReviewStatus.color
                            )

                            if !adminReviewedByName.isEmpty {
                                Divider().padding(.leading, 16)
                                DetailRow(label: "Reviewed By", value: adminReviewedByName)
                            }

                            if let adminReviewedAt {
                                Divider().padding(.leading, 16)
                                DetailRow(
                                    label: "Reviewed On",
                                    value: adminReviewedAt.formatted(
                                        date: .abbreviated,
                                        time: .shortened
                                    )
                                )
                            }

                            if !adminReviewNotes.isEmpty {
                                Divider().padding(.leading, 16)
                                DetailRow(label: "Officer Notes", value: adminReviewNotes)
                            }
                        }

                        // Driver info
                        sectionCard(title: "Driver Information", icon: "person.fill", accent: accent) {
                            DetailRow(label: "Driver Name",   value: d["driverName"]    as? String ?? "-")
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Work Contact",  value: d["workContact"]   as? String ?? "-")
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Date",          value: d["date"]          as? String ?? "-")
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Time",          value: d["time"]          as? String ?? "-")
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Generated By",  value: doc.entry.generatedBy)
                        }

                        // Vehicle info
                        sectionCard(title: "Vehicle", icon: "car.fill", accent: accent) {
                            DetailRow(label: "Vehicle Number", value: doc.entry.plate)
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Vehicle Type",   value: doc.entry.carType)
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Mileage (km)",   value: d["mileage"] as? String ?? "-")
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Purpose",        value: d["purpose"] as? String ?? "-")
                        }

                        // Equipment
                        sectionCard(title: "Checks & Equipment", icon: "checklist", accent: accent) {
                            VStack(spacing: 0) {
                                ForEach(VehicleEquipment.allCases) { item in
                                    ChecklistStatusRow(
                                        title: item.rawValue,
                                        isChecked: selectedEquipmentSet.contains(item.rawValue),
                                        accent: accent
                                    )
                                }
                            }
                        }

                        // Bodywork
                        sectionCard(title: "Body Work Defects / Others", icon: "wrench.and.screwdriver.fill", accent: accent) {
                            StatusDetailRow(
                                label: "Status",
                                value: bodyworkAllInOrder ? "All in Order" : "Defects Noted",
                                systemImage: bodyworkAllInOrder ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                                tint: bodyworkAllInOrder ? accent : .orange
                            )
                            if !bodyworkAllInOrder && !bodyworkDetails.isEmpty {
                                Divider().padding(.leading, 16)
                                DetailRow(label: "Details", value: bodyworkDetails)
                            }
                        }

                        // Damage images
                        if isLoadingDamageImages {
                            sectionCard(title: "New Damage Detected", icon: "camera.fill", accent: accent) {
                                HStack(spacing: 10) {
                                    ProgressView().tint(accent)
                                    Text("Loading damage images…")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 10)
                            }
                        } else if let damageImageError {
                            sectionCard(title: "New Damage Detected", icon: "camera.fill", accent: accent) {
                                Text(damageImageError)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 10)
                            }
                        } else if !damageImages.isEmpty {
                            sectionCard(title: "New Damage Detected", icon: "camera.fill", accent: accent) {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                                    ForEach(damageImages) { damageImage in
                                        Button {
                                            selectedDamageImage = ZoomableImageItem(image: damageImage.image)
                                        } label: {
                                            VStack(alignment: .leading, spacing: 8) {
                                                ZStack(alignment: .bottomTrailing) {
                                                    Color.black.opacity(0.04)
                                                    Image(uiImage: damageImage.image)
                                                        .resizable()
                                                        .scaledToFit()
                                                        .frame(maxWidth: .infinity)
                                                        .frame(height: 170)

                                                    Image(systemName: "magnifyingglass.circle.fill")
                                                        .font(.title2)
                                                        .symbolRenderingMode(.palette)
                                                        .foregroundStyle(.white, Color.black.opacity(0.55))
                                                        .padding(8)
                                                }
                                                .frame(height: 170)
                                                .clipShape(RoundedRectangle(cornerRadius: 10))

                                                HStack(spacing: 8) {
                                                    Text(damageImage.angle)
                                                        .font(.subheadline.weight(.semibold))
                                                        .foregroundColor(.primary)
                                                        .lineLimit(1)
                                                    Spacer(minLength: 4)
                                                    if damageImage.regionCount > 0 {
                                                        Text("\(damageImage.regionCount) area\(damageImage.regionCount == 1 ? "" : "s")")
                                                            .font(.caption.weight(.semibold))
                                                            .foregroundColor(.orange)
                                                    }
                                                }
                                            }
                                            .padding(9)
                                            .background(Color(.secondarySystemBackground))
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(accent.opacity(0.18), lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Open \(damageImage.angle) damage image")
                                        .accessibilityHint("Opens a full-screen image that can be zoomed and panned")
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 10)
                            }
                        }
                        Spacer().frame(height: 10)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Checklist Detail").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(accent).fontWeight(.semibold)
                }
            }
            .onAppear { loadDamageImages() }
            .fullScreenCover(item: $selectedDamageImage) { item in
                ZoomableImageViewer(image: item.image)
            }
        }
    }

    private func loadDamageImages() {
        damageImageError = nil

        let metadata = damagePhotoMetadata
        guard !metadata.isEmpty else {
            damageImages = legacyDamageImages.enumerated().map { index, image in
                ChecklistHistoryDamageImage(
                    image: image,
                    angle: "Damage Photo \(index + 1)",
                    regionCount: 0
                )
            }
            return
        }

        isLoadingDamageImages = true
        loadDamageImage(metadata: metadata, index: 0, loaded: [])
    }

    private func loadDamageImage(
        metadata: [ChecklistHistoryDamagePhoto],
        index: Int,
        loaded: [ChecklistHistoryDamageImage]
    ) {
        guard index < metadata.count else {
            isLoadingDamageImages = false
            damageImages = loaded
            return
        }

        let item = metadata[index]
        ReportStore.downloadDataFromStorage(path: item.storagePath, maxSize: 25 * 1024 * 1024) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    guard let image = UIImage(data: data) else {
                        loadDamageImage(metadata: metadata, index: index + 1, loaded: loaded)
                        return
                    }
                    let annotatedImage = checklistHistoryAnnotatedImage(
                        image: image,
                        regions: item.regions
                    )
                    loadDamageImage(
                        metadata: metadata,
                        index: index + 1,
                        loaded: loaded + [
                            ChecklistHistoryDamageImage(
                                image: annotatedImage,
                                angle: item.angle,
                                regionCount: item.regions.filter { $0.normalizedBox != nil }.count
                            )
                        ]
                    )
                case .failure(let error):
                    isLoadingDamageImages = false
                    if loaded.isEmpty {
                        damageImageError = "Could not load damage images from Firebase Storage: \(error.localizedDescription)"
                    } else {
                        damageImages = loaded
                    }
                }
            }
        }
    }

    private func checklistHistoryRegion(_ raw: [String: Any]) -> ChecklistHistoryDamageRegion {
        let boxData = raw["boundingBox"] as? [String: Any]
        let x = checklistHistoryNumber(boxData?["x"])
        let y = checklistHistoryNumber(boxData?["y"])
        let width = checklistHistoryNumber(boxData?["width"])
        let height = checklistHistoryNumber(boxData?["height"])

        let box: CGRect?
        if let x, let y, let width, let height, width > 0, height > 0 {
            let left = min(max(0, x), 1)
            let top = min(max(0, y), 1)
            let right = min(max(left, x + width), 1)
            let bottom = min(max(top, y + height), 1)
            box = right > left && bottom > top
                ? CGRect(x: left, y: top, width: right - left, height: bottom - top)
                : nil
        } else {
            box = nil
        }

        return ChecklistHistoryDamageRegion(
            damageType: raw["damageType"] as? String ?? "Damage",
            normalizedBox: box
        )
    }

    private func checklistHistoryNumber(_ value: Any?) -> CGFloat? {
        if let number = value as? NSNumber { return CGFloat(number.doubleValue) }
        if let value = value as? Double { return CGFloat(value) }
        if let value = value as? Int { return CGFloat(value) }
        return nil
    }

    private func checklistHistoryAnnotatedImage(
        image: UIImage,
        regions: [ChecklistHistoryDamageRegion]
    ) -> UIImage {
        let drawableRegions = regions.compactMap { region -> (ChecklistHistoryDamageRegion, CGRect)? in
            guard let box = region.normalizedBox else { return nil }
            return (region, box)
        }
        guard !drawableRegions.isEmpty else { return image }

        let normalizedImage = image.htxNormalizedImage()
        let imageSize = normalizedImage.size
        guard imageSize.width > 0, imageSize.height > 0 else { return image }

        let renderer = UIGraphicsImageRenderer(size: imageSize)
        return renderer.image { context in
            normalizedImage.draw(in: CGRect(origin: .zero, size: imageSize))

            let lineWidth = max(4, imageSize.width * 0.004)
            let fontSize = max(18, min(42, imageSize.width * 0.026))
            let font = UIFont.boldSystemFont(ofSize: fontSize)

            for (index, item) in drawableRegions.enumerated() {
                let box = item.1
                let rect = CGRect(
                    x: box.minX * imageSize.width,
                    y: box.minY * imageSize.height,
                    width: box.width * imageSize.width,
                    height: box.height * imageSize.height
                ).intersection(CGRect(origin: .zero, size: imageSize))
                guard rect.width > 0, rect.height > 0 else { continue }

                context.cgContext.setFillColor(UIColor.systemOrange.withAlphaComponent(0.12).cgColor)
                context.cgContext.fill(rect)
                context.cgContext.setStrokeColor(UIColor.systemOrange.cgColor)
                context.cgContext.setLineWidth(lineWidth)
                context.cgContext.stroke(rect)

                let label = "D\(index + 1): \(item.0.damageType.replacingOccurrences(of: "_", with: " ").capitalized)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.white
                ]
                let textSize = label.size(withAttributes: attributes)
                let labelWidth = min(imageSize.width, textSize.width + 20)
                let labelHeight = textSize.height + 12
                let labelX = min(max(0, rect.minX), max(0, imageSize.width - labelWidth))
                let labelY = max(0, rect.minY - labelHeight)
                let labelRect = CGRect(
                    x: labelX,
                    y: labelY,
                    width: labelWidth,
                    height: labelHeight
                )

                UIColor.systemOrange.setFill()
                UIBezierPath(roundedRect: labelRect, cornerRadius: 6).fill()
                label.draw(
                    in: labelRect.insetBy(dx: 10, dy: 6),
                    withAttributes: attributes
                )
            }
        }
    }

}

// MARK: - Fuel Detail Sheet
struct FuelDetailSheet: View {
    let doc: RawReportDocument
    let allowsFollowUpActions: Bool
    let onFollowUpUpdated: () -> Void

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var auth: AuthViewModel
    private let accent = HTXTheme.fuelOrange

    @State private var receiptImage: UIImage? = nil
    @State private var isLoadingReceipt = false
    @State private var receiptError: String? = nil
    @State private var selectedReceiptImage: ZoomableImageItem? = nil
    @State private var followUpStatus: FuelFollowUpStatus
    @State private var followUpNotes: String
    @State private var followedUpByName: String
    @State private var followedUpAt: Date?
    @State private var isSavingFollowUp = false
    @State private var followUpError: String? = nil
    @State private var pendingFollowUpDecision: FuelFollowUpStatus?

    init(
        doc: RawReportDocument,
        allowsFollowUpActions: Bool = false,
        onFollowUpUpdated: @escaping () -> Void = {}
    ) {
        self.doc = doc
        self.allowsFollowUpActions = allowsFollowUpActions
        self.onFollowUpUpdated = onFollowUpUpdated
        _followUpStatus = State(
            initialValue: FuelFollowUpStatus(firestoreValue: doc.raw["adminFollowUpStatus"])
        )
        _followUpNotes = State(initialValue: doc.raw["adminFollowUpNotes"] as? String ?? "")
        _followedUpByName = State(initialValue: doc.raw["adminFollowedUpByName"] as? String ?? "")
        _followedUpAt = State(initialValue: (doc.raw["adminFollowedUpAt"] as? Timestamp)?.dateValue())
    }

    private var d: [String: Any] { doc.raw }
    private var usedMastercard: Bool { d["usedMastercard"] as? Bool ?? false }
    private var receiptStoragePath: String? { d["receiptStoragePath"] as? String }
    private var legacyReceiptImage: UIImage? {
        guard let b64 = d["receiptBase64"] as? String,
              let data = Data(base64Encoded: b64) else { return nil }
        return UIImage(data: data)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SubtleHTXBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {

                        // Header
                        headerBlock(
                            icon: "fuelpump.fill",
                            title: doc.entry.plate,
                            subtitle: doc.entry.reportNo,
                            accent: accent
                        )

                        followUpCard

                        // Driver info
                        sectionCard(title: "Driver Information", icon: "person.fill", accent: accent) {
                            DetailRow(label: "Driver Name",   value: d["driverName"] as? String ?? "-")
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Generated By",  value: doc.entry.generatedBy)
                        }

                        // Refuel details
                        sectionCard(title: "Refuel Details", icon: "fuelpump.fill", accent: accent) {
                            DetailRow(label: "Date of Refuel",  value: d["refuelDate"]     as? String ?? "-")
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Time of Refuel",  value: d["refuelTime"]     as? String ?? "-")
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Vehicle Number",  value: d["vehicleNumber"]  as? String ?? "-")
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Vehicle Type",    value: doc.entry.carType)
                            Divider().padding(.leading, 16)
                            DetailRow(label: "Odometer",        value: kilometreValue(d["odometer"] as? String))
                        }

                        // Mastercard
                        sectionCard(title: "Mastercard Usage", icon: "creditcard.fill", accent: accent) {
                            DetailRow(label: "Mastercard Used", value: usedMastercard ? "Yes" : "No")
                        }

                        // Receipt
                        if isLoadingReceipt {
                            sectionCard(title: "Fuel Receipt", icon: "doc.text.fill", accent: accent) {
                                HStack(spacing: 10) {
                                    ProgressView().tint(accent)
                                    Text("Loading receipt…")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else if let receiptError {
                            sectionCard(title: "Fuel Receipt", icon: "doc.text.fill", accent: accent) {
                                Text(receiptError)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else if let img = receiptImage {
                            sectionCard(title: "Fuel Receipt", icon: "doc.text.fill", accent: accent) {
                                Button {
                                    selectedReceiptImage = ZoomableImageItem(image: img)
                                } label: {
                                    ZStack(alignment: .bottomTrailing) {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxHeight: 280)
                                            .frame(maxWidth: .infinity)

                                        Label("Tap to zoom", systemImage: "magnifyingglass")
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 7)
                                            .background(Color.black.opacity(0.62))
                                            .clipShape(Capsule())
                                            .padding(10)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Open fuel receipt")
                                .accessibilityHint("Opens a full-screen image that can be zoomed and panned")
                            }
                        }
                        Spacer().frame(height: 10)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Refuel Detail").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(accent).fontWeight(.semibold)
                }
            }
            .onAppear { loadReceiptImage() }
            .fullScreenCover(item: $selectedReceiptImage) { item in
                ZoomableImageViewer(image: item.image)
            }
            .alert(
                pendingFollowUpDecision == .rejected
                    ? "Reject Refuel Report?"
                    : "Complete Refuel Follow-up?",
                isPresented: Binding(
                    get: { pendingFollowUpDecision != nil },
                    set: { if !$0 { pendingFollowUpDecision = nil } }
                )
            ) {
                if let decision = pendingFollowUpDecision {
                    Button(
                        decision == .rejected ? "Reject Report" : "Mark Completed",
                        role: decision == .rejected ? .destructive : nil
                    ) {
                        saveFollowUp(as: decision)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    pendingFollowUpDecision == .rejected
                        ? "This marks the refuel submission as unacceptable. Its rejected status cannot be changed later."
                        : "This confirms that the refuel submission has been followed up. Its completed status cannot be changed later."
                )
            }
        }
    }

    private var followUpCard: some View {
        sectionCard(title: "Administrator Follow-up", icon: "person.badge.shield.checkmark.fill", accent: accent) {
            VStack(alignment: .leading, spacing: 16) {
                followUpStatusPanel

                if followUpStatus != .pending {
                    if !followedUpByName.isEmpty || followedUpAt != nil {
                        VStack(spacing: 0) {
                            if !followedUpByName.isEmpty {
                                followUpDetailRow(
                                    label: followUpStatus == .rejected ? "Rejected by" : "Approved by",
                                    value: followedUpByName
                                )
                            }

                            if !followedUpByName.isEmpty, followedUpAt != nil {
                                Divider()
                                    .padding(.leading, 12)
                            }

                            if let decisionDate = followedUpAt {
                                followUpDetailRow(
                                    label: followUpStatus == .rejected ? "Rejected on" : "Approved on",
                                    value: decisionDate.formatted(date: .abbreviated, time: .shortened)
                                )
                            }
                        }
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if !followUpNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Officer Notes")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                            Text(followUpNotes)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } else if allowsFollowUpActions {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 4) {
                            Text("Follow-up Notes")
                                .font(.subheadline.weight(.semibold))
                            Text("Optional")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }

                        Text("Record any action taken or information the next administrator should know.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    TextEditor(text: $followUpNotes)
                        .frame(minHeight: 110)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.20), lineWidth: 1)
                        )

                    if let followUpError {
                        Label(followUpError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.red)
                    }

                    if isSavingFollowUp {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Saving follow-up decision…")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    } else {
                        HStack(spacing: 12) {
                            Button {
                                pendingFollowUpDecision = .rejected
                            } label: {
                                Label("Reject Report", systemImage: "xmark.octagon.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .controlSize(.large)

                            Button {
                                pendingFollowUpDecision = .completed
                            } label: {
                            Label("Mark Follow-up Completed", systemImage: "checkmark.seal.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(accent)
                            .controlSize(.large)
                        }
                    }
                } else {
                    Text("This submission is waiting for administrator follow-up.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private var followUpStatusPanel: some View {
        HStack(spacing: 12) {
            Image(systemName: followUpStatus.icon)
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(followUpStatus.color)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Follow-up status")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(followUpStatus.title)
                    .font(.headline)
                    .foregroundColor(followUpStatus.color)
            }

            Spacer(minLength: 8)

            if followUpStatus != .pending {
                Label("Locked", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(followUpStatus.color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(followUpStatus.color.opacity(0.18), lineWidth: 1)
        )
    }

    private func followUpDetailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
        .padding(12)
    }

    private func saveFollowUp(as decision: FuelFollowUpStatus) {
        guard followUpStatus == .pending,
              decision == .completed || decision == .rejected,
              !isSavingFollowUp else { return }

        pendingFollowUpDecision = nil
        isSavingFollowUp = true
        followUpError = nil

        let payload: [String: Any] = [
            "adminFollowUpStatus": decision.rawValue,
            "adminFollowUpNotes": followUpNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            "adminFollowedUpByUid": auth.user?.uid ?? "",
            "adminFollowedUpByName": auth.currentUsername,
            "adminFollowedUpByEmail": auth.currentEmail,
            "adminFollowedUpAt": FieldValue.serverTimestamp()
        ]

        Firestore.firestore()
            .collection("fuel_refuel_reports")
            .document(doc.id)
            .setData(payload, merge: true) { error in
                DispatchQueue.main.async {
                    isSavingFollowUp = false
                    if let error {
                        let action = decision == .rejected ? "reject the report" : "complete the follow-up"
                        followUpError = "Could not \(action): \(error.localizedDescription)"
                        return
                    }
                    followUpStatus = decision
                    followedUpByName = auth.currentUsername
                    followedUpAt = Date()
                    onFollowUpUpdated()
                }
            }
    }

    private func loadReceiptImage() {
        receiptError = nil

        guard let path = receiptStoragePath, !path.isEmpty else {
            receiptImage = legacyReceiptImage
            return
        }

        isLoadingReceipt = true
        ReportStore.downloadDataFromStorage(path: path, maxSize: 20 * 1024 * 1024) { result in
            DispatchQueue.main.async {
                isLoadingReceipt = false
                switch result {
                case .success(let data):
                    receiptImage = UIImage(data: data)
                    if receiptImage == nil {
                        receiptError = "Receipt image could not be opened."
                    }
                case .failure(let error):
                    receiptError = "Could not load receipt from Firebase Storage: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Full-screen zoomable image viewer
private struct ZoomableImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ZoomableImageViewer: View {
    let image: UIImage

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minimumScale: CGFloat = 1
    private let maximumScale: CGFloat = 6

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnificationGesture)
                .simultaneousGesture(dragGesture)
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        if scale > minimumScale {
                            resetZoom()
                        } else {
                            scale = 2.5
                            lastScale = 2.5
                        }
                    }
                }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Close image")
                }
                .padding()

                Spacer()

                Text("Pinch to zoom • Drag to move • Double-tap to reset")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .padding(.bottom, 24)
                    .opacity(scale == minimumScale ? 1 : 0.75)
            }
        }
        .statusBarHidden(true)
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, minimumScale), maximumScale)
                if scale == minimumScale {
                    offset = .zero
                }
            }
            .onEnded { _ in
                if scale <= minimumScale {
                    resetZoom()
                } else {
                    lastScale = scale
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > minimumScale else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                guard scale > minimumScale else {
                    resetZoom()
                    return
                }
                lastOffset = offset
            }
    }

    private func resetZoom() {
        scale = minimumScale
        lastScale = minimumScale
        offset = .zero
        lastOffset = .zero
    }
}

// MARK: - Shared layout helpers

@ViewBuilder
private func headerBlock(icon: String, title: String, subtitle: String, accent: Color) -> some View {
    VStack(spacing: 6) {
        Image(systemName: icon).font(.system(size: 40)).foregroundColor(accent)
        Text(title).font(.largeTitle.weight(.black)).foregroundColor(.primary)
        Text(subtitle).font(.subheadline.weight(.semibold)).foregroundColor(accent)
    }
    .frame(maxWidth: .infinity).padding(.vertical, 24)
    .background(Color(.systemBackground).opacity(0.9))
    .clipShape(RoundedRectangle(cornerRadius: 18))
    .padding(.horizontal)
}

@ViewBuilder
private func sectionCard<Content: View>(
    title: String,
    icon: String,
    accent: Color,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        Label(title, systemImage: icon)
            .font(.headline).foregroundColor(accent)
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
        content()
            .padding(.bottom, 6)
    }
    .background(Color(.systemBackground).opacity(0.9))
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.12), lineWidth: 1))
    .padding(.horizontal)
}

@ViewBuilder
private func detailCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: 0) { content() }
        .background(Color(.systemBackground).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(HTXTheme.primaryPurple.opacity(0.12), lineWidth: 1))
        .padding(.horizontal)
}

@ViewBuilder
private func barcodeBlock(_ id: String, accent: Color) -> some View {
    VStack(spacing: 8) {
        Text("Barcode ID").font(.caption.weight(.semibold)).foregroundColor(.secondary)
        Text(id)
            .font(.system(.title2, design: .monospaced).weight(.bold))
            .foregroundColor(accent).tracking(3)
    }
    .frame(maxWidth: .infinity).padding()
    .background(accent.opacity(0.07))
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.2), lineWidth: 1))
    .padding(.horizontal)
}


private func kilometreValue(_ raw: String?) -> String {
    let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != "-" else { return "-" }
    if trimmed.localizedCaseInsensitiveContains("km") {
        return trimmed
    }
    return "\(trimmed) km"
}

// MARK: - Status Rows (shared)
private struct StatusDetailRow: View {
    let label: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 130, alignment: .leading)

            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(tint)
                    .frame(width: 20, alignment: .center)

                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct ChecklistStatusRow: View {
    let title: String
    let isChecked: Bool
    let accent: Color

    private var statusColor: Color { isChecked ? accent : .red }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isChecked ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(statusColor)
                .frame(width: 22, alignment: .center)

            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(isChecked ? "Checked" : "Missing")
                .font(.caption.weight(.semibold))
                .foregroundColor(statusColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(statusColor.opacity(0.10))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

// MARK: - Detail Row (shared)
struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.subheadline).foregroundColor(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}
