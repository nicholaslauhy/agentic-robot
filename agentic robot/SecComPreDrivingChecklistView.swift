//
//  SecComPreDrivingChecklistView.swift
//  agentic robot
//
//  Created by q2 on 29/5/26.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import FirebaseFirestore
import FirebaseAuth

// MARK: - Vehicle Catalogue

struct VehicleGroup: Identifiable {
    let id = UUID()
    let groupName: String
    let plates: [String]
    var carTypeName: String { groupName }
}

let secComVehicleGroups: [VehicleGroup] = [
    VehicleGroup(groupName: "Volvo XC 90",        plates: ["QX909B","QX910X"]),
    VehicleGroup(groupName: "Volvo S80",           plates: ["QX200L","QX443L"]),
    VehicleGroup(groupName: "Hyundai Saloon",      plates: ["QX970Y","QX971U"]),
    VehicleGroup(groupName: "Chevrolet Saloon",    plates: ["QX1349K","QX1350E"]),
    VehicleGroup(groupName: "AV Saloon",           plates: ["QX1895A","QX1896Y","QX1902M"]),
    VehicleGroup(groupName: "Pajero SUV",          plates: ["QX5000P","QX5002J","QX5003G","QX5145E"]),
    VehicleGroup(groupName: "Marked Car",          plates: ["QX314S","QX5223M"]),
    VehicleGroup(groupName: "Marked Van",          plates: ["PD377C","GBB9298P"]),
    VehicleGroup(groupName: "CAU",                 plates: ["TP221H","TP222E","TP223C","TP224A","TP225Y"]),
    VehicleGroup(groupName: "No Category",         plates: ["TP465X","TP466T","TP468M","TP470E","TP471C","QX2095K"]),
    VehicleGroup(groupName: "Land Cruiser 4.6GX",  plates: [
        "QX1967B","QX1968Z","QX1970R","QX1972K","QX1973H","QX1974E","QX1975C","QX1976A",
        "QX1978U","QX1980L","QX1982G","QX1985Z","QX2013Y","QX2016P","QX2017L","QX2018J",
        "QX2019G","QX2031U","QX2034L"
    ]),
    VehicleGroup(groupName: "Transporter",         plates: [
        "YQ9184H","YQ9194D","YQ9271P","YQ9340Z","YQ9346H","YQ9366A","YQ9403B","YQ9464A","YQ9479H"
    ]),
]

// MARK: - Equipment & Checks

enum VehicleEquipment: String, CaseIterable, Identifiable {
    case shellFuelCard     = "Shell Fuel Card"
    case mobileRadio       = "Mobile Radio Set"
    case fireExtinguisher  = "Fire Extinguisher"
    case firstAidKit       = "First Aid Kit"
    case siren             = "Siren"
    case strobeLight       = "Strobe Light"
    case flipboardSign     = "Flip Board Sign"
    case inCarCamera       = "In-Car Camera"
    case iuUnit            = "IU Unit"
    case engineOil         = "Engine Oil"
    case radiatorWater     = "Radiator Water"
    case brakeFluid        = "Brake Fluid"
    case batteryWater      = "Battery Water"
    case tyreCondition     = "Tyre Condition"
    case fuelFillerCap     = "Fuel Filler Cap"
    case others            = "Others"
    var id: String { rawValue }
}

// MARK: - Main Form View

struct SecComPreDrivingChecklistView: View {

    var onReportGenerated: () -> Void = {}

    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    // Basic fields
    @State private var date: Date = Date()
    @State private var time: Date = Date()
    @State private var driverName: String = ""
    @State private var workContact: String = ""

    // Vehicle picker
    @State private var useOtherVehicle: Bool = false
    @State private var selectedGroup: VehicleGroup? = nil
    @State private var selectedPlate: String = ""
    @State private var otherPlate: String = ""
    @State private var otherCarType: String = ""
    @State private var showVehiclePicker = false

    // Mileage & purpose
    @State private var mileage: String = ""
    @State private var purpose: String = ""

    // Equipment
    @State private var selectedEquipment: Set<VehicleEquipment> = []

    // Bodywork
    @State private var bodyworkAllInOrder: Bool = true
    @State private var bodyworkOtherDetail: String = ""

    // Damage images
    @State private var damageImages: [UIImage] = []
    @State private var showDamagePicker = false
    @State private var showDamageCamera = false
    @State private var showDamageFileImporter = false
    @State private var selectedDamagePhotoItem: PhotosPickerItem?

    // Submission
    @State private var isSubmitting = false
    @State private var submitError: String? = nil
    @State private var submitSuccess = false
    @State private var showReviewSheet = false
    @State private var showGenerateConfirmation = false

    // Validation
    @State private var showValidationError = false

    private var effectivePlate: String {
        useOtherVehicle ? otherPlate.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                       : selectedPlate
    }

    private var effectiveCarType: String {
        useOtherVehicle ? otherCarType.trimmingCharacters(in: .whitespacesAndNewlines)
                       : (selectedGroup?.groupName ?? "")
    }

    private var dateString: String {
        let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy"
        return f.string(from: date)
    }

    private var timeString: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: time)
    }

    var body: some View {
        ZStack {
            SubtleHTXBackground()

            ScrollView {
                VStack(spacing: 20) {

                    sectionCard(title: "Basic Information", icon: "info.circle.fill") {
                        formRow(label: "Date") {
                            DatePicker("", selection: $date, displayedComponents: .date)
                                .labelsHidden()
                                .tint(HTXTheme.primaryPurple)
                        }
                        Divider()
                        formRow(label: "Time") {
                            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .tint(HTXTheme.primaryPurple)
                        }
                        Divider()
                        formRow(label: "Driver Name") {
                            TextField("Full name", text: $driverName)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                        }
                        Divider()
                        formRow(label: "Work Contact") {
                            TextField("Contact number", text: $workContact)
                                .keyboardType(.phonePad)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    sectionCard(title: "Vehicle", icon: "car.fill") {
                        // Dropdown trigger
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
                                    .foregroundColor(selectedPlate.isEmpty && !useOtherVehicle ? .secondary : HTXTheme.primaryPurple)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)

                        if let grp = selectedGroup, !useOtherVehicle {
                            Divider()
                            formRow(label: "Vehicle Type") {
                                Text(grp.groupName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                        }

                        if useOtherVehicle {
                            Divider()
                            formRow(label: "Car Plate") {
                                TextField("e.g. SBA1234A", text: $otherPlate)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                                    .multilineTextAlignment(.trailing)
                            }
                            Divider()
                            formRow(label: "Car Type") {
                                TextField("e.g. Toyota Camry", text: $otherCarType)
                                    .autocorrectionDisabled()
                                    .multilineTextAlignment(.trailing)
                            }
                        }

                        Divider()
                        formRow(label: "Mileage") {
                            TextField("Numbers only, e.g. 12345", text: $mileage)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                        Divider()
                        formRow(label: "Purpose") {
                            TextField("Reason for trip", text: $purpose)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                        }
                    }

                    // Equipment checklist
                    sectionCard(title: "Checks & Equipment in Vehicle", icon: "checklist") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
                            ForEach(VehicleEquipment.allCases) { item in
                                equipmentToggle(item)
                            }
                        }
                    }

                    // Bodywork
                    sectionCard(title: "Body Work Defects / Others", icon: "wrench.and.screwdriver.fill") {
                        HStack(spacing: 12) {
                            bodyworkOption(label: "All in Order", selected: bodyworkAllInOrder) {
                                bodyworkAllInOrder = true
                            }
                            bodyworkOption(label: "Others", selected: !bodyworkAllInOrder) {
                                bodyworkAllInOrder = false
                            }
                        }
                        .padding(.bottom, 4)

                        if !bodyworkAllInOrder {
                            Divider()
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Details")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                TextEditor(text: $bodyworkOtherDetail)
                                    .frame(minHeight: 80)
                                    .padding(8)
                                    .background(Color(.systemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(HTXTheme.primaryPurple.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            .padding(.top, 6)
                        }
                    }

                    // Damage photos (optional)
                    sectionCard(title: "New Damage Detected (Optional)", icon: "camera.fill") {
                        if damageImages.isEmpty {
                            damagePhotoMenu {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(HTXTheme.primaryPurple)
                                    Text("Add Photo")
                                        .foregroundColor(HTXTheme.primaryPurple)
                                        .font(.subheadline.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(HTXTheme.primaryPurple.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(damageImages.indices, id: \.self) { idx in
                                        ZStack(alignment: .topTrailing) {
                                            Image(uiImage: damageImages[idx])
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 90, height: 90)
                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                            Button {
                                                damageImages.remove(at: idx)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.red)
                                                    .background(Color.white.clipShape(Circle()))
                                            }
                                            .offset(x: 6, y: -6)
                                        }
                                    }
                                    damagePhotoMenu {
                                        Image(systemName: "plus")
                                            .font(.title2)
                                            .foregroundColor(HTXTheme.primaryPurple)
                                            .frame(width: 90, height: 90)
                                            .background(HTXTheme.primaryPurple.opacity(0.08))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    // Validation error
                    if showValidationError {
                        Text(
                            selectedEquipment.isEmpty
                            ? "Please check at least one item in the equipment checklist."
                            : (!bodyworkAllInOrder && bodyworkOtherDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            ? "Please describe the body work defect details."
                            : "Please fill in all required fields and select a vehicle."
                        )
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

                    // Submit
                    Button {
                        validateAndShowReview()
                    } label: {
                        Text("Review Checklist Details")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .background(HTXTheme.primaryPurple)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
                    .disabled(isSubmitting)
                    .padding(.bottom, 30)
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("Pre-Driving Checklist")
        .navigationBarTitleDisplayMode(.inline)
        .tint(HTXTheme.primaryPurple)
        // Vehicle picker sheet
        .sheet(isPresented: $showVehiclePicker) {
            VehiclePickerSheet(
                selectedGroup: $selectedGroup,
                selectedPlate: $selectedPlate,
                useOther: $useOtherVehicle
            )
        }
        // Damage image options dialog moved to button level for correct anchor positioning
        .sheet(isPresented: $showDamageCamera) {
            ImagePicker(sourceType: .camera) { img in damageImages.append(img) }
        }
        .photosPicker(isPresented: $showDamagePicker, selection: $selectedDamagePhotoItem, matching: .images)
        .onChange(of: selectedDamagePhotoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run { damageImages.append(img) }
                }
                await MainActor.run { selectedDamagePhotoItem = nil }
            }
        }
        .fileImporter(
            isPresented: $showDamageFileImporter,
            allowedContentTypes: [.jpeg, .png],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    if url.startAccessingSecurityScopedResource(),
                       let data = try? Data(contentsOf: url),
                       let img = UIImage(data: data) {
                        damageImages.append(img)
                    }
                    url.stopAccessingSecurityScopedResource()
                }
            }
        }
        .onChange(of: mileage) { _, newValue in
            let digitsOnly = newValue.filter { $0.isNumber }
            if digitsOnly != newValue {
                mileage = digitsOnly
            }
        }
        .sheet(isPresented: $showReviewSheet) {
            SecComChecklistReviewSheet(
                date: dateString,
                time: timeString,
                driverName: driverName.trimmingCharacters(in: .whitespacesAndNewlines),
                workContact: workContact.trimmingCharacters(in: .whitespacesAndNewlines),
                vehicleNumber: effectivePlate,
                vehicleType: effectiveCarType,
                mileage: cleanMileage,
                purpose: purpose.trimmingCharacters(in: .whitespacesAndNewlines),
                selectedEquipment: selectedEquipment,
                bodyworkAllInOrder: bodyworkAllInOrder,
                bodyworkDetails: bodyworkOtherDetail.trimmingCharacters(in: .whitespacesAndNewlines),
                damageImageCount: damageImages.count,
                isSubmitting: isSubmitting,
                onGenerate: { showGenerateConfirmation = true }
            )
            .presentationDetents([.large])
        }
        .confirmationDialog(
            "Generate this checklist report?",
            isPresented: $showGenerateConfirmation,
            titleVisibility: .visible
        ) {
            Button("Generate Report") { submitForm() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please confirm that the details are correct before generating the report.")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func damagePhotoMenu<LabelContent: View>(@ViewBuilder label: () -> LabelContent) -> some View {
        Menu {
            Button {
                showDamageCamera = true
            } label: {
                Label("Take Photo", systemImage: "camera.fill")
            }

            Button {
                showDamagePicker = true
            } label: {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
            }

            Button {
                showDamageFileImporter = true
            } label: {
                Label("Upload JPG/PNG File", systemImage: "doc.badge.plus")
            }
        } label: {
            label()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(HTXTheme.primaryPurple)
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
    private func equipmentToggle(_ item: VehicleEquipment) -> some View {
        Button {
            if selectedEquipment.contains(item) {
                selectedEquipment.remove(item)
            } else {
                selectedEquipment.insert(item)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selectedEquipment.contains(item) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedEquipment.contains(item) ? HTXTheme.primaryPurple : .secondary)
                Text(item.rawValue)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func bodyworkOption(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(selected ? HTXTheme.primaryPurple : Color(.secondarySystemBackground))
                .foregroundColor(selected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(selected ? HTXTheme.primaryPurple : HTXTheme.softPurpleBorder, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private var cleanMileage: String {
        mileage.filter { $0.isNumber }
    }

    private func validateAndShowReview() {
        showValidationError = false
        submitError = nil
        mileage = cleanMileage

        let name = driverName.trimmingCharacters(in: .whitespacesAndNewlines)
        let contact = workContact.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, !contact.isEmpty,
              !effectivePlate.isEmpty, !effectiveCarType.isEmpty,
              !cleanMileage.isEmpty,
              !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !selectedEquipment.isEmpty,
              bodyworkAllInOrder || !bodyworkOtherDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            showValidationError = true
            return
        }

        showReviewSheet = true
    }

    // MARK: - Submit

    private func submitForm() {
        showValidationError = false
        submitError = nil

        let name = driverName.trimmingCharacters(in: .whitespacesAndNewlines)
        let contact = workContact.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, !contact.isEmpty,
              !effectivePlate.isEmpty, !effectiveCarType.isEmpty,
              !cleanMileage.isEmpty,
              !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !selectedEquipment.isEmpty,
              bodyworkAllInOrder || !bodyworkOtherDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            showValidationError = true
            return
        }

        isSubmitting = true

        let barcodeId = ReportStore.makeNumericBarcodeId()
        let reportNo  = "SECCOM/\(dateString.replacingOccurrences(of: "/", with: ""))/\(effectivePlate)"

        let data: [String: Any] = [
            "reportType":       "seccom_checklist",
            "reportNo":         reportNo,
            "barcodeId":        barcodeId,
            "date":             dateString,
            "time":             timeString,
            "driverName":       name,
            "workContact":      contact,
            "plate":            effectivePlate,
            "carType":          effectiveCarType,
            "mileage":          cleanMileage,
            "purpose":          purpose.trimmingCharacters(in: .whitespacesAndNewlines),
            "equipment":        selectedEquipment.map { $0.rawValue },
            "bodyworkAllInOrder": bodyworkAllInOrder,
            "bodyworkDetails":  bodyworkAllInOrder ? "" : bodyworkOtherDetail,
            "generatedBy":      Auth.auth().currentUser?.email ?? "Unknown",
            "detectionCount":   damageImages.count,
            "createdAt":        FieldValue.serverTimestamp()
        ]

        let saveFirestore: ([String: Any]) -> Void = { finalData in
            Firestore.firestore()
                .collection("seccom_checklists")
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

        func uploadDamageImages(_ images: [UIImage], index: Int = 0, paths: [String] = []) {
            guard index < images.count else {
                var finalData = data
                if !paths.isEmpty {
                    finalData["damageImageStoragePaths"] = paths
                }
                saveFirestore(finalData)
                return
            }

            guard let imageData = images[index].jpegData(compressionQuality: 0.82) else {
                DispatchQueue.main.async {
                    isSubmitting = false
                    submitError = "Could not read damage image \(index + 1). Please try again."
                }
                return
            }

            let imagePath = "seccom_checklists/\(barcodeId)/damage_images/damage_\(index + 1).jpg"
            ReportStore.uploadDataToStorage(imageData, path: imagePath, contentType: "image/jpeg") { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let path):
                        uploadDamageImages(images, index: index + 1, paths: paths + [path])
                    case .failure(let error):
                        isSubmitting = false
                        submitError = "Failed to upload damage image \(index + 1) to Firebase Storage: \(error.localizedDescription)"
                    }
                }
            }
        }

        uploadDamageImages(damageImages)
    }
}


// MARK: - SecCom Review Sheet

private struct SecComChecklistReviewSheet: View {
    let date: String
    let time: String
    let driverName: String
    let workContact: String
    let vehicleNumber: String
    let vehicleType: String
    let mileage: String
    let purpose: String
    let selectedEquipment: Set<VehicleEquipment>
    let bodyworkAllInOrder: Bool
    let bodyworkDetails: String
    let damageImageCount: Int
    let isSubmitting: Bool
    let onGenerate: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                SubtleHTXBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        reviewCard(title: "Basic Information", icon: "info.circle.fill") {
                            reviewRow("Date", date)
                            reviewRow("Time", time)
                            reviewRow("Driver Name", driverName)
                            reviewRow("Work Contact", workContact)
                        }

                        reviewCard(title: "Vehicle", icon: "car.fill") {
                            reviewRow("Vehicle Number", vehicleNumber)
                            reviewRow("Vehicle Type", vehicleType)
                            reviewRow("Mileage", "\(mileage) km")
                            reviewRow("Purpose", purpose)
                        }

                        reviewCard(title: "Checks & Equipment", icon: "checklist") {
                            ForEach(VehicleEquipment.allCases) { item in
                                let checked = selectedEquipment.contains(item)
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: checked ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(checked ? HTXTheme.primaryPurple : .red)
                                        .frame(width: 22)
                                    Text(item.rawValue)
                                        .font(.subheadline)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(checked ? "Checked" : "Missing")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(checked ? HTXTheme.primaryPurple : .red)
                                }
                                .padding(.vertical, 6)
                            }
                        }

                        reviewCard(title: "Body Work Defects / Others", icon: "wrench.and.screwdriver.fill") {
                            reviewRow("Status", bodyworkAllInOrder ? "All in Order" : "Others")
                            if !bodyworkAllInOrder {
                                reviewRow("Details", bodyworkDetails.isEmpty ? "-" : bodyworkDetails)
                            }
                        }

                        reviewCard(title: "New Damage Detected", icon: "camera.fill") {
                            reviewRow("Images Attached", "\(damageImageCount)")
                        }

                        Button {
                            onGenerate()
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
                        .background(HTXTheme.primaryPurple)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .disabled(isSubmitting)
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Confirm Checklist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(HTXTheme.primaryPurple)
                }
            }
        }
    }

    @ViewBuilder
    private func reviewCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(HTXTheme.primaryPurple)
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
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Vehicle Picker Sheet

struct VehiclePickerSheet: View {
    @Binding var selectedGroup: VehicleGroup?
    @Binding var selectedPlate: String
    @Binding var useOther: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var expandedGroup: UUID? = nil

    var body: some View {
        NavigationStack {
            List {
                ForEach(secComVehicleGroups) { group in
                    Section {
                        if expandedGroup == group.id {
                            ForEach(group.plates, id: \.self) { plate in
                                Button {
                                    selectedGroup = group
                                    selectedPlate = plate
                                    useOther = false
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(plate)
                                            .font(.system(.body, design: .monospaced).weight(.semibold))
                                            .foregroundColor(.primary)
                                        Spacer()
                                        if selectedPlate == plate && !useOther {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(HTXTheme.primaryPurple)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Button {
                            withAnimation {
                                expandedGroup = (expandedGroup == group.id) ? nil : group.id
                            }
                        } label: {
                            HStack {
                                Text(group.groupName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(HTXTheme.primaryPurple)
                                Spacer()
                                Image(systemName: expandedGroup == group.id ? "chevron.up" : "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Other option
                Section {
                    Button {
                        useOther = true
                        selectedPlate = ""
                        selectedGroup = nil
                        dismiss()
                    } label: {
                        HStack {
                            Text("Other (enter manually)")
                                .foregroundColor(.primary)
                            Spacer()
                            if useOther {
                                Image(systemName: "checkmark")
                                    .foregroundColor(HTXTheme.primaryPurple)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Select Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(HTXTheme.primaryPurple)
                }
            }
            .tint(HTXTheme.primaryPurple)
        }
    }
}
