import SwiftUI
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

// MARK: - Reports List View
struct ReportsListView: View {

    @State private var selectedCategory: ReportCategory = .np299

    // Per-category state
    @State private var np299Reports:  [ReportEntry] = []
    @State private var secComReports: [ReportEntry] = []
    @State private var fuelReports:   [ReportEntry] = []

    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var searchText = ""

    @State private var selectedReport: ReportEntry? = nil
    @State private var selectedPDFURL: URL? = nil

    // Active list for current tab
    private var activeReports: [ReportEntry] {
        switch selectedCategory {
        case .np299:  return np299Reports
        case .secCom: return secComReports
        case .fuel:   return fuelReports
        }
    }

    private var filteredReports: [ReportEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return activeReports }
        return activeReports.filter {
            $0.plate.lowercased().contains(query) ||
            $0.reportNo.lowercased().contains(query) ||
            $0.carType.lowercased().contains(query) ||
            $0.generatedBy.lowercased().contains(query) ||
            $0.barcodeId.contains(query)
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
                    TextField("Search by plate, officer, report no…", text: $searchText)
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
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selectedCategory.accentColor.opacity(0.25), lineWidth: 1))
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
                        Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundColor(.orange)
                        Text(errorMessage).multilineTextAlignment(.center).foregroundColor(.secondary)
                        Button("Retry") { fetchAll() }.buttonStyle(.borderedProminent).tint(selectedCategory.accentColor)
                    }
                    .padding()
                    Spacer()
                } else if filteredReports.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: searchText.isEmpty ? "folder.badge.questionmark" : "magnifyingglass")
                            .font(.system(size: 44))
                            .foregroundColor(selectedCategory.accentColor.opacity(0.5))
                        Text(searchText.isEmpty
                             ? selectedCategory.emptyLabel
                             : "No reports match \"\(searchText)\".")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                } else {
                    HStack {
                        Text("\(filteredReports.count) report\(filteredReports.count == 1 ? "" : "s")")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button { fetchAll() } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.subheadline)
                                .foregroundColor(selectedCategory.accentColor)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 4)

                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredReports) { report in
                                ReportRowCard(report: report, accent: selectedCategory.accentColor)
                                    .onTapGesture { selectedReport = report }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .navigationTitle("Existing Reports")
        .navigationBarTitleDisplayMode(.inline)
        .tint(selectedCategory.accentColor)
        .onAppear { fetchAll() }
        .onChange(of: selectedCategory) { _, _ in searchText = "" }
        .sheet(item: $selectedReport) { report in
            ReportDetailSheet(report: report) { url in
                selectedReport = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { selectedPDFURL = url }
            }
        }
        .sheet(item: $selectedPDFURL) { url in
            ReportPDFPreviewView(url: url)
        }
    }

    // MARK: - Category Tab Button
    @ViewBuilder
    private func categoryTab(_ cat: ReportCategory) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) { selectedCategory = cat }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: cat.icon)
                    .font(.subheadline)
                Text(cat.rawValue)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                selectedCategory == cat
                ? cat.accentColor
                : Color(.secondarySystemBackground)
            )
            .foregroundColor(selectedCategory == cat ? .white : .secondary)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(
                    selectedCategory == cat ? cat.accentColor : HTXTheme.softPurpleBorder,
                    lineWidth: 1.5
                )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Fetch All Collections

    private func fetchAll() {
        isLoading = true
        errorMessage = nil

        let group = DispatchGroup()

        group.enter()
        fetchCollection("reports") { entries in
            np299Reports = entries
            group.leave()
        }

        group.enter()
        fetchCollection("seccom_checklists") { entries in
            secComReports = entries
            group.leave()
        }

        group.enter()
        fetchCollection("fuel_refuel_reports") { entries in
            fuelReports = entries
            group.leave()
        }

        group.notify(queue: .main) {
            isLoading = false
        }
    }

    private func fetchCollection(_ collection: String, completion: @escaping ([ReportEntry]) -> Void) {
        Firestore.firestore()
            .collection(collection)
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    if let error {
                        self.errorMessage = error.localizedDescription
                        completion([])
                        return
                    }

                    let entries = (snapshot?.documents ?? []).compactMap { doc -> ReportEntry? in
                        let data = doc.data()
                        guard
                            let reportNo = data["reportNo"] as? String,
                            let plate    = data["plate"]    as? String
                        else { return nil }

                        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
                        return ReportEntry(
                            id:             doc.documentID,
                            reportNo:       reportNo,
                            plate:          plate,
                            carType:        data["carType"]        as? String ?? "-",
                            generatedBy:    data["generatedBy"]    as? String ?? "-",
                            detectionCount: data["detectionCount"] as? Int    ?? 0,
                            createdAt:      createdAt,
                            barcodeId:      data["barcodeId"]      as? String ?? doc.documentID,
                            pdfFileName:    data["pdfFileName"]    as? String,
                            pdfBase64:      data["pdfBase64"]      as? String
                        )
                    }
                    completion(entries)
                }
            }
    }
}

// MARK: - Report Row Card
private struct ReportRowCard: View {
    let report: ReportEntry
    let accent: Color

    private var generatedByText: String {
        let trimmed = report.generatedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "-" ? "Not recorded" : trimmed
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack {
                Image(systemName: "doc.text.fill")
                    .font(.title3)
                    .foregroundColor(.white)
            }
            .frame(width: 44, height: 44)
            .background(LinearGradient(colors: [accent, accent.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 4) {
                Text(report.plate)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(report.reportNo)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(accent)

                HStack(spacing: 6) {
                    Text(report.carType)
                    Text("·")
                    Text("\(report.detectionCount) case\(report.detectionCount == 1 ? "" : "s")")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(report.shortDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(accent.opacity(0.6))
            }
        }
        .padding(14)
        .background(Color(.systemBackground).opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
}

// MARK: - Report Detail Sheet
struct ReportDetailSheet: View {
    let report: ReportEntry
    var onViewPDF: (URL) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var pdfErrorMessage: String? = nil

    private var generatedByText: String {
        let trimmed = report.generatedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "-" ? "Not recorded" : trimmed
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SubtleHTXBackground().ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        VStack(spacing: 6) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 40))
                                .foregroundColor(HTXTheme.primaryPurple)
                            Text(report.plate)
                                .font(.largeTitle.weight(.black))
                                .foregroundColor(.primary)
                            Text(report.reportNo)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(HTXTheme.primaryPurple)
                            Label("Generated by \(generatedByText)", systemImage: "person.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(Color(.systemBackground).opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .padding(.horizontal)

                        VStack(spacing: 0) {
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
                        .background(Color(.systemBackground).opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(HTXTheme.primaryPurple.opacity(0.12), lineWidth: 1))
                        .padding(.horizontal)

                        VStack(spacing: 8) {
                            Text("Barcode ID")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            Text(report.barcodeId)
                                .font(.system(.title2, design: .monospaced).weight(.bold))
                                .foregroundColor(HTXTheme.primaryPurple)
                                .tracking(3)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(HTXTheme.primaryPurple.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(HTXTheme.primaryPurple.opacity(0.2), lineWidth: 1))
                        .padding(.horizontal)

                        if let pdfErrorMessage {
                            Text(pdfErrorMessage)
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        Button {
                            guard let url = ReportStore.resolvedPDFURL(for: report) else {
                                pdfErrorMessage = "This report record exists, but the PDF file is not available. Generate it again so the PDF can be saved."
                                return
                            }
                            pdfErrorMessage = nil
                            onViewPDF(url)
                        } label: {
                            HStack {
                                Image(systemName: "doc.richtext.fill")
                                Text(report.hasPDF ? "View PDF Report" : "PDF Not Saved")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(report.hasPDF ? HTXTheme.primaryPurple : Color.gray)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal)

                        Spacer().frame(height: 10)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Report Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(HTXTheme.primaryPurple)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Detail Row
private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
