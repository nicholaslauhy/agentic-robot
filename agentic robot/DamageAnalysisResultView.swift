import SwiftUI

struct DamageAnalysisResultView: View {

    let plate: String
    let carType: CarType
    let detections: [DamageDetection]
    var onLogout: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Damage Analysis")
                            .font(.largeTitle)
                            .bold()

                        Text("\(carType.rawValue) · \(plate)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Logout") {
                        onLogout()
                    }
                    .foregroundColor(.red)
                }
                .padding(.horizontal)
                .padding(.top)

                if detections.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)

                        Text("No obvious dents or scratches detected")
                            .font(.title3.bold())
                            .multilineTextAlignment(.center)

                        Text("The uploaded angles did not return any damage crops from the analysis server.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    Text("Found \(detections.count) possible damage area\(detections.count == 1 ? "" : "s"). The images below are zoomed-in crops returned by the analysis server.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    LazyVStack(spacing: 16) {
                        ForEach(detections) { detection in
                            DamageDetectionCard(
                                detection: detection,
                                accentColor: carType.accentColor
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 30)
        }
        .navigationBarBackButtonHidden(true)
    }
}

struct DamageDetectionCard: View {

    let detection: DamageDetection
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            
            if let cropImage = detection.cropImage {
                Image(uiImage: cropImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(accentColor.opacity(0.35), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.systemGray5))
                    .frame(height: 220)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundColor(.secondary)
                            
                            Text("Could not load crop image")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(detection.damageType.capitalized)
                        .font(.headline)

                    Text(detection.angleName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("\(Int(detection.confidence * 100))%")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(accentColor.opacity(0.12))
                    .foregroundColor(accentColor)
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
