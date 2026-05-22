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
        switch self.category {
        case .civilian: return HTXTheme.cyan
        case .scdf:     return Color(red: 1.00, green: 0.36, blue: 0.30)
        }
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
            HTXBackground()

            VStack(spacing: 0) {
                HTXScreenHeader(
                    title: "Vehicle Type",
                    subtitle: "Plate: \(plate)",
                    trailing: AnyView(HTXLogoutButton { onLogout() })
                )
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 18)

                Picker("Category", selection: $selectedCategory) {
                    ForEach(CarCategory.allCases, id: \.self) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .tint(HTXTheme.accentBright)
                .onChange(of: selectedCategory) { _, _ in
                    selectedType = nil
                }

                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 14
                    ) {
                        ForEach(filteredTypes) { type in
                            CarTypeCard(
                                type: type,
                                isSelected: selectedType == type
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                    selectedType = type
                                }
                            }
                        }
                    }
                    .padding(20)
                    .padding(.bottom, selectedType == nil ? 24 : 118)
                }
            }

            VStack {
                Spacer()
                if let selected = selectedType {
                    HTXCard {
                        VStack(spacing: 12) {
                            Text("Let's now start scanning the car for any scratches or dents.")
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .foregroundColor(HTXTheme.accent.opacity(0.95))

                            HTXPrimaryButton("START SCAN — \(selected.rawValue.uppercased())") {
                                onCarTypeSelected(selected)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.86), value: selectedType)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct CarTypeCard: View {

    let type: CarType
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: type.icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 58, height: 58)
                .background(type.accentColor.opacity(isSelected ? 0.42 : 0.20))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(type.accentColor.opacity(isSelected ? 0.85 : 0.35), lineWidth: 1)
                )

            Text(type.rawValue)
                .font(.subheadline.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 142)
        .padding(.vertical, 16)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(isSelected ? 0.17 : 0.09))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(type.accentColor.opacity(isSelected ? 0.70 : 0.18), lineWidth: isSelected ? 1.8 : 1)
        )
        .shadow(color: isSelected ? type.accentColor.opacity(0.25) : .clear, radius: 14, y: 8)
        .scaleEffect(isSelected ? 1.035 : 1.0)
        .animation(.spring(response: 0.3), value: isSelected)
    }
}
