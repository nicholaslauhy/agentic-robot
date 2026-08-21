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

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }

}
