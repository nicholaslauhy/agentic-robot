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

    // Confirmation alert for deletion
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
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                // ── Add Member ──────────────────────────────────────────
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {

                        Text("Add New Member")
                            .font(.headline)

                        TextField("Email", text: $newEmail)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)

                        HStack {
                            Group {
                                if isPasswordVisible {
                                    TextField("Temporary Password", text: $newPassword)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                } else {
                                    SecureField("Temporary Password", text: $newPassword)
                                }
                            }
                            Button {
                                isPasswordVisible.toggle()
                            } label: {
                                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                        
                        VStack(alignment: .leading, spacing: 6) {

                            Text("Role")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Picker("Role", selection: $selectedRole) {
                                Text("Member").tag("member")
                                Text("Admin").tag("admin")
                            }
                            .pickerStyle(.segmented)
                        }

                        if let addError {
                            Text(addError).foregroundColor(.red).font(.footnote)
                        }
                        if let addSuccess {
                            Text(addSuccess).foregroundColor(.green).font(.footnote)
                        }

                        Button {
                            addMemberViaREST()
                        } label: {
                            if isAdding {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Text("Create Account").frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isAdding)
                    }
                }
                .padding(.horizontal)

                // ── Member List ─────────────────────────────────────────
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {

                        HStack {
                            Text("All Members")
                                .font(.headline)
                            Spacer()
                            Button { fetchMembers() } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                        }

                        if isLoadingMembers {
                            ProgressView().frame(maxWidth: .infinity)
                        } else if let listError {
                            Text(listError).foregroundColor(.red).font(.footnote)
                        } else if members.isEmpty {
                            Text("No members yet.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(members) { member in
                                VStack(spacing: 0) {
                                    HStack(spacing: 12) {

                                        // Email + role badge
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(member.email)
                                                .font(.subheadline)
                                                .foregroundColor(member.active ? .primary : .gray)
                                            HStack(spacing: 6) {

                                                Text(member.role.capitalized)
                                                    .font(.caption)
                                                    .foregroundColor(member.role == "admin" ? .blue : .secondary)

                                                Text(member.active ? "ACTIVE" : "INACTIVE")
                                                    .font(.caption2)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(member.active ? Color.green.opacity(0.2)
                                                                              : Color.red.opacity(0.2))
                                                    .cornerRadius(6)
                                            }
                                        }

                                        Spacer()

                                        // ── Action buttons (only for others, not yourself) ──
                                        if member.id != auth.user?.uid {

                                            // Promote / Demote button
                                            Menu {

                                                Button {
                                                    updateRole(member, newRole: "member")
                                                } label: {
                                                    Label("Member", systemImage: member.role == "member" ? "checkmark" : "")
                                                }

                                                Button {
                                                    updateRole(member, newRole: "admin")
                                                } label: {
                                                    Label("Admin", systemImage: member.role == "admin" ? "checkmark" : "")
                                                }

                                            } label: {

                                                HStack(spacing: 4) {
                                                    Text(member.role.capitalized)
                                                        .font(.caption)

                                                    Image(systemName: "chevron.down")
                                                        .font(.caption2)
                                                }
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color(.systemGray6))
                                                .cornerRadius(8)
                                            }

                                            // Delete button
                                            Button {
                                                memberToDelete = member
                                                showDeleteConfirm = true
                                            } label: {
                                                Image(systemName: member.active ? "person.fill.xmark" : "person.fill.checkmark")
                                                    .foregroundColor(.red)
                                                    .imageScale(.large)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Add Member")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { fetchMembers() }
        // Deactivation confirmation alert
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
    
    private func toggleActiveStatus(_ member: MemberEntry) {

        let newStatus = !member.active

        Firestore.firestore()
            .collection("users")
            .document(member.id)
            .updateData([
                "active": newStatus
            ]) { err in

                DispatchQueue.main.async {

                    if let err {
                        self.listError = err.localizedDescription
                    } else {

                        if let idx = self.members.firstIndex(where: {
                            $0.id == member.id
                        }) {

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

            // Write Firestore record with default "member" role
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
            .updateData([
                "role": newRole
            ]) { err in

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

    // MARK: - Deactivate member
    private func deactivateMember(_ member: MemberEntry) {

        Firestore.firestore()
            .collection("users")
            .document(member.id)
            .updateData([
                "active": false
            ]) { err in

                DispatchQueue.main.async {

                    if let err {
                        self.listError = err.localizedDescription
                    } else {

                        if let idx = self.members.firstIndex(where: {
                            $0.id == member.id
                        }) {

                            self.members[idx].active = false
                        }
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

                    guard let email = doc.data()["email"] as? String else {
                        return nil
                    }

                    let role = doc.data()["role"] as? String ?? "member"
                    let active = doc.data()["active"] as? Bool ?? true

                    return MemberEntry(
                        id: doc.documentID,
                        email: email,
                        role: role,
                        active: active
                    )
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
