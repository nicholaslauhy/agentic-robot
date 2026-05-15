import SwiftUI

// MARK: - Result List View

struct DamageAnalysisResultView: View {

    let plate: String
    let carType: CarType
    let detections: [DamageDetection]
    var onBackToScratchScan: () -> Void
    var onLogout: () -> Void

    // Detail sheet state
    @State private var selectedDetection: DamageDetection? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {

                // ── Header ────────────────────────────────────────────────────
                HStack(alignment: .top) {
                    // Back button
                    Button {
                        onBackToScratchScan()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .fontWeight(.semibold)
                            Text("Back")
                        }
                        .foregroundColor(carType.accentColor)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Damage Analysis")
                            .font(.title2)
                            .bold()
                            .multilineTextAlignment(.center)
                        Text("\(carType.rawValue) · \(plate)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Spacer()

                    Button("Logout") {
                        onLogout()
                    }
                    .foregroundColor(.red)
                    .frame(width: 80, alignment: .trailing)
                }
                .padding(.horizontal)
                .padding(.top)

                // ── Content ───────────────────────────────────────────────────
                if detections.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)

                        Text("No obvious damage detected")
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
                    Text("Found \(detections.count) possible damage area\(detections.count == 1 ? "" : "s"). Tap a card to see its location on the car.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    LazyVStack(spacing: 20) {
                        ForEach(detections) { detection in
                            DamageDetectionCard(
                                detection: detection,
                                accentColor: carType.accentColor
                            )
                            .onTapGesture {
                                selectedDetection = detection
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 30)
        }
        .navigationBarBackButtonHidden(true)
        // ── Detail sheet ──────────────────────────────────────────────────────
        .sheet(item: $selectedDetection) { detection in
            DamageDetailSheet(
                detection: detection,
                accentColor: carType.accentColor
            )
        }
    }
}

// MARK: - Card

struct DamageDetectionCard: View {

    let detection: DamageDetection
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Crop image ────────────────────────────────────────────────────
            Group {
                if let cropImage = detection.cropImage {
                    Image(uiImage: cropImage)
                        .resizable()
                        .scaledToFit()          // show full crop, no clipping
                        .frame(maxWidth: .infinity)
                } else {
                    ZStack {
                        Color(.systemGray5)
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundColor(.secondary)
                            Text("Could not load image")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(height: 260)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(accentColor.opacity(0.35), lineWidth: 1)
            )

            // ── Labels row ────────────────────────────────────────────────────
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(detection.damageType.capitalized)
                        .font(.headline)
                    Text(detection.angleName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Text("\(Int(detection.confidence * 100))%")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(accentColor.opacity(0.12))
                        .foregroundColor(accentColor)
                        .clipShape(Capsule())

                    // Tap hint — only if context image is available
                    if detection.contextImage != nil {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.top, 10)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        // Subtle press effect
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Detail Sheet

struct DamageDetailSheet: View {

    let detection: DamageDetection
    let accentColor: Color

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var magnifyBy: CGFloat = 1.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // ── Context image (full car with highlighted damage) ───────
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Location on car", systemImage: "viewfinder")
                            .font(.headline)
                            .padding(.horizontal)

                        if let ctxImage = detection.contextImage {
                            Image(uiImage: ctxImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(accentColor.opacity(0.4), lineWidth: 1)
                                )
                                .padding(.horizontal)
                        } else {
                            Text("Context image not available")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        }
                    }

                    Divider().padding(.horizontal)

                    // ── Zoomed crop ───────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Damage close-up", systemImage: "magnifyingglass")
                            .font(.headline)
                            .padding(.horizontal)

                        if let cropImage = detection.cropImage {
                            Image(uiImage: cropImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(accentColor.opacity(0.4), lineWidth: 1)
                                )
                                .padding(.horizontal)
                        }
                    }

                    // ── Metadata ──────────────────────────────────────────────
                    VStack(spacing: 0) {
                        metaRow(label: "Type",       value: detection.damageType.capitalized)
                        Divider()
                        metaRow(label: "Angle",      value: detection.angleName)
                        Divider()
                        metaRow(label: "Confidence", value: "\(Int(detection.confidence * 100))%")
                    }
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
                }
                .padding(.bottom, 30)
            }
            .navigationTitle("Damage Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}
