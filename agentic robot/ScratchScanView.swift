import SwiftUI
import PhotosUI

// MARK: - Scan Angle Model

struct ScanAngle: Identifiable {
    let id: Int
    let label: String
    let instruction: String
}

let scanAngles: [ScanAngle] = [
    ScanAngle(id: 0, label: "Front",       instruction: "Stand in front — aim at the bonnet"),
    ScanAngle(id: 1, label: "Rear",        instruction: "Stand behind — aim at the boot"),
    ScanAngle(id: 2, label: "Left Side",   instruction: "Stand on the left side of the vehicle"),
    ScanAngle(id: 3, label: "Right Side",  instruction: "Stand on the right side of the vehicle"),
    ScanAngle(id: 4, label: "Front-Left",  instruction: "Stand at the front-left corner"),
    ScanAngle(id: 5, label: "Front-Right", instruction: "Stand at the front-right corner"),
    ScanAngle(id: 6, label: "Rear-Left",   instruction: "Stand at the rear-left corner"),
    ScanAngle(id: 7, label: "Rear-Right",  instruction: "Stand at the rear-right corner"),
]

// MARK: - Main View

struct ScratchScanView: View {

    let plate: String
    let carType: CarType
    var onLogout: () -> Void
    var onScanComplete: ([UIImage]) -> Void

    @State private var currentAngleIndex = 0
    @State private var capturedImages: [UIImage?] = Array(repeating: nil, count: 8)
    @State private var showCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showCompletionScreen = false
    @State private var localErrorMessage: String? = nil

    // Review/replace state
    @State private var replacingIndex: Int? = nil
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
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.caption.bold())
                        .foregroundColor(carType.accentColor)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(carType.accentColor)
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
        .sheet(isPresented: $showReplaceCamera) {
            ImagePicker(sourceType: .camera) { image in
                if let idx = replacingIndex {
                    capturedImages[idx] = image
                }
                replacingIndex = nil
            }
        }
        .onChange(of: replacePhotoItem) { _, newItem in
            guard let newItem, let idx = replacingIndex else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        capturedImages[idx] = uiImage
                        replacePhotoItem = nil
                        replacingIndex = nil
                    }
                }
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

            // PERSPECTIVE SILHOUETTE
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))

                PerspectiveSilhouetteView(carType: carType, angleId: currentAngleIndex)
                    .padding(24)
            }
            .frame(height: 240)
            .padding(.horizontal)

            // INSTRUCTION CARD
            HStack(spacing: 16) {
                Image(systemName: iconForAngle(currentAngleIndex))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(carType.accentColor)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(scanAngles[currentAngleIndex].label)
                        .font(.headline)
                    Text(scanAngles[currentAngleIndex].instruction)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
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
                        .onTapGesture {
                            withAnimation { currentAngleIndex = idx }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 90)

            if let err = localErrorMessage {
                Text(err)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            localErrorMessage = nil
                        }
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
                        .frame(maxWidth: .infinity)
                        .padding()
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
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(carType.accentColor)
                        .foregroundColor(.white)
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
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("All Angles Captured")
                        .font(.title2.bold())
                }
                .padding(.top, 8)

                Text("Tap any photo to replace it before submitting.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(0..<scanAngles.count, id: \.self) { idx in
                        ReviewThumbnail(
                            label: scanAngles[idx].label,
                            image: capturedImages[idx],
                            accentColor: carType.accentColor,
                            onTap: { replacingIndex = idx }
                        )
                    }
                }
                .padding(.horizontal)

                Button {
                    let images = capturedImages.compactMap { $0 }
                    onScanComplete(images)
                } label: {
                    Text("Submit for Analysis")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(carType.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                        .padding(.horizontal)
                }
                .padding(.bottom, 32)
            }
        }
        .confirmationDialog(
            "Replace Photo",
            isPresented: Binding(
                get: { replacingIndex != nil },
                set: { if !$0 { replacingIndex = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Take New Photo") {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showReplaceCamera = true
                }
            }
            PhotosPicker(selection: $replacePhotoItem, matching: .images) {
                Text("Choose from Library")
            }
            Button("Cancel", role: .cancel) { replacingIndex = nil }
        }
    }

    // MARK: - Helpers

    private func iconForAngle(_ id: Int) -> String {
        switch id {
        case 0: return "car.front.waves.up"
        case 1: return "car.rear.waves.up"
        case 2: return "arrow.left.square"
        case 3: return "arrow.right.square"
        case 4: return "arrow.up.left.square"
        case 5: return "arrow.up.right.square"
        case 6: return "arrow.down.left.square"
        case 7: return "arrow.down.right.square"
        default: return "camera"
        }
    }
}

// MARK: - Angle Thumbnail (strip)

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
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isCurrent ? accentColor : Color.clear, lineWidth: 2)
                    )

                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .background(Circle().fill(Color.white).padding(1))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(3)
                } else {
                    Image(systemName: isCurrent ? "camera.fill" : "circle.dashed")
                        .foregroundColor(isCurrent ? accentColor : .secondary)
                }
            }
            Text(label)
                .font(.system(size: 9, weight: isCurrent ? .bold : .regular))
                .foregroundColor(isCurrent ? accentColor : .secondary)
                .lineLimit(1)
        }
        .frame(width: 64)
    }
}

// MARK: - Review Thumbnail (grid)

struct ReviewThumbnail: View {
    let label: String
    let image: UIImage?
    let accentColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5))
                        .frame(height: 140)
                }

                HStack {
                    Text(label)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "pencil.circle.fill")
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.6), Color.clear],
                        startPoint: .bottom, endPoint: .top
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                )
            }
            .frame(height: 140)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(accentColor.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Perspective Silhouette View

struct PerspectiveSilhouetteView: View {

    let carType: CarType
    let angleId: Int

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let color = Color(.systemGray3)

            switch angleId {
            case 0: drawFrontView(context: context, w: w, h: h, color: color)
            case 1: drawRearView(context: context, w: w, h: h, color: color)
            case 2: drawSideView(context: context, w: w, h: h, color: color, mirrored: false)
            case 3: drawSideView(context: context, w: w, h: h, color: color, mirrored: true)
            case 4: drawCornerView(context: context, w: w, h: h, color: color, frontLeft: true)
            case 5: drawCornerView(context: context, w: w, h: h, color: color, frontLeft: false)
            case 6: drawCornerRearView(context: context, w: w, h: h, color: color, rearLeft: true)
            case 7: drawCornerRearView(context: context, w: w, h: h, color: color, rearLeft: false)
            default: break
            }

            var labelText = AttributedString(scanAngles[angleId].label)
            labelText.font = .systemFont(ofSize: 13, weight: .semibold)
            labelText.foregroundColor = Color(.systemGray2)
            context.draw(Text(labelText), at: CGPoint(x: w / 2, y: h - 10), anchor: .bottom)
        }
    }

    private var heightScale: CGFloat {
        switch carType {
        case .suv: return 1.15
        case .mpv: return 1.20
        default:
            if carType.category == .scdf { return 1.35 }
            return 1.0
        }
    }

    private var widthScale: CGFloat {
        switch carType {
        case .mpv: return 1.10
        default:
            if carType.category == .scdf { return 1.25 }
            return 1.0
        }
    }

    private func drawFrontView(context: GraphicsContext, w: CGFloat, h: CGFloat, color: Color) {
        let bodyW = w * 0.62 * widthScale
        let bodyH = h * 0.22 * heightScale
        let roofW = w * 0.38 * widthScale
        let roofH = h * 0.18 * heightScale
        let cx = w / 2
        let groundY = h * 0.75
        let bodyTop = groundY - bodyH

        fill(context, rect: CGRect(x: cx - bodyW/2, y: bodyTop, width: bodyW, height: bodyH), color: color, radius: 8)
        fill(context, rect: CGRect(x: cx - roofW/2, y: bodyTop - roofH + 4, width: roofW, height: roofH), color: color, radius: 6)
        let lightW = bodyW * 0.18, lightH = bodyH * 0.22
        fill(context, rect: CGRect(x: cx - bodyW/2 + 10, y: bodyTop + bodyH * 0.25, width: lightW, height: lightH), color: .white.opacity(0.7), radius: 3)
        fill(context, rect: CGRect(x: cx + bodyW/2 - 10 - lightW, y: bodyTop + bodyH * 0.25, width: lightW, height: lightH), color: .white.opacity(0.7), radius: 3)
        fill(context, rect: CGRect(x: cx - bodyW * 0.22, y: bodyTop + bodyH * 0.55, width: bodyW * 0.44, height: bodyH * 0.28), color: Color(.systemGray5), radius: 3)
        let wRadius = w * 0.08 * widthScale
        fillCircle(context, cx: cx - bodyW/2 + wRadius * 0.6, cy: groundY, r: wRadius, color: color)
        fillCircle(context, cx: cx + bodyW/2 - wRadius * 0.6, cy: groundY, r: wRadius, color: color)
    }

    private func drawRearView(context: GraphicsContext, w: CGFloat, h: CGFloat, color: Color) {
        let bodyW = w * 0.62 * widthScale
        let bodyH = h * 0.22 * heightScale
        let roofW = w * 0.38 * widthScale
        let roofH = h * 0.18 * heightScale
        let cx = w / 2
        let groundY = h * 0.75
        let bodyTop = groundY - bodyH

        fill(context, rect: CGRect(x: cx - bodyW/2, y: bodyTop, width: bodyW, height: bodyH), color: color, radius: 8)
        fill(context, rect: CGRect(x: cx - roofW/2, y: bodyTop - roofH + 4, width: roofW, height: roofH), color: color, radius: 6)
        let lightW = bodyW * 0.18, lightH = bodyH * 0.2
        fill(context, rect: CGRect(x: cx - bodyW/2 + 8, y: bodyTop + bodyH * 0.22, width: lightW, height: lightH), color: Color.red.opacity(0.5), radius: 3)
        fill(context, rect: CGRect(x: cx + bodyW/2 - 8 - lightW, y: bodyTop + bodyH * 0.22, width: lightW, height: lightH), color: Color.red.opacity(0.5), radius: 3)
        let bootPath = Path { p in
            p.move(to: CGPoint(x: cx - bodyW * 0.30, y: bodyTop + 6))
            p.addLine(to: CGPoint(x: cx + bodyW * 0.30, y: bodyTop + 6))
        }
        context.stroke(bootPath, with: .color(Color(.systemGray5)), lineWidth: 2)
        let wRadius = w * 0.08 * widthScale
        fillCircle(context, cx: cx - bodyW/2 + wRadius * 0.6, cy: groundY, r: wRadius, color: color)
        fillCircle(context, cx: cx + bodyW/2 - wRadius * 0.6, cy: groundY, r: wRadius, color: color)
    }

    private func drawSideView(context: GraphicsContext, w: CGFloat, h: CGFloat, color: Color, mirrored: Bool) {
        let bodyW = w * 0.78 * widthScale
        let bodyH = h * 0.22 * heightScale
        let roofW = bodyW * 0.46
        let roofH = h * 0.20 * heightScale
        let cx = w / 2
        let groundY = h * 0.75
        let bodyLeft = cx - bodyW / 2
        let bodyTop = groundY - bodyH

        fill(context, rect: CGRect(x: bodyLeft, y: bodyTop, width: bodyW, height: bodyH), color: color, radius: 8)
        let roofX = mirrored ? bodyLeft + bodyW * 0.32 : bodyLeft + bodyW * 0.22
        fill(context, rect: CGRect(x: roofX, y: bodyTop - roofH + 6, width: roofW, height: roofH), color: color, radius: 8)
        let winH = roofH * 0.70
        let win1X = mirrored ? roofX + roofW * 0.55 : roofX + roofW * 0.04
        let win2X = mirrored ? roofX + roofW * 0.10 : roofX + roofW * 0.52
        fill(context, rect: CGRect(x: win1X, y: bodyTop - winH + 4, width: roofW * 0.36, height: winH), color: Color(.systemGray5), radius: 4)
        fill(context, rect: CGRect(x: win2X, y: bodyTop - winH + 4, width: roofW * 0.36, height: winH), color: Color(.systemGray5), radius: 4)
        let wRadius = w * 0.09 * widthScale
        let frontWheelX = mirrored ? bodyLeft + bodyW * 0.72 : bodyLeft + bodyW * 0.22
        let rearWheelX  = mirrored ? bodyLeft + bodyW * 0.22 : bodyLeft + bodyW * 0.72
        fillCircle(context, cx: frontWheelX, cy: groundY, r: wRadius, color: color)
        fillCircle(context, cx: rearWheelX,  cy: groundY, r: wRadius, color: color)
    }

    private func drawCornerView(context: GraphicsContext, w: CGFloat, h: CGFloat, color: Color, frontLeft: Bool) {
        let cx = w / 2
        let groundY = h * 0.76
        let bodyW = w * 0.64 * widthScale
        let bodyH = h * 0.21 * heightScale
        let bodyTop = groundY - bodyH
        let skew: CGFloat = frontLeft ? -18 : 18

        let bodyPath = Path { p in
            p.move(to:    CGPoint(x: cx - bodyW/2 + skew, y: bodyTop))
            p.addLine(to: CGPoint(x: cx + bodyW/2 + skew, y: bodyTop))
            p.addLine(to: CGPoint(x: cx + bodyW/2,        y: groundY))
            p.addLine(to: CGPoint(x: cx - bodyW/2,        y: groundY))
            p.closeSubpath()
        }
        context.fill(bodyPath, with: .color(color))

        let roofW = bodyW * 0.45
        let roofH = h * 0.17 * heightScale
        let roofLeft = frontLeft ? cx - bodyW/2 + skew + bodyW*0.10 : cx - bodyW/2 + skew + bodyW*0.45
        fill(context, rect: CGRect(x: roofLeft, y: bodyTop - roofH + 5, width: roofW, height: roofH), color: color, radius: 6)

        let hX = frontLeft ? cx - bodyW/2 + skew + 6 : cx + bodyW/2 + skew - 28
        fill(context, rect: CGRect(x: hX, y: bodyTop + bodyH*0.2, width: 20, height: 12), color: .white.opacity(0.7), radius: 3)

        let wRadius = w * 0.082 * widthScale
        fillCircle(context, cx: cx - bodyW/2 + wRadius, cy: groundY, r: wRadius, color: color)
        fillCircle(context, cx: cx + bodyW/2 - wRadius, cy: groundY, r: wRadius, color: color)
    }

    private func drawCornerRearView(context: GraphicsContext, w: CGFloat, h: CGFloat, color: Color, rearLeft: Bool) {
        let cx = w / 2
        let groundY = h * 0.76
        let bodyW = w * 0.64 * widthScale
        let bodyH = h * 0.21 * heightScale
        let bodyTop = groundY - bodyH
        let skew: CGFloat = rearLeft ? 18 : -18

        let bodyPath = Path { p in
            p.move(to:    CGPoint(x: cx - bodyW/2 + skew, y: bodyTop))
            p.addLine(to: CGPoint(x: cx + bodyW/2 + skew, y: bodyTop))
            p.addLine(to: CGPoint(x: cx + bodyW/2,        y: groundY))
            p.addLine(to: CGPoint(x: cx - bodyW/2,        y: groundY))
            p.closeSubpath()
        }
        context.fill(bodyPath, with: .color(color))

        let roofW = bodyW * 0.45
        let roofH = h * 0.17 * heightScale
        let roofLeft = rearLeft ? cx - bodyW/2 + skew + bodyW*0.45 : cx - bodyW/2 + skew + bodyW*0.10
        fill(context, rect: CGRect(x: roofLeft, y: bodyTop - roofH + 5, width: roofW, height: roofH), color: color, radius: 6)

        let tX = rearLeft ? cx - bodyW/2 + skew + 6 : cx + bodyW/2 + skew - 28
        fill(context, rect: CGRect(x: tX, y: bodyTop + bodyH*0.2, width: 20, height: 12), color: Color.red.opacity(0.5), radius: 3)

        let wRadius = w * 0.082 * widthScale
        fillCircle(context, cx: cx - bodyW/2 + wRadius, cy: groundY, r: wRadius, color: color)
        fillCircle(context, cx: cx + bodyW/2 - wRadius, cy: groundY, r: wRadius, color: color)
    }

    private func fill(_ context: GraphicsContext, rect: CGRect, color: Color, radius: CGFloat) {
        context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(color))
    }

    private func fillCircle(_ context: GraphicsContext, cx: CGFloat, cy: CGFloat, r: CGFloat, color: Color) {
        context.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)), with: .color(color))
    }
}
