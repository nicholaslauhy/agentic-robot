import SwiftUI
import Vision

struct CarPlateResultView: View {

    let image: UIImage?
    @EnvironmentObject var auth: AuthViewModel

    @State private var plateText: String = "Detecting..."

    var body: some View {

        VStack(spacing: 20) {

            HStack {
                Text("Car Plate Result")
                    .font(.largeTitle)
                    .bold()

                Spacer()

                Button("Logout") {
                    auth.logout()
                }
                .foregroundColor(.red)
            }
            .padding(.horizontal)

            Text("Detected Car Plate Number:")
                .font(.headline)

            Text(plateText)
                .font(.system(size: 40, weight: .bold))

            Spacer()
        }
        .padding()
        .onAppear {
            recognizeText(from: image)
        }
    }

    func extractCarPlate(from text: String) -> String? {

        let cleaned = text
            .uppercased()
            .replacingOccurrences(of: " ", with: "")

        // Singapore-style plate regex
        let pattern = "[A-Z]{1,3}[0-9]{1,4}[A-Z]"

        if let regex = try? NSRegularExpression(pattern: pattern) {

            let range = NSRange(cleaned.startIndex..<cleaned.endIndex,
                                 in: cleaned)

            if let match = regex.firstMatch(in: cleaned, range: range),
               let matchRange = Range(match.range, in: cleaned) {

                return String(cleaned[matchRange])
            }
        }

        return nil
    }
    
    func recognizeText(from image: UIImage?) {

        guard let image = image,
              let cgImage = image.cgImage else {
            plateText = "No image detected"
            return
        }

        let request = VNRecognizeTextRequest { request, error in

            guard let results = request.results as? [VNRecognizedTextObservation] else {
                return
            }

            let text = results.compactMap {
                $0.topCandidates(1).first?.string
            }.joined(separator: " ")

            DispatchQueue.main.async {

                let cleaned = text
                    .uppercased()
                    .replacingOccurrences(of: " ", with: "")

                if let plate = extractCarPlate(from: cleaned) {
                    plateText = plate
                } else {
                    plateText = "No valid plate detected"
                }
            }
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage)

        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }
}
