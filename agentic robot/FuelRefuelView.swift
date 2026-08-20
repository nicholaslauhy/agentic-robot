import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import FirebaseAuth
import FirebaseFirestore

private enum FuelRefuelField: Hashable {
    case otherVehicleNumber
    case otherVehicleType
    case odometer
    case mastercardNumber
}

struct FuelRefuelView: View {

    var onReportGenerated: () -> Void = {}

    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    // Fields
    @State private var refuelDate: Date = Date()
    @State private var refuelTime: Date = Date()
    @State private var vehicleNumber: String = ""
    @State private var odometer: String = ""
    @State private var usedMastercard: Bool? = nil
    @State private var mastercardNumber: String = ""
    @FocusState private var focusedField: FuelRefuelField?

    // Vehicle picker (reuse same groups)
    @State private var selectedGroup: VehicleGroup? = nil
    @State private var selectedPlate: String = ""
    @State private var useOtherVehicle: Bool = false
    @State private var otherPlate: String = ""
    @State private var otherCarType: String = ""
    @State private var showVehiclePicker = false

    // Fuel receipt
    @State private var receiptImage: UIImage? = nil
    @State private var showReceiptCamera = false
    @State private var showReceiptPicker = false
    @State private var showReceiptFileImporter = false
    @State private var selectedReceiptItem: PhotosPickerItem?

    // Submit state
    @State private var isSubmitting = false
    @State private var submitError: String? = nil
    @State private var submitSuccess = false
    @State private var showValidationError = false
    @State private var showReviewSheet = false

    private var effectiveVehicleNumber: String {
        useOtherVehicle ? otherPlate.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        : selectedPlate
    }

    private var effectiveCarType: String {
        useOtherVehicle ? otherCarType.trimmingCharacters(in: .whitespacesAndNewlines)
                        : (selectedGroup?.groupName ?? "")
    }

    private var driverName: String {
        auth.currentUsername
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
                    Text("* Required field")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal)

                    // Basic info
                    sectionCard(title: "Driver Information", icon: "person.fill") {
                        formRow(label: "Name", required: true) {
                            HStack(spacing: 6) {
                                Text(driverName.isEmpty ? "Username not set" : driverName)
                                    .foregroundColor(driverName.isEmpty ? .orange : .primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    // Refuel details
                    sectionCard(title: "Refuel Details", icon: "fuelpump.fill") {
                        formRow(label: "Date of Refuel", required: true) {
                            DatePicker("", selection: $refuelDate, displayedComponents: .date)
                                .labelsHidden()
                                .tint(HTXTheme.fuelOrange)
                        }
                        Divider()
                        formRow(label: "Time of Refuel", required: true) {
                            DatePicker("", selection: $refuelTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .tint(HTXTheme.fuelOrange)
                        }
                        Divider()
                        // Vehicle number (dropdown)
                        Button {
                            dismissFormKeyboard()
                            DispatchQueue.main.async {
                                showVehiclePicker = true
                            }
                        } label: {
                            HStack {
                                HTXFieldLabel(text: "Vehicle Number", required: true)
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
                            formRow(label: "Vehicle Number", required: true) {
                                TextField("e.g. QX909B", text: $otherPlate)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                                    .multilineTextAlignment(.trailing)
                                    .focused($focusedField, equals: .otherVehicleNumber)
                            }
                            Divider()
                            formRow(label: "Vehicle Type", required: true) {
                                TextField("e.g. Toyota Camry", text: $otherCarType)
                                    .autocorrectionDisabled()
                                    .multilineTextAlignment(.trailing)
                                    .focused($focusedField, equals: .otherVehicleType)
                            }
                        }

                        Divider()
                        formRow(label: "Odometer (km)", required: true) {
                            TextField("Numbers only, e.g. 12345", text: $odometer)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .focused($focusedField, equals: .odometer)
                        }
                    }

                    // Mastercard
                    sectionCard(title: "Mastercard Usage", icon: "creditcard.fill") {
                        HTXFieldLabel(
                            text: "Was a Mastercard used?",
                            required: true,
                            color: .secondary,
                            font: .caption.weight(.semibold)
                        )
                        HStack(spacing: 12) {
                            mastercardOption(label: "Yes", value: true)
                            mastercardOption(label: "No",  value: false)
                        }
                        if usedMastercard == true {
                            Divider()
                            formRow(label: "Mastercard Number", required: true) {
                                TextField("1234 5678 9012 3456", text: $mastercardNumber)
                                    .keyboardType(.numberPad)
                                    .textContentType(.creditCardNumber)
                                    .multilineTextAlignment(.trailing)
                                    .focused($focusedField, equals: .mastercardNumber)
                            }
                        }
                    }

                    // Receipt
                    sectionCard(title: "Fuel Receipt (Optional)", icon: "doc.text.fill") {
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
                            Menu {
                                Button {
                                    showReceiptCamera = true
                                } label: {
                                    Label("Take Photo", systemImage: "camera.fill")
                                }

                                Button {
                                    showReceiptPicker = true
                                } label: {
                                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                                }

                                Button {
                                    showReceiptFileImporter = true
                                } label: {
                                    Label("Upload JPG/PNG File", systemImage: "doc.badge.plus")
                                }
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
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Please complete the following required fields:")
                                .font(.footnote.weight(.semibold))
                            ForEach(validationIssues, id: \.self) { issue in
                                Label(issue, systemImage: "exclamationmark.circle.fill")
                                    .font(.footnote)
                            }
                        }
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.red.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                        validateAndShowReview()
                    } label: {
                        Text("Review Refuel Details")
                            .font(.headline)
                            .frame(maxWidth: .infinity).padding()
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
        .sheet(isPresented: $showVehiclePicker, onDismiss: dismissFormKeyboard) {
            VehiclePickerSheet(
                selectedGroup: $selectedGroup,
                selectedPlate: $selectedPlate,
                useOther: $useOtherVehicle
            )
        }
        // Receipt image options
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
        .onChange(of: odometer) { _, newValue in
            let digitsOnly = newValue.filter { $0.isNumber }
            if digitsOnly != newValue {
                odometer = digitsOnly
            }
        }
        .onChange(of: mastercardNumber) { _, newValue in
            let digitsOnly = String(newValue.filter { $0.isNumber }.prefix(16))
            let formatted = formatMastercardNumber(digitsOnly)

            if mastercardNumber != formatted {
                mastercardNumber = formatted
            }

            if digitsOnly.count == 16 {
                focusedField = nil
            }
        }
        .sheet(isPresented: $showReviewSheet) {
            FuelRefuelReviewSheet(
                driverName: driverName.trimmingCharacters(in: .whitespacesAndNewlines),
                refuelDate: dateString,
                refuelTime: timeString,
                vehicleNumber: effectiveVehicleNumber,
                vehicleType: effectiveCarType,
                odometer: cleanOdometer,
                usedMastercard: usedMastercard ?? false,
                mastercardNumber: mastercardNumber.filter { $0.isNumber },
                hasReceipt: receiptImage != nil,
                isSubmitting: isSubmitting,
                onGenerate: submitForm
            )
            .presentationDetents([.large])
        }
    }

    private func dismissFormKeyboard() {
        focusedField = nil
        UIApplication.shared.endEditing()
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
    private func formRow<Trailing: View>(
        label: String,
        required: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            HTXFieldLabel(text: label, required: required)
            Spacer()
            trailing()
                .font(.subheadline)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func mastercardOption(label: String, value: Bool) -> some View {
        Button {
            focusedField = nil
            usedMastercard = value
            if value == false { mastercardNumber = "" }
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

    private var cleanOdometer: String {
        odometer.filter { $0.isNumber }
    }

    private var validationIssues: [String] {
        var issues: [String] = []
        let name = driverName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cardDigits = mastercardNumber.filter { $0.isNumber }

        if name.isEmpty { issues.append("Name — ask an administrator to set the account username") }
        if effectiveVehicleNumber.isEmpty { issues.append("Vehicle Number") }
        if effectiveCarType.isEmpty { issues.append(useOtherVehicle ? "Vehicle Type" : "Vehicle selection") }
        if cleanOdometer.isEmpty { issues.append("Odometer (km)") }
        if usedMastercard == nil { issues.append("Mastercard Usage — select Yes or No") }
        if usedMastercard == true, cardDigits.count != 16 {
            issues.append("Mastercard Number — enter all 16 digits")
        }
        return issues
    }

    private func formatMastercardNumber(_ digits: String) -> String {
        let limitedDigits = String(digits.filter { $0.isNumber }.prefix(16))

        return stride(from: 0, to: limitedDigits.count, by: 4)
            .map { index in
                let start = limitedDigits.index(limitedDigits.startIndex, offsetBy: index)
                let end = limitedDigits.index(
                    start,
                    offsetBy: min(4, limitedDigits.distance(from: start, to: limitedDigits.endIndex)),
                    limitedBy: limitedDigits.endIndex
                ) ?? limitedDigits.endIndex

                return String(limitedDigits[start..<end])
            }
            .joined(separator: " ")
    }

    private func validateAndShowReview() {
        showValidationError = false
        submitError = nil
        odometer = cleanOdometer

        guard validationIssues.isEmpty else {
            showValidationError = true
            return
        }

        showReviewSheet = true
    }

    private func receiptBase64ForFirestore(from image: UIImage) -> String? {
        // Firestore has a field-size limit of about 1 MB. Base64 is larger than the image data,
        // so keep the encoded string comfortably below that limit.
        let maxBase64Length = 900_000
        let targetLongestSides: [CGFloat] = [1200, 1000, 800, 650, 500, 380]
        let compressionQualities: [CGFloat] = [0.65, 0.55, 0.45, 0.35, 0.25, 0.18, 0.12]

        for longestSide in targetLongestSides {
            let resized = resizedImage(image, longestSide: longestSide)
            for quality in compressionQualities {
                guard let data = resized.jpegData(compressionQuality: quality) else { continue }
                let base64 = data.base64EncodedString()
                if base64.count <= maxBase64Length {
                    return base64
                }
            }
        }
        return nil
    }

    private func resizedImage(_ image: UIImage, longestSide: CGFloat) -> UIImage {
        let size = image.size
        let currentLongestSide = max(size.width, size.height)
        guard currentLongestSide > longestSide else { return image }

        let scale = longestSide / currentLongestSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)

        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - Submit

    private func submitForm() {
        showValidationError = false
        submitError = nil

        let name = driverName.trimmingCharacters(in: .whitespacesAndNewlines)
        let vehicleNumber = effectiveVehicleNumber

        guard validationIssues.isEmpty else {
            showValidationError = true
            return
        }

        isSubmitting = true

        let barcodeId = ReportStore.makeNumericBarcodeId()
        let reportNo  = "FUEL/\(dateString.replacingOccurrences(of: "/", with: ""))/\(vehicleNumber)"

        let data: [String: Any] = [
            "reportType":       "fuel_refuel",
            "reportNo":         reportNo,
            "barcodeId":        barcodeId,
            "driverName":       name,
            "refuelDate":       dateString,
            "refuelTime":       timeString,
            "vehicleNumber":    vehicleNumber,
            "carType":          effectiveCarType,
            "odometer":         cleanOdometer,
            "usedMastercard":   usedMastercard ?? false,
            "mastercardNumber":  usedMastercard == true ? mastercardNumber.filter { $0.isNumber } : "",
            "createdByUid":     auth.user?.uid ?? "",
            "createdByName":    name,
            "createdByEmail":   auth.currentEmail,
            "generatedBy":      name,
            "adminFollowUpStatus": "pending",
            "createdAt":        FieldValue.serverTimestamp()
        ]

        let saveFirestore: ([String: Any]) -> Void = { finalData in
            Firestore.firestore()
                .collection("fuel_refuel_reports")
                .document(barcodeId)
                .setData(finalData, merge: true) { error in
                    DispatchQueue.main.async {
                        isSubmitting = false
                        if let error {
                            submitError = "Failed to save: \(error.localizedDescription)"
                        } else {
                            showReviewSheet = false
                            onReportGenerated()
                        }
                    }
                }
        }

        guard let receiptImage else {
            saveFirestore(data)
            return
        }

        guard let receiptData = receiptImage.jpegData(compressionQuality: 0.82) else {
            isSubmitting = false
            submitError = "Could not read the receipt image. Please try another photo."
            return
        }

        let receiptPath = "fuel_refuel_reports/\(barcodeId)/receipt.jpg"
        ReportStore.uploadDataToStorage(receiptData, path: receiptPath, contentType: "image/jpeg") { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let path):
                    var finalData = data
                    finalData["receiptStoragePath"] = path
                    finalData["receiptFileName"] = "receipt.jpg"
                    saveFirestore(finalData)
                case .failure(let error):
                    isSubmitting = false
                    submitError = "Failed to upload receipt to Firebase Storage: \(error.localizedDescription)"
                }
            }
        }
    }
}


// MARK: - Fuel Refuel Review Sheet

private struct FuelRefuelReviewSheet: View {
    let driverName: String
    let refuelDate: String
    let refuelTime: String
    let vehicleNumber: String
    let vehicleType: String
    let odometer: String
    let usedMastercard: Bool
    let mastercardNumber: String
    let hasReceipt: Bool
    let isSubmitting: Bool
    let onGenerate: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showGenerateConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                SubtleHTXBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        reviewCard(title: "Driver Information", icon: "person.fill") {
                            reviewRow("Name", driverName)
                        }

                        reviewCard(title: "Refuel Details", icon: "fuelpump.fill") {
                            reviewRow("Date of Refuel", refuelDate)
                            reviewRow("Time of Refuel", refuelTime)
                            reviewRow("Vehicle Number", vehicleNumber)
                            reviewRow("Vehicle Type", vehicleType)
                            reviewRow("Odometer (km)", odometer)
                        }

                        reviewCard(title: "Mastercard Usage", icon: "creditcard.fill") {
                            reviewRow("Mastercard Used", usedMastercard ? "Yes" : "No")
                            if usedMastercard {
                                reviewRow("Card Number", mastercardNumber.isEmpty ? "-" : "**** **** **** " + String(mastercardNumber.suffix(4)))
                            }
                        }

                        reviewCard(title: "Fuel Receipt", icon: "doc.text.fill") {
                            reviewRow("Receipt Attached", hasReceipt ? "Yes" : "No")
                        }

                        Button {
                            showGenerateConfirmation = true
                        } label: {
                            if isSubmitting {
                                ProgressView().tint(.white)
                                    .frame(maxWidth: .infinity).padding()
                            } else {
                                Text("Generate Report")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity).padding()
                            }
                        }
                        .background(HTXTheme.fuelOrange)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .disabled(isSubmitting)
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Confirm Refuel Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(HTXTheme.fuelOrange)
                }
            }
            .alert("Generate this refuel report?", isPresented: $showGenerateConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Generate Report") { onGenerate() }
            } message: {
                Text("Please confirm that the details are correct before generating the report.")
            }
        }
    }

    @ViewBuilder
    private func reviewCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(HTXTheme.fuelOrange)
            content()
        }
        .padding(16)
        .subtleHTXCard()
        .padding(.horizontal)
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Theme extension
extension HTXTheme {
    static let fuelOrange = Color(red: 0.80, green: 0.40, blue: 0.00)
}
