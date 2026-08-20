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
    var onResolved: () -> Void = {}

    @EnvironmentObject private var auth: AuthViewModel

    @State private var currentStatus: VehicleOperationalStatus = .operational
    @State private var currentNotes = ""
    @State private var selectedStatus: VehicleOperationalStatus = .operational
    @State private var statusNotes = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var reportIsReady = false
    @State private var followUpStatus = "pending"
    @State private var followUpResolution = ""
    @State private var followedUpBy = ""
    @State private var followedUpAt: Date?
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

    private var isResolved: Bool {
        followUpStatus == "completed"
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
                    Text("Review the vehicle after this NP299 report was filed.")
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
            } else if !reportIsReady {
                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        "The NP299 report is still being saved. Retry once the report is available.",
                        systemImage: "clock.badge.exclamationmark"
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                    Button("Retry", action: reloadStatus)
                        .buttonStyle(.bordered)
                        .tint(HTXTheme.primaryPurple)
                }
            } else if isResolved {
                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        followUpResolution == "no_change"
                            ? "No change to vehicle status"
                            : "Vehicle status updated to \(currentStatus.title)",
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.green)

                    if !followedUpBy.isEmpty {
                        Text("Completed by \(followedUpBy)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let followedUpAt {
                        Text(followedUpAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Text("Current status: \(currentStatus.title)")
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

                HStack(spacing: 10) {
                    Button(action: resolveWithoutStatusChange) {
                        Text("No Status Change")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(.bordered)
                    .tint(HTXTheme.primaryPurple)
                    .disabled(isSaving)

                    Button(action: saveStatus) {
                        HStack(spacing: 7) {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text(isSaving ? "Saving…" : "Update Status")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
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
            let database = Firestore.firestore()
            let vehicleSnapshot = try await database
                .collection("vehicles")
                .document(vehicleID)
                .getDocument()
            let reportSnapshot = try await database
                .collection("reports")
                .document(reportID)
                .getDocument()
            let data = vehicleSnapshot.data() ?? [:]
            let reportData = reportSnapshot.data() ?? [:]
            let loadedStatus = VehicleOperationalStatus(
                firestoreValue: data["operationalStatus"]
            )
            let loadedNotes = data["statusNotes"] as? String ?? ""

            currentStatus = loadedStatus
            selectedStatus = loadedStatus
            currentNotes = loadedNotes
            statusNotes = loadedNotes
            reportIsReady = reportSnapshot.exists
            followUpStatus = reportData["vehicleStatusFollowUpStatus"] as? String ?? "pending"
            followUpResolution = reportData["vehicleStatusFollowUpResolution"] as? String ?? ""
            followedUpBy = reportData["vehicleStatusFollowedUpByName"] as? String ?? ""
            followedUpAt = (reportData["vehicleStatusFollowedUpAt"] as? Timestamp)?.dateValue()
            isLoading = false
        } catch {
            isLoading = false
            statusError = "Could not load vehicle status: \(error.localizedDescription)"
        }
    }

    private func reloadStatus() {
        Task { await loadStatus() }
    }

    private func saveStatus() {
        guard auth.isAdmin, !isSaving, hasChanges else { return }

        isSaving = true
        statusError = nil
        statusMessage = nil

        let database = Firestore.firestore()
        let vehicleReference = database.collection("vehicles").document(vehicleID)
        let historyReference = vehicleReference.collection("statusHistory").document()
        let reportReference = database.collection("reports").document(reportID)
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

        let reportFollowUpPayload: [String: Any] = [
            "vehicleStatusFollowUpStatus": "completed",
            "vehicleStatusFollowUpResolution": "status_updated",
            "vehicleStatusFollowUpPreviousStatus": previousStatus.rawValue,
            "vehicleStatusFollowUpNewStatus": selectedStatus.rawValue,
            "vehicleStatusFollowUpNotes": cleanedNotes,
            "vehicleStatusFollowedUpByUid": auth.user?.uid ?? "",
            "vehicleStatusFollowedUpByName": changedBy,
            "vehicleStatusFollowedUpAt": FieldValue.serverTimestamp()
        ]

        let batch = database.batch()
        batch.setData(vehiclePayload, forDocument: vehicleReference, merge: true)
        batch.setData(historyPayload, forDocument: historyReference)
        batch.setData(reportFollowUpPayload, forDocument: reportReference, merge: true)
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
                followUpStatus = "completed"
                followUpResolution = "status_updated"
                followedUpBy = changedBy
                followedUpAt = Date()
                statusMessage = "Vehicle status updated and linked to \(reportNo)."
                onResolved()
            }
        }
    }

    private func resolveWithoutStatusChange() {
        guard auth.isAdmin, !isSaving, reportIsReady else { return }

        isSaving = true
        statusError = nil
        statusMessage = nil

        let changedBy = auth.currentUsername.isEmpty ? auth.currentEmail : auth.currentUsername
        let cleanedNotes = statusNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: [String: Any] = [
            "vehicleStatusFollowUpStatus": "completed",
            "vehicleStatusFollowUpResolution": "no_change",
            "vehicleStatusFollowUpPreviousStatus": currentStatus.rawValue,
            "vehicleStatusFollowUpNewStatus": currentStatus.rawValue,
            "vehicleStatusFollowUpNotes": cleanedNotes,
            "vehicleStatusFollowedUpByUid": auth.user?.uid ?? "",
            "vehicleStatusFollowedUpByName": changedBy,
            "vehicleStatusFollowedUpAt": FieldValue.serverTimestamp()
        ]

        Firestore.firestore()
            .collection("reports")
            .document(reportID)
            .setData(payload, merge: true) { error in
                DispatchQueue.main.async {
                    isSaving = false
                    if let error {
                        statusError = "Could not complete vehicle follow-up: \(error.localizedDescription)"
                        return
                    }

                    followUpStatus = "completed"
                    followUpResolution = "no_change"
                    followedUpBy = changedBy
                    followedUpAt = Date()
                    statusMessage = "Vehicle status follow-up completed with no change."
                    onResolved()
                }
            }
    }
}
