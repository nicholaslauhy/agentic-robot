import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore

enum VehicleOperationalStatus: String, CaseIterable, Identifiable {
    case operational
    case repair
    case maintenance
    case outOfService = "out_of_service"
    case other

    var id: String { rawValue }

    init(firestoreValue: Any?) {
        let value = (firestoreValue as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self = VehicleOperationalStatus(rawValue: value ?? "") ?? .operational
    }

    var title: String {
        switch self {
        case .operational: return "Operational"
        case .repair: return "Repair Required"
        case .maintenance: return "Under Maintenance"
        case .outOfService: return "Out of Service"
        case .other: return "Other"
        }
    }

    var shortTitle: String {
        switch self {
        case .repair: return "Repair"
        case .maintenance: return "Maintenance"
        default: return title
        }
    }

    var icon: String {
        switch self {
        case .operational: return "checkmark.circle.fill"
        case .repair: return "wrench.adjustable.fill"
        case .maintenance: return "gearshape.2.fill"
        case .outOfService: return "exclamationmark.octagon.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .operational: return .green
        case .repair: return .orange
        case .maintenance: return .blue
        case .outOfService: return .red
        case .other: return .gray
        }
    }
}

private enum VehicleStatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case operational = "Operational"
    case repair = "Repair"
    case maintenance = "Maintenance"
    case outOfService = "Out of Service"
    case other = "Other"

    var id: String { rawValue }

    var status: VehicleOperationalStatus? {
        switch self {
        case .all: return nil
        case .operational: return .operational
        case .repair: return .repair
        case .maintenance: return .maintenance
        case .outOfService: return .outOfService
        case .other: return .other
        }
    }
}

private enum VehicleListScope: String, CaseIterable, Identifiable {
    case all = "All Vehicles"
    case statusFollowUp = "Status Follow-up"

    var id: String { rawValue }
}

private struct VehicleTypeSection: Identifiable {
    let type: String
    let vehicles: [ManagedVehicle]

    var id: String { type }
}

struct ManagedVehicle: Identifiable {
    let id: String
    var plate: String
    var carType: String
    var status: VehicleOperationalStatus
    var statusNotes: String
    var updatedBy: String
    var updatedAt: Date?

    static func identifier(for plate: String) -> String {
        plate
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
    }
}

private enum VehicleHistoryCategory: String {
    case np299
    case checklist
    case refuel
    case status

    var title: String {
        switch self {
        case .np299: return "NP299 Report"
        case .checklist: return "Pre-driving Checklist"
        case .refuel: return "Refuel Report"
        case .status: return "Vehicle Status Updated"
        }
    }

    var icon: String {
        switch self {
        case .np299: return "doc.text.fill"
        case .checklist: return "checklist.checked"
        case .refuel: return "fuelpump.fill"
        case .status: return "car.badge.gearshape.fill"
        }
    }

    var color: Color {
        switch self {
        case .np299: return HTXTheme.primaryPurple
        case .checklist: return Color(red: 0.08, green: 0.50, blue: 0.30)
        case .refuel: return HTXTheme.fuelOrange
        case .status: return .blue
        }
    }
}

private struct VehicleHistoryItem: Identifiable {
    let id: String
    let category: VehicleHistoryCategory
    let title: String
    let subtitle: String
    let detail: String
    let createdAt: Date?
    let report: RawReportDocument?

    var dateText: String {
        guard let createdAt else { return "Date unavailable" }
        return createdAt.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct VehicleBaselineSnapshot: Identifiable {
    let id: String
    let angleName: String
    let damageType: String
    let image: UIImage
    let normalizedBox: CGRect?
}

struct AdminVehicleManagementView: View {
    @State private var vehicles: [ManagedVehicle] = []
    @State private var pendingStatusFollowUps: [RawReportDocument] = []
    @State private var selectedStatusFollowUp: RawReportDocument?
    @State private var selectedPDFURL: URL?
    @State private var selectedScope: VehicleListScope = .all
    @State private var selectedFilter: VehicleStatusFilter = .all
    @State private var selectedVehicleType: String?
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var statusFollowUpError: String?

    private var filteredVehicles: [ManagedVehicle] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return vehicles.filter { vehicle in
            let matchesFilter = selectedFilter.status == nil || vehicle.status == selectedFilter.status
            let matchesVehicleType = selectedVehicleType == nil || vehicle.carType == selectedVehicleType
            guard matchesFilter, matchesVehicleType else { return false }
            guard !query.isEmpty else { return true }
            return vehicle.plate.lowercased().contains(query)
                || vehicle.carType.lowercased().contains(query)
                || vehicle.status.title.lowercased().contains(query)
        }
    }

    private var filteredStatusFollowUps: [RawReportDocument] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return pendingStatusFollowUps }
        return pendingStatusFollowUps.filter { document in
            document.entry.plate.lowercased().contains(query)
                || document.entry.reportNo.lowercased().contains(query)
                || document.entry.carType.lowercased().contains(query)
                || document.entry.generatedBy.lowercased().contains(query)
        }
    }

    private var vehicleTypes: [String] {
        Array(Set(vehicles.map(\.carType)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var vehicleSections: [VehicleTypeSection] {
        Dictionary(grouping: filteredVehicles, by: \.carType)
            .map { type, groupedVehicles in
                VehicleTypeSection(
                    type: type,
                    vehicles: groupedVehicles.sorted {
                        $0.plate.localizedStandardCompare($1.plate) == .orderedAscending
                    }
                )
            }
            .sorted { $0.type.localizedStandardCompare($1.type) == .orderedAscending }
    }

    private var attentionCount: Int {
        vehicles.filter { $0.status != .operational }.count
    }

    var body: some View {
        ZStack {
            SubtleHTXBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                summaryHeader
                scopePicker
                searchBar
                if selectedScope == .all {
                    vehicleTypeFilter
                    filterBar
                    content
                } else {
                    statusFollowUpContent
                }
            }
        }
        .navigationTitle("Vehicle Management")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: fetchVehicles)
        .onChange(of: selectedScope) { _, _ in
            searchText = ""
        }
        .sheet(item: $selectedStatusFollowUp) { document in
            ReportDetailSheet(
                document: document,
                onViewPDF: { url in
                    selectedStatusFollowUp = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        selectedPDFURL = url
                    }
                },
                onVehicleStatusFollowUpResolved: fetchVehicles
            )
        }
        .sheet(item: $selectedPDFURL) { url in
            ReportPDFPreviewView(url: url)
        }
        .requiresRole(.admin)
    }

    private var scopePicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("VEHICLE LIST")
                .font(.caption2.weight(.bold))
                .foregroundColor(.secondary)

            Picker("Vehicle list", selection: $selectedScope) {
                Text(VehicleListScope.all.rawValue).tag(VehicleListScope.all)
                Text("Status Follow-up (\(pendingStatusFollowUps.count))")
                    .tag(VehicleListScope.statusFollowUp)
            }
            .pickerStyle(.segmented)

            if selectedScope == .statusFollowUp {
                Text("New NP299 reports stay here until an administrator updates the vehicle status or confirms that no change is needed.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    private var summaryHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "car.2.fill")
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(HTXTheme.primaryPurple)
                .clipShape(RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 3) {
                Text("Fleet overview")
                    .font(.headline)
                Text("\(vehicles.count) vehicles · \(attentionCount) requiring attention")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: fetchVehicles) {
                Image(systemName: "arrow.clockwise")
                    .font(.headline)
                    .foregroundColor(HTXTheme.primaryPurple)
                    .frame(width: 42, height: 42)
                    .background(HTXTheme.primaryPurple.opacity(0.09))
                    .clipShape(Circle())
            }
            .disabled(isLoading)
        }
        .padding()
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STATUS")
                .font(.caption2.weight(.bold))
                .foregroundColor(.secondary)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(VehicleStatusFilter.allCases) { filter in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedFilter = filter
                            }
                        } label: {
                            Text(filter.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(selectedFilter == filter ? .white : .secondary)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 9)
                                .background(
                                    selectedFilter == filter
                                    ? HTXTheme.primaryPurple
                                    : Color(.secondarySystemBackground)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 10)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField(
                selectedScope == .all
                    ? "Search vehicle number, type or status"
                    : "Search pending vehicle or report",
                text: $searchText
            )
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
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(HTXTheme.primaryPurple.opacity(0.20), lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    private var vehicleTypeFilter: some View {
        Menu {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedVehicleType = nil
                }
            } label: {
                Label(
                    "All Vehicle Types",
                    systemImage: selectedVehicleType == nil ? "checkmark" : "car.2"
                )
            }

            Divider()

            ForEach(vehicleTypes, id: \.self) { vehicleType in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedVehicleType = vehicleType
                    }
                } label: {
                    Label(
                        vehicleType,
                        systemImage: selectedVehicleType == vehicleType ? "checkmark" : "car.side"
                    )
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "car.2.fill")
                    .foregroundColor(HTXTheme.primaryPurple)
                    .frame(width: 34, height: 34)
                    .background(HTXTheme.primaryPurple.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text("VEHICLE TYPE")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.secondary)
                    Text(selectedVehicleType ?? "All Vehicle Types")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                Spacer()

                if selectedVehicleType != nil {
                    Text("Filtered")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(HTXTheme.primaryPurple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(HTXTheme.primaryPurple.opacity(0.09))
                        .clipShape(Capsule())
                }

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(11)
            .background(Color(.systemBackground).opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(HTXTheme.primaryPurple.opacity(0.20), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            Spacer()
            ProgressView("Loading vehicles…")
                .tint(HTXTheme.primaryPurple)
            Spacer()
        } else if let errorMessage {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                Text(errorMessage)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry", action: fetchVehicles)
                    .buttonStyle(.borderedProminent)
                    .tint(HTXTheme.primaryPurple)
            }
            .padding()
            Spacer()
        } else if filteredVehicles.isEmpty {
            Spacer()
            ContentUnavailableView(
                "No vehicles found",
                systemImage: "car.2",
                description: Text("Try another search, vehicle type or status filter.")
            )
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 18, pinnedViews: [.sectionHeaders]) {
                    ForEach(vehicleSections) { section in
                        Section {
                            ForEach(section.vehicles) { vehicle in
                                NavigationLink {
                                    VehicleManagementDetailView(
                                        vehicle: vehicle,
                                        onVehicleUpdated: fetchVehicles
                                    )
                                } label: {
                                    vehicleRow(vehicle)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            vehicleTypeHeader(section)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .refreshable { fetchVehicles() }
        }
    }

    @ViewBuilder
    private var statusFollowUpContent: some View {
        if isLoading {
            Spacer()
            ProgressView("Loading pending follow-ups…")
                .tint(HTXTheme.primaryPurple)
            Spacer()
        } else if let statusFollowUpError, pendingStatusFollowUps.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                Text(statusFollowUpError)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry", action: fetchVehicles)
                    .buttonStyle(.borderedProminent)
                    .tint(HTXTheme.primaryPurple)
            }
            .padding()
            Spacer()
        } else if filteredStatusFollowUps.isEmpty {
            Spacer()
            ContentUnavailableView(
                searchText.isEmpty ? "No pending follow-ups" : "No matching follow-ups",
                systemImage: "checkmark.seal.fill",
                description: Text(
                    searchText.isEmpty
                        ? "Every filed NP299 has a completed vehicle-status decision."
                        : "Try another vehicle number or report number."
                )
            )
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredStatusFollowUps) { document in
                        Button {
                            selectedStatusFollowUp = document
                        } label: {
                            statusFollowUpRow(document)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .refreshable { fetchVehicles() }
        }
    }

    private func statusFollowUpRow(_ document: RawReportDocument) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "car.badge.clock.fill")
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 46, height: 46)
                .background(HTXTheme.primaryPurple)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(document.entry.plate)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(document.entry.reportNo)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(HTXTheme.primaryPurple)
                Text("Filed by \(document.entry.generatedBy)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text("Pending")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.10))
                    .clipShape(Capsule())
                Text(document.entry.shortDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(Color(.systemBackground).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(HTXTheme.primaryPurple.opacity(0.15), lineWidth: 1)
        )
    }

    private func vehicleTypeHeader(_ section: VehicleTypeSection) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "car.side.fill")
                .font(.subheadline)
                .foregroundColor(HTXTheme.primaryPurple)

            Text(section.type)
                .font(.headline)
                .foregroundColor(.primary)

            Spacer()

            Text("\(section.vehicles.count)")
                .font(.caption.weight(.bold))
                .foregroundColor(HTXTheme.primaryPurple)
                .frame(minWidth: 26, minHeight: 26)
                .background(HTXTheme.primaryPurple.opacity(0.10))
                .clipShape(Circle())
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(HTXTheme.primaryPurple.opacity(0.14), lineWidth: 1)
        )
    }

    private func vehicleRow(_ vehicle: ManagedVehicle) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "car.side.fill")
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(HTXTheme.primaryPurple)
                .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 4) {
                Text(vehicle.plate)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(vehicle.carType)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Label(vehicle.status.shortTitle, systemImage: vehicle.status.icon)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(vehicle.status.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(vehicle.status.color.opacity(0.10))
                    .clipShape(Capsule())
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(Color(.systemBackground).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(vehicle.status.color.opacity(0.15), lineWidth: 1)
        )
    }

    private func fetchVehicles() {
        isLoading = true
        errorMessage = nil
        statusFollowUpError = nil

        var merged: [String: ManagedVehicle] = [:]
        var loadedPendingStatusFollowUps: [RawReportDocument] = []
        var pendingFollowUpError: Error?
        for group in secComVehicleGroups {
            for plate in group.plates {
                let id = ManagedVehicle.identifier(for: plate)
                merged[id] = ManagedVehicle(
                    id: id,
                    plate: id,
                    carType: group.groupName,
                    status: .operational,
                    statusNotes: "",
                    updatedBy: "",
                    updatedAt: nil
                )
            }
        }

        let dispatchGroup = DispatchGroup()
        let database = Firestore.firestore()
        var firstError: Error?

        dispatchGroup.enter()
        database.collection("vehicles").getDocuments { snapshot, error in
            DispatchQueue.main.async {
                if let error { firstError = firstError ?? error }
                for document in snapshot?.documents ?? [] {
                    let data = document.data()
                    let plate = ManagedVehicle.identifier(
                        for: data["plate"] as? String ?? document.documentID
                    )
                    let existing = merged[plate]
                    merged[plate] = ManagedVehicle(
                        id: plate,
                        plate: plate,
                        carType: data["carType"] as? String ?? existing?.carType ?? "Unknown vehicle type",
                        status: VehicleOperationalStatus(firestoreValue: data["operationalStatus"]),
                        statusNotes: data["statusNotes"] as? String ?? "",
                        updatedBy: data["statusUpdatedByName"] as? String ?? "",
                        updatedAt: (data["statusUpdatedAt"] as? Timestamp)?.dateValue()
                    )
                }
                dispatchGroup.leave()
            }
        }

        loadReportVehicles(
            database: database,
            dispatchGroup: dispatchGroup,
            collection: "reports",
            plateField: "plate",
            merged: { plate, carType in
                mergeReportVehicle(plate: plate, carType: carType, into: &merged)
            },
            captureError: { firstError = firstError ?? $0 }
        )
        loadReportVehicles(
            database: database,
            dispatchGroup: dispatchGroup,
            collection: "seccom_checklists",
            plateField: "plate",
            merged: { plate, carType in
                mergeReportVehicle(plate: plate, carType: carType, into: &merged)
            },
            captureError: { firstError = firstError ?? $0 }
        )
        loadReportVehicles(
            database: database,
            dispatchGroup: dispatchGroup,
            collection: "fuel_refuel_reports",
            plateField: "vehicleNumber",
            merged: { plate, carType in
                mergeReportVehicle(plate: plate, carType: carType, into: &merged)
            },
            captureError: { firstError = firstError ?? $0 }
        )

        dispatchGroup.enter()
        database.collection("reports")
            .whereField("vehicleStatusFollowUpStatus", isEqualTo: "pending")
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    if let error { pendingFollowUpError = error }
                    loadedPendingStatusFollowUps = (snapshot?.documents ?? []).compactMap { document in
                        makeStatusFollowUpReport(
                            documentID: document.documentID,
                            data: document.data()
                        )
                    }
                    dispatchGroup.leave()
                }
            }

        dispatchGroup.notify(queue: .main) {
            isLoading = false
            pendingStatusFollowUps = loadedPendingStatusFollowUps.sorted {
                ($0.entry.createdAt ?? .distantPast) > ($1.entry.createdAt ?? .distantPast)
            }
            statusFollowUpError = pendingFollowUpError.map {
                "Could not load pending status follow-ups: \($0.localizedDescription)"
            }
            vehicles = merged.values.sorted { $0.plate.localizedStandardCompare($1.plate) == .orderedAscending }
            if vehicles.isEmpty, let firstError {
                errorMessage = "Could not load vehicles: \(firstError.localizedDescription)"
            }
        }
    }

    private func loadReportVehicles(
        database: Firestore,
        dispatchGroup: DispatchGroup,
        collection: String,
        plateField: String,
        merged: @escaping (String, String) -> Void,
        captureError: @escaping (Error) -> Void
    ) {
        dispatchGroup.enter()
        database.collection(collection).getDocuments { snapshot, error in
            DispatchQueue.main.async {
                if let error { captureError(error) }
                for document in snapshot?.documents ?? [] {
                    let data = document.data()
                    guard let plate = data[plateField] as? String else { continue }
                    merged(plate, data["carType"] as? String ?? "Unknown vehicle type")
                }
                dispatchGroup.leave()
            }
        }
    }

    private func mergeReportVehicle(
        plate: String,
        carType: String,
        into vehicles: inout [String: ManagedVehicle]
    ) {
        let id = ManagedVehicle.identifier(for: plate)
        guard !id.isEmpty else { return }
        if vehicles[id] == nil {
            vehicles[id] = ManagedVehicle(
                id: id,
                plate: id,
                carType: carType,
                status: .operational,
                statusNotes: "",
                updatedBy: "",
                updatedAt: nil
            )
        } else if vehicles[id]?.carType == "Unknown vehicle type", !carType.isEmpty {
            vehicles[id]?.carType = carType
        }
    }

    private func makeStatusFollowUpReport(
        documentID: String,
        data: [String: Any]
    ) -> RawReportDocument? {
        guard let reportNo = data["reportNo"] as? String,
              let plate = data["plate"] as? String else {
            return nil
        }

        let entry = ReportEntry(
            id: documentID,
            reportNo: reportNo,
            plate: plate,
            carType: data["carType"] as? String ?? "Unknown vehicle type",
            generatedBy: data["generatedBy"] as? String ?? "Not recorded",
            detectionCount: data["detectionCount"] as? Int ?? 0,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
            barcodeId: data["barcodeId"] as? String ?? documentID,
            pdfFileName: data["pdfFileName"] as? String,
            pdfBase64: data["pdfBase64"] as? String,
            pdfStoragePath: data["pdfStoragePath"] as? String
        )
        return RawReportDocument(id: documentID, entry: entry, raw: data)
    }
}

private struct VehicleManagementDetailView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @State private var vehicle: ManagedVehicle
    @State private var selectedStatus: VehicleOperationalStatus
    @State private var statusNotes: String
    @State private var isSavingStatus = false
    @State private var statusMessage: String?
    @State private var statusError: String?

    @State private var history: [VehicleHistoryItem] = []
    @State private var isLoadingHistory = false
    @State private var historyError: String?
    @State private var selectedHistory: VehicleHistoryItem?
    @State private var selectedPDFURL: URL?

    @State private var baselineSnapshots: [VehicleBaselineSnapshot] = []
    @State private var isLoadingBaseline = false
    @State private var baselineError: String?
    @State private var selectedBaseline: VehicleBaselineSnapshot?

    let onVehicleUpdated: () -> Void

    init(vehicle: ManagedVehicle, onVehicleUpdated: @escaping () -> Void) {
        _vehicle = State(initialValue: vehicle)
        _selectedStatus = State(initialValue: vehicle.status)
        _statusNotes = State(initialValue: vehicle.statusNotes)
        self.onVehicleUpdated = onVehicleUpdated
    }

    var body: some View {
        ZStack {
            SubtleHTXBackground().ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    vehicleHeader
                    statusCard
                    baselineCard
                    historyCard
                }
                .padding(.vertical, 16)
            }
        }
        .navigationTitle(vehicle.plate)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchHistory()
            loadBaseline()
        }
        .sheet(item: $selectedHistory) { item in
            if let report = item.report {
                switch item.category {
                case .np299:
                    ReportDetailSheet(
                        document: report,
                        onViewPDF: { url in
                            selectedHistory = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                selectedPDFURL = url
                            }
                        },
                        onVehicleStatusFollowUpResolved: onVehicleUpdated
                    )
                case .checklist:
                    SecComDetailSheet(doc: report)
                case .refuel:
                    FuelDetailSheet(doc: report)
                case .status:
                    EmptyView()
                }
            }
        }
        .sheet(item: $selectedPDFURL) { url in
            ReportPDFPreviewView(url: url)
        }
        .fullScreenCover(item: $selectedBaseline) { snapshot in
            VehicleBaselinePreview(snapshot: snapshot)
        }
    }

    private var vehicleHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "car.side.fill")
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 54, height: 54)
                .background(HTXTheme.primaryPurple)
                .clipShape(RoundedRectangle(cornerRadius: 15))

            VStack(alignment: .leading, spacing: 4) {
                Text(vehicle.plate)
                    .font(.title2.weight(.bold))
                Text(vehicle.carType)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Label(vehicle.status.shortTitle, systemImage: vehicle.status.icon)
                .font(.caption.weight(.semibold))
                .foregroundColor(vehicle.status.color)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(vehicle.status.color.opacity(0.10))
                .clipShape(Capsule())
        }
        .padding(16)
        .background(Color(.systemBackground).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var statusCard: some View {
        managementCard(title: "Vehicle Status", icon: "car.badge.gearshape.fill") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Current operational status")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                Menu {
                    ForEach(VehicleOperationalStatus.allCases) { status in
                        Button {
                            selectedStatus = status
                            statusMessage = nil
                            statusError = nil
                        } label: {
                            Label(status.title, systemImage: status.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selectedStatus.icon)
                            .foregroundColor(selectedStatus.color)
                        Text(selectedStatus.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(selectedStatus.color.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selectedStatus.color.opacity(0.20), lineWidth: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Status Notes (Optional)")
                        .font(.subheadline.weight(.semibold))
                    TextEditor(text: $statusNotes)
                        .frame(minHeight: 92)
                        .scrollContentBackground(.hidden)
                        .padding(9)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                        )
                }

                if let statusError {
                    Label(statusError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.red)
                }

                if let statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.green)
                }

                HStack {
                    Spacer()
                    Button(action: saveStatus) {
                        HStack(spacing: 8) {
                            if isSavingStatus {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text(isSavingStatus ? "Updating…" : "Update Vehicle Status")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .frame(height: 42)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HTXTheme.primaryPurple)
                    .disabled(isSavingStatus || !hasStatusChanges)
                    Spacer()
                }

                if !vehicle.updatedBy.isEmpty || vehicle.updatedAt != nil {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        if !vehicle.updatedBy.isEmpty {
                            Text("Last updated by \(vehicle.updatedBy)")
                        }
                        if let updatedAt = vehicle.updatedAt {
                            Text(updatedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var baselineCard: some View {
        managementCard(title: "Current Damage Baseline", icon: "rectangle.stack.badge.plus") {
            if isLoadingBaseline {
                HStack(spacing: 10) {
                    ProgressView().tint(HTXTheme.primaryPurple)
                    Text("Loading stored baseline images…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let baselineError {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Baseline images are unavailable")
                        .font(.subheadline.weight(.semibold))
                    Text(baselineError)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Retry", action: loadBaseline)
                        .font(.subheadline.weight(.semibold))
                }
            } else if baselineSnapshots.isEmpty {
                Text("No confirmed damage baseline has been saved for this vehicle.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("These are the latest confirmed damage locations used by the comparison system.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    ForEach(baselineSnapshots) { snapshot in
                        Button {
                            selectedBaseline = snapshot
                        } label: {
                            VehicleBaselineCard(snapshot: snapshot)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var historyCard: some View {
        managementCard(title: "Vehicle History", icon: "clock.arrow.circlepath") {
            if isLoadingHistory {
                HStack(spacing: 10) {
                    ProgressView().tint(HTXTheme.primaryPurple)
                    Text("Loading vehicle history…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let historyError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(historyError)
                        .font(.subheadline)
                        .foregroundColor(.red)
                    Button("Retry", action: fetchHistory)
                        .font(.subheadline.weight(.semibold))
                }
            } else if history.isEmpty {
                Text("No reports or status changes have been recorded for this vehicle.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(history.enumerated()), id: \.element.id) { index, item in
                        Button {
                            if item.report != nil { selectedHistory = item }
                        } label: {
                            historyRow(item)
                        }
                        .buttonStyle(.plain)
                        .disabled(item.report == nil)

                        if index < history.count - 1 {
                            Divider().padding(.leading, 54)
                        }
                    }
                }
            }
        }
    }

    private func historyRow(_ item: VehicleHistoryItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.category.icon)
                .font(.subheadline)
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(item.category.color)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundColor(item.category.color)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Text(item.dateText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            if item.report != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.top, 5)
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var hasStatusChanges: Bool {
        selectedStatus != vehicle.status
            || statusNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                != vehicle.statusNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveStatus() {
        guard !isSavingStatus, hasStatusChanges else { return }
        isSavingStatus = true
        statusError = nil
        statusMessage = nil

        let database = Firestore.firestore()
        let vehicleReference = database.collection("vehicles").document(vehicle.id)
        let historyReference = vehicleReference.collection("statusHistory").document()
        let cleanedNotes = statusNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let changedBy = auth.currentUsername.isEmpty ? auth.currentEmail : auth.currentUsername
        let payload: [String: Any] = [
            "plate": vehicle.plate,
            "carType": vehicle.carType,
            "operationalStatus": selectedStatus.rawValue,
            "statusNotes": cleanedNotes,
            "statusUpdatedByUid": auth.user?.uid ?? "",
            "statusUpdatedByName": changedBy,
            "statusUpdatedAt": FieldValue.serverTimestamp()
        ]
        let historyPayload: [String: Any] = [
            "previousStatus": vehicle.status.rawValue,
            "newStatus": selectedStatus.rawValue,
            "notes": cleanedNotes,
            "changedByUid": auth.user?.uid ?? "",
            "changedByName": changedBy,
            "changedAt": FieldValue.serverTimestamp()
        ]

        let batch = database.batch()
        batch.setData(payload, forDocument: vehicleReference, merge: true)
        batch.setData(historyPayload, forDocument: historyReference)
        batch.commit { error in
            DispatchQueue.main.async {
                isSavingStatus = false
                if let error {
                    statusError = "Could not update vehicle status: \(error.localizedDescription)"
                    return
                }

                vehicle.status = selectedStatus
                vehicle.statusNotes = cleanedNotes
                vehicle.updatedBy = changedBy
                vehicle.updatedAt = now
                statusMessage = "Vehicle status updated."
                onVehicleUpdated()
                fetchHistory()
            }
        }
    }

    private func fetchHistory() {
        isLoadingHistory = true
        historyError = nil

        let database = Firestore.firestore()
        let group = DispatchGroup()
        var loaded: [VehicleHistoryItem] = []
        var firstError: Error?

        fetchReportHistory(
            database: database,
            group: group,
            collection: "reports",
            plateField: "plate",
            category: .np299,
            loaded: { loaded.append(contentsOf: $0) },
            failed: { firstError = firstError ?? $0 }
        )
        fetchReportHistory(
            database: database,
            group: group,
            collection: "seccom_checklists",
            plateField: "plate",
            category: .checklist,
            loaded: { loaded.append(contentsOf: $0) },
            failed: { firstError = firstError ?? $0 }
        )
        fetchReportHistory(
            database: database,
            group: group,
            collection: "fuel_refuel_reports",
            plateField: "vehicleNumber",
            category: .refuel,
            loaded: { loaded.append(contentsOf: $0) },
            failed: { firstError = firstError ?? $0 }
        )

        group.enter()
        database.collection("vehicles")
            .document(vehicle.id)
            .collection("statusHistory")
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    if let error { firstError = firstError ?? error }
                    let changes = (snapshot?.documents ?? []).map { document in
                        let data = document.data()
                        let status = VehicleOperationalStatus(firestoreValue: data["newStatus"])
                        let changedBy = data["changedByName"] as? String ?? "Administrator"
                        let notes = (data["notes"] as? String ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let reportNo = (data["reportNo"] as? String ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let detail = [
                            reportNo.isEmpty ? nil : "Linked to NP299 \(reportNo)",
                            notes.isEmpty ? nil : notes
                        ]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                        return VehicleHistoryItem(
                            id: "status-\(document.documentID)",
                            category: .status,
                            title: status.title,
                            subtitle: "Updated by \(changedBy)",
                            detail: detail,
                            createdAt: (data["changedAt"] as? Timestamp)?.dateValue(),
                            report: nil
                        )
                    }
                    loaded.append(contentsOf: changes)
                    group.leave()
                }
            }

        group.notify(queue: .main) {
            isLoadingHistory = false
            history = loaded.sorted {
                ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
            if history.isEmpty, let firstError {
                historyError = "Could not load vehicle history: \(firstError.localizedDescription)"
            }
        }
    }

    private func fetchReportHistory(
        database: Firestore,
        group: DispatchGroup,
        collection: String,
        plateField: String,
        category: VehicleHistoryCategory,
        loaded: @escaping ([VehicleHistoryItem]) -> Void,
        failed: @escaping (Error) -> Void
    ) {
        group.enter()
        database.collection(collection)
            .whereField(plateField, isEqualTo: vehicle.plate)
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    defer { group.leave() }
                    if let error {
                        failed(error)
                        return
                    }

                    let items = (snapshot?.documents ?? []).compactMap { document -> VehicleHistoryItem? in
                        let data = document.data()
                        guard let rawReport = makeRawReport(
                            collection: collection,
                            documentID: document.documentID,
                            data: data
                        ) else { return nil }

                        let detail: String
                        switch category {
                        case .np299:
                            detail = "\(rawReport.entry.detectionCount) recorded damage case\(rawReport.entry.detectionCount == 1 ? "" : "s")"
                        case .checklist:
                            detail = ChecklistAdminReviewStatus(firestoreData: data).title
                        case .refuel:
                            detail = FuelFollowUpStatus(
                                firestoreValue: data["adminFollowUpStatus"]
                            ).title
                        case .status:
                            detail = ""
                        }

                        return VehicleHistoryItem(
                            id: "\(category.rawValue)-\(document.documentID)",
                            category: category,
                            title: category.title,
                            subtitle: rawReport.entry.reportNo,
                            detail: detail,
                            createdAt: rawReport.entry.createdAt,
                            report: rawReport
                        )
                    }
                    loaded(items)
                }
            }
    }

    private func makeRawReport(
        collection: String,
        documentID: String,
        data: [String: Any]
    ) -> RawReportDocument? {
        guard let reportNo = data["reportNo"] as? String else { return nil }
        let plate = collection == "fuel_refuel_reports"
            ? (data["vehicleNumber"] as? String ?? data["plate"] as? String)
            : data["plate"] as? String
        guard let plate else { return nil }

        let entry = ReportEntry(
            id: documentID,
            reportNo: reportNo,
            plate: plate,
            carType: data["carType"] as? String ?? vehicle.carType,
            generatedBy: data["generatedBy"] as? String
                ?? data["driverName"] as? String
                ?? "-",
            detectionCount: data["detectionCount"] as? Int ?? 0,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue(),
            barcodeId: data["barcodeId"] as? String ?? documentID,
            pdfFileName: data["pdfFileName"] as? String,
            pdfBase64: data["pdfBase64"] as? String,
            pdfStoragePath: data["pdfStoragePath"] as? String
        )
        return RawReportDocument(id: documentID, entry: entry, raw: data)
    }

    private func loadBaseline() {
        isLoadingBaseline = true
        baselineError = nil

        Task {
            do {
                let response = try await DamageAnalysisService.shared.getBaseline(plate: vehicle.plate)
                let snapshots = makeBaselineSnapshots(from: response)
                await MainActor.run {
                    baselineSnapshots = snapshots
                    isLoadingBaseline = false
                }
            } catch {
                await MainActor.run {
                    baselineSnapshots = []
                    isLoadingBaseline = false
                    baselineError = error.localizedDescription
                }
            }
        }
    }

    private func makeBaselineSnapshots(from response: BaselineLookupResponse) -> [VehicleBaselineSnapshot] {
        var snapshots: [VehicleBaselineSnapshot] = []
        let sortedBaselines = response.baselines.sorted {
            (Int($0.key) ?? 0) < (Int($1.key) ?? 0)
        }

        for (key, regions) in sortedBaselines {
            let angleIndex = Int(key) ?? 0
            let angleName = scanAngles.indices.contains(angleIndex)
                ? scanAngles[angleIndex].label
                : "Angle \(angleIndex + 1)"

            for (index, region) in regions.enumerated() {
                let fullImage = imageFromBase64(region.referenceImageBase64)
                let cropImage = imageFromBase64(region.referenceCropBase64)
                guard let image = fullImage ?? cropImage else { continue }

                let normalizedBox = baselineBox(
                    for: region,
                    fullImage: fullImage,
                    cropImage: cropImage
                )

                snapshots.append(
                    VehicleBaselineSnapshot(
                        id: "\(angleIndex)-\(index)",
                        angleName: angleName,
                        damageType: (region.label ?? "Damage")
                            .replacingOccurrences(of: "_", with: " ")
                            .capitalized,
                        image: image,
                        normalizedBox: normalizedBox
                    )
                )
            }
        }

        return snapshots
    }

    private func baselineBox(
        for region: BaselineRegion,
        fullImage: UIImage?,
        cropImage: UIImage?
    ) -> CGRect? {
        if let fullImage,
           let x1 = region.x1,
           let y1 = region.y1,
           let x2 = region.x2,
           let y2 = region.y2 {
            let width = CGFloat(
                region.imageWidth.flatMap { $0 > 0 ? $0 : nil }
                    ?? max(1, Int(fullImage.size.width.rounded()))
            )
            let height = CGFloat(
                region.imageHeight.flatMap { $0 > 0 ? $0 : nil }
                    ?? max(1, Int(fullImage.size.height.rounded()))
            )
            return normalizedBox(
                x1: CGFloat(x1),
                y1: CGFloat(y1),
                x2: CGFloat(x2),
                y2: CGFloat(y2),
                width: width,
                height: height
            )
        }

        if let cropImage,
           let x1 = region.templateX1,
           let y1 = region.templateY1,
           let x2 = region.templateX2,
           let y2 = region.templateY2 {
            return normalizedBox(
                x1: CGFloat(x1),
                y1: CGFloat(y1),
                x2: CGFloat(x2),
                y2: CGFloat(y2),
                width: max(1, cropImage.size.width),
                height: max(1, cropImage.size.height)
            )
        }

        return nil
    }

    private func normalizedBox(
        x1: CGFloat,
        y1: CGFloat,
        x2: CGFloat,
        y2: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> CGRect? {
        guard width > 0, height > 0, x2 > x1, y2 > y1 else { return nil }

        let left = min(max(0, x1 / width), 1)
        let top = min(max(0, y1 / height), 1)
        let right = min(max(0, x2 / width), 1)
        let bottom = min(max(0, y2 / height), 1)
        guard right > left, bottom > top else { return nil }

        return CGRect(
            x: left,
            y: top,
            width: right - left,
            height: bottom - top
        )
    }

    private func imageFromBase64(_ value: String?) -> UIImage? {
        guard var value, !value.isEmpty else { return nil }
        if let comma = value.firstIndex(of: ","), value[..<comma].contains("base64") {
            value = String(value[value.index(after: comma)...])
        }
        guard let data = Data(base64Encoded: value) else { return nil }
        return UIImage(data: data)
    }

    @ViewBuilder
    private func managementCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(HTXTheme.primaryPurple)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.systemBackground).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(HTXTheme.primaryPurple.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

private struct VehicleBaselineCard: View {
    let snapshot: VehicleBaselineSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VehicleBaselineImage(snapshot: snapshot)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 11))

            Text(snapshot.damageType)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
            Text(snapshot.angleName)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }
}

private struct VehicleBaselineImage: View {
    let snapshot: VehicleBaselineSnapshot

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.04)
                Image(uiImage: snapshot.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)

                if let box = snapshot.normalizedBox {
                    let rect = displayRect(
                        normalizedBox: box,
                        imageSize: snapshot.image.size,
                        containerSize: geometry.size
                    )
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.orange.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.orange, lineWidth: 3)
                        )
                        .frame(width: max(2, rect.width), height: max(2, rect.height))
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
    }

    private func displayRect(
        normalizedBox: CGRect,
        imageSize: CGSize,
        containerSize: CGSize
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let displayedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (containerSize.width - displayedSize.width) / 2,
            y: (containerSize.height - displayedSize.height) / 2
        )
        return CGRect(
            x: origin.x + normalizedBox.minX * displayedSize.width,
            y: origin.y + normalizedBox.minY * displayedSize.height,
            width: normalizedBox.width * displayedSize.width,
            height: normalizedBox.height * displayedSize.height
        )
    }
}

private struct VehicleBaselinePreview: View {
    let snapshot: VehicleBaselineSnapshot
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

            VehicleBaselineImage(snapshot: snapshot)
                .padding()
                .scaleEffect(scale)
                .offset(offset)
                .contentShape(Rectangle())
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
                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.damageType)
                            .font(.headline)
                        Text(snapshot.angleName)
                            .font(.caption)
                    }
                    .foregroundColor(.white)

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
