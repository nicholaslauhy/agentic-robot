import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Review Models

enum ChecklistAdminReviewStatus: String, Equatable {
    case pending = "pending"
    case escalationRequired = "escalation_required"
    case noEscalation = "no_escalation"

    init(firestoreValue: Any?) {
        let raw = (firestoreValue as? String)?.lowercased() ?? ""
        self = ChecklistAdminReviewStatus(rawValue: raw) ?? .pending
    }

    var title: String {
        switch self {
        case .pending: return "Pending Review"
        case .escalationRequired: return "NP299 Required"
        case .noEscalation: return "No Escalation"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "clock.badge.exclamationmark"
        case .escalationRequired: return "exclamationmark.shield.fill"
        case .noEscalation: return "checkmark.seal.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .orange
        case .escalationRequired: return HTXTheme.primaryPurple
        case .noEscalation: return .green
        }
    }
}

private enum ChecklistReviewFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case pending = "Pending"
    case escalation = "NP299"
    case completed = "No Escalation"

    var id: String { rawValue }
}

private struct AdminChecklistRecord: Identifiable {
    let id: String
    let reportNo: String
    let plate: String
    let carType: String
    let driverName: String
    let createdAt: Date?
    let detectionCount: Int
    let status: ChecklistAdminReviewStatus
    let raw: [String: Any]

    var dateText: String {
        guard let createdAt else { return "Date unavailable" }
        return createdAt.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct AdminDamageRegion: Identifiable {
    let id = UUID()
    let damageType: String
    let confidence: Double
    let source: String
    let explanation: String
    let normalizedBBox: CGRect?

    var sourceLabel: String {
        source == "manual" ? "Marked by driver" : "AI suggestion confirmed by driver"
    }
}

private struct AdminDamagePhotoMetadata: Identifiable {
    let id = UUID()
    let storagePath: String
    let angle: String
    let angleIndex: Int
    let guideVehicleType: String?
    let regions: [AdminDamageRegion]
}

private struct LoadedAdminDamagePhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    let metadata: AdminDamagePhotoMetadata
}

private struct ChecklistNP299Payload: Identifiable {
    let id = UUID()
    let carType: CarType
    let detections: [MutableDamageDetection]
}

// MARK: - Admin Queue

struct AdminChecklistReviewView: View {
    @State private var records: [AdminChecklistRecord] = []
    @State private var selectedFilter: ChecklistReviewFilter = .all
    @State private var selectedRecord: AdminChecklistRecord?
    @State private var deletionCandidate: AdminChecklistRecord?
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var deletionFeedbackTitle = ""
    @State private var deletionFeedbackMessage: String?

    private let accent = Color(red: 0.08, green: 0.50, blue: 0.30)

    private var filteredRecords: [AdminChecklistRecord] {
        records.filter { record in
            let matchesStatus: Bool
            switch selectedFilter {
            case .pending:
                matchesStatus = record.status == .pending
            case .escalation:
                matchesStatus = record.status == .escalationRequired
            case .completed:
                matchesStatus = record.status == .noEscalation
            case .all:
                matchesStatus = true
            }

            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matchesSearch = query.isEmpty
                || record.plate.lowercased().contains(query)
                || record.reportNo.lowercased().contains(query)
                || record.driverName.lowercased().contains(query)

            return matchesStatus && matchesSearch
        }
    }

    private var pendingCount: Int {
        records.filter { $0.status == .pending }.count
    }

    var body: some View {
        ZStack {
            SubtleHTXBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                summaryHeader
                filterBar
                searchBar
                content
            }

            if isDeleting {
                Color.black.opacity(0.32).ignoresSafeArea()
                ProgressView("Deleting checklist…")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .navigationTitle("Pre-driving Follow-up")
        .navigationBarTitleDisplayMode(.inline)
        .tint(accent)
        .onAppear(perform: fetchChecklists)
        .sheet(item: $selectedRecord) { record in
            AdminChecklistReviewDetail(record: record) {
                fetchChecklists()
            }
        }
        .alert(
            "Delete Checklist?",
            isPresented: Binding(
                get: { deletionCandidate != nil },
                set: { if !$0 { deletionCandidate = nil } }
            ),
            presenting: deletionCandidate
        ) { record in
            Button("Delete Permanently", role: .destructive) {
                deleteChecklist(record)
            }
            Button("Cancel", role: .cancel) { deletionCandidate = nil }
        } message: { record in
            Text("\(record.reportNo) and its submitted damage images will be permanently deleted. This cannot be undone.")
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

    private var summaryHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "checklist.checked")
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(accent)
                .clipShape(RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 3) {
                Text("Pre-driving Follow-up")
                    .font(.headline)
                Text("\(pendingCount) checklist\(pendingCount == 1 ? "" : "s") awaiting review")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()

            Button(action: fetchChecklists) {
                Image(systemName: "arrow.clockwise")
                    .font(.headline)
                    .foregroundColor(accent)
                    .frame(width: 42, height: 42)
                    .background(accent.opacity(0.08))
                    .clipShape(Circle())
            }
            .disabled(isLoading)
        }
        .padding()
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(ChecklistReviewFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(selectedFilter == filter ? accent : Color(.secondarySystemBackground))
                            .foregroundColor(selectedFilter == filter ? .white : .secondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search vehicle, driver or report number", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.18), lineWidth: 1))
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            Spacer()
            ProgressView("Loading submitted checklists…")
                .tint(accent)
            Spacer()
        } else if let errorMessage {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry", action: fetchChecklists)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
            }
            .padding()
            Spacer()
        } else if filteredRecords.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: selectedFilter == .pending ? "checkmark.circle" : "tray")
                    .font(.system(size: 46))
                    .foregroundColor(accent.opacity(0.55))
                Text(searchText.isEmpty ? emptyMessage : "No matching checklists")
                    .foregroundColor(.secondary)
            }
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredRecords) { record in
                        HStack(spacing: 9) {
                            Button {
                                selectedRecord = record
                            } label: {
                                AdminChecklistRow(record: record, accent: accent)
                            }
                            .buttonStyle(.plain)

                            Button {
                                deletionCandidate = record
                            } label: {
                                Image(systemName: "trash.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.red)
                                    .frame(width: 44, height: 44)
                                    .background(Color.red.opacity(0.09))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete \(record.reportNo)")
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
    }

    private var emptyMessage: String {
        switch selectedFilter {
        case .pending: return "No checklists are awaiting review."
        case .escalation: return "No checklists require NP299 escalation."
        case .completed: return "No checklists have been closed without escalation."
        case .all: return "No pre-driving checklists have been submitted."
        }
    }

    private func fetchChecklists() {
        isLoading = true
        errorMessage = nil

        Firestore.firestore()
            .collection("seccom_checklists")
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    isLoading = false
                    if let error {
                        errorMessage = "Could not load submitted checklists: \(error.localizedDescription)"
                        records = []
                        return
                    }

                    records = (snapshot?.documents ?? []).compactMap { document in
                        let data = document.data()
                        guard let reportNo = data["reportNo"] as? String,
                              let plate = data["plate"] as? String else { return nil }

                        return AdminChecklistRecord(
                            id: document.documentID,
                            reportNo: reportNo,
                            plate: plate,
                            carType: data["carType"] as? String ?? "-",
                            driverName: data["driverName"] as? String ?? data["generatedBy"] as? String ?? "-",
                            createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
                            detectionCount: data["detectionCount"] as? Int ?? 0,
                            status: ChecklistAdminReviewStatus(firestoreValue: data["adminReviewStatus"]),
                            raw: data
                        )
                    }
                }
            }
    }

    private func deleteChecklist(_ record: AdminChecklistRecord) {
        deletionCandidate = nil
        isDeleting = true

        var storagePaths = record.raw["damageImageStoragePaths"] as? [String] ?? []
        let photos = record.raw["damagePhotos"] as? [[String: Any]] ?? []
        storagePaths.append(contentsOf: photos.compactMap { $0["storagePath"] as? String })

        ReportStore.deleteReport(
            collection: "seccom_checklists",
            documentID: record.id,
            storagePaths: storagePaths
        ) { result in
            DispatchQueue.main.async {
                isDeleting = false
                switch result {
                case .success(let deletionResult):
                    records.removeAll { $0.id == record.id }
                    if selectedRecord?.id == record.id { selectedRecord = nil }
                    if !deletionResult.storagePathsNotDeleted.isEmpty {
                        deletionFeedbackTitle = "Checklist Deleted with Warning"
                        deletionFeedbackMessage = "The checklist was deleted, but \(deletionResult.storagePathsNotDeleted.count) image file\(deletionResult.storagePathsNotDeleted.count == 1 ? "" : "s") could not be removed. Check Firebase Storage permissions."
                    }
                case .failure(let error):
                    deletionFeedbackTitle = "Could Not Delete Checklist"
                    deletionFeedbackMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct AdminChecklistRow: View {
    let record: AdminChecklistRecord
    let accent: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "car.side.fill")
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(accent)
                .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 4) {
                Text(record.plate)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(record.reportNo)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(accent)
                Text("\(record.driverName) · \(record.detectionCount) damage area\(record.detectionCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Label(record.status.title, systemImage: record.status.icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(record.status.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(record.status.color.opacity(0.10))
                    .clipShape(Capsule())
                Text(record.dateText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(Color(.systemBackground).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(record.status.color.opacity(0.14), lineWidth: 1))
    }
}

// MARK: - Review Detail

private struct AdminChecklistReviewDetail: View {
    let record: AdminChecklistRecord
    let onSaved: () -> Void

    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var reviewStatus: ChecklistAdminReviewStatus
    @State private var reviewNotes: String
    @State private var reviewedByName: String
    @State private var reviewedAt: Date?
    @State private var loadedPhotos: [LoadedAdminDamagePhoto] = []
    @State private var isLoadingPhotos = false
    @State private var photoError: String?
    @State private var selectedPhoto: LoadedAdminDamagePhoto?
    @State private var pendingDecision: ChecklistAdminReviewStatus?
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var np299Payload: ChecklistNP299Payload?
    @State private var isGeneratingNP299 = false
    @State private var np299PDFURL: URL?
    @State private var generatedNP299ReportNo: String?

    private let accent = Color(red: 0.08, green: 0.50, blue: 0.30)

    init(record: AdminChecklistRecord, onSaved: @escaping () -> Void) {
        self.record = record
        self.onSaved = onSaved
        _reviewStatus = State(initialValue: record.status)
        _reviewNotes = State(initialValue: record.raw["adminReviewNotes"] as? String ?? "")
        _reviewedByName = State(initialValue: record.raw["adminReviewedByName"] as? String ?? "")
        _reviewedAt = State(
            initialValue: (record.raw["adminReviewedAt"] as? Timestamp)?.dateValue()
        )
    }

    private var data: [String: Any] { record.raw }
    private var bodyworkAllInOrder: Bool { data["bodyworkAllInOrder"] as? Bool ?? true }
    private var equipment: [String] { data["equipment"] as? [String] ?? [] }

    var body: some View {
        NavigationStack {
            ZStack {
                SubtleHTXBackground().ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        detailHeader
                        statusCard
                        driverCard
                        vehicleCard
                        checklistCard
                        damageEvidenceCard
                        decisionCard
                        Spacer().frame(height: 18)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Review Checklist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(accent)
                }
            }
            .onAppear(perform: loadDamagePhotos)
            .fullScreenCover(item: $selectedPhoto) { photo in
                AdminDamagePhotoViewer(photo: photo)
            }
            .fullScreenCover(item: $np299Payload) { payload in
                PoliceReportStageZeroView(
                    plate: record.plate,
                    carType: payload.carType,
                    detections: payload.detections,
                    scanImages: [],
                    onLogout: { auth.logout() },
                    isGeneratingReport: $isGeneratingNP299,
                    pdfURL: $np299PDFURL,
                    isPresented: Binding(
                        get: { np299Payload != nil },
                        set: { if !$0 { np299Payload = nil } }
                    )
                )
                .environment(
                    \.htxNP299EscalationContext,
                    NP299EscalationContext(
                        checklistID: record.id,
                        checklistReportNo: record.reportNo,
                        informantName: record.driverName,
                        workContact: data["workContact"] as? String ?? "",
                        incidentDate: record.createdAt,
                        onReportSaved: { reportNo in
                            generatedNP299ReportNo = reportNo
                            onSaved()
                        }
                    )
                )
            }
            .alert(
                "Confirm Decision",
                isPresented: Binding(
                    get: { pendingDecision != nil },
                    set: { if !$0 { pendingDecision = nil } }
                ),
                presenting: pendingDecision
            ) {
                decision in
                Button(decisionButtonTitle(for: decision)) {
                    saveDecision(decision)
                }
                Button("Cancel", role: .cancel) { pendingDecision = nil }
            } message: { decision in
                Text(decisionDialogMessage(for: decision))
            }
        }
    }

    private var detailHeader: some View {
        VStack(spacing: 6) {
            Image(systemName: "checklist.checked")
                .font(.system(size: 40))
                .foregroundColor(accent)
            Text(record.plate)
                .font(.largeTitle.weight(.black))
            Text(record.reportNo)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Color(.systemBackground).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal)
    }

    private var statusCard: some View {
        adminSection(title: "Review Status", icon: reviewStatus.icon) {
            HStack(spacing: 10) {
                Image(systemName: reviewStatus.icon)
                    .foregroundColor(reviewStatus.color)
                Text(reviewStatus.title)
                    .font(.headline)
                    .foregroundColor(reviewStatus.color)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            if !reviewedByName.isEmpty || reviewedAt != nil {
                Divider().padding(.horizontal, 16)
                if !reviewedByName.isEmpty {
                    adminDetailRow("Reviewed By", reviewedByName)
                }
                if !reviewedByName.isEmpty, reviewedAt != nil {
                    Divider().padding(.horizontal, 16)
                }
                if let reviewedAt {
                    adminDetailRow(
                        "Reviewed On",
                        reviewedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            }
        }
    }

    private var driverCard: some View {
        adminSection(title: "Driver Information", icon: "person.fill") {
            adminDetailRow("Driver", record.driverName)
            Divider().padding(.horizontal, 16)
            adminDetailRow("Work Contact", data["workContact"] as? String ?? "-")
            Divider().padding(.horizontal, 16)
            adminDetailRow("Submitted", record.dateText)
        }
    }

    private var vehicleCard: some View {
        adminSection(title: "Vehicle", icon: "car.fill") {
            adminDetailRow("Vehicle Number", record.plate)
            Divider().padding(.horizontal, 16)
            adminDetailRow("Vehicle Type", record.carType)
            Divider().padding(.horizontal, 16)
            adminDetailRow("Mileage", kilometreText(data["mileage"] as? String))
            Divider().padding(.horizontal, 16)
            adminDetailRow("Purpose", data["purpose"] as? String ?? "-")
        }
    }

    private var checklistCard: some View {
        adminSection(title: "Checklist Summary", icon: "checklist") {
            adminDetailRow("Equipment Recorded", equipment.isEmpty ? "None" : "\(equipment.count) item\(equipment.count == 1 ? "" : "s")")
            Divider().padding(.horizontal, 16)
            adminDetailRow("Body Work", bodyworkAllInOrder ? "All in order" : "Defects noted")
            if let details = data["bodyworkDetails"] as? String, !details.isEmpty {
                Divider().padding(.horizontal, 16)
                adminDetailRow("Driver Notes", details)
            }
        }
    }

    @ViewBuilder
    private var damageEvidenceCard: some View {
        adminSection(title: "Confirmed Damage Evidence", icon: "camera.fill") {
            if isLoadingPhotos {
                HStack(spacing: 10) {
                    ProgressView().tint(accent)
                    Text("Loading submitted images…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(16)
            } else if let photoError {
                Text(photoError)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.red)
                    .padding(16)
            } else if loadedPhotos.isEmpty {
                Text("No damage images were submitted with this checklist.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(16)
            } else {
                VStack(spacing: 16) {
                    ForEach(loadedPhotos) { photo in
                        Button {
                            selectedPhoto = photo
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(photo.metadata.angle)
                                        .font(.headline)
                                        .foregroundColor(accent)
                                    Spacer()
                                    Label("Tap to inspect", systemImage: "magnifyingglass")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                }

                                AdminDamageAnnotatedImage(
                                    image: photo.image,
                                    regions: photo.metadata.regions,
                                    showLabels: true
                                )
                                .frame(height: 245)
                                .background(Color.black.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                                ForEach(photo.metadata.regions) { region in
                                    HStack(alignment: .top, spacing: 9) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(region.damageType.capitalized)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundColor(.primary)
                                            Text(region.sourceLabel)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if region.source != "manual" {
                                            Text("\(Int((region.confidence * 100).rounded()))%")
                                                .font(.caption.weight(.bold))
                                                .foregroundColor(accent)
                                        }
                                    }
                                }
                            }
                            .padding(12)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
    }

    private var decisionCard: some View {
        adminSection(title: "Administrator Decision", icon: "person.badge.shield.checkmark.fill") {
            VStack(alignment: .leading, spacing: 12) {
                if reviewStatus == .pending {
                    Text("Follow-up Notes (Optional)")
                        .font(.subheadline.weight(.semibold))

                    TextEditor(text: $reviewNotes)
                        .frame(minHeight: 90)
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(0.18), lineWidth: 1))
                } else {
                    Label("Decision recorded", systemImage: "lock.fill")
                        .font(.headline)
                        .foregroundColor(reviewStatus.color)

                    Text("This classification is final and cannot be changed.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if !reviewNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Follow-up Notes")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            Text(reviewNotes)
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                if let saveError {
                    Text(saveError)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.red)
                }

                if reviewStatus == .pending {
                    Button {
                        pendingDecision = .escalationRequired
                    } label: {
                        Label("Escalate to NP299", systemImage: "exclamationmark.shield.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HTXTheme.primaryPurple)
                    .disabled(isSaving)

                    Button {
                        pendingDecision = .noEscalation
                    } label: {
                        Label("No Police Report Required", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .disabled(isSaving)
                } else if reviewStatus == .escalationRequired {
                    if let reportNo = generatedNP299ReportNo ?? data["np299ReportNo"] as? String,
                       !reportNo.isEmpty {
                        Label("NP299 Generated · \(reportNo)", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundColor(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(13)
                            .background(Color.green.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Button {
                            openNP299Workflow()
                        } label: {
                            Label("Continue NP299 Report", systemImage: "doc.text.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(HTXTheme.primaryPurple)
                        .disabled(isSaving || isLoadingPhotos)
                    }
                } else {
                    Label("No Police Report Required", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13)
                        .background(Color.green.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if isSaving {
                    HStack(spacing: 10) {
                        ProgressView().tint(accent)
                        Text("Saving administrator decision…")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
    }

    private func decisionDialogMessage(for decision: ChecklistAdminReviewStatus) -> String {
        decision == .escalationRequired
            ? "Escalate this damage to NP299? The original checklist and evidence will remain stored."
            : "Close this checklist without a police report? The original checklist and evidence will remain stored."
    }

    private func decisionButtonTitle(for status: ChecklistAdminReviewStatus) -> String {
        status == .escalationRequired ? "Confirm Escalation" : "Confirm No Escalation"
    }

    private func saveDecision(_ status: ChecklistAdminReviewStatus) {
        guard reviewStatus == .pending else {
            saveError = "This checklist already has a final administrator decision."
            pendingDecision = nil
            return
        }

        pendingDecision = nil
        isSaving = true
        saveError = nil

        let payload: [String: Any] = [
            "adminReviewStatus": status.rawValue,
            "policeReportRequired": status == .escalationRequired,
            "adminReviewNotes": reviewNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            "adminReviewedByUid": auth.user?.uid ?? "",
            "adminReviewedByName": auth.currentUsername,
            "adminReviewedByEmail": auth.currentEmail,
            "adminReviewedAt": FieldValue.serverTimestamp(),
            "baselineUpdateStatus": record.detectionCount == 0
                ? "not_required"
                : (status == .escalationRequired ? "awaiting_np299" : "not_approved")
        ]

        Firestore.firestore()
            .collection("seccom_checklists")
            .document(record.id)
            .setData(payload, merge: true) { error in
                DispatchQueue.main.async {
                    isSaving = false
                    if let error {
                        saveError = "Could not save the administrator decision: \(error.localizedDescription)"
                        return
                    }
                    reviewStatus = status
                    reviewedByName = auth.currentUsername
                    reviewedAt = Date()
                    onSaved()
                    if status == .escalationRequired {
                        openNP299Workflow()
                    } else {
                        dismiss()
                    }
                }
            }
    }

    private func openNP299Workflow() {
        saveError = nil

        if isLoadingPhotos {
            saveError = "Damage evidence is still loading. Please wait a moment and try again."
            return
        }

        if let photoError, !damagePhotoMetadata().isEmpty {
            saveError = "The NP299 form cannot open until its damage evidence is available: \(photoError)"
            return
        }

        let carType = resolvedNP299CarType()
        let detections = loadedPhotos.flatMap { photo in
            photo.metadata.regions.map { region in
                MutableDamageDetection(
                    angleIndex: photo.metadata.angleIndex,
                    angleName: photo.metadata.angle,
                    damageType: region.damageType,
                    confidence: region.confidence,
                    cropImage: renderAnnotatedCrop(
                        image: photo.image,
                        bbox: region.normalizedBBox
                    ),
                    contextImage: nil,
                    cleanContextImage: photo.image.htxNormalizedImage(),
                    normalizedBBox: region.normalizedBBox,
                    isBaseline: false,
                    explanation: region.explanation.isEmpty
                        ? "\(region.damageType.capitalized) confirmed from the pre-driving checklist."
                        : region.explanation
                )
            }
        }

        np299Payload = ChecklistNP299Payload(
            carType: carType,
            detections: detections
        )
    }

    private func resolvedNP299CarType() -> CarType {
        for photo in loadedPhotos {
            if let rawType = photo.metadata.guideVehicleType,
               let exactType = CarType(rawValue: rawType) {
                return exactType
            }
        }

        if let exactType = CarType(rawValue: record.carType) {
            return exactType
        }

        let value = record.carType.lowercased()
        if value.contains("ambulance") { return .emergencyAmbulance }
        if value.contains("hazmat") { return .hazmat }
        if value.contains("suv") || value.contains("xc 90") ||
            value.contains("pajero") || value.contains("land cruiser") {
            return .suv
        }
        if value.contains("van") || value.contains("transporter") || value.contains("mpv") {
            return .mpv
        }
        return .sedan
    }

    private func loadDamagePhotos() {
        guard loadedPhotos.isEmpty, !isLoadingPhotos else { return }
        let metadata = damagePhotoMetadata()
        guard !metadata.isEmpty else { return }

        isLoadingPhotos = true
        photoError = nil
        loadDamagePhoto(metadata, index: 0, loaded: [])
    }

    private func loadDamagePhoto(
        _ metadata: [AdminDamagePhotoMetadata],
        index: Int,
        loaded: [LoadedAdminDamagePhoto]
    ) {
        guard index < metadata.count else {
            isLoadingPhotos = false
            loadedPhotos = loaded
            return
        }

        let item = metadata[index]
        ReportStore.downloadDataFromStorage(path: item.storagePath, maxSize: 25 * 1024 * 1024) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    guard let image = UIImage(data: data) else {
                        loadDamagePhoto(metadata, index: index + 1, loaded: loaded)
                        return
                    }
                    loadDamagePhoto(
                        metadata,
                        index: index + 1,
                        loaded: loaded + [LoadedAdminDamagePhoto(image: image, metadata: item)]
                    )
                case .failure(let error):
                    isLoadingPhotos = false
                    loadedPhotos = loaded
                    photoError = loaded.isEmpty
                        ? "Could not load submitted damage images: \(error.localizedDescription)"
                        : nil
                }
            }
        }
    }

    private func damagePhotoMetadata() -> [AdminDamagePhotoMetadata] {
        if let rawPhotos = data["damagePhotos"] as? [[String: Any]], !rawPhotos.isEmpty {
            return rawPhotos.compactMap { rawPhoto in
                guard let path = rawPhoto["storagePath"] as? String, !path.isEmpty else { return nil }
                let rawRegions = rawPhoto["confirmedDamage"] as? [[String: Any]] ?? []
                let regions = rawRegions.map(parseDamageRegion)
                return AdminDamagePhotoMetadata(
                    storagePath: path,
                    angle: rawPhoto["angle"] as? String ?? "Vehicle Image",
                    angleIndex: Int(number(rawPhoto["angleIndex"]) ?? 0),
                    guideVehicleType: rawPhoto["guideVehicleType"] as? String,
                    regions: regions
                )
            }
        }

        let legacyPaths = data["damageImageStoragePaths"] as? [String] ?? []
        return legacyPaths.enumerated().map { index, path in
            AdminDamagePhotoMetadata(
                storagePath: path,
                angle: "Damage Photo \(index + 1)",
                angleIndex: min(index, 3),
                guideVehicleType: nil,
                regions: []
            )
        }
    }

    private func parseDamageRegion(_ raw: [String: Any]) -> AdminDamageRegion {
        let boxDictionary = raw["boundingBox"] as? [String: Any]
        let x = number(boxDictionary?["x"])
        let y = number(boxDictionary?["y"])
        let width = number(boxDictionary?["width"])
        let height = number(boxDictionary?["height"])
        let box: CGRect? = {
            guard let x, let y, let width, let height, width > 0, height > 0 else { return nil }
            return CGRect(x: x, y: y, width: width, height: height)
        }()

        return AdminDamageRegion(
            damageType: raw["damageType"] as? String ?? "damage",
            confidence: number(raw["confidence"]) ?? 1,
            source: raw["source"] as? String ?? "ai_confirmed",
            explanation: raw["explanation"] as? String ?? "",
            normalizedBBox: box
        )
    }

    private func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    @ViewBuilder
    private func adminSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(accent)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            content()
        }
        .background(Color(.systemBackground).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.12), lineWidth: 1))
        .padding(.horizontal)
    }

    private func adminDetailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func kilometreText(_ value: String?) -> String {
        let text = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "-" }
        return text.localizedCaseInsensitiveContains("km") ? text : "\(text) km"
    }
}

// MARK: - Annotated Evidence Image

private struct AdminDamageAnnotatedImage: View {
    let image: UIImage
    let regions: [AdminDamageRegion]
    let showLabels: Bool

    var body: some View {
        GeometryReader { geometry in
            let imageRect = fittedImageRect(in: geometry.size)

            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)

                ForEach(Array(regions.enumerated()), id: \.element.id) { index, region in
                    if let box = region.normalizedBBox {
                        let rect = CGRect(
                            x: imageRect.minX + box.minX * imageRect.width,
                            y: imageRect.minY + box.minY * imageRect.height,
                            width: box.width * imageRect.width,
                            height: box.height * imageRect.height
                        )

                        Rectangle()
                            .stroke(Color.orange, lineWidth: 2.5)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)

                        if showLabels {
                            Text("D\(index + 1): \(region.damageType.capitalized)")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(Color.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .offset(
                                    x: min(max(imageRect.minX, rect.minX), max(imageRect.minX, imageRect.maxX - 145)),
                                    y: max(imageRect.minY, rect.minY - 24)
                                )
                        }
                    }
                }
            }
        }
    }

    private func fittedImageRect(in container: CGSize) -> CGRect {
        guard image.size.width > 0, image.size.height > 0 else { return .zero }
        let scale = min(container.width / image.size.width, container.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

private struct AdminDamagePhotoViewer: View {
    let photo: LoadedAdminDamagePhoto

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geometry in
                AdminDamageAnnotatedImage(
                    image: photo.image,
                    regions: photo.metadata.regions,
                    showLabels: true
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = min(max(lastScale * value, 1), 6)
                            }
                            .onEnded { _ in lastScale = scale },
                        DragGesture()
                            .onChanged { value in
                                guard scale > 1 else { return }
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in lastOffset = offset }
                    )
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.3)) {
                        if scale > 1 {
                            scale = 1
                            lastScale = 1
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            scale = 2.5
                            lastScale = 2.5
                        }
                    }
                }
            }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.headline.bold())
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.58))
                            .clipShape(Circle())
                    }
                    Spacer()
                    Text(photo.metadata.angle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.58))
                        .clipShape(Capsule())
                }
                .padding()
                Spacer()
            }
        }
        .statusBarHidden(true)
    }
}
