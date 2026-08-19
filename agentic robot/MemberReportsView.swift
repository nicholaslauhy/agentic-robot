import SwiftUI
import FirebaseAuth
import FirebaseFirestore

private enum MemberReportFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case np299 = "NP299"
    case checklist = "Pre-driving"
    case refuel = "Refuel"

    var id: String { rawValue }

    var category: ReportCategory? {
        switch self {
        case .all: return nil
        case .np299: return .np299
        case .checklist: return .secCom
        case .refuel: return .fuel
        }
    }

    var icon: String {
        switch self {
        case .all: return "tray.full.fill"
        case .np299: return ReportCategory.np299.icon
        case .checklist: return ReportCategory.secCom.icon
        case .refuel: return ReportCategory.fuel.icon
        }
    }
}

private enum MemberReportProgressFilter: String, CaseIterable, Identifiable {
    case all = "All Statuses"
    case pending = "Pending"
    case updated = "Updated"

    var id: String { rawValue }
}

private struct MemberReportStatus {
    let title: String
    let icon: String
    let color: Color
    let isPending: Bool
}

private struct MemberReportItem: Identifiable {
    let category: ReportCategory
    let document: RawReportDocument

    var id: String { "\(category.rawValue)-\(document.id)" }

    var status: MemberReportStatus {
        switch category {
        case .np299:
            let linkedChecklist = document.raw["sourceChecklistId"] as? String
            if linkedChecklist?.isEmpty == false {
                return MemberReportStatus(
                    title: "Approved NP299",
                    icon: "checkmark.seal.fill",
                    color: .green,
                    isPending: false
                )
            }
            return MemberReportStatus(
                title: "Submitted",
                icon: "paperplane.fill",
                color: .blue,
                isPending: false
            )

        case .secCom:
            switch ChecklistAdminReviewStatus(firestoreData: document.raw) {
            case .pending:
                return MemberReportStatus(
                    title: "Pending Review",
                    icon: "clock.badge.exclamationmark",
                    color: .orange,
                    isPending: true
                )
            case .escalationRequired:
                return MemberReportStatus(
                    title: "NP299 Required",
                    icon: "exclamationmark.shield.fill",
                    color: HTXTheme.primaryPurple,
                    isPending: true
                )
            case .np299InProgress:
                return MemberReportStatus(
                    title: "NP299 In Progress",
                    icon: "doc.badge.clock.fill",
                    color: .blue,
                    isPending: true
                )
            case .np299Filed:
                return MemberReportStatus(
                    title: "NP299 Filed",
                    icon: "checkmark.seal.fill",
                    color: .green,
                    isPending: false
                )
            case .noEscalation:
                return MemberReportStatus(
                    title: "No Escalation",
                    icon: "checkmark.seal.fill",
                    color: .green,
                    isPending: false
                )
            }

        case .fuel:
            switch FuelFollowUpStatus(firestoreValue: document.raw["adminFollowUpStatus"]) {
            case .pending:
                return MemberReportStatus(
                    title: "Pending Follow-up",
                    icon: "clock.badge.exclamationmark",
                    color: .orange,
                    isPending: true
                )
            case .completed:
                return MemberReportStatus(
                    title: "Follow-up Completed",
                    icon: "checkmark.seal.fill",
                    color: .green,
                    isPending: false
                )
            }
        }
    }

    var officerNotes: String {
        switch category {
        case .np299:
            return document.raw["officerNotes"] as? String ?? ""
        case .secCom:
            return document.raw["adminReviewNotes"] as? String ?? ""
        case .fuel:
            return document.raw["adminFollowUpNotes"] as? String ?? ""
        }
    }
}

struct MemberReportsView: View {
    @EnvironmentObject private var auth: AuthViewModel

    @State private var reports: [MemberReportItem] = []
    @State private var selectedCategory: MemberReportFilter = .all
    @State private var selectedProgress: MemberReportProgressFilter = .all
    @State private var selectedReport: MemberReportItem?
    @State private var selectedPDFURL: URL?
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var displayedReports: [MemberReportItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return reports.filter { item in
            if let category = selectedCategory.category, item.category != category {
                return false
            }

            switch selectedProgress {
            case .all:
                break
            case .pending where !item.status.isPending:
                return false
            case .updated where item.status.isPending:
                return false
            default:
                break
            }

            guard !query.isEmpty else { return true }
            let entry = item.document.entry
            return entry.plate.lowercased().contains(query)
                || entry.reportNo.lowercased().contains(query)
                || entry.carType.lowercased().contains(query)
                || item.status.title.lowercased().contains(query)
        }
    }

    private var pendingCount: Int {
        reports.filter { $0.status.isPending }.count
    }

    var body: some View {
        ZStack {
            SubtleHTXBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                summaryHeader
                categoryFilters
                progressFilters
                searchBar
                content
            }
        }
        .navigationTitle("My Reports")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: fetchReports)
        .sheet(item: $selectedReport) { item in
            switch item.category {
            case .np299:
                ReportDetailSheet(report: item.document.entry) { url in
                    selectedReport = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        selectedPDFURL = url
                    }
                }
            case .secCom:
                SecComDetailSheet(doc: item.document)
            case .fuel:
                FuelDetailSheet(doc: item.document)
            }
        }
        .sheet(item: $selectedPDFURL) { url in
            ReportPDFPreviewView(url: url)
        }
        .requiresRole(.member)
    }

    private var summaryHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder.badge.person.crop")
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(HTXTheme.primaryPurple)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 3) {
                Text("Your submissions")
                    .font(.headline)
                Text("\(reports.count) total · \(pendingCount) pending")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: fetchReports) {
                Image(systemName: "arrow.clockwise")
                    .font(.headline)
                    .foregroundColor(HTXTheme.primaryPurple)
                    .frame(width: 40, height: 40)
                    .background(HTXTheme.primaryPurple.opacity(0.08))
                    .clipShape(Circle())
            }
            .disabled(isLoading)
            .accessibilityLabel("Refresh my reports")
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var categoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(MemberReportFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = filter
                        }
                    } label: {
                        Label(filter.rawValue, systemImage: filter.icon)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                selectedCategory == filter
                                ? HTXTheme.primaryPurple
                                : Color(.secondarySystemBackground)
                            )
                            .foregroundColor(selectedCategory == filter ? .white : .secondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 5)
        }
    }

    private var progressFilters: some View {
        HStack(spacing: 8) {
            ForEach(MemberReportProgressFilter.allCases) { filter in
                Button {
                    selectedProgress = filter
                } label: {
                    Text(filter.rawValue)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selectedProgress == filter
                            ? HTXTheme.primaryPurple.opacity(0.12)
                            : Color.clear
                        )
                        .foregroundColor(
                            selectedProgress == filter ? HTXTheme.primaryPurple : .secondary
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search vehicle or report number", text: $searchText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(HTXTheme.primaryPurple.opacity(0.18), lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            Spacer()
            ProgressView("Loading your reports…")
                .tint(HTXTheme.primaryPurple)
            Spacer()
        } else if let errorMessage {
            Spacer()
            ContentUnavailableView(
                "Could not load reports",
                systemImage: "exclamationmark.triangle.fill",
                description: Text(errorMessage)
            )
            Button("Try Again", action: fetchReports)
                .buttonStyle(.borderedProminent)
                .tint(HTXTheme.primaryPurple)
                .padding(.top, 10)
            Spacer()
        } else if displayedReports.isEmpty {
            Spacer()
            ContentUnavailableView(
                searchText.isEmpty ? "No reports here yet" : "No matching reports",
                systemImage: searchText.isEmpty ? "folder" : "magnifyingglass",
                description: Text(
                    searchText.isEmpty
                    ? "Reports that you submit will appear here with their follow-up status."
                    : "Try another vehicle number, report number or status."
                )
            )
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(displayedReports) { item in
                        Button {
                            selectedReport = item
                        } label: {
                            memberReportCard(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .refreshable { fetchReports() }
        }
    }

    private func memberReportCard(_ item: MemberReportItem) -> some View {
        let entry = item.document.entry
        let status = item.status

        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.category.icon)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(item.category.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.plate)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(entry.reportNo)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(item.category.accentColor)
                    Text("\(categoryTitle(item.category)) · \(entry.shortDate)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Label(status.title, systemImage: status.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(status.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(status.color.opacity(0.10))
                    .clipShape(Capsule())

                if !item.officerNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("Officer Notes", systemImage: "text.bubble.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(HTXTheme.primaryPurple)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.systemBackground).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(status.color.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    private func categoryTitle(_ category: ReportCategory) -> String {
        switch category {
        case .np299: return "NP299"
        case .secCom: return "Pre-driving Checklist"
        case .fuel: return "Refuel Form"
        }
    }

    private func fetchReports() {
        guard !isLoading, let uid = auth.user?.uid, !uid.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        let group = DispatchGroup()
        var ownedNP299: [RawReportDocument] = []
        var ownedChecklists: [RawReportDocument] = []
        var ownedRefuel: [RawReportDocument] = []
        var firstError: Error?

        func fetch(_ collection: String, completion: @escaping ([RawReportDocument]) -> Void) {
            group.enter()
            fetchOwnedCollection(collection, uid: uid) { result in
                switch result {
                case .success(let documents): completion(documents)
                case .failure(let error):
                    if firstError == nil { firstError = error }
                    completion([])
                }
                group.leave()
            }
        }

        fetch("reports") { ownedNP299 = $0 }
        fetch("seccom_checklists") { ownedChecklists = $0 }
        fetch("fuel_refuel_reports") { ownedRefuel = $0 }

        group.notify(queue: .main) {
            if let firstError {
                isLoading = false
                errorMessage = "\(firstError.localizedDescription) If the app was just updated, deploy the Phase 10 Firebase rules and try again."
                return
            }

            fetchLinkedNP299(from: ownedChecklists) { linkedNP299 in
                let combinedNP299 = deduplicatedReports(ownedNP299 + linkedNP299)
                reports = (
                    combinedNP299.map { MemberReportItem(category: .np299, document: $0) }
                    + ownedChecklists.map { MemberReportItem(category: .secCom, document: $0) }
                    + ownedRefuel.map { MemberReportItem(category: .fuel, document: $0) }
                )
                .sorted {
                    ($0.document.entry.createdAt ?? .distantPast)
                        > ($1.document.entry.createdAt ?? .distantPast)
                }
                isLoading = false
            }
        }
    }

    private func fetchOwnedCollection(
        _ collection: String,
        uid: String,
        completion: @escaping (Result<[RawReportDocument], Error>) -> Void
    ) {
        Firestore.firestore()
            .collection(collection)
            .whereField("createdByUid", isEqualTo: uid)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    if let error {
                        completion(.failure(error))
                        return
                    }

                    let documents = (snapshot?.documents ?? []).compactMap {
                        makeRawReport(id: $0.documentID, data: $0.data(), collection: collection)
                    }
                    completion(.success(documents))
                }
            }
    }

    private func fetchLinkedNP299(
        from checklists: [RawReportDocument],
        completion: @escaping ([RawReportDocument]) -> Void
    ) {
        let reportIDs = Set(checklists.compactMap { checklist -> String? in
            let value = checklist.raw["np299ReportId"] as? String
            return value?.isEmpty == false ? value : nil
        })

        guard !reportIDs.isEmpty else {
            completion([])
            return
        }

        let group = DispatchGroup()
        var linkedReports: [RawReportDocument] = []

        for reportID in reportIDs {
            group.enter()
            Firestore.firestore().collection("reports").document(reportID).getDocument { snapshot, _ in
                DispatchQueue.main.async {
                    defer { group.leave() }
                    guard let snapshot,
                          snapshot.exists,
                          let data = snapshot.data(),
                          let report = makeRawReport(
                            id: snapshot.documentID,
                            data: data,
                            collection: "reports"
                          ) else {
                        return
                    }
                    linkedReports.append(report)
                }
            }
        }

        group.notify(queue: .main) {
            completion(linkedReports)
        }
    }

    private func makeRawReport(
        id: String,
        data: [String: Any],
        collection: String
    ) -> RawReportDocument? {
        guard let reportNo = data["reportNo"] as? String else { return nil }

        let plate: String?
        if collection == "fuel_refuel_reports" {
            plate = data["vehicleNumber"] as? String ?? data["plate"] as? String
        } else {
            plate = data["plate"] as? String
        }
        guard let plate else { return nil }

        let entry = ReportEntry(
            id: id,
            reportNo: reportNo,
            plate: plate,
            carType: data["carType"] as? String ?? "-",
            generatedBy: data["generatedBy"] as? String ?? data["createdByName"] as? String ?? "-",
            detectionCount: data["detectionCount"] as? Int ?? 0,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
            barcodeId: data["barcodeId"] as? String ?? id,
            pdfFileName: data["pdfFileName"] as? String,
            pdfBase64: data["pdfBase64"] as? String,
            pdfStoragePath: data["pdfStoragePath"] as? String
        )

        return RawReportDocument(id: id, entry: entry, raw: data)
    }

    private func deduplicatedReports(_ documents: [RawReportDocument]) -> [RawReportDocument] {
        var seen: Set<String> = []
        return documents.filter { seen.insert($0.id).inserted }
    }
}
