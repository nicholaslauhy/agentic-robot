import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import FirebaseFirestore
import FirebaseAuth

struct FuelRefuelView: View {

    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    // Fields
    @State private var driverName: String = ""
    @State private var refuelDate: Date = Date()
    @State private var refuelTime: Date = Date()
    @State private var vehicleNumber: String = ""
    @State private var odometer: String = ""
    @State private var usedMastercard: Bool? = nil

    // Vehicle picker (reuse same groups)
    @State private var selectedGroup: VehicleGroup? = nil
    @State private var selectedPlate: String = ""
    @State private var useOtherVehicle: Bool = false
    @State private var otherPlate: String = ""
    @State private var otherCarType: String = ""
    @State private var showVehiclePicker = false

    // Fuel receipt
    @State private var receiptImage: UIImage? = nil
    @State private var showReceiptOptions = false
    @State private var showReceiptCamera = false
    @State private var showReceiptPicker = false
    @State private var showReceiptFileImporter = false
    @State private var selectedReceiptItem: PhotosPickerItem?

    // Submit state
    @State private var isSubmitting = false
    @State private var submitError: String? = nil
    @State private var submitSuccess = false
    @State private var showValidationError = false

    private var effectiveVehicleNumber: String {
        useOtherVehicle ? otherPlate.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        : selectedPlate
    }

    private var effectiveCarType: String {
        useOtherVehicle ? otherCarType.trimmingCharacters(in: .whitespacesAndNewlines)
                        : (selectedGroup?.groupName ?? "")
    }

    private var dateString: String {
        let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"
        return f.string(from: refuelDate)
    }

    private var timeString: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: refuelTime)
    }

    var body: some View {
        ZStack {
            SubtleHTXBackground()

            ScrollView {
                VStack(spacing: 20) {

                    // Basic info
                    sectionCard(title: "Driver Information", icon: "person.fill") {
                        formRow(label: "Name") {
                            TextField("Full name", text: $driverName)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                        }
                    }

                    // Refuel details
                    sectionCard(title: "Refuel Details", icon: "fuelpump.fill") {
                        formRow(label: "Date of Refuel") {
                            DatePicker("", selection: $refuelDate, displayedComponents: .date)
                                .labelsHidden()
                                .tint(HTXTheme.fuelOrange)
                        }
                        Divider()
                        formRow(label: "Time of Refuel") {
                            DatePicker("", selection: $refuelTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .tint(HTXTheme.fuelOrange)
                        }
                        Divider()
                        // Vehicle number (dropdown)
                        Button {
                            showVehiclePicker = true
                        } label: {
                            HStack {
                                Text("Vehicle Number")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(useOtherVehicle ? "Other" : (selectedPlate.isEmpty ? "Select…" : selectedPlate))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(selectedPlate.isEmpty && !useOtherVehicle ? .secondary : HTXTheme.fuelOrange)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)

                        if useOtherVehicle {
                            Divider()
                            formRow(label: "Vehicle Number") {
                                TextField("e.g. QX909B", text: $otherPlate)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                                    .multilineTextAlignment(.trailing)
                            }
                            Divider()
                            formRow(label: "Vehicle Type") {
                                TextField("e.g. Toyota Camry", text: $otherCarType)
                                    .autocorrectionDisabled()
                                    .multilineTextAlignment(.trailing)
                            }
                        }

                        Divider()
                        formRow(label: "Odometer (km)") {
                            TextField("Reading", text: $odometer)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    // Mastercard
                    sectionCard(title: "Mastercard Usage", icon: "creditcard.fill") {
                        HStack(spacing: 12) {
                            mastercardOption(label: "Yes", value: true)
                            mastercardOption(label: "No",  value: false)
                        }
                    }

                    // Receipt
                    sectionCard(title: "Fuel Receipt", icon: "doc.text.fill") {
                        if let receiptImage {
                            VStack(spacing: 10) {
                                Image(uiImage: receiptImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 220)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                Button {
                                    self.receiptImage = nil
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.red)
                                }
                            }
                        } else {
                            Button {
                                showReceiptOptions = true
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(HTXTheme.fuelOrange)
                                    Text("Attach Receipt")
                                        .foregroundColor(HTXTheme.fuelOrange)
                                        .font(.subheadline.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(HTXTheme.fuelOrange.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if showValidationError {
                        Text("Please fill in all required fields.")
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    if let submitError {
                        Text(submitError)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Button {
                        submitForm()
                    } label: {
                        if isSubmitting {
                            ProgressView().tint(.white)
                                .frame(maxWidth: .infinity).padding()
                        } else {
                            Text("Submit Refuel Report")
                                .font(.headline)
                                .frame(maxWidth: .infinity).padding()
                        }
                    }
                    .background(HTXTheme.fuelOrange)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
                    .disabled(isSubmitting)
                    .padding(.bottom, 30)
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("Fuel Refuel Report")
        .navigationBarTitleDisplayMode(.inline)
        .tint(HTXTheme.fuelOrange)
        // Vehicle picker
        .sheet(isPresented: $showVehiclePicker) {
            VehiclePickerSheet(
                selectedGroup: $selectedGroup,
                selectedPlate: $selectedPlate,
                useOther: $useOtherVehicle
            )
        }
        // Receipt image options
        .confirmationDialog("Attach Receipt", isPresented: $showReceiptOptions, titleVisibility: .visible) {
            Button("Take Photo")            { showReceiptCamera = true }
            Button("Choose from Library")   { showReceiptPicker = true }
            Button("Upload JPG/PNG File")   { showReceiptFileImporter = true }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showReceiptCamera) {
            ImagePicker(sourceType: .camera) { img in receiptImage = img }
        }
        .photosPicker(isPresented: $showReceiptPicker, selection: $selectedReceiptItem, matching: .images)
        .onChange(of: selectedReceiptItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run { receiptImage = img }
                }
                await MainActor.run { selectedReceiptItem = nil }
            }
        }
        .fileImporter(
            isPresented: $showReceiptFileImporter,
            allowedContentTypes: [.jpeg, .png]
        ) { result in
            if case .success(let url) = result {
                if url.startAccessingSecurityScopedResource(),
                   let data = try? Data(contentsOf: url),
                   let img = UIImage(data: data) {
                    receiptImage = img
                }
                url.stopAccessingSecurityScopedResource()
            }
        }
        .alert("Report Submitted", isPresented: $submitSuccess) {
            Button("Done") { dismiss() }
        } message: {
            Text("The fuel refuel report has been saved successfully.")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(HTXTheme.fuelOrange)
            content()
        }
        .padding(16)
        .subtleHTXCard()
        .padding(.horizontal)
    }

    @ViewBuilder
    private func formRow<Trailing: View>(label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
            trailing()
                .font(.subheadline)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func mastercardOption(label: String, value: Bool) -> some View {
        Button {
            usedMastercard = value
        } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(usedMastercard == value ? HTXTheme.fuelOrange : Color(.secondarySystemBackground))
                .foregroundColor(usedMastercard == value ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(usedMastercard == value ? HTXTheme.fuelOrange : HTXTheme.softPurpleBorder, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Submit

    private func submitForm() {
        showValidationError = false
        submitError = nil

        let name = driverName.trimmingCharacters(in: .whitespacesAndNewlines)
        let vehicleNumber = effectiveVehicleNumber

        guard !name.isEmpty,
              !vehicleNumber.isEmpty,
              !odometer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              usedMastercard != nil
        else {
            showValidationError = true
            return
        }

        isSubmitting = true

        let barcodeId = ReportStore.makeNumericBarcodeId()
        let reportNo  = "FUEL/\(dateString.replacingOccurrences(of: "/", with: ""))/\(vehicleNumber)"

        var data: [String: Any] = [
            "reportType":       "fuel_refuel",
            "reportNo":         reportNo,
            "barcodeId":        barcodeId,
            "driverName":       name,
            "refuelDate":       dateString,
            "refuelTime":       timeString,
            "vehicleNumber":    vehicleNumber,
            "carType":          effectiveCarType,
            "odometer":         odometer.trimmingCharacters(in: .whitespacesAndNewlines),
            "usedMastercard":   usedMastercard ?? false,
            "generatedBy":      Auth.auth().currentUser?.email ?? "Unknown",
            "detectionCount":   0,
            "createdAt":        FieldValue.serverTimestamp()
        ]

        if let receiptImage,
           let receiptData = receiptImage.jpegData(compressionQuality: 0.7) {
            data["receiptBase64"] = receiptData.base64EncodedString()
        }

        Firestore.firestore()
            .collection("fuel_refuel_reports")
            .document(barcodeId)
            .setData(data, merge: true) { error in
                DispatchQueue.main.async {
                    isSubmitting = false
                    if let error {
                        submitError = "Failed to save: \(error.localizedDescription)"
                    } else {
                        submitSuccess = true
                    }
                }
            }
    }
}

// MARK: - Theme extension
extension HTXTheme {
    static let fuelOrange = Color(red: 0.80, green: 0.40, blue: 0.00)
}
