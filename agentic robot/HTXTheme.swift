//
//  HTXTheme.swift
//  agentic robot
//
//  Created by q2 on 22/5/26.
//

import SwiftUI

// MARK: - HTX Brand Colors & Theme
enum HTXTheme {
    static let gradientTop    = Color(red: 0.18, green: 0.00, blue: 0.38)   // #2D0060
    static let gradientMid    = Color(red: 0.55, green: 0.18, blue: 0.72)   // brighter HTX purple
    static let gradientBot    = Color(red: 0.29, green: 0.00, blue: 0.50)   // #4A0080
    static let accent         = Color(red: 0.81, green: 0.58, blue: 0.85)   // #CE93D8
    static let accentBright   = Color(red: 0.88, green: 0.25, blue: 0.98)   // #E040FB
    static let cyan           = Color(red: 0.00, green: 0.78, blue: 1.00)
    static let deepPurple     = Color(red: 0.20, green: 0.00, blue: 0.35)
    static let cardBg         = Color.white.opacity(0.12)
    static let cardBorder     = Color.white.opacity(0.20)
    static let inputBg        = Color.white.opacity(0.12)
    static let inputBorder    = Color.white.opacity(0.25)
    static let errorRed       = Color(red: 1, green: 0.42, blue: 0.42)
    static let successGreen   = Color(red: 0.41, green: 0.94, blue: 0.68)
    static let destructiveRed = Color(red: 1, green: 0.27, blue: 0.27)
    static let civBlue        = Color(red: 0.08, green: 0.40, blue: 0.85)
    static let scdfRed        = Color(red: 0.72, green: 0.11, blue: 0.09)
}

// MARK: - Background Gradient
struct HTXBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.91, green: 0.82, blue: 0.95),
                    HTXTheme.gradientMid,
                    HTXTheme.gradientBot,
                    HTXTheme.deepPurple
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [HTXTheme.accentBright.opacity(0.28), .clear],
                center: UnitPoint(x: 0.76, y: 0.12),
                startRadius: 0,
                endRadius: 360
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [HTXTheme.cyan.opacity(0.15), .clear],
                center: UnitPoint(x: 0.18, y: 0.35),
                startRadius: 0,
                endRadius: 300
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Frosted Glass Card
struct HTXCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(22)
            .background(.ultraThinMaterial.opacity(0.22))
            .background(HTXTheme.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.38), HTXTheme.accentBright.opacity(0.28)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.1
                    )
            )
            .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
    }
}

// MARK: - HTX Text Field
struct HTXTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var autocap: TextInputAutocapitalization = .never

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.caption)
                .fontWeight(.bold)
                .tracking(1.2)
                .foregroundColor(HTXTheme.accent)

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocap)
                .autocorrectionDisabled()
                .padding(14)
                .background(HTXTheme.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(HTXTheme.inputBorder, lineWidth: 1))
                .foregroundColor(.white)
                .tint(HTXTheme.accentBright)
        }
    }
}

// MARK: - HTX Secure Field
struct HTXSecureField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    @Binding var isVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.caption)
                .fontWeight(.bold)
                .tracking(1.2)
                .foregroundColor(HTXTheme.accent)

            HStack {
                Group {
                    if isVisible {
                        TextField(placeholder, text: $text)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField(placeholder, text: $text)
                    }
                }
                .foregroundColor(.white)

                Button { isVisible.toggle() } label: {
                    Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(HTXTheme.accent)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(HTXTheme.inputBg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(HTXTheme.inputBorder, lineWidth: 1))
            .tint(HTXTheme.accentBright)
        }
    }
}

// MARK: - Primary Button (purple gradient)
struct HTXPrimaryButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    init(_ title: String, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(title)
                        .fontWeight(.bold)
                        .tracking(1.3)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .background(
            LinearGradient(
                colors: [Color(red: 0.61, green: 0.15, blue: 0.69), HTXTheme.accentBright],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(Capsule())
        .foregroundColor(.white)
        .shadow(color: HTXTheme.accentBright.opacity(0.38), radius: 14, y: 5)
        .disabled(isLoading)
    }
}

// MARK: - Secondary Button
struct HTXSecondaryButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .background(Color.white.opacity(0.10))
        .clipShape(Capsule())
        .foregroundColor(.white)
        .overlay(Capsule().stroke(Color.white.opacity(0.20), lineWidth: 1))
    }
}

// MARK: - Ghost Button
struct HTXGhostButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        }
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
        .foregroundColor(.white)
        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
    }
}

// MARK: - Alert Banner
struct HTXAlert: View {
    let message: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 15))
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
        }
        .foregroundColor(isError ? HTXTheme.errorRed : HTXTheme.successGreen)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isError ? HTXTheme.errorRed : HTXTheme.successGreen).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke((isError ? HTXTheme.errorRed : HTXTheme.successGreen).opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - Logout Button
struct HTXLogoutButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Logout")
            }
            .font(.subheadline)
            .fontWeight(.bold)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(HTXTheme.destructiveRed.opacity(0.15))
            .foregroundColor(HTXTheme.destructiveRed)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(HTXTheme.destructiveRed.opacity(0.4), lineWidth: 1))
        }
    }
}

// MARK: - HTX Logo View
/// Uses the HTX logo asset from Assets.xcassets (named "HTXLogo").
/// Falls back to an SF Symbol placeholder if the image is missing.
struct HTXLogoView: View {
    var size: CGFloat = 120

    var body: some View {
        Group {
            if let _ = UIImage(named: "HTXLogo") {
                Image("HTXLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: size, height: size)
                    Image(systemName: "sparkles")
                        .resizable()
                        .scaledToFit()
                        .frame(width: size * 0.55)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [HTXTheme.cyan, HTXTheme.accentBright],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
        }
        .shadow(color: HTXTheme.accentBright.opacity(0.45), radius: 20)
    }
}

// MARK: - Small reusable UI bits
struct HTXScreenHeader: View {
    let title: String
    let subtitle: String?
    let trailing: AnyView?

    init(title: String, subtitle: String? = nil, trailing: AnyView? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(HTXTheme.accent.opacity(0.88))
                }
            }
            Spacer()
            if let trailing { trailing }
        }
    }
}

struct HTXStatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.bold())
            .tracking(0.7)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.18))
            .foregroundColor(color)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.28), lineWidth: 1))
    }
}

struct HTXLoadingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(1.25)
                    .tint(.white)
                Text(message)
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(26)
            .background(Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(radius: 18)
            .padding(.horizontal, 36)
        }
    }
}
