//
//  CarTypeSelectionView.swift
//  agentic robot
//
//  Created by q2 on 14/5/26.
//

import SwiftUI

enum CarCategory: String, CaseIterable {
    case civilian = "Civilian Vehicle"
    case scdf = "SCDF Vehicle"
}

enum CarType: String, CaseIterable, Identifiable {
    // Civilian
    case sedan = "Sedan"
    case suv = "SUV"
    case mpv = "MPV"
    // SCDF
    case pumpLadder = "Pump Ladder"
    case lightFireAttack = "Light Fire Attack Vehicle"
    case fireMedical = "Fire Medical Vehicle"
    case emergencyAmbulance = "Emergency Ambulance"
    case combinedPlatformLadder = "Combined Platform Ladder"
    case medicalSupport = "Medical Support Vehicle"
    case respondersPerformance = "Responders Performance Vehicle"
    case hazmat = "Hazmat & Special Rescue Vehicle"

    var id: String { rawValue }

    var category: CarCategory {
        switch self {
        case .sedan, .suv, .mpv: return .civilian
        default: return .scdf
        }
    }

    var icon: String {
        switch self {
        case .sedan:                  return "car.fill"
        case .suv:                    return "car.fill"
        case .mpv:                    return "bus.fill"
        case .pumpLadder:             return "flame.fill"
        case .lightFireAttack:        return "bolt.fill"
        case .fireMedical:            return "cross.fill"
        case .emergencyAmbulance:     return "staroflife.fill"
        case .combinedPlatformLadder: return "arrow.up.to.line"
        case .medicalSupport:         return "cross.case.fill"
        case .respondersPerformance:  return "figure.run"
        case .hazmat:                 return "hazardsign.fill"
        }
    }

    var accentColor: Color {
        HTXTheme.primaryPurple
    }
}

struct CarTypeSelectionView: View {

    let plate: String
    var onLogout: () -> Void
    var onCarTypeSelected: (CarType) -> Void

    @State private var selectedCategory: CarCategory = .civilian
    @State private var selectedType: CarType? = nil
    @State private var showConfirmBanner = false

    private var filteredTypes: [CarType] {
        CarType.allCases.filter { $0.category == selectedCategory }
    }

    var body: some View {
        ZStack {
            SubtleHTXBackground()

            VStack(spacing: 0) {

            // HEADER
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vehicle Type")
                        .font(.largeTitle)
                        .foregroundColor(HTXTheme.primaryPurple).bold()
                    Text("Plate: \(plate)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Logout") { onLogout() }
                    .foregroundColor(.red)
            }
            .padding()

            // CATEGORY PICKER
            Picker("Category", selection: $selectedCategory) {
                ForEach(CarCategory.allCases, id: \.self) { cat in
                    Text(cat.rawValue).tag(cat)
                }
            }
            .pickerStyle(.segmented)
            .tint(HTXTheme.primaryPurple)
            .padding(.horizontal)
            .onChange(of: selectedCategory) { _, _ in
                selectedType = nil
            }

            // TYPE GRID
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 16
                ) {
                    ForEach(filteredTypes) { type in
                        CarTypeCard(
                            type: type,
                            isSelected: selectedType == type
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) {
                                selectedType = type
                            }
                        }
                    }
                }
                .padding()
            }

            // CONFIRM BUTTON
            if let selected = selectedType {
                VStack(spacing: 8) {
                    Text("Let's now start scanning the car for any scratches or dents.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))

                    Button {
                        onCarTypeSelected(selected)
                    } label: {
                        Text("Start Scan — \(selected.rawValue)")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(HTXTheme.primaryPurple)
                            .foregroundColor(.white)
                            .cornerRadius(14)
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom, 20)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.spring(response: 0.4), value: selectedType)
            }
        }
        }
        .navigationBarBackButtonHidden(true)
        .tint(HTXTheme.primaryPurple)
    }
}

struct CarTypeCard: View {

    let type: CarType
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: type.icon)
                .font(.system(size: 32))
                .foregroundColor(isSelected ? .white : HTXTheme.primaryPurple)

            Text(type.rawValue)
                .font(.subheadline)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .foregroundColor(isSelected ? .white : .primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? HTXTheme.primaryPurple : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? HTXTheme.primaryPurple : HTXTheme.softPurpleBorder, lineWidth: 2)
        )
        .scaleEffect(isSelected ? 1.04 : 1.0)
        .shadow(color: isSelected ? HTXTheme.primaryPurple.opacity(0.28) : .clear, radius: 8, y: 4)
        .animation(.spring(response: 0.3), value: isSelected)
    }
}
