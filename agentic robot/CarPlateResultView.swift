import SwiftUI

struct CarPlateResultView: View {

    let plate: String
    var onLogout: () -> Void

    @State private var navigateToTypeSelection = false
    @State private var selectedCarType: CarType? = nil
    @State private var navigateToScratchScan = false

    @State private var scannedImages: [UIImage] = []
    @State private var shouldOpenScratchOnReview = false

    @State private var isAnalyzing = false
    @State private var analysisErrorMessage: String? = nil
    @State private var damageDetections: [DamageDetection] = []
    @State private var navigateToDamageResults = false

    private let damageAnalysisService = DamageAnalysisService.shared

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
                
                Text(plate.isEmpty ? "No result" : plate)
                    .font(.system(size: 40, weight: .bold))
                
                if let analysisErrorMessage {
                    Text(analysisErrorMessage)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                Button {
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
        .navigationDestination(isPresented: $navigateToTypeSelection) {
            CarTypeSelectionView(
                plate: plate,
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
                    plate: plate,
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
                    plate: plate,
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
                    
                    // Close ScratchScanView first
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
