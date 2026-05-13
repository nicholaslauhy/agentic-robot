import SwiftUI

struct ContentView: View {

    @StateObject var auth = AuthViewModel()

    var body: some View {

        NavigationStack {
            RootView()
        }
        .environmentObject(auth)
    }
}
