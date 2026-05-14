import SwiftUI

struct CarPlateResultView: View {

    let plate: String
    var onLogout: () -> Void

    @State private var navigateToTypeSelection = false
    @State private var selectedCarType: CarType? = nil
    @State private var navigateToScratchScan = false
    @State private var scannedImages: [UIImage] = []

    var body: some View {
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

            Spacer()

            Button {
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
        .navigationDestination(isPresented: $navigateToTypeSelection) {
            CarTypeSelectionView(
                plate: plate,
                onLogout: onLogout,
                onCarTypeSelected: { carType in
                    selectedCarType = carType
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
                    onScanComplete: { images in
                        scannedImages = images
                        // TODO: send images to your server for scratch analysis
                    }
                )
            }
        }
    }
}
