//
//  ReportTypeSelectionView.swift
//  agentic robot
//
//  Created by q2 on 29/5/26.
//

import SwiftUI

// MARK: - Report Type
enum ReportType: String, CaseIterable, Identifiable {
    case np299        = "NP299 Police Report"
    case secCom       = "SecCom Vehicle Pre-Driving Checklist"
    case fuelRefuel   = "Fuel Refuel Report"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .np299:      return "doc.text.magnifyingglass"
        case .secCom:     return "checklist"
        case .fuelRefuel: return "fuelpump.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .np299:      return "Scan licence plate and generate a police damage report"
        case .secCom:     return "Pre-driving vehicle inspection and equipment checklist"
        case .fuelRefuel: return "Record fuel top-up details and attach receipt"
        }
    }

    var accentColor: Color {
        switch self {
        case .np299:      return HTXTheme.primaryPurple
        case .secCom:     return Color(red: 0.08, green: 0.50, blue: 0.30)
        case .fuelRefuel: return Color(red: 0.80, green: 0.40, blue: 0.00)
        }
    }
}

// MARK: - View
struct ReportTypeSelectionView: View {

    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var navigateToNP299     = false
    @State private var navigateToSecCom    = false
    @State private var navigateToFuel      = false

    var body: some View {
        ZStack {
            SubtleHTXBackground()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Report Generation")
                            .font(.largeTitle.weight(.bold))
                            .foregroundColor(HTXTheme.primaryPurple)
                        Text("Choose the type of report to fill")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Logout") { auth.logout() }
                        .foregroundColor(.red)
                }
                .padding()

                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(ReportType.allCases) { type in
                            ReportTypeCard(type: type) {
                                switch type {
                                case .np299:      navigateToNP299  = true
                                case .secCom:     navigateToSecCom = true
                                case .fuelRefuel: navigateToFuel   = true
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationBarBackButtonHidden(false)
        .tint(HTXTheme.primaryPurple)
        // NP299 — existing flow
        .navigationDestination(isPresented: $navigateToNP299) {
            LoggedInView()
        }
        // SecCom checklist
        .navigationDestination(isPresented: $navigateToSecCom) {
            SecComPreDrivingChecklistView {
                navigateToSecCom = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    dismiss()
                }
            }
        }
        // Fuel refuel
        .navigationDestination(isPresented: $navigateToFuel) {
            FuelRefuelView {
                navigateToFuel = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Card
private struct ReportTypeCard: View {
    let type: ReportType
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: type.icon)
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(
                        LinearGradient(
                            colors: [type.accentColor, type.accentColor.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(type.rawValue)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    Text(type.subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(type.accentColor)
            }
            .padding()
            .subtleHTXCard()
        }
        .buttonStyle(.plain)
    }
}
