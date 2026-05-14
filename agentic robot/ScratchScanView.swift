import SwiftUI
import PhotosUI

// MARK: - Scan Angle Model

struct ScanAngle: Identifiable {
    let id: Int
    let label: String
    let instruction: String
    let iconName: String
}

let scanAngles: [ScanAngle] = [
    ScanAngle(id: 0, label: "Front",      instruction: "Stand in front — aim at the bonnet",    iconName: "car.front.waves.up"),
    ScanAngle(id: 1, label: "Rear",       instruction: "Stand behind — aim at the boot",         iconName: "car.rear.waves.up"),
    ScanAngle(id: 2, label: "Left Side",  instruction: "Stand on the left side of the vehicle",  iconName: "arrow.left.square"),
    ScanAngle(id: 3, label: "Right Side", instruction: "Stand on the right side of the vehicle", iconName: "arrow.right.square"),
]

// MARK: - Main View

struct ScratchScanView: View {

    let plate: String
    let carType: CarType
    var onLogout: () -> Void
    var onScanComplete: ([UIImage]) -> Void

    @State private var currentAngleIndex = 0
    @State private var capturedImages: [UIImage?] = Array(repeating: nil, count: 4)
    @State private var showCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showCompletionScreen = false
    @State private var localErrorMessage: String? = nil

    // Replace state — kept separate and stable
    @State private var replacingIndex: Int? = nil
    @State private var showReplaceActionSheet = false
    @State private var showReplaceCamera = false
    @State private var replacePhotoItem: PhotosPickerItem?

    private var capturedCount: Int { capturedImages.compactMap { $0 }.count }
    private var progress: Double { Double(capturedCount) / Double(scanAngles.count) }

    var body: some View {
        VStack(spacing: 0) {

            // HEADER
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scratch Scan")
                        .font(.largeTitle).bold()
                    Text("\(carType.rawValue)  ·  \(plate)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Logout") { onLogout() }
                    .foregroundColor(.red)
            }
            .padding()

            // PROGRESS BAR
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(capturedCount) of \(scanAngles.count) angles captured")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.caption.bold()).foregroundColor(carType.accentColor)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray5)).frame(height: 8)
                        RoundedRectangle(cornerRadius: 4).fill(carType.accentColor)
                            .frame(width: geo.size.width * progress, height: 8)
                            .animation(.spring(response: 0.5), value: progress)
                    }
                }
                .frame(height: 8)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)

            if showCompletionScreen {
                reviewView
            } else {
                scanGuideView
            }
        }
        .navigationBarBackButtonHidden(true)

        // ── Main capture sheets ────────────────────────────────────────────
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera) { image in
                capturedImages[currentAngleIndex] = image
                advanceOrComplete()
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        capturedImages[currentAngleIndex] = uiImage
                        selectedPhotoItem = nil
                        advanceOrComplete()
                    }
                }
            }
        }

        // ── Replace sheets — triggered ONLY after confirmationDialog fires ─
        .sheet(isPresented: $showReplaceCamera) {
            ImagePicker(sourceType: .camera) { image in
                if let idx = replacingIndex {
                    capturedImages[idx] = image
                }
                replacingIndex = nil
            }
        }
        .onChange(of: replacePhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        if let idx = replacingIndex {
                            capturedImages[idx] = uiImage
                        }
                        replacePhotoItem = nil
                        replacingIndex = nil
                    }
                }
            }
        }

        // ── Replace action sheet — lives at root so it always fires ────────
        .confirmationDialog(
            replacingIndex != nil ? "Replace \(scanAngles[replacingIndex!].label) Photo" : "Replace Photo",
            isPresented: $showReplaceActionSheet,
            titleVisibility: .visible
        ) {
            Button("Take New Photo") {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showReplaceCamera = true
                } else {
                    localErrorMessage = "Camera is not available on this device."
                    replacingIndex = nil
                }
            }
            // PhotosPicker can't sit inside confirmationDialog — use a workaround
            Button("Choose from Library") {
                // We trigger this via a hidden PhotosPicker driven by replacePhotoItem
                // Set a flag so the picker sheet appears
                showReplaceLibrary = true
            }
            Button("Cancel", role: .cancel) {
                replacingIndex = nil
            }
        }
        .sheet(isPresented: $showReplaceLibrary) {
            ReplaceLibraryPicker(selectedItem: $replacePhotoItem)
        }
    }

    @State private var showReplaceLibrary = false

    // MARK: - Advance or Complete

    private func advanceOrComplete() {
        if currentAngleIndex < scanAngles.count - 1 {
            withAnimation { currentAngleIndex += 1 }
        } else {
            withAnimation { showCompletionScreen = true }
        }
    }

    // MARK: - Scan Guide View

    private var scanGuideView: some View {
        VStack(spacing: 16) {

            // SILHOUETTE
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))

                CarSilhouetteView(carType: carType, angleId: currentAngleIndex)
                    .padding(20)
            }
            .frame(height: 250)
            .padding(.horizontal)

            // INSTRUCTION CARD
            HStack(spacing: 16) {
                Image(systemName: scanAngles[currentAngleIndex].iconName)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(carType.accentColor)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(scanAngles[currentAngleIndex].label).font(.headline)
                    Text(scanAngles[currentAngleIndex].instruction)
                        .font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
            .padding(.horizontal)

            // THUMBNAIL STRIP
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<scanAngles.count, id: \.self) { idx in
                        AngleThumbnail(
                            label: scanAngles[idx].label,
                            image: capturedImages[idx],
                            isCurrent: idx == currentAngleIndex,
                            accentColor: carType.accentColor
                        )
                        .onTapGesture { withAnimation { currentAngleIndex = idx } }
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 90)

            if let err = localErrorMessage {
                Text(err).foregroundColor(.red).font(.footnote)
                    .multilineTextAlignment(.center).padding(.horizontal)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { localErrorMessage = nil }
                    }
            }

            Spacer()

            // BACK + CAPTURE BUTTONS
            HStack(spacing: 12) {
                if currentAngleIndex > 0 {
                    Button {
                        withAnimation { currentAngleIndex -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 52, height: 52)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                    }
                }

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity).padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                }

                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        localErrorMessage = nil
                        showCamera = true
                    } else {
                        localErrorMessage = "Camera is not available on this device."
                    }
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity).padding()
                        .background(carType.accentColor).foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .animation(.easeInOut, value: currentAngleIndex)
    }

    // MARK: - Review View

    private var reviewView: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                    Text("All Angles Captured").font(.title2.bold())
                }
                .padding(.top, 8)

                Text("Tap any photo to replace it before submitting.")
                    .font(.subheadline).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(0..<scanAngles.count, id: \.self) { idx in
                        ReviewThumbnail(
                            label: scanAngles[idx].label,
                            image: capturedImages[idx],
                            accentColor: carType.accentColor
                        ) {
                            replacingIndex = idx
                            showReplaceActionSheet = true
                        }
                    }
                }
                .padding(.horizontal)

                if let err = localErrorMessage {
                    Text(err).foregroundColor(.red).font(.footnote)
                        .multilineTextAlignment(.center).padding(.horizontal)
                }

                Button {
                    onScanComplete(capturedImages.compactMap { $0 })
                } label: {
                    Text("Submit for Analysis")
                        .font(.headline).frame(maxWidth: .infinity).padding()
                        .background(carType.accentColor).foregroundColor(.white)
                        .cornerRadius(14).padding(.horizontal)
                }
                .padding(.bottom, 32)
            }
        }
    }
}

// MARK: - Replace Library Picker (sheet wrapper)
// PhotosPicker can't be used inside confirmationDialog, so we wrap it in a sheet

struct ReplaceLibraryPicker: UIViewControllerRepresentable {
    @Binding var selectedItem: PhotosPickerItem?
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIViewController {
        // Present a PHPickerViewController directly
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ReplaceLibraryPicker
        init(_ parent: ReplaceLibraryPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else {
                parent.dismiss()
                return
            }
            result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                if let image = object as? UIImage {
                    DispatchQueue.main.async {
                        // Convert UIImage back to PhotosPickerItem isn't possible,
                        // so we store the image directly via a notification
                        NotificationCenter.default.post(
                            name: .replacePickerImage,
                            object: image
                        )
                        self.parent.dismiss()
                    }
                }
            }
        }
    }
}

extension Notification.Name {
    static let replacePickerImage = Notification.Name("replacePickerImage")
}

// MARK: - Angle Thumbnail

struct AngleThumbnail: View {
    let label: String
    let image: UIImage?
    let isCurrent: Bool
    let accentColor: Color

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCurrent ? accentColor.opacity(0.15) : Color(.systemGray6))
                    .frame(width: 60, height: 60)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(isCurrent ? accentColor : Color.clear, lineWidth: 2))
                if let img = image {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 60, height: 60).clipShape(RoundedRectangle(cornerRadius: 8))
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        .background(Circle().fill(Color.white).padding(1))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(3)
                } else {
                    Image(systemName: isCurrent ? "camera.fill" : "circle.dashed")
                        .foregroundColor(isCurrent ? accentColor : .secondary)
                }
            }
            Text(label).font(.system(size: 9, weight: isCurrent ? .bold : .regular))
                .foregroundColor(isCurrent ? accentColor : .secondary).lineLimit(1)
        }
        .frame(width: 64)
    }
}

// MARK: - Review Thumbnail

struct ReviewThumbnail: View {
    let label: String
    let image: UIImage?
    let accentColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {

            ZStack(alignment: .bottomLeading) {

                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))

                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                }

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.75),
                        Color.clear
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )

                HStack {
                    Text(label)
                        .font(.caption.bold())
                        .foregroundColor(.white)

                    Spacer()

                    Image(systemName: "pencil.circle.fill")
                        .foregroundColor(.white)
                }
                .padding(10)
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(accentColor.opacity(0.35), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Car Silhouette View
// Uses SwiftUI Path with bezier curves for realistic vehicle shapes

struct CarSilhouetteView: View {
    let carType: CarType
    let angleId: Int   // 0=Front, 1=Rear, 2=Left, 3=Right

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                silhouettePath(w: w, h: h)
                detailOverlay(w: w, h: h)
                angleLabel(w: w, h: h)
            }
        }
    }

    // MARK: Main body path

    @ViewBuilder
    private func silhouettePath(w: CGFloat, h: CGFloat) -> some View {
        switch angleId {
        case 0:
            FrontFaceShape(carType: carType)
                .fill(Color(.systemGray3))

        case 1:
            RearFaceShape(carType: carType)
                .fill(Color(.systemGray3))

        case 2:
            SideProfileShape(carType: carType, flipped: false)
                .fill(Color(.systemGray3))

        case 3:
            SideProfileShape(carType: carType, flipped: true)
                .fill(Color(.systemGray3))

        default:
            EmptyView()
        }
    }

    // MARK: Light/detail overlay drawn on top

    @ViewBuilder
    private func detailOverlay(w: CGFloat, h: CGFloat) -> some View {
        switch angleId {
        case 0: FrontDetailOverlay(carType: carType, w: w, h: h)
        case 1: RearDetailOverlay(carType: carType, w: w, h: h)
        case 2: SideDetailOverlay(carType: carType, w: w, h: h, flipped: false)
        case 3: SideDetailOverlay(carType: carType, w: w, h: h, flipped: true)
        default: EmptyView()
        }
    }

    private func angleLabel(w: CGFloat, h: CGFloat) -> some View {
        Text(scanAngles[angleId].label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.secondary)
            .frame(width: w, alignment: .center)
            .position(x: w / 2, y: h - 8)
    }
}

// MARK: - Front Face Shape

struct FrontFaceShape: Shape {
    let carType: CarType

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = w / 2
        let isLarge = carType.category == .scdf
        let isTall  = carType == .suv || carType == .mpv || isLarge

        // Proportions
        let bodyW  = w * (isLarge ? 0.82 : 0.72)
        let bodyH  = h * (isTall  ? 0.32 : 0.26)
        let roofW  = w * (isTall  ? 0.62 : 0.50)
        let roofH  = h * (isTall  ? 0.26 : 0.22)
        let groundY = h * 0.78
        let bodyTop = groundY - bodyH
        let wheelR  = w * (isLarge ? 0.11 : 0.09)

        var p = Path()

        // Body — slightly trapezoidal (wider at bottom)
        let bx = cx - bodyW / 2
        p.move(to: CGPoint(x: bx + 6, y: bodyTop))
        p.addLine(to: CGPoint(x: bx + bodyW - 6, y: bodyTop))
        p.addQuadCurve(to: CGPoint(x: bx + bodyW, y: bodyTop + 8), control: CGPoint(x: bx + bodyW, y: bodyTop))
        p.addLine(to: CGPoint(x: bx + bodyW + (isTall ? 4 : 0), y: groundY - wheelR * 0.6))
        p.addLine(to: CGPoint(x: bx - (isTall ? 4 : 0), y: groundY - wheelR * 0.6))
        p.addQuadCurve(to: CGPoint(x: bx + 6, y: bodyTop), control: CGPoint(x: bx, y: bodyTop))
        p.closeSubpath()

        // Roof
        let rx = cx - roofW / 2
        let roofBottom = bodyTop + 4
        let roofTop = roofBottom - roofH
        p.move(to: CGPoint(x: rx + roofW * 0.08, y: roofBottom))
        p.addLine(to: CGPoint(x: rx + roofW * 0.92, y: roofBottom))
        p.addQuadCurve(to: CGPoint(x: rx + roofW * 0.92, y: roofTop + 6),
                       control: CGPoint(x: rx + roofW, y: roofBottom - 4))
        p.addQuadCurve(to: CGPoint(x: rx + roofW * 0.08, y: roofTop + 6),
                       control: CGPoint(x: cx, y: roofTop))
        p.addQuadCurve(to: CGPoint(x: rx + roofW * 0.08, y: roofBottom),
                       control: CGPoint(x: rx, y: roofBottom - 4))
        p.closeSubpath()

        // Wheels (arches)
        let wlCx = cx - bodyW * 0.30
        let wrCx = cx + bodyW * 0.30
        for wheelCx in [wlCx, wrCx] {
            p.addEllipse(in: CGRect(x: wheelCx - wheelR, y: groundY - wheelR,
                                    width: wheelR * 2, height: wheelR * 2))
        }

        return p
    }
}

// MARK: - Rear Face Shape

struct RearFaceShape: Shape {
    let carType: CarType

    func path(in rect: CGRect) -> Path {
        // Rear is visually very similar to front — same shape, details differ
        FrontFaceShape(carType: carType).path(in: rect)
    }
}

// MARK: - Side Profile Shape

struct SideProfileShape: Shape {
    let carType: CarType
    let flipped: Bool

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let isLarge = carType.category == .scdf
        let isSUV   = carType == .suv
        let isMPV   = carType == .mpv

        let groundY = h * 0.80
        let wheelR  = w * (isLarge ? 0.10 : 0.085)
        let bodyH   = h * (isLarge ? 0.34 : isMPV ? 0.30 : isSUV ? 0.28 : 0.24)
        let bodyW   = w * (isLarge ? 0.88 : 0.84)
        let bodyLeft = (w - bodyW) / 2
        let bodyRight = bodyLeft + bodyW
        let bodyTop  = groundY - bodyH

        // Wheel centres
        let frontWX = flipped ? bodyRight - bodyW * 0.22 : bodyLeft + bodyW * 0.22
        let rearWX  = flipped ? bodyRight - bodyW * 0.75 : bodyLeft + bodyW * 0.75

        var p = Path()

        if isLarge {
            // Boxy truck / fire engine profile
            p.move(to: CGPoint(x: bodyLeft, y: groundY - wheelR * 0.5))
            p.addLine(to: CGPoint(x: bodyLeft, y: bodyTop))
            p.addLine(to: CGPoint(x: bodyRight, y: bodyTop))
            p.addLine(to: CGPoint(x: bodyRight, y: groundY - wheelR * 0.5))
        } else if isMPV {
            // Tall flat-roofed van silhouette
            let roofLeft  = flipped ? bodyLeft + bodyW * 0.08 : bodyLeft + bodyW * 0.04
            let roofRight = flipped ? bodyLeft + bodyW * 0.96 : bodyLeft + bodyW * 0.92
            let roofTop   = bodyTop - h * 0.18

            p.move(to: CGPoint(x: bodyLeft + 8, y: groundY - wheelR * 0.5))
            p.addLine(to: CGPoint(x: bodyLeft + 8, y: bodyTop + 2))
            p.addLine(to: CGPoint(x: roofLeft, y: roofTop))
            p.addLine(to: CGPoint(x: roofRight, y: roofTop))
            p.addLine(to: CGPoint(x: bodyRight - 8, y: bodyTop + 2))
            p.addLine(to: CGPoint(x: bodyRight - 8, y: groundY - wheelR * 0.5))
        } else if isSUV {
            // Tall boxy SUV — upright pillars, flat roof
            let roofH     = h * 0.20
            let cabinLeft  = flipped ? bodyLeft + bodyW * 0.10 : bodyLeft + bodyW * 0.08
            let cabinRight = flipped ? bodyLeft + bodyW * 0.92 : bodyLeft + bodyW * 0.90
            let roofTop    = bodyTop - roofH

            p.move(to: CGPoint(x: bodyLeft + 4, y: groundY - wheelR * 0.5))
            p.addLine(to: CGPoint(x: bodyLeft + 4, y: bodyTop))
            p.addLine(to: CGPoint(x: cabinLeft, y: roofTop + 4))
            p.addQuadCurve(to: CGPoint(x: cabinLeft + 6, y: roofTop),
                           control: CGPoint(x: cabinLeft, y: roofTop))
            p.addLine(to: CGPoint(x: cabinRight - 6, y: roofTop))
            p.addQuadCurve(to: CGPoint(x: cabinRight, y: roofTop + 4),
                           control: CGPoint(x: cabinRight, y: roofTop))
            p.addLine(to: CGPoint(x: bodyRight - 4, y: bodyTop))
            p.addLine(to: CGPoint(x: bodyRight - 4, y: groundY - wheelR * 0.5))
        } else {
            // Sedan — sloped bonnet, curved roofline, short boot
            let hoodLen   = bodyW * (flipped ? 0.22 : 0.26)
            let bootLen   = bodyW * (flipped ? 0.26 : 0.22)
            let roofStart = flipped ? bodyRight - hoodLen - bodyW * 0.46 : bodyLeft + hoodLen
            let roofEnd   = flipped ? bodyRight - hoodLen                 : bodyLeft + hoodLen + bodyW * 0.46
            let roofTop   = bodyTop - h * 0.19
            let roofPeak  = (roofStart + roofEnd) / 2

            // Boot/bonnet end heights
            let hoodTopY = bodyTop + h * 0.04
            let bootTopY = bodyTop + h * 0.06

            p.move(to: CGPoint(x: flipped ? bodyRight - 4 : bodyLeft + 4,
                               y: groundY - wheelR * 0.5))
            if flipped {
                // Right side — boot on left, bonnet on right
                p.addLine(to: CGPoint(x: bodyRight - 4, y: bootTopY))
                p.addQuadCurve(to: CGPoint(x: roofEnd - 6, y: bodyTop),
                               control: CGPoint(x: bodyRight - 4, y: bodyTop - 2))
                p.addQuadCurve(to: CGPoint(x: roofPeak, y: roofTop),
                               control: CGPoint(x: roofEnd - 10, y: roofTop + 2))
                p.addQuadCurve(to: CGPoint(x: roofStart + 6, y: bodyTop),
                               control: CGPoint(x: roofStart + 10, y: roofTop + 2))
                p.addLine(to: CGPoint(x: bodyLeft + 4, y: hoodTopY))
                p.addLine(to: CGPoint(x: bodyLeft + 4, y: groundY - wheelR * 0.5))
            } else {
                // Left side — bonnet on left, boot on right
                p.addLine(to: CGPoint(x: bodyLeft + 4, y: hoodTopY))
                p.addQuadCurve(to: CGPoint(x: roofStart + 6, y: bodyTop),
                               control: CGPoint(x: bodyLeft + 4, y: bodyTop - 2))
                p.addQuadCurve(to: CGPoint(x: roofPeak, y: roofTop),
                               control: CGPoint(x: roofStart + 10, y: roofTop + 2))
                p.addQuadCurve(to: CGPoint(x: roofEnd - 6, y: bodyTop),
                               control: CGPoint(x: roofEnd - 10, y: roofTop + 2))
                p.addLine(to: CGPoint(x: bodyRight - 4, y: bootTopY))
                p.addLine(to: CGPoint(x: bodyRight - 4, y: groundY - wheelR * 0.5))
            }
        }

        // Cut out wheel arches
        p.addEllipse(in: CGRect(x: frontWX - wheelR * 1.1, y: groundY - wheelR * 1.1,
                                 width: wheelR * 2.2, height: wheelR * 2.2))
        p.addEllipse(in: CGRect(x: rearWX - wheelR * 1.1, y: groundY - wheelR * 1.1,
                                 width: wheelR * 2.2, height: wheelR * 2.2))

        // Wheels (solid circles)
        p.addEllipse(in: CGRect(x: frontWX - wheelR, y: groundY - wheelR,
                                 width: wheelR * 2, height: wheelR * 2))
        p.addEllipse(in: CGRect(x: rearWX - wheelR, y: groundY - wheelR,
                                 width: wheelR * 2, height: wheelR * 2))

        if flipped {
            // Mirror horizontally
            var transform = CGAffineTransform(translationX: w, y: 0).scaledBy(x: -1, y: 1)
            return p.applying(transform)
        }
        return p
    }
}

// MARK: - Front Detail Overlay (headlights, grille)

struct FrontDetailOverlay: View {
    let carType: CarType
    let w: CGFloat, h: CGFloat

    var body: some View {
        let isLarge = carType.category == .scdf
        let isTall  = carType == .suv || carType == .mpv || isLarge
        let bodyW   = w * (isLarge ? 0.82 : 0.72)
        let bodyH   = h * (isTall ? 0.32 : 0.26)
        let groundY = h * 0.78
        let bodyTop = groundY - bodyH
        let cx      = w / 2

        return ZStack {
            // Headlights
            let lightW = bodyW * 0.16
            let lightH = bodyH * 0.18
            let lightY = bodyTop + bodyH * 0.22
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.85))
                .frame(width: lightW, height: lightH)
                .position(x: cx - bodyW * 0.28, y: lightY)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.85))
                .frame(width: lightW, height: lightH)
                .position(x: cx + bodyW * 0.28, y: lightY)
            // Grille
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray5))
                .frame(width: bodyW * 0.40, height: bodyH * 0.22)
                .position(x: cx, y: bodyTop + bodyH * 0.65)
            // Number plate
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(.systemGray4))
                .frame(width: bodyW * 0.22, height: bodyH * 0.10)
                .position(x: cx, y: bodyTop + bodyH * 0.88)
        }
    }
}

// MARK: - Rear Detail Overlay (tail lights, boot line)

struct RearDetailOverlay: View {
    let carType: CarType
    let w: CGFloat, h: CGFloat

    var body: some View {
        let isLarge = carType.category == .scdf
        let isTall  = carType == .suv || carType == .mpv || isLarge
        let bodyW   = w * (isLarge ? 0.82 : 0.72)
        let bodyH   = h * (isTall ? 0.32 : 0.26)
        let groundY = h * 0.78
        let bodyTop = groundY - bodyH
        let cx      = w / 2

        return ZStack {
            // Tail lights (red)
            let lightW = bodyW * 0.16
            let lightH = bodyH * 0.16
            let lightY = bodyTop + bodyH * 0.22
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.red.opacity(0.7))
                .frame(width: lightW, height: lightH)
                .position(x: cx - bodyW * 0.28, y: lightY)
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.red.opacity(0.7))
                .frame(width: lightW, height: lightH)
                .position(x: cx + bodyW * 0.28, y: lightY)
            // Boot line
            Path { p in
                p.move(to: CGPoint(x: cx - bodyW * 0.28, y: bodyTop + 5))
                p.addLine(to: CGPoint(x: cx + bodyW * 0.28, y: bodyTop + 5))
            }
            .stroke(Color(.systemGray5), lineWidth: 2)
            // Rear plate
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(.systemGray4))
                .frame(width: bodyW * 0.22, height: bodyH * 0.10)
                .position(x: cx, y: bodyTop + bodyH * 0.75)
        }
    }
}

// MARK: - Side Detail Overlay (windows, door lines)

struct SideDetailOverlay: View {
    let carType: CarType
    let w: CGFloat, h: CGFloat
    let flipped: Bool

    var body: some View {
        let isLarge = carType.category == .scdf
        let isSUV   = carType == .suv
        let isMPV   = carType == .mpv
        let groundY = h * 0.80
        let bodyH   = h * (isLarge ? 0.34 : isMPV ? 0.30 : isSUV ? 0.28 : 0.24)
        let bodyW   = w * (isLarge ? 0.88 : 0.84)
        let bodyLeft  = (w - bodyW) / 2
        let bodyRight = bodyLeft + bodyW
        let bodyTop   = groundY - bodyH
        let roofH     = h * (isLarge ? 0.0 : isMPV ? 0.18 : isSUV ? 0.20 : 0.19)
        let roofTop   = bodyTop - roofH

        // Window region
        let winStartX = flipped ? bodyRight - bodyW * 0.82 : bodyLeft + bodyW * 0.18
        let winW      = bodyW * (isMPV ? 0.64 : isLarge ? 0.70 : 0.60)
        let winTop    = roofTop + roofH * 0.1
        let winH      = roofH * 0.75

        return ZStack {
            // Window glass
            if !isLarge {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(.systemGray5).opacity(0.8))
                    .frame(width: winW, height: winH)
                    .position(x: winStartX + winW / 2, y: winTop + winH / 2)

                // Window divider (B-pillar)
                let pillarX = winStartX + winW * (isMPV ? 0.50 : 0.46)
                Path { p in
                    p.move(to: CGPoint(x: pillarX, y: winTop))
                    p.addLine(to: CGPoint(x: pillarX, y: winTop + winH))
                }
                .stroke(Color(.systemGray3), lineWidth: 3)

                // Door line
                Path { p in
                    let doorX = flipped ? bodyRight - bodyW * 0.50 : bodyLeft + bodyW * 0.50
                    p.move(to: CGPoint(x: doorX, y: bodyTop))
                    p.addLine(to: CGPoint(x: doorX, y: groundY - h * 0.085 * 2))
                }
                .stroke(Color(.systemGray4), lineWidth: 1.5)
            } else {
                // Cab window for large vehicles
                let cabW = bodyW * 0.28
                let cabLeft = flipped ? bodyRight - cabW - bodyW * 0.05 : bodyLeft + bodyW * 0.05
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5).opacity(0.8))
                    .frame(width: cabW, height: bodyH * 0.38)
                    .position(x: cabLeft + cabW / 2, y: bodyTop + bodyH * 0.22)
            }
        }
    }
}
