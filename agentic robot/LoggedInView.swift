import SwiftUI

struct LoggedInView: View {
    var onLogout: () -> Void // Closure for logout action

    var body: some View {
        VStack {
            Text("Welcome!")
                .font(.largeTitle)

            Button("Logout") {
                onLogout() // Call the logout closure
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
