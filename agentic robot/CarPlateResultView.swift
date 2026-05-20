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
            VStack(spacing: 20) {
                
                HStack {
                    Text("Car Plate Result")
                        .font(.largeTitle)
                        .bold()
                    
                    Spacer()
                    
                    Button("Logout") {
                        onLogout()
                    }
                    .foregroundColor(.red)
                }
                .padding()
                
                Text("Detected Plate:")
                    .font(.headline)
                
                Text(editablePlate.isEmpty ? "No result" : editablePlate)
                    .font(.system(size: 40, weight: .bold))

                if let plateEditError {
                    Text(plateEditError)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                if let analysisErrorMessage {
                    Text(analysisErrorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Spacer()

                Button {
                    plateDraft = editablePlate
                    plateEditError = nil
                    showEditPlateSheet = true
                } label: {
                    HStack {
                        Image(systemName: "pencil")
                        Text("Edit Licence Plate")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .foregroundColor(.blue)
                    .cornerRadius(14)
                    .padding(.horizontal)
                }
                
                Button {
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
                } label: {
                    Text("Proceed to Scratch Scan")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                        .padding(.horizontal)
                }
                .padding(.bottom, 24)
            }

            if isAnalyzing {
                analyzingOverlay
            }
        }
        .sheet(isPresented: $showEditPlateSheet) {
            editPlateSheet
        }
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
            VStack(alignment: .leading, spacing: 18) {
                Text("Edit Licence Plate")
                    .font(.title2)
                    .bold()

                Text("Update the plate number if the AI detected it wrongly.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("Enter licence plate", text: $plateDraft)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(14)

                Spacer()

                Button {
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
                } label: {
                    Text("Save Plate Number")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        showEditPlateSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var analyzingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(1.3)

                Text("Analyzing your pictures for any dents or scratches...")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let analysisErrorMessage {
                    Text(analysisErrorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(radius: 12)
            .padding(.horizontal, 28)
        }
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
