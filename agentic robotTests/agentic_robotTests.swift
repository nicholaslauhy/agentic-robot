//
//  agentic_robotTests.swift
//  agentic robotTests
//
//  Created by q2 on 12/5/26.
//

import AVFoundation
import XCTest
@testable import HTX_Inspect

final class agentic_robotTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testDetailedScanRemainsAnAdditionToFourOverviewAngles() {
        XCTAssertTrue(DetailedVehicleScanSpecification.isOptional)
        XCTAssertTrue(DetailedVehicleScanSpecification.beginsOnlyAfterOverviewCapture)
        XCTAssertEqual(DetailedVehicleScanSpecification.requiredOverviewCaptureCount, 4)
        XCTAssertEqual(
            DetailedVehicleScanSpecification.baselinePolicy,
            .retainFourOverviewAngles
        )
    }

    func testDetailedScanHasStableTwelvePanelWalkAround() {
        let panels = DetailedVehicleScanSpecification.panels

        XCTAssertEqual(panels.count, 12)
        XCTAssertEqual(Set(panels.map(\.id)).count, panels.count)
        XCTAssertEqual(panels.map(\.sequenceNumber), Array(1...12))
        XCTAssertEqual(panels.first, .frontUpper)
        XCTAssertEqual(panels.last, .rightFrontQuarter)
    }

    func testEveryDetailedPanelMapsBackToOneOverviewAngle() {
        XCTAssertEqual(DetailedVehicleScanSpecification.panels(for: .front).count, 2)
        XCTAssertEqual(DetailedVehicleScanSpecification.panels(for: .rear).count, 2)
        XCTAssertEqual(DetailedVehicleScanSpecification.panels(for: .leftSide).count, 4)
        XCTAssertEqual(DetailedVehicleScanSpecification.panels(for: .rightSide).count, 4)
    }

    func testCaptureSweepProvidesFiveOrderedViewpoints() {
        XCTAssertEqual(
            DetailedVehicleScanSpecification.capturePoses.map(\.nominalDegrees),
            [-20, -10, 0, 10, 20]
        )
        XCTAssertFalse(DetailedVehicleScanSpecification.automaticallyEnableTorch)
    }

    func testGuidedRecordingUsesShortControlledSweep() {
        XCTAssertEqual(
            DetailedVehicleScanSpecification.recommendedRecordingDurationSeconds,
            3.0...7.0
        )
        XCTAssertEqual(
            DetailedVehicleScanSpecification.preferredRecordingDurationSeconds,
            5.0
        )
        XCTAssertEqual(
            DetailedVehicleScanSpecification.maximumRecordingDurationSeconds,
            30.0
        )
    }

    func testCameraGuideUsesNearlyAllOfPortraitScreen() {
        let size = CGSize(width: 834, height: 1194)
        let layout = DetailedCameraGuideLayout(size: size, angle: .front)

        XCTAssertGreaterThanOrEqual(layout.guideRect.width / size.width, 0.95)
        XCTAssertGreaterThanOrEqual(layout.guideRect.height / size.height, 0.82)
        XCTAssertTrue(layout.guideRect.contains(layout.silhouetteRect))
        XCTAssertEqual(
            layout.silhouetteRect.width / layout.silhouetteRect.height,
            1.55,
            accuracy: 0.01
        )
    }

    func testCameraGuideUsesNearlyAllOfLandscapeScreen() {
        let size = CGSize(width: 1194, height: 834)
        let layout = DetailedCameraGuideLayout(size: size, angle: .leftSide)

        XCTAssertGreaterThanOrEqual(layout.guideRect.width / size.width, 0.95)
        XCTAssertGreaterThanOrEqual(layout.guideRect.height / size.height, 0.75)
        XCTAssertTrue(layout.guideRect.contains(layout.silhouetteRect))
        XCTAssertEqual(
            layout.silhouetteRect.width / layout.silhouetteRect.height,
            2.05,
            accuracy: 0.01
        )
    }

    func testDetailedScanQualityRequiresThreeUsableViewpoints() {
        let clearFrames = (0..<5).map { index in
            DetailedScanFrame(
                timestampSeconds: Double(index),
                image: UIImage(),
                brightness: 0.50,
                sharpness: 0.03,
                clippedPixelRatio: 0.02
            )
        }
        XCTAssertTrue(DetailedScanFrameProcessor.assess(clearFrames).passed)

        let blurredFrames = (0..<5).map { index in
            DetailedScanFrame(
                timestampSeconds: Double(index),
                image: UIImage(),
                brightness: 0.50,
                sharpness: 0.002,
                clippedPixelRatio: 0.02
            )
        }
        let rejected = DetailedScanFrameProcessor.assess(blurredFrames)
        XCTAssertFalse(rejected.passed)
        XCTAssertTrue(rejected.issues.contains { $0.localizedCaseInsensitiveContains("shaky") })
    }

    @MainActor
    func testDetailedFrameProcessorExtractsFiveFramesFromVideo() async throws {
        let videoURL = try await makeTexturedTestVideo()
        defer { try? FileManager.default.removeItem(at: videoURL) }

        let processed = try await DetailedScanFrameProcessor.process(
            videoURL: videoURL,
            durationSeconds: 3
        )

        XCTAssertEqual(
            processed.frames.count,
            DetailedScanFrameProcessor.representativeFrameCount
        )
        XCTAssertEqual(processed.assessment.usableFrameCount, 5)
        XCTAssertTrue(processed.assessment.passed)
        for (actual, expected) in zip(
            processed.frames.map(\.timestampSeconds),
            DetailedScanFrameProcessor.sampleFractions.map { $0 * 3 }
        ) {
            XCTAssertEqual(actual, expected, accuracy: 0.03)
        }
    }

    @MainActor
    func testDetailedSubmissionRejectsEmptyCapturePayload() {
        XCTAssertThrowsError(try DetailedScanSubmissionValidator.validate([])) { error in
            guard case DetailedScanAnalysisError.noCaptures = error else {
                return XCTFail("Expected noCaptures, received \(error)")
            }
        }
    }

    @MainActor
    func testDetailedSubmissionRequiresEveryExpectedPanel() {
        let captures = DetailedVehicleScanSpecification.panels.dropLast().map {
            makeDetailedCapture(panel: $0)
        }

        XCTAssertThrowsError(try DetailedScanSubmissionValidator.validate(captures)) { error in
            guard case DetailedScanAnalysisError.incompleteCaptureSet(let missing, _) = error else {
                return XCTFail("Expected incompleteCaptureSet, received \(error)")
            }
            XCTAssertEqual(missing, [.rightFrontQuarter])
        }
    }

    @MainActor
    func testDetailedSubmissionRequiresFiveFramesForEveryPanel() {
        var captures = DetailedVehicleScanSpecification.panels.map {
            makeDetailedCapture(panel: $0)
        }
        captures[captures.count - 1] = makeDetailedCapture(
            panel: .rightFrontQuarter,
            frameCount: 4
        )

        XCTAssertThrowsError(try DetailedScanSubmissionValidator.validate(captures)) { error in
            guard case DetailedScanAnalysisError.incompletePanelFrames(
                let panel,
                let expected,
                let actual
            ) = error else {
                return XCTFail("Expected incompletePanelFrames, received \(error)")
            }
            XCTAssertEqual(panel, .rightFrontQuarter)
            XCTAssertEqual(expected, 5)
            XCTAssertEqual(actual, 4)
        }
    }

    @MainActor
    func testDetailedSubmissionIsReturnedInCanonicalPanelOrder() throws {
        let captures = DetailedVehicleScanSpecification.panels.reversed().map {
            makeDetailedCapture(panel: $0)
        }
        let validated = try DetailedScanSubmissionValidator.validate(captures)

        XCTAssertEqual(
            validated.map(\.panel),
            DetailedVehicleScanSpecification.panels
        )
        XCTAssertEqual(validated.reduce(0) { $0 + $1.representativeFrames.count }, 60)
    }

    @MainActor
    func testDetailedBackendReceiptMustAcknowledgeEverySubmittedFrame() {
        let capture = makeDetailedCapture(panel: .frontUpper)
        let response = DetailedPanelAnalysisResponse(
            panelId: DetailedVehiclePanel.frontUpper.rawValue,
            processedFrames: 4,
            analysisPerformed: true,
            analysisRequestId: "test-request",
            results: []
        )

        XCTAssertThrowsError(
            try DetailedScanSubmissionValidator.validate(
                response: response,
                for: capture,
                submittedFrameCount: 5
            )
        ) { error in
            guard case DetailedScanAnalysisError.mismatchedProcessedFrameCount(
                let panel,
                let expected,
                let actual
            ) = error else {
                return XCTFail("Expected mismatchedProcessedFrameCount, received \(error)")
            }
            XCTAssertEqual(panel, .frontUpper)
            XCTAssertEqual(expected, 5)
            XCTAssertEqual(actual, 4)
        }
    }

    @MainActor
    func testDetailedBackendMustConfirmAnalysisWasPerformed() {
        let capture = makeDetailedCapture(panel: .frontUpper)
        let response = DetailedPanelAnalysisResponse(
            panelId: DetailedVehiclePanel.frontUpper.rawValue,
            processedFrames: 5,
            analysisPerformed: false,
            analysisRequestId: "",
            results: []
        )

        XCTAssertThrowsError(
            try DetailedScanSubmissionValidator.validate(
                response: response,
                for: capture,
                submittedFrameCount: 5
            )
        ) { error in
            guard case DetailedScanAnalysisError.backendAnalysisNotConfirmed(let panel) = error else {
                return XCTFail("Expected backendAnalysisNotConfirmed, received \(error)")
            }
            XCTAssertEqual(panel, .frontUpper)
        }
    }

    @MainActor
    private func makeDetailedCapture(
        panel: DetailedVehiclePanel,
        frameCount: Int = DetailedScanFrameProcessor.representativeFrameCount
    ) -> DetailedPanelCapture {
        let frames = (0..<frameCount).map { index in
            DetailedScanFrame(
                timestampSeconds: Double(index),
                image: UIImage(),
                brightness: 0.5,
                sharpness: 0.03,
                clippedPixelRatio: 0.02
            )
        }
        return DetailedPanelCapture(
            panel: panel,
            previewImage: UIImage(),
            videoURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("\(panel.rawValue)-test.mov"),
            durationSeconds: 5,
            representativeFrames: frames,
            qualityAssessment: DetailedScanQualityAssessment(
                passed: true,
                usableFrameCount: frameCount,
                totalFrameCount: frameCount,
                issues: []
            )
        )
    }

    private func makeTexturedTestVideo() async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("detailed-frame-test-\(UUID().uuidString).mov")
        let width = 320
        let height = 240
        let frameRate: Int32 = 15
        let frameCount = 45
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
        )
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        guard writer.canAdd(input) else {
            throw NSError(
                domain: "DetailedScanVideoTest",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not add the video writer input."]
            )
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "DetailedScanVideoTest", code: 2)
        }
        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            let pixelBuffer = try makeTexturedPixelBuffer(
                width: width,
                height: height,
                phase: frameIndex
            )
            let appended = adaptor.append(
                pixelBuffer,
                withPresentationTime: CMTime(value: Int64(frameIndex), timescale: frameRate)
            )
            guard appended else {
                throw writer.error ?? NSError(domain: "DetailedScanVideoTest", code: 3)
            }
        }

        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw writer.error ?? NSError(domain: "DetailedScanVideoTest", code: 4)
        }
        return url
    }

    private func makeTexturedPixelBuffer(
        width: Int,
        height: Int,
        phase: Int
    ) throws -> CVPixelBuffer {
        var optionalBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &optionalBuffer
        )
        guard status == kCVReturnSuccess, let buffer = optionalBuffer else {
            throw NSError(domain: "DetailedScanVideoTest", code: 5)
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw NSError(domain: "DetailedScanVideoTest", code: 6)
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            let row = baseAddress.advanced(by: y * bytesPerRow)
                .assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let isLight = ((x / 8) + (y / 8) + (phase / 3)).isMultiple(of: 2)
                let value: UInt8 = isLight ? 205 : 50
                let offset = x * 4
                row[offset] = value
                row[offset + 1] = value
                row[offset + 2] = value
                row[offset + 3] = 255
            }
        }
        return buffer
    }

    @MainActor
    func testDetailedPanelResponsePreservesPersistenceMetadata() throws {
        let json = """
        {
          "panelId": "left_front_door",
          "processedFrames": 5,
          "analysisPerformed": true,
          "analysisRequestId": "unit-test-request",
          "results": [{
            "panelId": "left_front_door",
            "frameIndex": 2,
            "observedFrames": 4,
            "totalFrames": 5,
            "persistence": 0.8,
            "multiFrameStatus": "corroborated",
            "normalisedTrackBox": [0.2, 0.3, 0.4, 0.5],
            "angleIndex": 2,
            "angleName": "Left Side",
            "damageType": "scratch",
            "confidence": 0.81,
            "cropBase64": "",
            "contextBase64": "",
            "cleanContextBase64": ""
          }]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(DetailedPanelAnalysisResponse.self, from: json)
        XCTAssertTrue(decoded.analysisPerformed)
        XCTAssertEqual(decoded.analysisRequestId, "unit-test-request")
        XCTAssertEqual(decoded.results.first?.observedFrames, 4)
        XCTAssertEqual(decoded.results.first?.damage.damageType, "scratch")
    }

    func testAdjacentPanelFragmentsMergeAfterOverviewProjection() {
        func finding(panel: String, x1: Int, x2: Int) -> DetailedProjectedDamageFinding {
            DetailedProjectedDamageFinding(
                panelIds: [panel],
                observedFrames: 3,
                totalFrames: 5,
                persistence: 0.6,
                multiFrameStatus: "corroborated",
                projectionMethod: "feature_affine",
                projectionConfidence: 0.8,
                projectionInliers: 12,
                projectionInlierRatio: 0.6,
                damage: DamageDetection(
                    angleIndex: 2,
                    angleName: "Left Side",
                    damageType: "scratch",
                    confidence: 0.8,
                    x1: x1,
                    y1: 300,
                    x2: x2,
                    y2: 350,
                    imageWidth: 1000,
                    imageHeight: 700
                )
            )
        }

        let merged = DetailedScanDuplicateMerger.merge([
            finding(panel: "left_front_door", x1: 400, x2: 505),
            finding(panel: "left_rear_door", x1: 510, x2: 620),
        ])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(Set(merged[0].panelIds).count, 2)
    }

    func testBaselineUpdatesOnlyAfterNP299IsFiled() {
        XCTAssertEqual(
            DetailedVehicleScanSpecification.baselineUpdateTrigger,
            .np299ReportFiled
        )
        XCTAssertEqual(
            DetailedVehicleScanSpecification.duplicatePolicy,
            .mapToOverviewThenMerge
        )
    }

    @MainActor
    func testReviewedDetailedDamageAvoidsDuplicateOverviewCaseButKeepsManualCase() {
        func detection(x: CGFloat, source: DamageCaptureSource) -> MutableDamageDetection {
            MutableDamageDetection(
                angleIndex: 2,
                angleName: "Left Side",
                damageType: "scratch",
                confidence: 0.8,
                cropImage: nil,
                contextImage: nil,
                cleanContextImage: nil,
                normalizedBBox: CGRect(x: x, y: 0.30, width: 0.15, height: 0.08),
                captureSource: source
            )
        }

        let overview = detection(x: 0.20, source: .overviewAnalysis)
        let duplicateDetailed = detection(x: 0.21, source: .detailedMultiAngle)
        let manual = detection(x: 0.21, source: .manual)
        let result = DetailedFindingIntegrator.integrating(
            existing: [overview],
            outcome: DetailedScanReviewOutcome(
                acceptedFindings: [duplicateDetailed],
                manualDetections: [manual]
            )
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains { $0.id == overview.id })
        XCTAssertTrue(result.contains { $0.id == manual.id })
        XCTAssertFalse(result.contains { $0.id == duplicateDetailed.id })
    }

    @MainActor
    func testDetailedEvidenceDescriptionRetainsViewCount() {
        let detection = MutableDamageDetection(
            angleIndex: 0,
            angleName: "Front",
            damageType: "dent",
            confidence: 0.75,
            cropImage: nil,
            contextImage: nil,
            cleanContextImage: nil,
            normalizedBBox: CGRect(x: 0.2, y: 0.3, width: 0.1, height: 0.1),
            captureSource: .detailedMultiAngle,
            observedFrameCount: 4,
            totalFrameCount: 5
        )

        XCTAssertEqual(
            detection.detailedEvidenceDescription,
            "Confirmed from 4 of 5 multi-angle views"
        )
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }

}
