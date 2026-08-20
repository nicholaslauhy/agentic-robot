import SwiftUI
import FirebaseFirestore

enum FuelFollowUpStatus: String, Equatable {
    case pending
    case completed
    case rejected

    init(firestoreValue: Any?) {
        let value = (firestoreValue as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self = FuelFollowUpStatus(rawValue: value ?? "") ?? .pending
    }

    var title: String {
        switch self {
        case .pending: return "Pending"
        case .completed: return "Completed"
        case .rejected: return "Rejected"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "clock.badge.exclamationmark"
        case .completed: return "checkmark.seal.fill"
        case .rejected: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .orange
        case .completed: return .green
        case .rejected: return .red
        }
    }
}

private enum FuelFollowUpFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case pending = "Pending"
    case completed = "Completed"
    case rejected = "Rejected"

    var id: String { rawValue }
}

struct AdminFuelFollowUpView: View {
    private let initialReportID: String?

    @State private var reports: [RawReportDocument] = []
    @State private var selectedFilter: FuelFollowUpFilter = .all
    @State private var selectedReport: RawReportDocument?
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var unavailableReportMessage: String?
    @State private var didHandleInitialReport = false
    @State private var deletionCandidate: RawReportDocument?
    @State private var isDeleting = false
    @State private var deletionFeedbackTitle = ""
    @State private var deletionFeedbackMessage: String?

    private let accent = HTXTheme.fuelOrange

    init(initialReportID: String? = nil) {
        self.initialReportID = initialReportID
    }

    private var filteredReports: [RawReportDocument] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return reports.filter { report in
            let status = FuelFollowUpStatus(firestoreValue: report.raw["adminFollowUpStatus"])
            let matchesFilter: Bool
            switch selectedFilter {
            case .all: matchesFilter = true
            case .pending: matchesFilter = status == .pending
            case .completed: matchesFilter = status == .completed
            case .rejected: matchesFilter = status == .rejected
            }

            guard matchesFilter else { return false }
            guard !query.isEmpty else { return true }
            return report.entry.plate.lowercased().contains(query)
                || report.entry.reportNo.lowercased().contains(query)
                || report.entry.generatedBy.lowercased().contains(query)
        }
    }

    private var pendingCount: Int {
        reports.filter {
            FuelFollowUpStatus(firestoreValue: $0.raw["adminFollowUpStatus"]) == .pending
        }.count
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
                ProgressView("Deleting refuel report…")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .navigationTitle("Refuel Follow-up")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: fetchReports)
        .sheet(item: $selectedReport, onDismiss: fetchReports) { report in
            FuelDetailSheet(
                doc: report,
                allowsFollowUpActions: true,
                onFollowUpUpdated: fetchReports
            )
        }
        .alert(
            "Report Unavailable",
            isPresented: Binding(
                get: { unavailableReportMessage != nil },
                set: { if !$0 { unavailableReportMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { unavailableReportMessage = nil }
        } message: {
            Text(unavailableReportMessage ?? "")
        }
        .alert(
            "Delete Refuel Report?",
            isPresented: Binding(
                get: { deletionCandidate != nil },
                set: { if !$0 { deletionCandidate = nil } }
            ),
            presenting: deletionCandidate
        ) { report in
            Button("Delete Permanently", role: .destructive) {
                deleteReport(report)
            }
            Button("Cancel", role: .cancel) { deletionCandidate = nil }
        } message: { report in
            Text("\(report.entry.reportNo) and its attached receipt will be permanently deleted. This cannot be undone.")
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
            Image(systemName: "fuelpump.circle.fill")
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(accent)
                .clipShape(RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 3) {
                Text("Refuel submissions")
                    .font(.headline)
                Text("\(pendingCount) report\(pendingCount == 1 ? "" : "s") awaiting follow-up")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: fetchReports) {
                Image(systemName: "arrow.clockwise")
                    .font(.headline)
                    .foregroundColor(accent)
                    .frame(width: 42, height: 42)
                    .background(accent.opacity(0.09))
                    .clipShape(Circle())
            }
            .disabled(isLoading)
        }
        .padding()
    }

    private var filterBar: some View {
        HStack(spacing: 9) {
            ForEach(FuelFollowUpFilter.allCases) { filter in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedFilter = filter
                    }
                } label: {
                    Text(filter.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .foregroundColor(selectedFilter == filter ? .white : .secondary)
                        .background(selectedFilter == filter ? accent : Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search vehicle, driver or report number", text: $searchText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(.systemBackground).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.22), lineWidth: 1))
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            Spacer()
            ProgressView("Loading refuel reports…")
                .tint(accent)
            Spacer()
        } else if let errorMessage {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                Text(errorMessage)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                Button("Retry", action: fetchReports)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
            }
            .padding()
            Spacer()
        } else if filteredReports.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "fuelpump.slash.fill")
                    .font(.system(size: 42))
                    .foregroundColor(accent.opacity(0.55))
                Text(emptyMessage)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredReports) { report in
                        HStack(spacing: 9) {
                            Button {
                                selectedReport = report
                            } label: {
                                reportRow(report)
                            }
                            .buttonStyle(.plain)

                            Button {
                                deletionCandidate = report
                            } label: {
                                Image(systemName: "trash.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.red)
                                    .frame(width: 44, height: 44)
                                    .background(Color.red.opacity(0.09))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete \(report.entry.reportNo)")
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .refreshable { fetchReports() }
        }
    }

    private func reportRow(_ report: RawReportDocument) -> some View {
        let status = FuelFollowUpStatus(firestoreValue: report.raw["adminFollowUpStatus"])
        return HStack(spacing: 14) {
            Image(systemName: "fuelpump.fill")
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(accent)
                .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 4) {
                Text(report.entry.plate)
                    .font(.headline)
                Text(report.entry.reportNo)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(accent)
                Text(report.entry.generatedBy)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Label(status.title, systemImage: status.icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(status.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(status.color.opacity(0.10))
                    .clipShape(Capsule())
                Text(report.entry.shortDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(Color(.systemBackground).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(status.color.opacity(0.14), lineWidth: 1))
    }

    private var emptyMessage: String {
        switch selectedFilter {
        case .all: return "No refuel reports have been submitted."
        case .pending: return "No refuel reports are awaiting follow-up."
        case .completed: return "No refuel follow-ups have been completed."
        case .rejected: return "No refuel reports have been rejected."
        }
    }

    private func fetchReports() {
        isLoading = true
        errorMessage = nil

        Firestore.firestore()
            .collection("fuel_refuel_reports")
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    isLoading = false
                    if let error {
                        reports = []
                        errorMessage = "Could not load refuel reports: \(error.localizedDescription)"
                        return
                    }

                    reports = (snapshot?.documents ?? []).compactMap { document in
                        let data = document.data()
                        guard let reportNo = data["reportNo"] as? String else { return nil }
                        let vehicle = data["vehicleNumber"] as? String ?? data["plate"] as? String ?? "-"
                        let entry = ReportEntry(
                            id: document.documentID,
                            reportNo: reportNo,
                            plate: vehicle,
                            carType: data["carType"] as? String ?? "-",
                            generatedBy: data["generatedBy"] as? String ?? data["driverName"] as? String ?? "-",
                            detectionCount: 0,
                            createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
                            barcodeId: data["barcodeId"] as? String ?? document.documentID,
                            pdfFileName: data["pdfFileName"] as? String,
                            pdfBase64: data["pdfBase64"] as? String,
                            pdfStoragePath: data["pdfStoragePath"] as? String
                        )
                        return RawReportDocument(id: document.documentID, entry: entry, raw: data)
                    }
                    openInitialReportIfNeeded()
                }
            }
    }

    private func openInitialReportIfNeeded() {
        guard !didHandleInitialReport,
              let initialReportID,
              !initialReportID.isEmpty else { return }

        didHandleInitialReport = true
        if let report = reports.first(where: { $0.id == initialReportID }) {
            selectedReport = report
        } else {
            unavailableReportMessage = "This refuel report may have been deleted or is no longer available."
        }
    }

    private func deleteReport(_ report: RawReportDocument) {
        deletionCandidate = nil
        isDeleting = true

        let storagePaths = [report.raw["receiptStoragePath"] as? String]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

        ReportStore.deleteReport(
            collection: "fuel_refuel_reports",
            documentID: report.id,
            storagePaths: storagePaths
        ) { result in
            DispatchQueue.main.async {
                isDeleting = false
                switch result {
                case .success(let deletionResult):
                    reports.removeAll { $0.id == report.id }
                    if selectedReport?.id == report.id {
                        selectedReport = nil
                    }

                    if !deletionResult.storagePathsNotDeleted.isEmpty {
                        deletionFeedbackTitle = "Report Deleted with Warning"
                        deletionFeedbackMessage = "The refuel report was deleted, but its receipt could not be removed. Check Firebase Storage permissions."
                    }
                case .failure(let error):
                    deletionFeedbackTitle = "Could Not Delete Report"
                    deletionFeedbackMessage = error.localizedDescription
                }
            }
        }
    }
}
