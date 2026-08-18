//
//  SecComPreDrivingChecklistView.swift
//  agentic robot
//
//  Created by q2 on 29/5/26.
//

import SwiftUI
import UIKit
import PhotosUI
import FirebaseAuth
import FirebaseFirestore

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

struct ChecklistDamagePhoto: Identifiable {
    let id: UUID
    let image: UIImage
    let angleIndex: Int
    let guideCarType: CarType
    let confirmedRegions: [ChecklistDamageRegion]

    init(
        id: UUID = UUID(),
        image: UIImage,
        angleIndex: Int,
        guideCarType: CarType,
        confirmedRegions: [ChecklistDamageRegion] = []
    ) {
        self.id = id
        self.image = image
        self.angleIndex = angleIndex
        self.guideCarType = guideCarType
        self.confirmedRegions = confirmedRegions
    }

    var angleLabel: String {
        scanAngles[min(max(angleIndex, 0), scanAngles.count - 1)].label
    }
}

struct ChecklistDamageRegion: Identifiable {
    let id: UUID
    var damageType: String
    var confidence: Double
    var normalizedBBox: CGRect?
    var cropImage: UIImage?
    var explanation: String
    var isManuallyAdded: Bool

    init(
        id: UUID = UUID(),
        damageType: String,
        confidence: Double,
        normalizedBBox: CGRect?,
        cropImage: UIImage?,
        explanation: String,
        isManuallyAdded: Bool
    ) {
        self.id = id
        self.damageType = damageType
        self.confidence = confidence
        self.normalizedBBox = normalizedBBox
        self.cropImage = cropImage
        self.explanation = explanation
        self.isManuallyAdded = isManuallyAdded
    }

    init(detection: DamageDetection, sourceImage: UIImage) {
        let normalizedImage = sourceImage.htxNormalizedImage()
        let sourceWidth = CGFloat(detection.imageWidth ?? Int(normalizedImage.size.width))
        let sourceHeight = CGFloat(detection.imageHeight ?? Int(normalizedImage.size.height))

        let box: CGRect?
        if let x1 = detection.x1,
           let y1 = detection.y1,
           let x2 = detection.x2,
           let y2 = detection.y2,
           sourceWidth > 0,
           sourceHeight > 0,
           x2 > x1,
           y2 > y1 {
            let nx1 = max(0, min(1, CGFloat(x1) / sourceWidth))
            let ny1 = max(0, min(1, CGFloat(y1) / sourceHeight))
            let nx2 = max(0, min(1, CGFloat(x2) / sourceWidth))
            let ny2 = max(0, min(1, CGFloat(y2) / sourceHeight))
            box = nx2 > nx1 && ny2 > ny1
                ? CGRect(x: nx1, y: ny1, width: nx2 - nx1, height: ny2 - ny1)
                : nil
        } else {
            box = nil
        }

        self.init(
            id: detection.id,
            damageType: detection.damageType,
            confidence: detection.confidence,
            normalizedBBox: box,
            cropImage: detection.cropImage,
            explanation: detection.explanation,
            isManuallyAdded: false
        )
    }
}

private struct ChecklistDamageReviewSession: Identifiable {
    let id = UUID()
    let image: UIImage
    let angleIndex: Int
    let guideCarType: CarType
    let replacementID: UUID?
    let detectedRegions: [ChecklistDamageRegion]
}

private enum ChecklistDamageProcessingStage: Equatable {
    case angleValidation
    case damageAnalysis
}

// MARK: - Main Form View

struct SecComPreDrivingChecklistView: View {

    var onReportGenerated: () -> Void = {}

    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    // Basic fields
    @State private var date: Date = Date()
    @State private var time: Date = Date()
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

    // Optional, guided damage photos
    @State private var damagePhotos: [ChecklistDamagePhoto] = []
    @State private var showDamageCaptureSetup = false
    @State private var damageCaptureAngleIndex = 0
    @State private var damageCaptureCarType: CarType = .sedan
    @State private var selectedDamagePhoto: ChecklistDamagePhoto?
    @State private var damagePhotoBeingReplacedID: UUID?
    @State private var showDamagePicker = false
    @State private var showDamageCamera = false
    @State private var selectedDamagePhotoItem: PhotosPickerItem?
    @State private var isValidatingDamagePhoto = false
    @State private var damageValidationTask: URLSessionDataTask?
    @State private var damageValidationID: UUID?
    @State private var rejectedDamagePhoto: UIImage?
    @State private var rejectedDamageResult: GeminiAngleService.AngleValidationResult?
    @StateObject private var damageAngleProgress = HTXProgressTracker()
    @State private var damageAnalysisTask: Task<Void, Never>?
    @State private var isAnalyzingDamagePhoto = false
    @State private var pendingAnalysisImage: UIImage?
    @State private var damageAnalysisError: String?
    @State private var damageReviewSession: ChecklistDamageReviewSession?
    @StateObject private var damageAnalysisProgress = HTXProgressTracker()

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

    private var driverName: String {
        auth.currentUsername
    }

    private var damageProcessingStage: ChecklistDamageProcessingStage {
        isAnalyzingDamagePhoto ? .damageAnalysis : .angleValidation
    }

    /// Angle validation occupies the first 35% of the overall operation. Damage
    /// analysis continues from 35% to 100%, so the user sees one continuous bar.
    private var overallDamageProcessingProgress: Double {
        if isAnalyzingDamagePhoto {
            return 0.35 + (min(max(damageAnalysisProgress.value, 0), 1) * 0.65)
        }
        return min(max(damageAngleProgress.value, 0), 1) * 0.35
    }

    private var inferredDamageCarType: CarType {
        let name = effectiveCarType.lowercased()
        if name.contains("suv") || name.contains("pajero") || name.contains("land cruiser") || name.contains("xc 90") {
            return .suv
        }
        if name.contains("mpv") || name.contains("van") || name.contains("transporter") || name.contains("cau") {
            return .mpv
        }
        return .sedan
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
                    sectionCard(title: "Equipment in Vehicle (Optional)", icon: "checklist") {
                        Text("Select only the equipment currently in the vehicle. You may leave everything unselected when none of these items are present.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

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
                        Text("Only add a photo when you notice new damage. Select the vehicle angle first so the photo can be checked before it is attached.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if damagePhotos.isEmpty {
                            addDamagePhotoButton
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(damagePhotos) { photo in
                                        VStack(alignment: .leading, spacing: 7) {
                                            ZStack(alignment: .topTrailing) {
                                                Button {
                                                    selectedDamagePhoto = photo
                                                } label: {
                                                    Image(uiImage: photo.image)
                                                        .resizable()
                                                        .scaledToFill()
                                                        .frame(width: 140, height: 95)
                                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                                        .overlay(alignment: .bottomTrailing) {
                                                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                                                .font(.caption.weight(.bold))
                                                                .foregroundColor(.white)
                                                                .padding(6)
                                                                .background(Color.black.opacity(0.55))
                                                                .clipShape(Circle())
                                                                .padding(6)
                                                        }
                                                }
                                                .buttonStyle(.plain)

                                                Button {
                                                    damagePhotos.removeAll { $0.id == photo.id }
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundColor(.red)
                                                        .background(Color.white.clipShape(Circle()))
                                                }
                                                .offset(x: 6, y: -6)
                                            }

                                            Text(photo.angleLabel)
                                                .font(.caption.weight(.semibold))
                                                .foregroundColor(HTXTheme.primaryPurple)
                                            Text("\(photo.guideCarType.rawValue) guide")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Text("\(photo.confirmedRegions.count) confirmed")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundColor(.green)
                                        }
                                        .frame(width: 140, alignment: .leading)
                                    }

                                    Button {
                                        prepareDamageCapture()
                                    } label: {
                                        VStack(alignment: .leading, spacing: 7) {
                                            VStack(spacing: 7) {
                                                Image(systemName: "plus")
                                                    .font(.title2)
                                                Text("Add another")
                                                    .font(.caption.weight(.semibold))
                                            }
                                            .frame(width: 140, height: 95)
                                            .background(HTXTheme.primaryPurple.opacity(0.08))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))

                                            Text("New photo")
                                                .font(.caption.weight(.semibold))
                                            Text("Choose angle")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .foregroundColor(HTXTheme.primaryPurple)
                                        .frame(width: 140, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    // Validation error
                    if showValidationError {
                        Text(
                            (!bodyworkAllInOrder && bodyworkOtherDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && damagePhotos.isEmpty)
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
        .sheet(isPresented: $showDamageCaptureSetup) {
            ChecklistDamageCaptureSetupSheet(
                vehicleName: effectiveCarType,
                angleIndex: $damageCaptureAngleIndex,
                guideCarType: $damageCaptureCarType,
                onCancel: {
                    damagePhotoBeingReplacedID = nil
                },
                onTakePhoto: {
                    showDamageCaptureSetup = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        showDamageCamera = true
                    }
                },
                onChoosePhoto: {
                    showDamageCaptureSetup = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        showDamagePicker = true
                    }
                }
            )
        }
        .fullScreenCover(item: $selectedDamagePhoto) { photo in
            ChecklistDamagePhotoViewer(
                photo: photo,
                onClose: { selectedDamagePhoto = nil },
                onReplace: { prepareDamagePhotoReplacement(photo) },
                onDelete: { deleteDamagePhoto(photo) }
            )
        }
        .fullScreenCover(item: $damageReviewSession) { session in
            ChecklistDamageReviewView(
                session: session,
                onCancel: {
                    damageReviewSession = nil
                    damagePhotoBeingReplacedID = nil
                },
                onConfirm: { regions in
                    attachReviewedDamagePhoto(from: session, regions: regions)
                }
            )
        }
        .fullScreenCover(isPresented: $showDamageCamera) {
            CameraOverlayImagePicker(
                carType: damageCaptureCarType,
                angleId: damageCaptureAngleIndex,
                usesDamageWorkflowProgress: true
            ) { image in
                showDamageCamera = false
                beginDamageAnalysis(image)
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showDamagePicker, selection: $selectedDamagePhotoItem, matching: .images)
        .onChange(of: selectedDamagePhotoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run { validateDamagePhoto(img) }
                } else {
                    await MainActor.run {
                        selectedDamagePhotoItem = nil
                        submitError = "The selected damage photo could not be opened. Please choose another image."
                    }
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
                damagePhotoSummaries: damagePhotos.map { photo in
                    let types = photo.confirmedRegions
                        .map { $0.damageType.capitalized }
                        .joined(separator: ", ")
                    return "\(photo.angleLabel) · \(types)"
                },
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
        .overlay {
            if isValidatingDamagePhoto || isAnalyzingDamagePhoto {
                ChecklistDamageProcessingOverlay(
                    stage: damageProcessingStage,
                    overallProgress: overallDamageProcessingProgress,
                    onCancel: cancelCurrentDamageProcessing
                )
            }
        }
        .overlay {
            if let rejectedDamageResult {
                AngleFailurePopup(
                    expected: expectedDamageAngle.rawValue,
                    detected: rejectedDamageResult.detectedAngle.rawValue,
                    confidence: rejectedDamageResult.confidence,
                    reason: rejectedDamageResult.reason,
                    canOverride: true,
                    onRetake: discardRejectedDamagePhoto,
                    onOverride: overrideRejectedDamagePhoto
                )
            }
        }
        .alert("Damage analysis could not be completed", isPresented: Binding(
            get: { damageAnalysisError != nil },
            set: { if !$0 { damageAnalysisError = nil } }
        )) {
            if pendingAnalysisImage != nil {
                Button("Try Again") {
                    if let image = pendingAnalysisImage {
                        beginDamageAnalysis(image)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingAnalysisImage = nil
                damagePhotoBeingReplacedID = nil
            }
        } message: {
            Text(damageAnalysisError ?? "Please try again.")
        }
    }

    // MARK: - Helpers

    private var addDamagePhotoButton: some View {
        Button {
            prepareDamageCapture()
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add Damage Photo")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(HTXTheme.primaryPurple)
            .frame(maxWidth: .infinity)
            .padding()
            .background(HTXTheme.primaryPurple.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var expectedDamageAngle: GeminiAngleService.DetectedAngle {
        switch damageCaptureAngleIndex {
        case 0: return .front
        case 1: return .rear
        case 2: return .left
        case 3: return .right
        default: return .unknown
        }
    }

    private func prepareDamageCapture() {
        guard !effectivePlate.isEmpty, !effectiveCarType.isEmpty else {
            submitError = "Select the vehicle before adding a damage photo."
            return
        }

        submitError = nil
        damagePhotoBeingReplacedID = nil
        damageCaptureAngleIndex = 0
        damageCaptureCarType = inferredDamageCarType
        rejectedDamagePhoto = nil
        rejectedDamageResult = nil
        showDamageCaptureSetup = true
    }

    private func beginDamageAnalysis(_ image: UIImage) {
        damageAnalysisTask?.cancel()
        pendingAnalysisImage = image
        damageAnalysisError = nil
        selectedDamagePhotoItem = nil
        rejectedDamagePhoto = nil
        rejectedDamageResult = nil
        isAnalyzingDamagePhoto = true
        damageAnalysisProgress.start(estimatedDuration: 35)

        let angleIndex = damageCaptureAngleIndex
        let guideCarType = damageCaptureCarType
        let replacementID = damagePhotoBeingReplacedID
        let plate = effectivePlate

        damageAnalysisTask = Task {
            do {
                let results = try await DamageAnalysisService.shared.analyzeForPlate(
                    plate: plate,
                    images: [image],
                    angleIndices: [angleIndex]
                )
                try Task.checkCancellation()

                // Stored baseline regions are useful to the comparison algorithm but
                // are not new defects for the driver to submit again.
                let newRegions = results
                    .filter { !($0.isBaseline ?? false) }
                    .map { ChecklistDamageRegion(detection: $0, sourceImage: image) }

                await MainActor.run {
                    damageAnalysisProgress.completeAnimated {
                        guard !Task.isCancelled else { return }
                        isAnalyzingDamagePhoto = false
                        damageAnalysisProgress.stop()
                        pendingAnalysisImage = nil
                        damageAnalysisTask = nil
                        damageReviewSession = ChecklistDamageReviewSession(
                            image: image,
                            angleIndex: angleIndex,
                            guideCarType: guideCarType,
                            replacementID: replacementID,
                            detectedRegions: newRegions
                        )
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    isAnalyzingDamagePhoto = false
                    damageAnalysisProgress.stop()
                    damageAnalysisTask = nil
                }
            } catch {
                await MainActor.run {
                    isAnalyzingDamagePhoto = false
                    damageAnalysisProgress.stop()
                    damageAnalysisTask = nil
                    damageAnalysisError = error.localizedDescription
                }
            }
        }
    }

    private func attachReviewedDamagePhoto(
        from session: ChecklistDamageReviewSession,
        regions: [ChecklistDamageRegion]
    ) {
        let acceptedPhoto = ChecklistDamagePhoto(
            id: session.replacementID ?? UUID(),
            image: session.image,
            angleIndex: session.angleIndex,
            guideCarType: session.guideCarType,
            confirmedRegions: regions
        )

        if let replacementID = session.replacementID,
           let index = damagePhotos.firstIndex(where: { $0.id == replacementID }) {
            damagePhotos[index] = acceptedPhoto
        } else {
            damagePhotos.append(acceptedPhoto)
        }

        damageReviewSession = nil
        damagePhotoBeingReplacedID = nil
        bodyworkAllInOrder = false
        rejectedDamagePhoto = nil
        rejectedDamageResult = nil
    }

    private func prepareDamagePhotoReplacement(_ photo: ChecklistDamagePhoto) {
        damagePhotoBeingReplacedID = photo.id
        damageCaptureAngleIndex = photo.angleIndex
        damageCaptureCarType = photo.guideCarType
        selectedDamagePhoto = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            showDamageCaptureSetup = true
        }
    }

    private func deleteDamagePhoto(_ photo: ChecklistDamagePhoto) {
        damagePhotos.removeAll { $0.id == photo.id }
        selectedDamagePhoto = nil
        if damagePhotoBeingReplacedID == photo.id {
            damagePhotoBeingReplacedID = nil
        }
    }

    private func validateDamagePhoto(_ image: UIImage) {
        let validationID = UUID()
        damageValidationID = validationID
        rejectedDamagePhoto = nil
        rejectedDamageResult = nil
        isValidatingDamagePhoto = true
        damageAngleProgress.start(estimatedDuration: 12)

        damageValidationTask = GeminiAngleService.validateExpectedAngle(
            image: image,
            expectedAngle: expectedDamageAngle
        ) { result in
            guard damageValidationID == validationID else { return }
            damageValidationTask = nil

            damageAngleProgress.completeAnimated {
                guard damageValidationID == validationID else { return }
                damageValidationID = nil
                selectedDamagePhotoItem = nil

                if result.isAccepted {
                    beginDamageAnalysis(image)
                    // Keep the unified overlay visible while its active step
                    // changes from angle validation to damage analysis.
                    isValidatingDamagePhoto = false
                    damageAngleProgress.stop()
                } else {
                    isValidatingDamagePhoto = false
                    damageAngleProgress.stop()
                    rejectedDamagePhoto = image
                    rejectedDamageResult = result
                }
            }
        }
    }

    private func cancelDamagePhotoValidation() {
        damageValidationID = nil
        damageValidationTask?.cancel()
        damageValidationTask = nil
        damageAngleProgress.stop()
        isValidatingDamagePhoto = false
        selectedDamagePhotoItem = nil
        submitError = "Damage photo verification was cancelled."
    }

    private func discardRejectedDamagePhoto() {
        rejectedDamagePhoto = nil
        rejectedDamageResult = nil
        selectedDamagePhotoItem = nil
        DispatchQueue.main.async {
            showDamageCaptureSetup = true
        }
    }

    private func overrideRejectedDamagePhoto() {
        guard let image = rejectedDamagePhoto else { return }
        beginDamageAnalysis(image)
    }

    private func cancelDamageAnalysis() {
        damageAnalysisTask?.cancel()
        damageAnalysisTask = nil
        damageAnalysisProgress.stop()
        isAnalyzingDamagePhoto = false
        pendingAnalysisImage = nil
        damagePhotoBeingReplacedID = nil
        submitError = "Damage analysis was cancelled. The photo was not attached."
    }

    private func cancelCurrentDamageProcessing() {
        if isAnalyzingDamagePhoto {
            cancelDamageAnalysis()
        } else {
            cancelDamagePhotoValidation()
        }
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
              bodyworkAllInOrder
                || !bodyworkOtherDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !damagePhotos.isEmpty
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
              bodyworkAllInOrder
                || !bodyworkOtherDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !damagePhotos.isEmpty
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
            "createdByUid":     auth.user?.uid ?? "",
            "createdByName":    name,
            "createdByEmail":   auth.currentEmail,
            "generatedBy":      name,
            "damageImageCount": damagePhotos.count,
            "detectionCount":   damagePhotos.reduce(0) { $0 + $1.confirmedRegions.count },
            "adminReviewStatus": "pending",
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

        func uploadDamageImages(
            _ photos: [ChecklistDamagePhoto],
            index: Int = 0,
            paths: [String] = [],
            metadata: [[String: Any]] = []
        ) {
            guard index < photos.count else {
                var finalData = data
                if !paths.isEmpty {
                    finalData["damageImageStoragePaths"] = paths
                    finalData["damagePhotos"] = metadata
                }
                saveFirestore(finalData)
                return
            }

            let photo = photos[index]
            guard let imageData = photo.image.jpegData(compressionQuality: 0.82) else {
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
                        let confirmedDamage = photo.confirmedRegions.map { region -> [String: Any] in
                            var value: [String: Any] = [
                                "damageType": region.damageType,
                                "confidence": region.confidence,
                                "explanation": region.explanation,
                                "source": region.isManuallyAdded ? "manual" : "ai_confirmed"
                            ]
                            if let box = region.normalizedBBox {
                                value["boundingBox"] = [
                                    "x": Double(box.minX),
                                    "y": Double(box.minY),
                                    "width": Double(box.width),
                                    "height": Double(box.height)
                                ]
                            }
                            return value
                        }
                        let photoMetadata: [String: Any] = [
                            "storagePath": path,
                            "angle": photo.angleLabel,
                            "angleIndex": photo.angleIndex,
                            "guideVehicleType": photo.guideCarType.rawValue,
                            "confirmedDamage": confirmedDamage
                        ]
                        uploadDamageImages(
                            photos,
                            index: index + 1,
                            paths: paths + [path],
                            metadata: metadata + [photoMetadata]
                        )
                    case .failure(let error):
                        isSubmitting = false
                        submitError = "Failed to upload damage image \(index + 1) to Firebase Storage: \(error.localizedDescription)"
                    }
                }
            }
        }

        uploadDamageImages(damagePhotos)
    }
}


// MARK: - Multi-step Damage Processing

private struct ChecklistDamageProcessingOverlay: View {
    let stage: ChecklistDamageProcessingStage
    let overallProgress: Double
    let onCancel: () -> Void

    private var clampedProgress: Double {
        min(max(overallProgress, 0), 1)
    }

    private var percent: Int {
        Int((clampedProgress * 100).rounded())
    }

    private var currentMessage: String {
        switch stage {
        case .angleValidation:
            return "Checking the selected vehicle side, visibility and camera alignment."
        case .damageAnalysis:
            return "The photo passed the angle check. Now checking for scratches, dents and other visible damage."
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.42).ignoresSafeArea()

            VStack(spacing: 17) {
                Image(systemName: "car.side.and.exclamationmark")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(HTXTheme.primaryPurple)

                Text("Inspecting Vehicle Photo")
                    .font(.title3.bold())

                Text(currentMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    processingStep(
                        number: 1,
                        title: "Validate vehicle angle",
                        detail: stage == .angleValidation ? "In progress" : "Completed",
                        isActive: stage == .angleValidation,
                        isComplete: stage == .damageAnalysis
                    )

                    Rectangle()
                        .fill(stage == .damageAnalysis ? Color.green : Color(.systemGray4))
                        .frame(width: 2, height: 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 15)

                    processingStep(
                        number: 2,
                        title: "Analyse visible damage",
                        detail: stage == .damageAnalysis ? "In progress" : "Waiting",
                        isActive: stage == .damageAnalysis,
                        isComplete: false
                    )
                }
                .padding(13)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(spacing: 8) {
                    ProgressView(value: clampedProgress, total: 1)
                        .tint(HTXTheme.primaryPurple)
                        .scaleEffect(x: 1, y: 1.8, anchor: .center)

                    HStack {
                        Text(stage == .angleValidation ? "Step 1 of 2" : "Step 2 of 2")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(percent)%")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundColor(HTXTheme.primaryPurple)
                            .contentTransition(.numericText())
                    }
                }

                Button(action: onCancel) {
                    Label("Cancel Processing", systemImage: "xmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(24)
            .frame(maxWidth: 390)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
            .padding(.horizontal, 24)
        }
        .transition(.opacity)
    }

    private func processingStep(
        number: Int,
        title: String,
        detail: String,
        isActive: Bool,
        isComplete: Bool
    ) -> some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(isComplete ? Color.green : isActive ? HTXTheme.primaryPurple : Color(.systemGray4))
                    .frame(width: 30, height: 30)

                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                } else {
                    Text("\(number)")
                        .font(.caption.bold())
                        .foregroundColor(isActive ? .white : .secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(isActive || isComplete ? .primary : .secondary)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(isComplete ? .green : isActive ? HTXTheme.primaryPurple : .secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Driver Damage Review

private let checklistDamageTypes = [
    "scratch", "dent", "paint chip", "crack",
    "broken glass", "lamp broken", "tire flat", "other"
]

private enum ChecklistDamageDecision {
    case undecided
    case confirmed
    case rejected
}

private struct ChecklistDamageCandidate: Identifiable {
    let id: UUID
    var region: ChecklistDamageRegion
    var decision: ChecklistDamageDecision

    init(region: ChecklistDamageRegion, decision: ChecklistDamageDecision = .undecided) {
        self.id = region.id
        self.region = region
        self.decision = decision
    }
}

private struct ChecklistDamageReviewView: View {
    let session: ChecklistDamageReviewSession
    let onCancel: () -> Void
    let onConfirm: ([ChecklistDamageRegion]) -> Void

    @State private var candidates: [ChecklistDamageCandidate]
    @State private var showManualEditor = false
    @State private var showCancelConfirmation = false

    init(
        session: ChecklistDamageReviewSession,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping ([ChecklistDamageRegion]) -> Void
    ) {
        self.session = session
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _candidates = State(initialValue: session.detectedRegions.map { ChecklistDamageCandidate(region: $0) })
    }

    private var confirmedRegions: [ChecklistDamageRegion] {
        candidates.filter { $0.decision == .confirmed }.map(\.region)
    }

    private var hasUndecidedDetections: Bool {
        candidates.contains { $0.decision == .undecided }
    }

    private var visibleRegions: [ChecklistDamageRegion] {
        candidates.filter { $0.decision != .rejected }.map(\.region)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SubtleHTXBackground().ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Confirm the damage in this photo")
                                .font(.title3.bold())
                            Text("Select Yes or No for every suggested area. If the system missed something, draw the area and choose its damage type.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)

                        ChecklistDamageAnnotatedImage(
                            image: session.image,
                            regions: visibleRegions,
                            showLabels: true
                        )
                        .frame(height: 330)
                        .background(Color.black.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)

                        if candidates.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "viewfinder.circle")
                                    .font(.system(size: 40))
                                    .foregroundColor(HTXTheme.primaryPurple)
                                Text("No damage was found automatically")
                                    .font(.headline)
                                Text("If there is visible damage in the photo, add it manually before attaching the photo.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(22)
                            .subtleHTXCard()
                            .padding(.horizontal)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Suggested damage areas")
                                    .font(.headline)
                                    .padding(.horizontal)

                                ForEach(Array(candidates.indices), id: \.self) { index in
                                    damageCandidateCard(index: index)
                                }
                            }
                        }

                        Button {
                            showManualEditor = true
                        } label: {
                            Label("Draw a Missed Damage Area", systemImage: "square.dashed")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)
                        .tint(HTXTheme.primaryPurple)
                        .padding(.horizontal)

                        if hasUndecidedDetections {
                            Label("Answer Yes or No for every suggested area.", systemImage: "exclamationmark.circle.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.orange)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.horizontal)
                        } else if confirmedRegions.isEmpty {
                            Label("Confirm at least one area or add the damage manually.", systemImage: "exclamationmark.circle.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.orange)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.horizontal)
                        }

                        Button {
                            onConfirm(confirmedRegions)
                        } label: {
                            Text("Attach \(confirmedRegions.count) Confirmed Damage Area\(confirmedRegions.count == 1 ? "" : "s")")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .background(canAttach ? HTXTheme.primaryPurple : Color.gray.opacity(0.45))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .disabled(!canAttach)
                        .padding(.horizontal)
                        .padding(.bottom, 28)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Review Damage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showCancelConfirmation = true }
                }
            }
            .sheet(isPresented: $showManualEditor) {
                ChecklistManualDamageEditor(image: session.image) { region in
                    candidates.append(ChecklistDamageCandidate(region: region, decision: .confirmed))
                }
            }
            .confirmationDialog(
                "Discard this damage photo?",
                isPresented: $showCancelConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard Photo", role: .destructive, action: onCancel)
                Button("Continue Reviewing", role: .cancel) {}
            } message: {
                Text("The photo and your damage decisions will not be attached to the checklist.")
            }
        }
    }

    private var canAttach: Bool {
        !hasUndecidedDetections && !confirmedRegions.isEmpty
    }

    @ViewBuilder
    private func damageCandidateCard(index: Int) -> some View {
        let candidate = candidates[index]
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if let crop = candidate.region.cropImage
                    ?? checklistDamageCrop(image: session.image, bbox: candidate.region.normalizedBBox) {
                    Image(uiImage: crop)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 112, height: 82)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Menu {
                        ForEach(checklistDamageTypes, id: \.self) { type in
                            Button(type.capitalized) {
                                candidates[index].region.damageType = type
                                candidates[index].region.explanation = "\(type.capitalized) identified on the \(angleLabel(for: session.angleIndex))."
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(candidate.region.damageType.capitalized)
                                .font(.headline)
                            Image(systemName: "chevron.down")
                                .font(.caption.bold())
                        }
                        .foregroundColor(HTXTheme.primaryPurple)
                    }

                    Text(candidate.region.isManuallyAdded
                         ? "Added manually"
                         : "AI confidence: \(Int((candidate.region.confidence * 100).rounded()))%")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !candidate.region.explanation.isEmpty {
                        Text(candidate.region.explanation)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()

                if candidate.region.isManuallyAdded {
                    Button(role: .destructive) {
                        candidates.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }

            if candidate.region.isManuallyAdded {
                Label("Confirmed by driver", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.green)
            } else {
                Text("Is this the damage you are reporting?")
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 12) {
                    decisionButton(
                        title: "Yes",
                        icon: "checkmark.circle.fill",
                        selected: candidate.decision == .confirmed,
                        color: .green
                    ) {
                        candidates[index].decision = .confirmed
                    }

                    decisionButton(
                        title: "No",
                        icon: "xmark.circle.fill",
                        selected: candidate.decision == .rejected,
                        color: .red
                    ) {
                        candidates[index].decision = .rejected
                    }
                }
            }
        }
        .padding(14)
        .subtleHTXCard()
        .padding(.horizontal)
    }

    private func decisionButton(
        title: String,
        icon: String,
        selected: Bool,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(selected ? color : Color(.secondarySystemBackground))
                .foregroundColor(selected ? .white : color)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(color.opacity(selected ? 0 : 0.4), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ChecklistManualDamageEditor: View {
    let image: UIImage
    let onAdd: (ChecklistDamageRegion) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var damageType = checklistDamageTypes[0]
    @State private var normalizedBBox: CGRect?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Choose the damage type, then drag a box tightly around the damaged area.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(checklistDamageTypes, id: \.self) { type in
                            Button {
                                damageType = type
                            } label: {
                                Text(type.capitalized)
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(damageType == type ? HTXTheme.primaryPurple : Color(.secondarySystemBackground))
                                    .foregroundColor(damageType == type ? .white : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)

                    GeometryReader { canvas in
                        BoundingBoxOverlayView(
                            image: image,
                            normalizedBBox: $normalizedBBox,
                            accentColor: .orange,
                            isInteractive: true
                        )
                        .frame(
                            width: canvas.size.width,
                            height: canvas.size.height,
                            alignment: .center
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 480)
                    .background(Color.black.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)

                    if let box = normalizedBBox,
                       let preview = checklistDamageAnnotatedCrop(image: image, bbox: box) {
                        VStack(alignment: .center, spacing: 10) {
                            Label("Close-up Preview", systemImage: "magnifyingglass")
                                .font(.subheadline.bold())

                            Image(uiImage: preview)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .frame(maxHeight: 230)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(HTXTheme.primaryPurple.opacity(0.25), lineWidth: 1)
                                )

                            Text("This is the damage close-up that will be attached. Draw again above to replace the boundary.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                    } else {
                        Label("Draw a boundary before adding this damage.", systemImage: "hand.draw")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Add Missed Damage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let region = ChecklistDamageRegion(
                            damageType: damageType,
                            confidence: 1,
                            normalizedBBox: normalizedBBox,
                            cropImage: checklistDamageAnnotatedCrop(image: image, bbox: normalizedBBox),
                            explanation: "\(damageType.capitalized) marked by the driver.",
                            isManuallyAdded: true
                        )
                        onAdd(region)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(normalizedBBox == nil)
                }
            }
        }
    }
}

private struct ChecklistDamageAnnotatedImage: View {
    let image: UIImage
    let regions: [ChecklistDamageRegion]
    let showLabels: Bool

    var body: some View {
        GeometryReader { geometry in
            let imageRect = fittedImageRect(in: geometry.size)

            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)

                ForEach(Array(regions.enumerated()), id: \.element.id) { index, region in
                    if let box = region.normalizedBBox {
                        let rect = CGRect(
                            x: imageRect.minX + box.minX * imageRect.width,
                            y: imageRect.minY + box.minY * imageRect.height,
                            width: box.width * imageRect.width,
                            height: box.height * imageRect.height
                        )

                        Rectangle()
                            .stroke(Color.orange, lineWidth: 2.5)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)

                        if showLabels {
                            Text("D\(index + 1): \(region.damageType.capitalized)")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(Color.orange)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .offset(
                                    x: min(max(imageRect.minX, rect.minX), max(imageRect.minX, imageRect.maxX - 130)),
                                    y: max(imageRect.minY, rect.minY - 24)
                                )
                        }
                    }
                }
            }
        }
    }

    private func fittedImageRect(in container: CGSize) -> CGRect {
        guard image.size.width > 0, image.size.height > 0, container.width > 0, container.height > 0 else {
            return .zero
        }
        let scale = min(container.width / image.size.width, container.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

private func checklistDamageCrop(image: UIImage, bbox: CGRect?) -> UIImage? {
    guard let bbox else { return nil }
    let normalized = image.htxNormalizedImage()
    guard let cgImage = normalized.cgImage else { return nil }

    let paddingX = bbox.width * 0.25
    let paddingY = bbox.height * 0.25
    let padded = CGRect(
        x: max(0, bbox.minX - paddingX),
        y: max(0, bbox.minY - paddingY),
        width: min(1, bbox.maxX + paddingX) - max(0, bbox.minX - paddingX),
        height: min(1, bbox.maxY + paddingY) - max(0, bbox.minY - paddingY)
    )
    let pixelRect = CGRect(
        x: padded.minX * CGFloat(cgImage.width),
        y: padded.minY * CGFloat(cgImage.height),
        width: padded.width * CGFloat(cgImage.width),
        height: padded.height * CGFloat(cgImage.height)
    ).integral

    guard pixelRect.width > 1,
          pixelRect.height > 1,
          let cropped = cgImage.cropping(to: pixelRect) else { return nil }
    return UIImage(cgImage: cropped, scale: 1, orientation: .up)
}

/// Creates the same type of close-up used by the NP299 manual-damage flow:
/// retain some surrounding vehicle context and draw the selected boundary on
/// the cropped image so the driver can verify exactly what will be submitted.
private func checklistDamageAnnotatedCrop(image: UIImage, bbox: CGRect?) -> UIImage? {
    guard let bbox else { return nil }
    let normalized = image.htxNormalizedImage()
    guard let cgImage = normalized.cgImage else { return nil }

    let imageWidth = CGFloat(cgImage.width)
    let imageHeight = CGFloat(cgImage.height)
    let damageRect = CGRect(
        x: bbox.minX * imageWidth,
        y: bbox.minY * imageHeight,
        width: bbox.width * imageWidth,
        height: bbox.height * imageHeight
    ).intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

    guard damageRect.width > 1, damageRect.height > 1 else { return nil }

    let padX = max(damageRect.width * 0.55, imageWidth * 0.01)
    let padY = max(damageRect.height * 0.55, imageHeight * 0.01)
    let cropRect = damageRect
        .insetBy(dx: -padX, dy: -padY)
        .intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        .integral

    guard cropRect.width > 1,
          cropRect.height > 1,
          let croppedCG = cgImage.cropping(to: cropRect) else { return nil }

    let croppedImage = UIImage(cgImage: croppedCG, scale: 1, orientation: .up)
    let localDamageRect = CGRect(
        x: damageRect.minX - cropRect.minX,
        y: damageRect.minY - cropRect.minY,
        width: damageRect.width,
        height: damageRect.height
    ).intersection(CGRect(origin: .zero, size: cropRect.size))

    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: cropRect.size, format: format)

    return renderer.image { _ in
        UIColor.white.setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: cropRect.size)).fill()
        croppedImage.draw(in: CGRect(origin: .zero, size: cropRect.size))

        UIColor.orange.setStroke()
        let safeRect = localDamageRect.insetBy(dx: 1.5, dy: 1.5)
        let path = UIBezierPath(rect: safeRect)
        path.lineWidth = max(cropRect.width * 0.01, 3)
        path.stroke()
    }
}

private func angleLabel(for index: Int) -> String {
    guard scanAngles.indices.contains(index) else { return "vehicle" }
    return scanAngles[index].label
}


// MARK: - Damage Photo Viewer

private struct ChecklistDamagePhotoViewer: View {
    let photo: ChecklistDamagePhoto
    let onClose: () -> Void
    let onReplace: () -> Void
    let onDelete: () -> Void

    @State private var scale: CGFloat = 1
    @State private var previousScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var previousOffset: CGSize = .zero
    @State private var showDeleteConfirmation = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geometry in
                ChecklistDamageAnnotatedImage(
                    image: photo.image,
                    regions: photo.confirmedRegions,
                    showLabels: true
                )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .contentShape(Rectangle())
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = min(max(previousScale * value, 1), 6)
                                    if scale == 1 { offset = .zero }
                                }
                                .onEnded { _ in
                                    previousScale = scale
                                    if scale == 1 {
                                        offset = .zero
                                        previousOffset = .zero
                                    }
                                },
                            DragGesture()
                                .onChanged { value in
                                    guard scale > 1 else { return }
                                    offset = CGSize(
                                        width: previousOffset.width + value.translation.width,
                                        height: previousOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    previousOffset = offset
                                }
                        )
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.3)) {
                            if scale > 1 {
                                scale = 1
                                previousScale = 1
                                offset = .zero
                                previousOffset = .zero
                            } else {
                                scale = 2.5
                                previousScale = 2.5
                            }
                        }
                    }
            }

            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text("Pinch or double-tap to zoom")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                }
                .padding()

                Spacer()

                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(photo.angleLabel)
                                .font(.headline)
                            Text("\(photo.guideCarType.rawValue) silhouette")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Button(action: onReplace) {
                            Label("Replace", systemImage: "arrow.triangle.2.circlepath.camera")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(HTXTheme.primaryPurple)

                        Button {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding()
            }
        }
        .alert("Delete this damage photo?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The photo will be removed from this checklist.")
        }
    }
}

// MARK: - Guided Damage Capture Setup

private struct ChecklistDamageCaptureSetupSheet: View {
    let vehicleName: String
    @Binding var angleIndex: Int
    @Binding var guideCarType: CarType
    let onCancel: () -> Void
    let onTakePhoto: () -> Void
    let onChoosePhoto: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let guideTypes: [CarType] = [.sedan, .suv, .mpv]
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ZStack {
                SubtleHTXBackground().ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Selected Vehicle")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                            Text(vehicleName)
                                .font(.headline)
                                .foregroundColor(HTXTheme.primaryPurple)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Which angle shows the damage?")
                                .font(.headline)

                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(scanAngles) { angle in
                                    Button {
                                        angleIndex = angle.id
                                    } label: {
                                        VStack(spacing: 7) {
                                            Image(systemName: angle.iconName)
                                                .font(.title3)
                                            Text(angle.label)
                                                .font(.subheadline.weight(.semibold))
                                        }
                                        .foregroundColor(angleIndex == angle.id ? .white : HTXTheme.primaryPurple)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(angleIndex == angle.id ? HTXTheme.primaryPurple : Color(.systemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(HTXTheme.primaryPurple.opacity(0.35), lineWidth: 1.5)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            Text(scanAngles[angleIndex].instruction)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Vehicle silhouette")
                                .font(.headline)
                            Text("Choose the outline that most closely matches the vehicle.")
                                .font(.footnote)
                                .foregroundColor(.secondary)

                            HStack(spacing: 10) {
                                ForEach(guideTypes) { type in
                                    Button {
                                        guideCarType = type
                                    } label: {
                                        VStack(spacing: 7) {
                                            Image(systemName: type.icon)
                                                .font(.title3)
                                            Text(type.rawValue)
                                                .font(.caption.weight(.semibold))
                                        }
                                        .foregroundColor(guideCarType == type ? .white : HTXTheme.primaryPurple)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                        .background(guideCarType == type ? HTXTheme.primaryPurple : Color(.systemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(HTXTheme.primaryPurple.opacity(0.35), lineWidth: 1.5)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        VStack(spacing: 10) {
                            Button(action: onTakePhoto) {
                                Label("Open Guided Camera", systemImage: "camera.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            }
                            .background(HTXTheme.primaryPurple)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                            .opacity(UIImagePickerController.isSourceTypeAvailable(.camera) ? 1 : 0.5)

                            Button(action: onChoosePhoto) {
                                Label("Choose Existing Photo", systemImage: "photo.on.rectangle")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)
                            .tint(HTXTheme.primaryPurple)

                            if !UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Text("The simulator has no camera. Choose a photo to test the same angle validation.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Add Damage Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
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
    let damagePhotoSummaries: [String]
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

                        reviewCard(title: "Equipment in Vehicle", icon: "checklist") {
                            if selectedEquipment.isEmpty {
                                reviewRow("Equipment", "None recorded")
                            } else {
                                ForEach(VehicleEquipment.allCases.filter { selectedEquipment.contains($0) }) { item in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(HTXTheme.primaryPurple)
                                        .frame(width: 22)
                                    Text(item.rawValue)
                                        .font(.subheadline)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("Present")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(HTXTheme.primaryPurple)
                                }
                                .padding(.vertical, 6)
                                }
                            }
                        }

                        reviewCard(title: "Body Work Defects / Others", icon: "wrench.and.screwdriver.fill") {
                            reviewRow("Status", bodyworkAllInOrder ? "All in Order" : "Others")
                            if !bodyworkAllInOrder {
                                reviewRow("Details", bodyworkDetails.isEmpty ? "-" : bodyworkDetails)
                            }
                        }

                        reviewCard(title: "New Damage Detected", icon: "camera.fill") {
                            reviewRow("Images Attached", "\(damagePhotoSummaries.count)")
                            ForEach(Array(damagePhotoSummaries.enumerated()), id: \.offset) { index, summary in
                                reviewRow("Photo \(index + 1)", summary)
                            }
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
