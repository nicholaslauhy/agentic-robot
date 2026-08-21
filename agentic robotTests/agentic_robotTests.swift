//
//  agentic_robotTests.swift
//  agentic robotTests
//
//  Created by q2 on 12/5/26.
//

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
            DetailedVehicleScanSpecification.recordingDurationSeconds,
            3.0...7.0
        )
        XCTAssertEqual(
            DetailedVehicleScanSpecification.preferredRecordingDurationSeconds,
            5.0
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

    func testDetailedPanelResponsePreservesPersistenceMetadata() throws {
        let json = """
        {
          "panelId": "left_front_door",
          "processedFrames": 5,
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
