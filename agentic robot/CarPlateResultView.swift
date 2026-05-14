import SwiftUI

struct CarPlateResultView: View {

    let plate: String
    var onLogout: () -> Void  // ← add this

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Car Plate Result")
                    .font(.largeTitle)
                    .bold()

                Spacer()

                Button("Logout") {
                    onLogout()  // ← call this instead
                }
                .foregroundColor(.red)
            }
            .padding()

            Text("Detected Plate:")
                .font(.headline)

            Text(plate.isEmpty ? "No result" : plate)
                .font(.system(size: 40, weight: .bold))

            Spacer()
        }
    }
}
