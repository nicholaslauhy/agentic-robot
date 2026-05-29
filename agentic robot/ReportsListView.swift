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

// MARK: - Raw report document (carries full Firestore data)
struct RawReportDocument: Identifiable {
    let id: String           // Firestore document ID
    let entry: ReportEntry   // shared display fields
    let raw: [String: Any]   // full document for type-specific detail views
}

// MARK: - Reports List View
struct ReportsListView: View {

    @State private var selectedCategory: ReportCategory = .np299

    @State private var np299Docs:  [RawReportDocument] = []
    @State private var secComDocs: [RawReportDocument] = []
    @State private var fuelDocs:   [RawReportDocument] = []

    @State private var isLoading    = false
    @State private var errorMessage: String? = nil
    @State private var searchText   = ""

    @State private var selectedDoc: RawReportDocument? = nil
    @State private var selectedPDFURL: URL? = nil

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
                                ReportRowCard(report: doc.entry, accent: selectedCategory.accentColor)
                                    .onTapGesture { selectedDoc = doc }
                            }
                        }
                        .padding(.horizontal).padding(.bottom, 24)
                    }
                }
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
                ReportDetailSheet(report: doc.entry) { url in
                    selectedDoc = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { selectedPDFURL = url }
                }
            case .secCom:
                SecComDetailSheet(doc: doc)
            case .fuel:
                FuelDetailSheet(doc: doc)
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

        group.notify(queue: .main) { isLoading = false }
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
                            pdfBase64:      data["pdfBase64"]      as? String
                        )
                        return RawReportDocument(id: doc.documentID, entry: entry, raw: data)
                    }
                    completion(docs)
                }
            }
    }
}

// MARK: - Report Row Card
private struct ReportRowCard: View {
    let report: ReportEntry
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
                    Text("·")
                    Text("\(report.detectionCount) case\(report.detectionCount == 1 ? "" : "s")")
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
    let report: ReportEntry
    var onViewPDF: (URL) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var pdfErrorMessage: String? = nil

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

                        // Barcode
                        barcodeBlock(report.barcodeId, accent: HTXTheme.primaryPurple)

                        if let pdfErrorMessage {
                            Text(pdfErrorMessage).font(.footnote.weight(.semibold))
                                .foregroundColor(.red).multilineTextAlignment(.center).padding(.horizontal)
                        }

                        Button {
                            guard let url = ReportStore.resolvedPDFURL(for: report) else {
                                pdfErrorMessage = "PDF not available. Regenerate the report to save a PDF."
                                return
                            }
                            pdfErrorMessage = nil
                            onViewPDF(url)
                        } label: {
                            HStack {
                                Image(systemName: "doc.richtext.fill")
                                Text(report.hasPDF ? "View PDF Report" : "PDF Not Saved")
                            }
                            .font(.headline).frame(maxWidth: .infinity).padding()
                            .background(report.hasPDF ? HTXTheme.primaryPurple : Color.gray)
                            .foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 14))
                        }
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
struct SecComDetailSheet: View {
    let doc: RawReportDocument
    @Environment(\.dismiss) var dismiss
    private let accent = Color(red: 0.08, green: 0.50, blue: 0.30)

    private var d: [String: Any] { doc.raw }

    private var equipment: [String] { d["equipment"] as? [String] ?? [] }
    private var selectedEquipmentSet: Set<String> {
        Set(equipment.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
    }
    private var damageImages: [UIImage] {
        guard let b64Array = d["damageImagesBase64"] as? [String] else { return [] }
        return b64Array.compactMap { b64 in
            guard let data = Data(base64Encoded: b64) else { return nil }
            return UIImage(data: data)
        }
    }
    private var bodyworkAllInOrder: Bool { d["bodyworkAllInOrder"] as? Bool ?? true }
    private var bodyworkDetails: String { d["bodyworkDetails"] as? String ?? "" }

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
                            DetailRow(label: "Mileage",        value: (d["mileage"] as? String ?? "-") + " km")
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
                        if !damageImages.isEmpty {
                            sectionCard(title: "New Damage Detected", icon: "camera.fill", accent: accent) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(damageImages.indices, id: \.self) { idx in
                                            Image(uiImage: damageImages[idx])
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 132, height: 132)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(accent.opacity(0.18), lineWidth: 1)
                                                )
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                }
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
        }
    }
}

// MARK: - Fuel Detail Sheet
struct FuelDetailSheet: View {
    let doc: RawReportDocument
    @Environment(\.dismiss) var dismiss
    private let accent = HTXTheme.fuelOrange

    private var d: [String: Any] { doc.raw }
    private var usedMastercard: Bool { d["usedMastercard"] as? Bool ?? false }
    private var receiptImage: UIImage? {
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
                            DetailRow(label: "Odometer",        value: (d["odometer"] as? String ?? "-") + " km")
                        }

                        // Mastercard
                        sectionCard(title: "Mastercard Usage", icon: "creditcard.fill", accent: accent) {
                            StatusDetailRow(
                                label: "Mastercard Used",
                                value: usedMastercard ? "Yes" : "No",
                                systemImage: usedMastercard ? "checkmark.circle.fill" : "xmark.circle.fill",
                                tint: usedMastercard ? accent : .secondary
                            )
                        }

                        // Receipt
                        if let img = receiptImage {
                            sectionCard(title: "Fuel Receipt", icon: "doc.text.fill", accent: accent) {
                                Image(uiImage: img)
                                    .resizable().scaledToFit()
                                    .frame(maxHeight: 280)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .frame(maxWidth: .infinity)
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
        }
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(isChecked ? accent : .secondary)
                .frame(width: 22, alignment: .center)

            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(isChecked ? "Checked" : "Unchecked")
                .font(.caption.weight(.semibold))
                .foregroundColor(isChecked ? accent : .secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background((isChecked ? accent : Color.secondary).opacity(0.10))
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
