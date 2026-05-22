import SwiftUI

struct CarPlateResultView: View {

    let plate: String
    var onLogout: () -> Void

    @State private var editablePlate: String
    @State private var plateDraft: String = ""
    @State private var showEditPlateSheet = false
    @State private var plateEditError: String? = nil

    @State private var navigateToTypeSelection = false
    @State private var selectedCarType: CarType? = nil
    @State private var navigateToScratchScan = false

    @State private var scannedImages: [UIImage] = []
    @State private var shouldOpenScratchOnReview = false

    @State private var isAnalyzing = false
    @State private var analysisErrorMessage: String? = nil
    @State private var damageDetections: [DamageDetection] = []
    @State private var navigateToDamageResults = false

    @State private var didRunTypewriter = false

    private let damageAnalysisService = DamageAnalysisService.shared

    init(
        plate: String,
        onLogout: @escaping () -> Void
    ) {
        self.plate = plate
        self.onLogout = onLogout
        _editablePlate = State(initialValue: plate)
    }

    var body: some View {
        ZStack {
            HTXBackground()

            VStack(spacing: 20) {
                HTXScreenHeader(
                    title: "Car Plate Result",
                    subtitle: "Confirm vehicle identity",
                    trailing: AnyView(HTXLogoutButton { onLogout() })
                )
                .padding(.horizontal, 20)
                .padding(.top, 18)

                Spacer(minLength: 20)

                HTXCard {
                    VStack(spacing: 18) {
                        Image(systemName: "licenseplate.fill")
                            .font(.system(size: 46, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [HTXTheme.cyan, HTXTheme.accentBright],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Text("Detected Plate")
                            .font(.headline)
                            .foregroundColor(HTXTheme.accent.opacity(0.9))

                        Text(editablePlate.isEmpty ? "No result" : editablePlate)
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .tracking(2)
                            .foregroundColor(.white)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))

                        if let plateEditError {
                            HTXAlert(message: plateEditError, isError: true)
                        }

                        if let analysisErrorMessage {
                            HTXAlert(message: analysisErrorMessage, isError: true)
                        }

                        VStack(spacing: 12) {
                            HTXPrimaryButton("PROCEED TO SCRATCH SCAN") {
                                let cleanedPlate = editablePlate
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .uppercased()

                                guard !cleanedPlate.isEmpty else {
                                    plateEditError = "Please enter a valid licence plate number."
                                    return
                                }

                                editablePlate = cleanedPlate
                                shouldOpenScratchOnReview = false
                                navigateToTypeSelection = true
                            }

                            HTXSecondaryButton("Edit Licence Plate", systemImage: "pencil") {
                                plateDraft = editablePlate
                                plateEditError = nil
                                showEditPlateSheet = true
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 34)
            }

            if isAnalyzing {
                analyzingOverlay
            }
        }
        .sheet(isPresented: $showEditPlateSheet) {
            editPlateSheet
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $navigateToTypeSelection) {
            CarTypeSelectionView(
                plate: editablePlate,
                onLogout: onLogout,
                onCarTypeSelected: { carType in
                    selectedCarType = carType
                    shouldOpenScratchOnReview = false
                    navigateToScratchScan = true
                }
            )
        }
        .navigationDestination(isPresented: $navigateToScratchScan) {
            if let carType = selectedCarType {
                ScratchScanView(
                    plate: editablePlate,
                    carType: carType,
                    onLogout: onLogout,
                    onBackToPlateResult: {
                        navigateToScratchScan = false
                        navigateToTypeSelection = false
                    },
                    initialImages: shouldOpenScratchOnReview ? scannedImages : [],
                    startOnReviewScreen: shouldOpenScratchOnReview,
                    onScanComplete: { images, finishLoading in
                        scannedImages = images
                        startDamageAnalysis(
                            images: images,
                            carType: carType,
                            finishLoading: finishLoading
                        )
                    }
                )
            }
        }
        .navigationDestination(isPresented: $navigateToDamageResults) {
            if let carType = selectedCarType {
                DamageAnalysisResultView(
                    plate: editablePlate,
                    carType: carType,
                    detections: damageDetections,
                    scanImages: scannedImages,
                    onBackToScratchScan: {
                        navigateToDamageResults = false
                        shouldOpenScratchOnReview = true

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            navigateToScratchScan = true
                        }
                    },
                    onLogout: onLogout
                )
            }
        }
        .onDisappear {
            didRunTypewriter = false
        }
    }

    private var editPlateSheet: some View {
        NavigationStack {
            ZStack {
                HTXBackground()

                VStack(alignment: .leading, spacing: 18) {
                    Text("Edit Licence Plate")
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    Text("Update the plate number if the AI detected it wrongly.")
                        .font(.subheadline)
                        .foregroundColor(HTXTheme.accent.opacity(0.9))

                    TextField("Enter licence plate", text: $plateDraft)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .tint(HTXTheme.accentBright)
                        .padding()
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.2), lineWidth: 1))

                    Spacer()

                    HTXPrimaryButton("SAVE PLATE NUMBER") {
                        let cleanedPlate = plateDraft
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .uppercased()

                        guard !cleanedPlate.isEmpty else {
                            plateEditError = "Please enter a valid licence plate number."
                            return
                        }

                        editablePlate = cleanedPlate
                        plateEditError = nil
                        showEditPlateSheet = false
                    }
                }
                .padding(22)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        showEditPlateSheet = false
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var analyzingOverlay: some View {
        HTXLoadingOverlay(message: "Analyzing your pictures for any dents or scratches...")
    }

    private func startDamageAnalysis(
        images: [UIImage],
        carType: CarType,
        finishLoading: @escaping () -> Void
    ) {
        if isAnalyzing {
            return
        }

        isAnalyzing = true
        analysisErrorMessage = nil

        Task {
            do {
                let results = try await damageAnalysisService.analyze(images: images)
                
                await MainActor.run {
                    print("Damage analysis succeeded")
                    print("Result count:", results.count)
                    
                    scannedImages = images
                    damageDetections = results
                    isAnalyzing = false
                    finishLoading()
                    
                    navigateToScratchScan = false
                }
                
                try? await Task.sleep(nanoseconds: 300_000_000)

                await MainActor.run {
                    navigateToDamageResults = true
                }

            } catch {
                await MainActor.run {
                    print("Damage analysis failed:", error)

                    isAnalyzing = false
                    analysisErrorMessage = "Damage analysis failed: \(error.localizedDescription)"
                    finishLoading()
                }
            }
        }
    }
}
