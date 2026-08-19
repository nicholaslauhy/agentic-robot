import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// Optional administrator follow-up shown only after an NP299 report has been generated.
/// It writes to the same vehicle document and status-history collection used by
/// Vehicle Management, while linking the change back to the report that prompted it.
struct PostReportVehicleStatusView: View {
    let plate: String
    let carType: String
    let reportID: String
    let reportNo: String
    let sourceChecklistID: String?

    @EnvironmentObject private var auth: AuthViewModel

    @State private var currentStatus: VehicleOperationalStatus = .operational
    @State private var currentNotes = ""
    @State private var selectedStatus: VehicleOperationalStatus = .operational
    @State private var statusNotes = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var statusMessage: String?
    @State private var statusError: String?

    private var vehicleID: String {
        ManagedVehicle.identifier(for: plate)
    }

    private var hasChanges: Bool {
        selectedStatus != currentStatus
            || statusNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                != currentNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "car.badge.gearshape.fill")
                    .foregroundColor(HTXTheme.primaryPurple)
                    .frame(width: 36, height: 36)
                    .background(HTXTheme.primaryPurple.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Vehicle Status Follow-up")
                        .font(.headline)
                    Text("Optional — update the vehicle after filing this NP299 report.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if isLoading {
                HStack(spacing: 9) {
                    ProgressView().tint(HTXTheme.primaryPurple)
                    Text("Loading current vehicle status…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
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

                TextField("Status notes (optional)", text: $statusNotes, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(11)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                    )

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
                        HStack(spacing: 7) {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text(isSaving ? "Updating…" : "Update Status")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(HTXTheme.primaryPurple)
                    .disabled(isSaving || !hasChanges)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(HTXTheme.primaryPurple.opacity(0.14), lineWidth: 1)
        )
        .task(id: vehicleID) {
            await loadStatus()
        }
    }

    @MainActor
    private func loadStatus() async {
        guard auth.isAdmin else {
            isLoading = false
            return
        }

        isLoading = true
        statusError = nil

        do {
            let snapshot = try await Firestore.firestore()
                .collection("vehicles")
                .document(vehicleID)
                .getDocument()
            let data = snapshot.data() ?? [:]
            let loadedStatus = VehicleOperationalStatus(
                firestoreValue: data["operationalStatus"]
            )
            let loadedNotes = data["statusNotes"] as? String ?? ""

            currentStatus = loadedStatus
            selectedStatus = loadedStatus
            currentNotes = loadedNotes
            statusNotes = loadedNotes
            isLoading = false
        } catch {
            isLoading = false
            statusError = "Could not load vehicle status: \(error.localizedDescription)"
        }
    }

    private func saveStatus() {
        guard auth.isAdmin, !isSaving, hasChanges else { return }

        isSaving = true
        statusError = nil
        statusMessage = nil

        let database = Firestore.firestore()
        let vehicleReference = database.collection("vehicles").document(vehicleID)
        let historyReference = vehicleReference.collection("statusHistory").document()
        let cleanedNotes = statusNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let changedBy = auth.currentUsername.isEmpty ? auth.currentEmail : auth.currentUsername
        let previousStatus = currentStatus

        var vehiclePayload: [String: Any] = [
            "plate": plate.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            "carType": carType,
            "operationalStatus": selectedStatus.rawValue,
            "statusNotes": cleanedNotes,
            "statusUpdatedByUid": auth.user?.uid ?? "",
            "statusUpdatedByName": changedBy,
            "statusUpdatedAt": FieldValue.serverTimestamp(),
            "lastNP299ReportId": reportID,
            "lastNP299ReportNo": reportNo
        ]

        var historyPayload: [String: Any] = [
            "previousStatus": previousStatus.rawValue,
            "newStatus": selectedStatus.rawValue,
            "notes": cleanedNotes,
            "changedByUid": auth.user?.uid ?? "",
            "changedByName": changedBy,
            "changedAt": FieldValue.serverTimestamp(),
            "source": sourceChecklistID == nil ? "np299_report" : "checklist_np299",
            "reportId": reportID,
            "reportNo": reportNo
        ]

        if let sourceChecklistID, !sourceChecklistID.isEmpty {
            vehiclePayload["lastSourceChecklistId"] = sourceChecklistID
            historyPayload["sourceChecklistId"] = sourceChecklistID
        }

        let batch = database.batch()
        batch.setData(vehiclePayload, forDocument: vehicleReference, merge: true)
        batch.setData(historyPayload, forDocument: historyReference)
        batch.commit { error in
            DispatchQueue.main.async {
                isSaving = false
                if let error {
                    statusError = "Could not update vehicle status: \(error.localizedDescription)"
                    return
                }

                currentStatus = selectedStatus
                currentNotes = cleanedNotes
                statusNotes = cleanedNotes
                statusMessage = "Vehicle status updated and linked to \(reportNo)."
            }
        }
    }
}
