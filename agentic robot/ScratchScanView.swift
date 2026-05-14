import SwiftUI
import PhotosUI
import Photos

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

    // Replace flow — single source of truth
    @State private var replacingIndex: Int? = nil
    @State private var showReplaceSheet = false     // confirmationDialog trigger
    @State private var showReplaceCamera = false
    @State private var showReplaceLibrary = false
    @State private var replaceImage: UIImage? = nil // set by PHPicker callback

    private var capturedCount: Int { capturedImages.compactMap { $0 }.count }
    private var progress: Double { Double(capturedCount) / Double(scanAngles.count) }

    var body: some View {
        VStack(spacing: 0) {

            // HEADER
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scratch Scan").font(.largeTitle).bold()
                    Text("\(carType.rawValue)  ·  \(plate)")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
                Button("Logout") { onLogout() }.foregroundColor(.red)
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
            .padding(.horizontal).padding(.bottom, 12)

            if showCompletionScreen { reviewView } else { scanGuideView }
        }
        .navigationBarBackButtonHidden(true)

        // ── Main capture ───────────────────────────────────────────────────
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
                   let img = UIImage(data: data) {
                    await MainActor.run {
                        capturedImages[currentAngleIndex] = img
                        selectedPhotoItem = nil
                        advanceOrComplete()
                    }
                }
            }
        }

        // ── Replace: confirmation sheet ────────────────────────────────────
        .confirmationDialog(
            replacingIndex.map { "Replace \(scanAngles[$0].label) Photo" } ?? "Replace Photo",
            isPresented: $showReplaceSheet,
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
            Button("Choose from Library") {
                showReplaceLibrary = true
            }
            Button("Cancel", role: .cancel) { replacingIndex = nil }
        }

        // ── Replace: camera ────────────────────────────────────────────────
        .sheet(isPresented: $showReplaceCamera) {
            ImagePicker(sourceType: .camera) { image in
                if let idx = replacingIndex { capturedImages[idx] = image }
                replacingIndex = nil
            }
        }

        // ── Replace: photo library (PHPicker — writes directly to replaceImage) ──
        .sheet(isPresented: $showReplaceLibrary) {
            PHPickerRepresentable { image in
                if let idx = replacingIndex { capturedImages[idx] = image }
                replacingIndex = nil
                showReplaceLibrary = false
            }
        }
    }

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

            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground))
                CarSilhouetteView(carType: carType, angleId: currentAngleIndex).padding(.horizontal, 18).padding(.vertical, 10)
            }
            .frame(height: 310).padding(.horizontal)

            HStack(spacing: 16) {
                Image(systemName: scanAngles[currentAngleIndex].iconName)
                    .font(.system(size: 26, weight: .bold)).foregroundColor(carType.accentColor).frame(width: 40)
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

            HStack(spacing: 12) {
                Button {
                    if currentAngleIndex > 0 {
                        withAnimation { currentAngleIndex -= 1 }
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(carType.accentColor)
                        .frame(width: 52, height: 52)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                }
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity).padding()
                        .background(Color(.secondarySystemBackground)).cornerRadius(12)
                }
                Button {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        localErrorMessage = nil; showCamera = true
                    } else {
                        localErrorMessage = "Camera is not available on this device."
                    }
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity).padding()
                        .background(carType.accentColor).foregroundColor(.white).cornerRadius(12)
                }
            }
            .padding(.horizontal).padding(.bottom, 24)
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
                            showReplaceSheet = true
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

// MARK: - PHPicker wrapper
// Delivers UIImage directly — no PhotosPickerItem conversion needed

struct PHPickerRepresentable: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (UIImage) -> Void
        init(onPick: @escaping (UIImage) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else { return }
            result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                if let image = object as? UIImage {
                    DispatchQueue.main.async { self.onPick(image) }
                }
            }
        }
    }
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
                if let img = image {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(height: 140).clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray5)).frame(height: 140)
                }
                HStack {
                    Text(label).font(.caption.bold()).foregroundColor(.white)
                    Spacer()
                    Image(systemName: "pencil.circle.fill").foregroundColor(.white)
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(
                    LinearGradient(colors: [Color.black.opacity(0.6), Color.clear],
                                   startPoint: .bottom, endPoint: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                )
            }
            .frame(height: 140)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(accentColor.opacity(0.4), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Car Silhouette View

struct CarSilhouetteView: View {
    let carType: CarType
    let angleId: Int   // 0=Front, 1=Rear, 2=Left, 3=Right

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                VehicleGuideDrawing(
                    carType: carType,
                    angleId: angleId,
                    w: w,
                    h: h
                )

                Text(scanAngles[angleId].label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.75))
                    .position(x: w / 2, y: h - 12)
            }
        }
    }
}

// MARK: - Vehicle Guide Drawing

struct VehicleGuideDrawing: View {
    let carType: CarType
    let angleId: Int
    let w: CGFloat
    let h: CGFloat

    private var isFront: Bool { angleId == 0 }
    private var isRear: Bool { angleId == 1 }
    private var isLeftSide: Bool { angleId == 2 }
    private var isRightSide: Bool { angleId == 3 }

    var body: some View {
        ZStack {
            SoftGroundShadow(w: w, h: h)

            if isFront || isRear {
                VehicleFaceDrawing(
                    carType: carType,
                    isFront: isFront,
                    w: w,
                    h: h
                )
            } else {
                VehicleSideDrawing(
                    carType: carType,
                    flipped: isRightSide,
                    w: w,
                    h: h
                )
            }
        }
    }
}

// MARK: - Shared Drawing Helpers

struct SoftGroundShadow: View {
    let w: CGFloat
    let h: CGFloat

    var body: some View {
        Ellipse()
            .fill(Color.black.opacity(0.045))
            .frame(width: w * 0.72, height: h * 0.055)
            .position(x: w / 2, y: h * 0.80)
    }
}

extension Path {
    mutating func roundedRect(_ rect: CGRect, radius: CGFloat) {
        let r = min(radius, min(rect.width, rect.height) / 2)
        move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r),
                     control: CGPoint(x: rect.maxX, y: rect.minY))
        addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                     control: CGPoint(x: rect.maxX, y: rect.maxY))
        addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                     control: CGPoint(x: rect.minX, y: rect.maxY))
        addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY),
                     control: CGPoint(x: rect.minX, y: rect.minY))
        closeSubpath()
    }
}

// MARK: - Face View

struct VehicleFaceDrawing: View {
    let carType: CarType
    let isFront: Bool
    let w: CGFloat
    let h: CGFloat

    private var isLarge: Bool { carType.category == .scdf }
    private var isSUV: Bool { carType == .suv }
    private var isMPV: Bool { carType == .mpv }
    private var isTall: Bool { isSUV || isMPV || isLarge }

    private var cx: CGFloat { w / 2 }
    private var bodyW: CGFloat { w * (isLarge ? 0.64 : isTall ? 0.58 : 0.54) }
    private var bodyH: CGFloat { h * (isLarge ? 0.58 : isTall ? 0.54 : 0.49) }
    private var topY: CGFloat { h * (isLarge ? 0.18 : isTall ? 0.22 : 0.25) }
    private var bottomY: CGFloat { topY + bodyH }
    private var leftX: CGFloat { cx - bodyW / 2 }
    private var rightX: CGFloat { cx + bodyW / 2 }

    private var bodyColor: Color { Color(.systemGray3).opacity(0.92) }
    private var lineColor: Color { Color(.systemGray2).opacity(0.55) }
    private var glassColor: Color { Color(.systemGray6).opacity(0.82) }

    var body: some View {
        ZStack {
            rearWheelStubs
            mainBody
            windshield
            hoodOrBootLines
            lights
            grilleOrRearPanel
            licensePlate
            mirrors
            roofAccent
        }
    }

    private var mainBody: some View {
        faceBodyPath
            .fill(
                LinearGradient(
                    colors: [
                        Color(.systemGray2).opacity(0.78),
                        bodyColor,
                        Color(.systemGray4).opacity(0.95)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(faceBodyPath.stroke(Color(.systemGray2).opacity(0.35), lineWidth: 1.2))
    }

    private var faceBodyPath: Path {
        var p = Path()

        if isLarge {
            p.move(to: CGPoint(x: leftX + bodyW * 0.06, y: bottomY))
            p.addLine(to: CGPoint(x: leftX, y: topY + bodyH * 0.28))
            p.addQuadCurve(to: CGPoint(x: leftX + bodyW * 0.10, y: topY + bodyH * 0.08),
                           control: CGPoint(x: leftX + bodyW * 0.02, y: topY + bodyH * 0.12))
            p.addLine(to: CGPoint(x: rightX - bodyW * 0.10, y: topY + bodyH * 0.08))
            p.addQuadCurve(to: CGPoint(x: rightX, y: topY + bodyH * 0.28),
                           control: CGPoint(x: rightX - bodyW * 0.02, y: topY + bodyH * 0.12))
            p.addLine(to: CGPoint(x: rightX - bodyW * 0.06, y: bottomY))
            p.closeSubpath()
        } else {
            p.move(to: CGPoint(x: leftX + bodyW * 0.08, y: bottomY))
            p.addLine(to: CGPoint(x: leftX, y: topY + bodyH * 0.58))
            p.addQuadCurve(to: CGPoint(x: leftX + bodyW * 0.11, y: topY + bodyH * 0.22),
                           control: CGPoint(x: leftX + bodyW * 0.01, y: topY + bodyH * 0.32))
            p.addQuadCurve(to: CGPoint(x: leftX + bodyW * 0.31, y: topY + bodyH * 0.06),
                           control: CGPoint(x: leftX + bodyW * 0.18, y: topY + bodyH * 0.08))
            p.addLine(to: CGPoint(x: rightX - bodyW * 0.31, y: topY + bodyH * 0.06))
            p.addQuadCurve(to: CGPoint(x: rightX - bodyW * 0.11, y: topY + bodyH * 0.22),
                           control: CGPoint(x: rightX - bodyW * 0.18, y: topY + bodyH * 0.08))
            p.addQuadCurve(to: CGPoint(x: rightX, y: topY + bodyH * 0.58),
                           control: CGPoint(x: rightX - bodyW * 0.01, y: topY + bodyH * 0.32))
            p.addLine(to: CGPoint(x: rightX - bodyW * 0.08, y: bottomY))
            p.closeSubpath()
        }

        return p
    }

    private var windshield: some View {
        let winW = bodyW * (isLarge ? 0.62 : isTall ? 0.58 : 0.54)
        let winH = bodyH * (isLarge ? 0.28 : 0.26)
        let winY = topY + bodyH * (isLarge ? 0.24 : 0.23)

        return ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(glassColor)
                .frame(width: winW, height: winH)
                .position(x: cx, y: winY)

            Path { p in
                p.move(to: CGPoint(x: cx, y: winY - winH * 0.42))
                p.addLine(to: CGPoint(x: cx, y: winY + winH * 0.40))
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 1)

            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.systemGray4).opacity(0.75))
                .frame(width: winW * 0.11, height: winH * 0.12)
                .position(x: cx, y: winY + winH * 0.05)
        }
    }

    private var hoodOrBootLines: some View {
        let upperY = topY + bodyH * (isLarge ? 0.44 : 0.48)
        let lowerY = topY + bodyH * 0.66

        return ZStack {
            Path { p in
                if isFront {
                    p.move(to: CGPoint(x: leftX + bodyW * 0.18, y: upperY))
                    p.addQuadCurve(to: CGPoint(x: cx, y: lowerY),
                                   control: CGPoint(x: leftX + bodyW * 0.37, y: upperY + bodyH * 0.05))
                    p.addQuadCurve(to: CGPoint(x: rightX - bodyW * 0.18, y: upperY),
                                   control: CGPoint(x: rightX - bodyW * 0.37, y: upperY + bodyH * 0.05))
                } else {
                    p.move(to: CGPoint(x: leftX + bodyW * 0.16, y: upperY))
                    p.addLine(to: CGPoint(x: rightX - bodyW * 0.16, y: upperY))
                    p.move(to: CGPoint(x: leftX + bodyW * 0.24, y: lowerY))
                    p.addLine(to: CGPoint(x: rightX - bodyW * 0.24, y: lowerY))
                }
            }
            .stroke(lineColor, lineWidth: 1.4)
        }
    }

    private var lights: some View {
        let y = topY + bodyH * (isFront ? 0.56 : 0.50)
        let lightW = bodyW * (isLarge ? 0.23 : 0.20)
        let lightH = bodyH * 0.052

        return ZStack {
            lightShape(left: true)
                .fill(isFront ? Color.white.opacity(0.9) : Color.red.opacity(0.68))
                .frame(width: lightW, height: lightH)
                .position(x: leftX + bodyW * 0.22, y: y)

            lightShape(left: false)
                .fill(isFront ? Color.white.opacity(0.9) : Color.red.opacity(0.68))
                .frame(width: lightW, height: lightH)
                .position(x: rightX - bodyW * 0.22, y: y)
        }
    }

    private func lightShape(left: Bool) -> Path {
        var p = Path()
        let skew: CGFloat = left ? 1 : -1

        p.move(to: CGPoint(x: 0, y: 0.15))
        p.addLine(to: CGPoint(x: 0.80, y: 0.00))
        p.addQuadCurve(to: CGPoint(x: 1.00, y: 0.35),
                       control: CGPoint(x: 0.98, y: 0.02))
        p.addLine(to: CGPoint(x: 0.94, y: 0.90))
        p.addQuadCurve(to: CGPoint(x: 0.08, y: 0.78),
                       control: CGPoint(x: 0.45, y: 1.00))
        p.closeSubpath()

        let scale = CGAffineTransform(scaleX: 1, y: 1)
        let flip = left ? CGAffineTransform.identity :
            CGAffineTransform(translationX: 1, y: 0).scaledBy(x: -1, y: 1)
        let skewTransform = CGAffineTransform(a: 1, b: 0, c: 0.06 * skew, d: 1, tx: 0, ty: 0)
        return p.applying(scale).applying(flip).applying(skewTransform)
    }

    private var grilleOrRearPanel: some View {
        let y = topY + bodyH * (isFront ? 0.65 : 0.61)

        return ZStack {
            if isFront {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(.systemGray5).opacity(0.88))
                    .frame(width: bodyW * 0.45, height: bodyH * 0.105)
                    .position(x: cx, y: y)

                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color(.systemGray3).opacity(0.95))
                            .frame(width: bodyW * 0.39, height: 2)
                    }
                }
                .position(x: cx, y: y)

                Circle()
                    .fill(Color(.systemGray2).opacity(0.75))
                    .frame(width: bodyH * 0.095, height: bodyH * 0.095)
                    .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                    .position(x: cx, y: y)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemGray4).opacity(0.45))
                    .frame(width: bodyW * 0.50, height: bodyH * 0.14)
                    .position(x: cx, y: y)

                Path { p in
                    p.move(to: CGPoint(x: leftX + bodyW * 0.20, y: y - bodyH * 0.10))
                    p.addQuadCurve(to: CGPoint(x: rightX - bodyW * 0.20, y: y - bodyH * 0.10),
                                   control: CGPoint(x: cx, y: y - bodyH * 0.03))
                }
                .stroke(Color(.systemGray2).opacity(0.35), lineWidth: 1.3)
            }
        }
    }

    private var licensePlate: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(.systemGray5).opacity(0.96))
            .frame(width: bodyW * 0.23, height: bodyH * 0.075)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.55), lineWidth: 0.8))
            .position(x: cx, y: topY + bodyH * (isFront ? 0.78 : 0.67))
    }

    private var mirrors: some View {
        let y = topY + bodyH * 0.43
        let mirrorW = bodyW * 0.12
        let mirrorH = bodyH * 0.08

        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray3).opacity(0.95))
                .frame(width: mirrorW, height: mirrorH)
                .rotationEffect(.degrees(-5))
                .position(x: leftX - mirrorW * 0.26, y: y)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.systemGray3).opacity(0.95))
                .frame(width: mirrorW, height: mirrorH)
                .rotationEffect(.degrees(5))
                .position(x: rightX + mirrorW * 0.26, y: y)
        }
    }

    private var roofAccent: some View {
        Path { p in
            p.move(to: CGPoint(x: leftX + bodyW * 0.30, y: topY + bodyH * 0.05))
            p.addQuadCurve(to: CGPoint(x: rightX - bodyW * 0.30, y: topY + bodyH * 0.05),
                           control: CGPoint(x: cx, y: topY))
        }
        .stroke(Color.white.opacity(0.38), lineWidth: 1)
    }

    private var rearWheelStubs: some View {
        let wheelW = bodyW * 0.11
        let wheelH = bodyH * 0.21
        let y = bottomY - wheelH * 0.38

        return ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(.systemGray2).opacity(0.95))
                .frame(width: wheelW, height: wheelH)
                .position(x: leftX + bodyW * 0.10, y: y)
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(.systemGray2).opacity(0.95))
                .frame(width: wheelW, height: wheelH)
                .position(x: rightX - bodyW * 0.10, y: y)
        }
    }
}

// MARK: - Side View

struct VehicleSideDrawing: View {
    let carType: CarType
    let flipped: Bool
    let w: CGFloat
    let h: CGFloat

    private var isLarge: Bool { carType.category == .scdf }
    private var isSUV: Bool { carType == .suv }
    private var isMPV: Bool { carType == .mpv }

    private var bodyColor: Color { Color(.systemGray3).opacity(0.92) }
    private var detailColor: Color { Color(.systemGray2).opacity(0.55) }
    private var glassColor: Color { Color(.systemGray6).opacity(0.82) }

    var body: some View {
        ZStack {
            let transform = flipped
                ? CGAffineTransform(translationX: w, y: 0).scaledBy(x: -1, y: 1)
                : CGAffineTransform.identity

            sideBodyPath
                .applying(transform)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(.systemGray2).opacity(0.72),
                            bodyColor,
                            Color(.systemGray4).opacity(0.90)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(sideBodyPath.applying(transform).stroke(Color(.systemGray2).opacity(0.35), lineWidth: 1.2))

            sideWindowPath
                .applying(transform)
                .fill(glassColor)

            sideWindowPath
                .applying(transform)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)

            sideDetailLines(transform: transform)
            wheelLayer(transform: transform)
            mirrorsAndLights(transform: transform)
            doorHandles(transform: transform)
        }
    }

    private var metrics: SideMetrics {
        let bodyW = w * (isLarge ? 0.82 : 0.84)
        let left = (w - bodyW) / 2
        let right = left + bodyW

        // This fixes the monster-truck issue: wheel size is capped by height, not driven mostly by width.
        let wheelR = min(w * (isLarge ? 0.050 : isSUV ? 0.052 : 0.048),
                         h * (isLarge ? 0.145 : isSUV ? 0.135 : 0.125))
        let groundY = h * 0.77
        let sillY = groundY - wheelR * 0.35

        return SideMetrics(
            left: left,
            right: right,
            width: bodyW,
            wheelR: wheelR,
            groundY: groundY,
            sillY: sillY
        )
    }

    private var sideBodyPath: Path {
        let m = metrics
        var p = Path()

        if isLarge {
            largeVehicleBody(path: &p, m: m)
        } else if isMPV {
            mpvBody(path: &p, m: m)
        } else if isSUV {
            suvBody(path: &p, m: m)
        } else {
            sedanBody(path: &p, m: m)
        }

        return p
    }

    private var sideWindowPath: Path {
        let m = metrics
        var p = Path()

        if isLarge {
            let x = m.left + m.width * 0.055
            let y = m.sillY - h * 0.335
            p.roundedRect(CGRect(x: x, y: y, width: m.width * 0.22, height: h * 0.145), radius: 8)
        } else if isMPV {
            let top = m.sillY - h * 0.330
            let base = m.sillY - h * 0.155
            p.move(to: CGPoint(x: m.left + m.width * 0.20, y: base))
            p.addLine(to: CGPoint(x: m.left + m.width * 0.29, y: top + h * 0.035))
            p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.80, y: top + h * 0.020),
                           control: CGPoint(x: m.left + m.width * 0.48, y: top - h * 0.012))
            p.addLine(to: CGPoint(x: m.left + m.width * 0.88, y: base))
            p.closeSubpath()
        } else if isSUV {
            let top = m.sillY - h * 0.300
            let base = m.sillY - h * 0.145
            p.move(to: CGPoint(x: m.left + m.width * 0.25, y: base))
            p.addLine(to: CGPoint(x: m.left + m.width * 0.34, y: top + h * 0.035))
            p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.76, y: top + h * 0.030),
                           control: CGPoint(x: m.left + m.width * 0.55, y: top + h * 0.005))
            p.addLine(to: CGPoint(x: m.left + m.width * 0.84, y: base))
            p.closeSubpath()
        } else {
            let top = m.sillY - h * 0.285
            let base = m.sillY - h * 0.135
            p.move(to: CGPoint(x: m.left + m.width * 0.28, y: base))
            p.addLine(to: CGPoint(x: m.left + m.width * 0.38, y: top + h * 0.035))
            p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.70, y: top + h * 0.020),
                           control: CGPoint(x: m.left + m.width * 0.54, y: top - h * 0.010))
            p.addLine(to: CGPoint(x: m.left + m.width * 0.78, y: base))
            p.closeSubpath()
        }

        return p
    }

    private func sedanBody(path p: inout Path, m: SideMetrics) {
        let hoodTop = m.sillY - h * 0.155
        let roofTop = m.sillY - h * 0.305
        let bootTop = m.sillY - h * 0.130

        p.move(to: CGPoint(x: m.left + m.width * 0.02, y: m.sillY))
        p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.08, y: hoodTop + h * 0.030),
                       control: CGPoint(x: m.left + m.width * 0.02, y: hoodTop + h * 0.070))
        p.addLine(to: CGPoint(x: m.left + m.width * 0.25, y: hoodTop))
        p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.37, y: roofTop + h * 0.035),
                       control: CGPoint(x: m.left + m.width * 0.30, y: hoodTop - h * 0.015))
        p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.69, y: roofTop + h * 0.030),
                       control: CGPoint(x: m.left + m.width * 0.52, y: roofTop - h * 0.020))
        p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.78, y: bootTop),
                       control: CGPoint(x: m.left + m.width * 0.74, y: roofTop + h * 0.045))
        p.addLine(to: CGPoint(x: m.right - m.width * 0.08, y: bootTop + h * 0.015))
        p.addQuadCurve(to: CGPoint(x: m.right - m.width * 0.02, y: m.sillY),
                       control: CGPoint(x: m.right - m.width * 0.01, y: bootTop + h * 0.075))
        p.closeSubpath()
    }

    private func suvBody(path p: inout Path, m: SideMetrics) {
        let hoodTop = m.sillY - h * 0.185
        let roofTop = m.sillY - h * 0.335
        let rearTop = m.sillY - h * 0.170

        p.move(to: CGPoint(x: m.left + m.width * 0.02, y: m.sillY))
        p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.09, y: hoodTop + h * 0.030),
                       control: CGPoint(x: m.left + m.width * 0.02, y: hoodTop + h * 0.075))
        p.addLine(to: CGPoint(x: m.left + m.width * 0.26, y: hoodTop))
        p.addLine(to: CGPoint(x: m.left + m.width * 0.35, y: roofTop + h * 0.025))
        p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.76, y: roofTop + h * 0.030),
                       control: CGPoint(x: m.left + m.width * 0.55, y: roofTop - h * 0.005))
        p.addLine(to: CGPoint(x: m.left + m.width * 0.84, y: rearTop))
        p.addLine(to: CGPoint(x: m.right - m.width * 0.06, y: rearTop + h * 0.015))
        p.addQuadCurve(to: CGPoint(x: m.right - m.width * 0.02, y: m.sillY),
                       control: CGPoint(x: m.right - m.width * 0.01, y: rearTop + h * 0.075))
        p.closeSubpath()
    }

    private func mpvBody(path p: inout Path, m: SideMetrics) {
        let hoodTop = m.sillY - h * 0.170
        let roofTop = m.sillY - h * 0.350
        let rearTop = m.sillY - h * 0.175

        p.move(to: CGPoint(x: m.left + m.width * 0.02, y: m.sillY))
        p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.07, y: hoodTop + h * 0.040),
                       control: CGPoint(x: m.left + m.width * 0.02, y: hoodTop + h * 0.075))
        p.addLine(to: CGPoint(x: m.left + m.width * 0.18, y: hoodTop))
        p.addLine(to: CGPoint(x: m.left + m.width * 0.28, y: roofTop + h * 0.020))
        p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.82, y: roofTop + h * 0.025),
                       control: CGPoint(x: m.left + m.width * 0.55, y: roofTop - h * 0.010))
        p.addLine(to: CGPoint(x: m.left + m.width * 0.90, y: rearTop))
        p.addLine(to: CGPoint(x: m.right - m.width * 0.05, y: rearTop + h * 0.020))
        p.addQuadCurve(to: CGPoint(x: m.right - m.width * 0.02, y: m.sillY),
                       control: CGPoint(x: m.right - m.width * 0.01, y: rearTop + h * 0.080))
        p.closeSubpath()
    }

    private func largeVehicleBody(path p: inout Path, m: SideMetrics) {
        let cabTop = m.sillY - h * 0.395
        let boxTop = m.sillY - h * 0.350
        let cabEnd = m.left + m.width * 0.33

        p.move(to: CGPoint(x: m.left + m.width * 0.02, y: m.sillY))
        p.addLine(to: CGPoint(x: m.left + m.width * 0.02, y: cabTop + h * 0.090))
        p.addQuadCurve(to: CGPoint(x: m.left + m.width * 0.08, y: cabTop),
                       control: CGPoint(x: m.left + m.width * 0.025, y: cabTop + h * 0.020))
        p.addLine(to: CGPoint(x: cabEnd - m.width * 0.04, y: cabTop))
        p.addLine(to: CGPoint(x: cabEnd, y: boxTop))
        p.addLine(to: CGPoint(x: m.right - m.width * 0.03, y: boxTop))
        p.addQuadCurve(to: CGPoint(x: m.right - m.width * 0.02, y: boxTop + h * 0.030),
                       control: CGPoint(x: m.right - m.width * 0.01, y: boxTop))
        p.addLine(to: CGPoint(x: m.right - m.width * 0.02, y: m.sillY))
        p.closeSubpath()
    }

    private func sideDetailLines(transform: CGAffineTransform) -> some View {
        let m = metrics
        let window = sideWindowPath.applying(transform)
        let beltY = isLarge ? m.sillY - h * 0.145 : m.sillY - h * 0.118
        let lowerY = m.sillY - h * 0.050

        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: m.left + m.width * 0.10, y: beltY))
                p.addLine(to: CGPoint(x: m.right - m.width * 0.10, y: beltY))
                p.move(to: CGPoint(x: m.left + m.width * 0.18, y: lowerY))
                p.addLine(to: CGPoint(x: m.right - m.width * 0.18, y: lowerY))
            }
            .applying(transform)
            .stroke(detailColor, lineWidth: 1.2)

            if !isLarge {
                let firstDoor = m.left + m.width * (isMPV ? 0.43 : 0.48)
                let secondDoor = m.left + m.width * (isMPV ? 0.66 : 0.64)
                Path { p in
                    p.move(to: CGPoint(x: firstDoor, y: m.sillY - h * 0.135))
                    p.addLine(to: CGPoint(x: firstDoor, y: m.sillY - h * 0.010))
                    p.move(to: CGPoint(x: secondDoor, y: m.sillY - h * 0.130))
                    p.addLine(to: CGPoint(x: secondDoor, y: m.sillY - h * 0.015))
                }
                .applying(transform)
                .stroke(Color(.systemGray2).opacity(0.42), lineWidth: 1.1)
            }

            Path { p in
                let pillar1 = m.left + m.width * (isMPV ? 0.43 : isSUV ? 0.50 : 0.51)
                let pillar2 = m.left + m.width * (isMPV ? 0.62 : isSUV ? 0.66 : 0.65)

                if !isLarge {
                    p.move(to: CGPoint(x: pillar1, y: m.sillY - h * 0.285))
                    p.addLine(to: CGPoint(x: pillar1, y: m.sillY - h * 0.135))
                    p.move(to: CGPoint(x: pillar2, y: m.sillY - h * 0.285))
                    p.addLine(to: CGPoint(x: pillar2, y: m.sillY - h * 0.135))
                }
            }
            .applying(transform)
            .stroke(Color(.systemGray3).opacity(0.75), lineWidth: 3)

            window
                .stroke(Color(.systemGray2).opacity(0.18), lineWidth: 0.8)
        }
    }

    private func wheelLayer(transform: CGAffineTransform) -> some View {
        let m = metrics
        let frontX = isLarge ? m.left + m.width * 0.19 : m.left + m.width * 0.21
        let rearX = isLarge ? m.left + m.width * 0.76 : m.left + m.width * 0.76
        let archR = m.wheelR * 1.33

        return ZStack {
            ForEach([frontX, rearX], id: \.self) { x in
                let pt = CGPoint(x: x, y: m.groundY).applying(transform)

                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: archR * 2, height: archR * 2)
                    .position(pt)

                Circle()
                    .fill(Color(.systemGray2).opacity(0.96))
                    .frame(width: m.wheelR * 2, height: m.wheelR * 2)
                    .position(pt)

                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: m.wheelR * 1.05, height: m.wheelR * 1.05)
                    .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                    .position(pt)

                ForEach(0..<6, id: \.self) { spoke in
                    Capsule()
                        .fill(Color(.systemGray3))
                        .frame(width: m.wheelR * 0.08, height: m.wheelR * 0.80)
                        .rotationEffect(.degrees(Double(spoke) * 30))
                        .position(pt)
                }
            }
        }
    }

    private func mirrorsAndLights(transform: CGAffineTransform) -> some View {
        let m = metrics
        let frontLight = CGPoint(x: m.left + m.width * 0.055, y: m.sillY - h * 0.135).applying(transform)
        let rearLight = CGPoint(x: m.right - m.width * 0.055, y: m.sillY - h * 0.115).applying(transform)
        let mirror = CGPoint(x: m.left + m.width * (isMPV ? 0.225 : 0.265), y: m.sillY - h * 0.175).applying(transform)

        return ZStack {
            Capsule()
                .fill(Color.white.opacity(0.88))
                .frame(width: w * 0.040, height: h * 0.020)
                .position(frontLight)

            Capsule()
                .fill(Color.red.opacity(0.62))
                .frame(width: w * 0.040, height: h * 0.022)
                .position(rearLight)

            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.systemGray3).opacity(0.95))
                .frame(width: w * 0.035, height: h * 0.030)
                .position(mirror)
        }
    }

    private func doorHandles(transform: CGAffineTransform) -> some View {
        let m = metrics
        guard !isLarge else { return AnyView(EmptyView()) }

        let y = m.sillY - h * 0.105
        let h1 = CGPoint(x: m.left + m.width * 0.43, y: y).applying(transform)
        let h2 = CGPoint(x: m.left + m.width * 0.61, y: y).applying(transform)

        return AnyView(
            ZStack {
                Capsule()
                    .fill(Color(.systemGray2).opacity(0.60))
                    .frame(width: w * 0.032, height: h * 0.010)
                    .position(h1)
                Capsule()
                    .fill(Color(.systemGray2).opacity(0.60))
                    .frame(width: w * 0.032, height: h * 0.010)
                    .position(h2)
            }
        )
    }
}

// MARK: - Side Metrics

private struct SideMetrics {
    let left: CGFloat
    let right: CGFloat
    let width: CGFloat
    let wheelR: CGFloat
    let groundY: CGFloat
    let sillY: CGFloat
}
