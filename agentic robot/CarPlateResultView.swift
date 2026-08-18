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
    @State private var damageAnalysisTask: Task<Void, Never>? = nil
    @StateObject private var damageProgress = HTXProgressTracker()
    
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
            SubtleHTXBackground()

            VStack(spacing: 20) {
                
                HStack {
                    Text("Licence Plate Result")
                        .font(.largeTitle.weight(.bold))
                        .foregroundColor(HTXTheme.primaryPurple)
                    
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
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .foregroundColor(HTXTheme.primaryPurple)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(HTXTheme.primaryPurple.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

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
                    .foregroundColor(HTXTheme.primaryPurple)
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
                        .background(HTXTheme.primaryPurple)
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
                    onScanComplete: { images, angleIndices, finishLoading in
                        scannedImages = images
                        startDamageAnalysis(
                            images: images,
                            angleIndices: angleIndices,
                            carType: carType,
                            finishLoading: finishLoading
                        )
                    },
                    onCancelAnalysis: cancelDamageAnalysis
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

                HTXFieldLabel(
                    text: "Licence Plate",
                    required: true,
                    color: HTXTheme.primaryPurple,
                    font: .caption.weight(.semibold)
                )

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
                        .background(HTXTheme.primaryPurple)
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

            HTXProcessingProgressOverlay(
                title: "Analyzing vehicle damage…",
                message: "Comparing all vehicle views with previous damage records.",
                progress: damageProgress.value,
                accentColor: HTXTheme.primaryPurple,
                onCancel: cancelDamageAnalysis
            )
        }
    }

    private func startDamageAnalysis(
        images: [UIImage],
        angleIndices: [Int],
        carType: CarType,
        finishLoading: @escaping () -> Void
    ) {
        if isAnalyzing {
            return
        }

        isAnalyzing = true
        analysisErrorMessage = nil
        damageProgress.start(estimatedDuration: 75)

        damageAnalysisTask = Task {
            do {
                let results = try await damageAnalysisService.analyzeForPlate(plate: editablePlate, images: images, angleIndices: angleIndices)
                
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    print("Damage analysis succeeded")
                    print("Result count:", results.count)

                    damageProgress.completeAnimated {
                        scannedImages = images
                        damageDetections = results
                        isAnalyzing = false
                        damageAnalysisTask = nil
                        finishLoading()

                        // ScratchScanView also animates its visible progress bar
                        // to 100% before this navigation occurs.
                        Task {
                            try? await Task.sleep(for: .milliseconds(900))
                            navigateToScratchScan = false
                            navigateToDamageResults = true
                        }
                    }
                }

            } catch {
                await MainActor.run {
                    print("Damage analysis failed:", error)

                    damageProgress.stop()
                    isAnalyzing = false
                    damageAnalysisTask = nil
                    if error is CancellationError || (error as? URLError)?.code == .cancelled {
                        analysisErrorMessage = "Damage analysis was cancelled."
                    } else {
                        analysisErrorMessage = "Damage analysis failed: \(error.localizedDescription)"
                    }
                    finishLoading()
                }
            }
        }
    }

    private func cancelDamageAnalysis() {
        damageAnalysisTask?.cancel()
        damageAnalysisTask = nil
        damageProgress.stop()
        isAnalyzing = false
        analysisErrorMessage = "Damage analysis was cancelled."
    }
}
