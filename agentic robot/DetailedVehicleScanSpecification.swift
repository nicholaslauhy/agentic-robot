import Foundation

// MARK: - Four-angle baseline coordinate system

/// The detailed panel scan adds evidence to the existing four-angle workflow.
/// It does not create a separate 12-image baseline.
enum VehicleOverviewAngle: Int, CaseIterable, Codable, Identifiable, Sendable {
    case front = 0
    case rear = 1
    case leftSide = 2
    case rightSide = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .front: return "Front"
        case .rear: return "Rear"
        case .leftSide: return "Left Side"
        case .rightSide: return "Right Side"
        }
    }
}

// MARK: - Detailed panel sequence

/// Stable identifiers for detailed capture zones. The declaration order is the
/// recommended walk-around order, beginning at the front and ending at the
/// right-front corner.
enum DetailedVehiclePanel: String, CaseIterable, Codable, Identifiable, Sendable {
    case frontUpper = "front_upper"
    case frontLower = "front_lower"

    case leftFrontQuarter = "left_front_quarter"
    case leftFrontDoor = "left_front_door"
    case leftRearDoor = "left_rear_door"
    case leftRearQuarter = "left_rear_quarter"

    case rearUpper = "rear_upper"
    case rearLower = "rear_lower"

    case rightRearQuarter = "right_rear_quarter"
    case rightRearDoor = "right_rear_door"
    case rightFrontDoor = "right_front_door"
    case rightFrontQuarter = "right_front_quarter"

    var id: String { rawValue }

    var sequenceNumber: Int {
        Self.allCases.firstIndex(of: self).map { $0 + 1 } ?? 0
    }

    var overviewAngle: VehicleOverviewAngle {
        switch self {
        case .frontUpper, .frontLower:
            return .front
        case .rearUpper, .rearLower:
            return .rear
        case .leftFrontQuarter, .leftFrontDoor, .leftRearDoor, .leftRearQuarter:
            return .leftSide
        case .rightRearQuarter, .rightRearDoor, .rightFrontDoor, .rightFrontQuarter:
            return .rightSide
        }
    }

    var displayName: String {
        switch self {
        case .frontUpper: return "Front Upper"
        case .frontLower: return "Front Bumper"
        case .leftFrontQuarter: return "Left Front Quarter"
        case .leftFrontDoor: return "Left Front Door"
        case .leftRearDoor: return "Left Rear Door"
        case .leftRearQuarter: return "Left Rear Quarter"
        case .rearUpper: return "Rear Upper"
        case .rearLower: return "Rear Bumper"
        case .rightRearQuarter: return "Right Rear Quarter"
        case .rightRearDoor: return "Right Rear Door"
        case .rightFrontDoor: return "Right Front Door"
        case .rightFrontQuarter: return "Right Front Quarter"
        }
    }

    var coverageHint: String {
        switch self {
        case .frontUpper:
            return "Keep the bonnet, grille and both headlamps visible."
        case .frontLower:
            return "Keep the full front bumper and both lower corners visible."
        case .rearUpper:
            return "Keep the boot or tailgate and both rear lamps visible."
        case .rearLower:
            return "Keep the full rear bumper and both lower corners visible."
        case .leftFrontQuarter, .rightFrontQuarter:
            return "Keep the front wheel arch and adjoining body panel visible."
        case .leftFrontDoor, .rightFrontDoor:
            return "Keep the complete front door panel visible."
        case .leftRearDoor, .rightRearDoor:
            return "Keep the complete rear door panel visible."
        case .leftRearQuarter, .rightRearQuarter:
            return "Keep the rear wheel arch and adjoining body panel visible."
        }
    }
}

enum DetailedScanCapturePose: String, CaseIterable, Codable, Identifiable, Sendable {
    case leftOblique = "left_oblique"
    case slightLeft = "slight_left"
    case straight = "straight"
    case slightRight = "slight_right"
    case rightOblique = "right_oblique"

    var id: String { rawValue }

    /// Nominal viewing angle relative to a straight-on view of the panel.
    var nominalDegrees: Int {
        switch self {
        case .leftOblique: return -20
        case .slightLeft: return -10
        case .straight: return 0
        case .slightRight: return 10
        case .rightOblique: return 20
        }
    }
}

enum DetailedScanBaselinePolicy: String, Codable, Sendable {
    /// Map panel findings into front, rear, left or right coordinates before
    /// comparing or updating the existing baseline.
    case retainFourOverviewAngles
}

enum DetailedScanDuplicatePolicy: String, Codable, Sendable {
    /// Candidate fragments are mapped to the overview image first, then merged
    /// by location and appearance so a scratch crossing two panels remains one
    /// damage case.
    case mapToOverviewThenMerge
}

enum DetailedScanBaselineUpdateTrigger: String, Codable, Sendable {
    /// Capture and review do not modify the confirmed baseline. The baseline is
    /// changed only after the associated NP299 report has been filed.
    case np299ReportFiled
}

// MARK: - Phase 0 specification

/// Single source of truth for the first version of the detailed vehicle scan.
/// Later phases should read these values instead of duplicating panel order,
/// capture guidance or baseline rules in individual views and services.
struct DetailedVehicleScanSpecification {
    static let version = 1

    /// Detailed scanning is an additional step, not a replacement for the four
    /// overview photographs. It is optional while the workflow is evaluated.
    static let isOptional = true
    static let requiredOverviewCaptureCount = VehicleOverviewAngle.allCases.count
    static let beginsOnlyAfterOverviewCapture = true

    static let panels = DetailedVehiclePanel.allCases
    static let capturePoses = DetailedScanCapturePose.allCases

    /// One continuous arc is recorded for each panel. The operator moves around
    /// the panel while keeping it centred; rotating the iPad from one spot is
    /// not sufficient because the reflections need to change with viewpoint.
    static let recommendedRecordingDurationSeconds: ClosedRange<Double> = 3.0...7.0
    static let preferredRecordingDurationSeconds = 5.0
    static let maximumRecordingDurationSeconds = 30.0
    static let preferredVideoWidth = 3840
    static let preferredVideoHeight = 2160
    static let preferredCameraZoomFactor = 1.0
    static let automaticallyEnableTorch = false

    /// A proportional target works for both passenger cars and larger response
    /// vehicles, where one fixed camera-to-vehicle distance would not.
    static let acceptablePanelFrameCoverage: ClosedRange<Double> = 0.55...0.90
    static let targetPanelFrameCoverage = 0.72

    static let operatorInstruction =
        "Move in one slow arc from left-oblique, through straight-on, to right-oblique. Keep the highlighted panel centred and fully visible."

    static let baselinePolicy: DetailedScanBaselinePolicy = .retainFourOverviewAngles
    static let duplicatePolicy: DetailedScanDuplicatePolicy = .mapToOverviewThenMerge
    static let baselineUpdateTrigger: DetailedScanBaselineUpdateTrigger = .np299ReportFiled

    /// Roof capture is deliberately excluded from version 1. It can be added as
    /// a separate zone later without changing the four-angle baseline contract.
    static let includesRoof = false

    static func panels(for angle: VehicleOverviewAngle) -> [DetailedVehiclePanel] {
        panels.filter { $0.overviewAngle == angle }
    }
}
