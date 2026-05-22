import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct MemberManagementView: View {

    @EnvironmentObject var auth: AuthViewModel

    // Add member form
    @State private var newEmail = ""
    @State private var newPassword = ""
    @State private var isPasswordVisible = false
    @State private var addError: String? = nil
    @State private var addSuccess: String? = nil
    @State private var isAdding = false
    @State private var selectedRole = "member"

    // Member list
    @State private var members: [MemberEntry] = []
    @State private var isLoadingMembers = false
    @State private var listError: String? = nil

    // Confirmation alert for deactivation/reactivation
    @State private var memberToDelete: MemberEntry? = nil
    @State private var showDeleteConfirm = false

    private let apiKey = "AIzaSyCDs7rIGPLFs4JySTcIw5E2cusYSLlGiHM"

    struct MemberEntry: Identifiable {
        let id: String       // Firebase Auth UID = Firestore doc ID
        let email: String
        var role: String     // "admin" or "member"
        var active: Bool
    }

    var body: some View {
        ZStack {
            HTXBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HTXScreenHeader(
                        title: "Add Member",
                        subtitle: "Admin account management",
                        trailing: nil
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                    HTXCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Create New Account", systemImage: "person.badge.plus.fill")
                                .font(.headline)
                                .foregroundColor(.white)

                            HTXTextField(
                                label: "Email",
                                placeholder: "member@email.com",
                                text: $newEmail,
                                keyboardType: .emailAddress
                            )

                            HTXSecureField(
                                label: "Temporary Password",
                                placeholder: "Minimum 6 characters",
                                text: $newPassword,
                                isVisible: $isPasswordVisible
                            )

                            VStack(alignment: .leading, spacing: 8) {
                                Text("ROLE")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .tracking(1.2)
                                    .foregroundColor(HTXTheme.accent)

                                Picker("Role", selection: $selectedRole) {
                                    Text("Member").tag("member")
                                    Text("Admin").tag("admin")
                                }
                                .pickerStyle(.segmented)
                                .tint(HTXTheme.accentBright)
                            }

                            if let addError {
                                HTXAlert(message: addError, isError: true)
                            }
                            if let addSuccess {
                                HTXAlert(message: addSuccess, isError: false)
                            }

                            HTXPrimaryButton("CREATE ACCOUNT", isLoading: isAdding) {
                                addMemberViaREST()
                            }
                            .disabled(isAdding)
                        }
                    }
                    .padding(.horizontal, 20)

                    HTXCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Label("All Members", systemImage: "person.3.fill")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Spacer()
                                Button { fetchMembers() } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .foregroundColor(.white)
                                        .padding(9)
                                        .background(Color.white.opacity(0.10))
                                        .clipShape(Circle())
                                }
                            }

                            if isLoadingMembers {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .tint(.white)
                                    Spacer()
                                }
                                .padding(.vertical, 18)
                            } else if let listError {
                                HTXAlert(message: listError, isError: true)
                            } else if members.isEmpty {
                                Text("No members yet.")
                                    .font(.subheadline)
                                    .foregroundColor(HTXTheme.accent.opacity(0.85))
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 18)
                            } else {
                                VStack(spacing: 12) {
                                    ForEach(members) { member in
                                        memberRow(member)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { fetchMembers() }
        .alert(
            memberToDelete?.active == true
            ? "Deactivate \(memberToDelete?.email ?? "this user")?"
            : "Reactivate \(memberToDelete?.email ?? "this user")?",
            isPresented: $showDeleteConfirm,
            presenting: memberToDelete
        ) { member in
            Button(member.active ? "Deactivate" : "Reactivate",
                   role: member.active ? .destructive : nil) {
                toggleActiveStatus(member)
            }
            Button("Cancel", role: .cancel) {}
        } message: { member in
            Text(
                member.active
                ? "This user will lose access to the application until reactivated."
                : "This user will regain access to the application."
            )
        }
    }

    @ViewBuilder
    private func memberRow(_ member: MemberEntry) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(member.role == "admin" ? HTXTheme.accentBright.opacity(0.28) : HTXTheme.cyan.opacity(0.22))
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: member.role == "admin" ? "shield.lefthalf.filled" : "person.fill")
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(member.email)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(member.active ? .white : .white.opacity(0.45))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    HTXStatusPill(
                        text: member.role.capitalized,
                        color: member.role == "admin" ? HTXTheme.accentBright : HTXTheme.cyan
                    )
                    HTXStatusPill(
                        text: member.active ? "Active" : "Inactive",
                        color: member.active ? HTXTheme.successGreen : HTXTheme.errorRed
                    )
                }
            }

            Spacer()

            if member.id != auth.user?.uid {
                Menu {
                    Button {
                        updateRole(member, newRole: "member")
                    } label: {
                        Label("Member", systemImage: member.role == "member" ? "checkmark" : "person")
                    }

                    Button {
                        updateRole(member, newRole: "admin")
                    } label: {
                        Label("Admin", systemImage: member.role == "admin" ? "checkmark" : "shield")
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.white)
                        .padding(9)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Circle())
                }

                Button {
                    memberToDelete = member
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: member.active ? "person.fill.xmark" : "person.fill.checkmark")
                        .foregroundColor(member.active ? HTXTheme.errorRed : HTXTheme.successGreen)
                        .padding(9)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Toggle active status
    private func toggleActiveStatus(_ member: MemberEntry) {
        let newStatus = !member.active

        Firestore.firestore()
            .collection("users")
            .document(member.id)
            .updateData(["active": newStatus]) { err in
                DispatchQueue.main.async {
                    if let err {
                        self.listError = err.localizedDescription
                    } else {
                        if let idx = self.members.firstIndex(where: { $0.id == member.id }) {
                            self.members[idx].active = newStatus
                        }
                    }
                }
            }
    }

    // MARK: - Add member via REST (keeps admin session intact)
    private func addMemberViaREST() {
        let email = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !email.isEmpty, !password.isEmpty else {
            addError = "Please fill in both fields."
            return
        }

        isAdding = true
        addError = nil
        addSuccess = nil

        guard let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(apiKey)") else {
            addError = "Invalid API configuration."
            isAdding = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password,
            "returnSecureToken": false
        ])

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                DispatchQueue.main.async {
                    self.addError = error.localizedDescription
                    self.isAdding = false
                }
                return
            }

            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async {
                    self.addError = "Unexpected server response."
                    self.isAdding = false
                }
                return
            }

            if let errorObj = json["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                DispatchQueue.main.async {
                    self.addError = self.friendlyRESTError(message)
                    self.isAdding = false
                }
                return
            }

            guard let newUid = json["localId"] as? String else {
                DispatchQueue.main.async {
                    self.addError = "Could not retrieve new user ID."
                    self.isAdding = false
                }
                return
            }

            // Write Firestore record
            Firestore.firestore().collection("users").document(newUid).setData([
                "email": email,
                "role": self.selectedRole,
                "active": true
            ]) { err in
                DispatchQueue.main.async {
                    self.isAdding = false
                    if let err {
                        self.addError = err.localizedDescription
                    } else {
                        self.addSuccess = "\(email) added successfully."
                        self.newEmail = ""
                        self.newPassword = ""
                        self.selectedRole = "member"
                        self.fetchMembers()
                    }
                }
            }
        }.resume()
    }

    // MARK: - Promote / Demote role
    private func updateRole(_ member: MemberEntry, newRole: String) {
        Firestore.firestore()
            .collection("users")
            .document(member.id)
            .updateData(["role": newRole]) { err in
                DispatchQueue.main.async {
                    if err == nil {
                        if let idx = self.members.firstIndex(where: { $0.id == member.id }) {
                            self.members[idx] = MemberEntry(
                                id: member.id,
                                email: member.email,
                                role: newRole,
                                active: member.active
                            )
                        }
                    } else {
                        self.listError = "Failed to update role."
                    }
                }
            }
    }

    // MARK: - Fetch members
    private func fetchMembers() {
        isLoadingMembers = true
        listError = nil
        Firestore.firestore().collection("users").getDocuments { snapshot, error in
            DispatchQueue.main.async {
                self.isLoadingMembers = false
                if let error {
                    self.listError = error.localizedDescription
                    return
                }
                self.members = (snapshot?.documents ?? []).compactMap { doc in
                    guard let email = doc.data()["email"] as? String else { return nil }
                    let role = doc.data()["role"] as? String ?? "member"
                    let active = doc.data()["active"] as? Bool ?? true
                    return MemberEntry(id: doc.documentID, email: email, role: role, active: active)
                }
                .sorted { $0.email < $1.email }
            }
        }
    }

    private func friendlyRESTError(_ code: String) -> String {
        switch code {
        case "EMAIL_EXISTS":            return "This email is already in use."
        case "INVALID_EMAIL":           return "Please enter a valid email address."
        case "WEAK_PASSWORD : Password should be at least 6 characters":
                                        return "Password must be at least 6 characters."
        default:                        return "Error: \(code)"
        }
    }
}
