import PhotosUI
import SwiftUI
import UIKit

struct DetailedPanelCapture: Identifiable {
    let panel: DetailedVehiclePanel
    let image: UIImage

    var id: String { panel.id }
}

/// Optional close-up capture performed after the four overview photographs.
/// These images are kept separate from the four-angle baseline so later phases
/// can analyse and project them without changing the existing baseline format.
struct DetailedVehicleScanView: View {
    let plate: String
    let carType: CarType
    let onCancel: () -> Void
    let onComplete: ([DetailedPanelCapture]) -> Void

    @State private var selectedPanel = DetailedVehicleScanSpecification.panels[0]
    @State private var captures: [DetailedVehiclePanel: UIImage] = [:]
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showExitConfirmation = false
    @State private var errorMessage: String?

    private var currentIndex: Int {
        DetailedVehicleScanSpecification.panels.firstIndex(of: selectedPanel) ?? 0
    }

    private var progress: Double {
        Double(captures.count) / Double(max(1, DetailedVehicleScanSpecification.panels.count))
    }

    private var orderedCaptures: [DetailedPanelCapture] {
        DetailedVehicleScanSpecification.panels.compactMap { panel in
            captures[panel].map { DetailedPanelCapture(panel: panel, image: $0) }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SubtleHTXBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        header
                        progressCard
                        panelGuideCard
                        captureCard
                        panelStrip
                        actionButtons
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") {
                        if captures.isEmpty {
                            onCancel()
                        } else {
                            showExitConfirmation = true
                        }
                    }
                }
            }
            .confirmationDialog(
                "Leave Detailed Scan?",
                isPresented: $showExitConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard Detailed Photos", role: .destructive) { onCancel() }
                Button("Continue Scanning", role: .cancel) {}
            } message: {
                Text("The detailed photos captured in this scan will be discarded. Your four overview photos will not be affected.")
            }
            .fullScreenCover(isPresented: $showCamera) {
                ImagePicker(
                    sourceType: .camera,
                    completionHandler: { image in
                        store(image)
                        showCamera = false
                    },
                    cancellationHandler: { showCamera = false }
                )
                .ignoresSafeArea()
            }
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self),
                              let image = UIImage(data: data) else {
                            await MainActor.run {
                                errorMessage = "The selected photo could not be opened."
                                selectedPhotoItem = nil
                            }
                            return
                        }
                        await MainActor.run {
                            store(image)
                            selectedPhotoItem = nil
                        }
                    } catch {
                        await MainActor.run {
                            errorMessage = "The selected photo could not be opened: \(error.localizedDescription)"
                            selectedPhotoItem = nil
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Optional Detailed Scan")
                .font(.largeTitle.bold())
                .foregroundColor(HTXTheme.primaryPurple)
            Text("\(carType.rawValue) · \(plate)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Capture one close-up for each highlighted vehicle panel. This does not replace the four overview images.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .padding(.top, 18)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Detailed coverage")
                    .font(.headline)
                Spacer()
                Text("\(captures.count) of \(DetailedVehicleScanSpecification.panels.count)")
                    .font(.subheadline.bold())
                    .foregroundColor(HTXTheme.primaryPurple)
            }
            ProgressView(value: progress)
                .tint(HTXTheme.primaryPurple)
        }
        .padding()
        .background(HTXTheme.softPurpleCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var panelGuideCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Panel \(currentIndex + 1) of \(DetailedVehicleScanSpecification.panels.count)")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Text(selectedPanel.displayName)
                        .font(.title2.bold())
                        .foregroundColor(HTXTheme.primaryPurple)
                }
                Spacer()
                Text(selectedPanel.overviewAngle.label)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(HTXTheme.primaryPurple.opacity(0.12))
                    .foregroundColor(HTXTheme.primaryPurple)
                    .clipShape(Capsule())
            }

            ZStack {
                CarSilhouetteView(
                    carType: carType,
                    angleId: selectedPanel.overviewAngle.rawValue
                )

                DetailedPanelHighlightOverlay(panel: selectedPanel)
            }
            .frame(maxWidth: 780)
            .frame(height: 280)
            .frame(maxWidth: .infinity)
            .background(HTXTheme.softPurpleCard.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .topLeading) {
                Label(selectedPanel.displayName, systemImage: "viewfinder")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial)
                    .foregroundColor(HTXTheme.primaryPurple)
                    .clipShape(Capsule())
                    .padding(10)
            }

            DetailedScanSweepGuide()

            VStack(alignment: .leading, spacing: 6) {
                Label(selectedPanel.coverageHint, systemImage: "camera.viewfinder")
                Label(DetailedVehicleScanSpecification.operatorInstruction, systemImage: "arrow.left.and.right")
            }
            .font(.footnote)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(HTXTheme.softPurpleBorder, lineWidth: 1))
    }

    private var captureCard: some View {
        Group {
            if let image = captures[selectedPanel] {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    Label("Captured", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.green.opacity(0.92))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .padding(10)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 42))
                        .foregroundColor(HTXTheme.primaryPurple)
                    Text("No photo captured for this panel")
                        .font(.headline)
                    Text("Keep the panel centred and fill most of the frame.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 190)
                .background(HTXTheme.softPurpleCard)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var panelStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(DetailedVehicleScanSpecification.panels) { panel in
                    Button {
                        selectedPanel = panel
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(captures[panel] == nil ? Color(.systemGray5) : Color.green.opacity(0.18))
                                    .frame(width: 38, height: 38)
                                Image(systemName: captures[panel] == nil ? "camera" : "checkmark")
                                    .font(.caption.bold())
                                    .foregroundColor(captures[panel] == nil ? .secondary : .green)
                            }
                            Text("\(panel.sequenceNumber)")
                                .font(.caption2.bold())
                        }
                        .padding(8)
                        .background(selectedPanel == panel ? HTXTheme.primaryPurple.opacity(0.13) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Panel \(panel.sequenceNumber), \(panel.displayName)")
                }
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemBackground))
                        .foregroundColor(HTXTheme.primaryPurple)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                        errorMessage = "Camera is not available on this device. Choose a photo from the library instead."
                        return
                    }
                    errorMessage = nil
                    showCamera = true
                } label: {
                    Label("Open Camera", systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(HTXTheme.primaryPurple)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            Button {
                onComplete(orderedCaptures)
            } label: {
                Label("Complete Detailed Scan", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(captures.count == DetailedVehicleScanSpecification.panels.count ? HTXTheme.primaryPurple : Color(.systemGray4))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(captures.count != DetailedVehicleScanSpecification.panels.count)
        }
    }

    private func store(_ image: UIImage) {
        captures[selectedPanel] = image.htxNormalizedImage()
        errorMessage = nil

        guard let next = DetailedVehicleScanSpecification.panels
            .dropFirst(currentIndex + 1)
            .first(where: { captures[$0] == nil }) else { return }
        withAnimation { selectedPanel = next }
    }
}

private struct DetailedPanelHighlightOverlay: View {
    let panel: DetailedVehiclePanel

    var body: some View {
        GeometryReader { geometry in
            let rect = highlightRect(in: geometry.size)

            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            HTXTheme.primaryPurple.opacity(0.10),
                            HTXTheme.primaryPurple.opacity(0.38),
                            Color.cyan.opacity(0.20)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(HTXTheme.primaryPurple, style: StrokeStyle(lineWidth: 3, dash: [9, 6]))
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .shadow(color: HTXTheme.primaryPurple.opacity(0.20), radius: 8)
                .allowsHitTesting(false)
        }
        .accessibilityHidden(true)
    }

    private func highlightRect(in size: CGSize) -> CGRect {
        let normalized: CGRect

        switch panel {
        case .frontUpper, .rearUpper:
            normalized = CGRect(x: 0.30, y: 0.31, width: 0.40, height: 0.25)
        case .frontLower, .rearLower:
            normalized = CGRect(x: 0.25, y: 0.57, width: 0.50, height: 0.20)
        case .leftFrontQuarter, .rightRearQuarter:
            normalized = CGRect(x: 0.15, y: 0.49, width: 0.18, height: 0.25)
        case .leftFrontDoor, .rightRearDoor:
            normalized = CGRect(x: 0.31, y: 0.47, width: 0.19, height: 0.27)
        case .leftRearDoor, .rightFrontDoor:
            normalized = CGRect(x: 0.50, y: 0.47, width: 0.18, height: 0.27)
        case .leftRearQuarter, .rightFrontQuarter:
            normalized = CGRect(x: 0.67, y: 0.49, width: 0.18, height: 0.25)
        }

        return CGRect(
            x: normalized.minX * size.width,
            y: normalized.minY * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height
        )
    }
}

private struct DetailedScanSweepGuide: View {
    @State private var sweepToRight = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Start −20°", systemImage: "camera.fill")
                Spacer()
                Text("Straight")
                Spacer()
                Label("End +20°", systemImage: "camera.fill")
            }
            .font(.caption.bold())
            .foregroundColor(.secondary)

            GeometryReader { geometry in
                let markerSize: CGFloat = 34
                let travel = max(0, geometry.size.width - markerSize)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.cyan.opacity(0.28),
                                    HTXTheme.primaryPurple.opacity(0.72),
                                    Color.cyan.opacity(0.28)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 12)

                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: markerSize))
                        .foregroundStyle(.white, HTXTheme.primaryPurple)
                        .offset(x: sweepToRight ? travel : 0)
                }
                .frame(height: markerSize)
                .onAppear {
                    guard !sweepToRight else { return }
                    withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                        sweepToRight = true
                    }
                }
            }
            .frame(height: 34)

            Text("Move around the highlighted panel in one slow sweep. Keep the panel centred; do not only rotate the iPad from one spot.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .background(HTXTheme.softPurpleCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Move from minus 20 degrees through straight on to plus 20 degrees around the highlighted panel")
    }
}
