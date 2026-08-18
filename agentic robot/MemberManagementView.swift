import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct MemberManagementView: View {

    @EnvironmentObject var auth: AuthViewModel

    // Add member form
    @State private var newUsername = ""
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

    // Account actions
    @State private var memberToPermanentlyDelete: MemberEntry? = nil
    @State private var isDeletingUser = false
    @State private var deletionFeedbackMessage: String? = nil

    // Username editor
    @State private var memberToEdit: MemberEntry? = nil
    @State private var usernameDraft = ""
    @State private var usernameEditError: String? = nil
    @State private var isSavingUsername = false

    private let apiKey = "AIzaSyCDs7rIGPLFs4JySTcIw5E2cusYSLlGiHM"

    struct MemberEntry: Identifiable {
        let id: String       // Firebase Auth UID = Firestore doc ID
        let email: String
        var username: String
        var role: String     // "admin" or "member"
        var active: Bool

        var hasUsername: Bool {
            !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        ZStack {
            SubtleHTXBackground()

            ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                // ── Add Account ─────────────────────────────────────────
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {

                        Text("Add New Account")
                            .font(.headline)

                        TextField("Full name / username", text: $newUsername)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.name)
                            .autocorrectionDisabled()

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
                        .tint(HTXTheme.primaryPurple)
                        .disabled(isAdding)
                    }
                }
                .padding(.horizontal)

                // ── Account List ────────────────────────────────────────
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {

                        HStack {
                            Text("All Accounts")
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
                            Text("No accounts yet.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(members) { member in
                                VStack(spacing: 0) {
                                    HStack(spacing: 12) {

                                        // Username, email + role badge
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(member.hasUsername ? member.username : "Username missing")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundColor(
                                                    member.hasUsername
                                                    ? (member.active ? .primary : .gray)
                                                    : .orange
                                                )
                                            Text(member.email)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            HStack(spacing: 6) {
                                                Text(member.role.capitalized)
                                                    .font(.caption)
                                                    .foregroundColor(member.role == "admin" ? HTXTheme.primaryPurple : .secondary)

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

                                        Button {
                                            usernameDraft = member.username
                                            usernameEditError = nil
                                            memberToEdit = member
                                        } label: {
                                            Image(systemName: "person.text.rectangle")
                                                .foregroundColor(HTXTheme.primaryPurple)
                                                .imageScale(.large)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Edit username for \(member.email)")

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

                                            // Permanent account deletion
                                            Button {
                                                memberToPermanentlyDelete = member
                                            } label: {
                                                Image(systemName: "trash.fill")
                                                    .foregroundColor(.red)
                                                    .imageScale(.large)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel("Delete \(member.email) permanently")
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
        .groupBoxStyle(SubtleHTXGroupBoxStyle())
        .tint(HTXTheme.primaryPurple)

        if isDeletingUser {
            Color.black.opacity(0.32).ignoresSafeArea()
            ProgressView("Deleting account…")
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        }
        .navigationTitle("Manage Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { fetchMembers() }
        .sheet(item: $memberToEdit) { member in
            usernameEditor(for: member)
                .interactiveDismissDisabled(isSavingUsername)
        }
        .alert(
            "Delete Account Permanently?",
            isPresented: Binding(
                get: { memberToPermanentlyDelete != nil },
                set: { if !$0 { memberToPermanentlyDelete = nil } }
            ),
            presenting: memberToPermanentlyDelete
        ) { member in
            Button("Delete Permanently", role: .destructive) {
                deleteUser(member)
            }
            Button("Cancel", role: .cancel) { memberToPermanentlyDelete = nil }
        } message: { member in
            Text("This permanently deletes \(member.email) from Firebase Authentication and the account list. Existing submitted reports are kept as audit records and can be deleted separately by an administrator.")
        }
        .alert(
            "Could Not Delete Account",
            isPresented: Binding(
                get: { deletionFeedbackMessage != nil },
                set: { if !$0 { deletionFeedbackMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { deletionFeedbackMessage = nil }
        } message: {
            Text(deletionFeedbackMessage ?? "")
        }
        .requiresRole(.admin)
    }

    private func usernameEditor(for member: MemberEntry) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Account")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(member.email)
                        .font(.headline)
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("Full name / username")
                        .font(.subheadline.weight(.semibold))
                    TextField("Enter the user's full name", text: $usernameDraft)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                }

                Text("This name will be inserted automatically into forms completed by this account.")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                if let usernameEditError {
                    Text(usernameEditError)
                        .font(.footnote)
                        .foregroundColor(.red)
                }

                Spacer()

                Button {
                    saveUsername(for: member)
                } label: {
                    if isSavingUsername {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Save Username")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(HTXTheme.primaryPurple)
                .disabled(isSavingUsername)
            }
            .padding()
            .navigationTitle(member.hasUsername ? "Edit Username" : "Add Username")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { memberToEdit = nil }
                        .disabled(isSavingUsername)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func saveUsername(for member: MemberEntry) {
        let username = usernameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else {
            usernameEditError = "Username cannot be empty."
            return
        }

        isSavingUsername = true
        usernameEditError = nil

        Firestore.firestore()
            .collection("users")
            .document(member.id)
            .updateData([
                "username": username,
                "updatedAt": FieldValue.serverTimestamp()
            ]) { error in
                DispatchQueue.main.async {
                    self.isSavingUsername = false
                    if let error {
                        self.usernameEditError = "Could not save username: \(error.localizedDescription)"
                        return
                    }

                    if let index = self.members.firstIndex(where: { $0.id == member.id }) {
                        self.members[index].username = username
                    }
                    self.memberToEdit = nil
                    self.usernameDraft = ""
                }
            }
    }

    // MARK: - Permanently delete account
    private func deleteUser(_ member: MemberEntry) {
        guard member.id != auth.user?.uid else {
            deletionFeedbackMessage = "You cannot delete the account you are currently using."
            return
        }

        memberToPermanentlyDelete = nil
        isDeletingUser = true
        listError = nil

        FirebaseAdminService.deleteUser(uid: member.id) { result in
            DispatchQueue.main.async {
                isDeletingUser = false
                switch result {
                case .success:
                    members.removeAll { $0.id == member.id }
                case .failure(let error):
                    deletionFeedbackMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Add member via REST (keeps admin session intact)
    private func addMemberViaREST() {
        let username = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !username.isEmpty, !email.isEmpty, !password.isEmpty else {
            addError = "Please fill in the username, email and temporary password."
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
                "username": username,
                "role": self.selectedRole,
                "active": true,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ]) { err in
                DispatchQueue.main.async {
                    self.isAdding = false
                    if let err {
                        self.addError = err.localizedDescription
                    } else {
                        self.sendPasswordResetEmail(to: email)
                        self.addSuccess = "\(email) added successfully. Password reset email sent to user."
                        self.newUsername = ""
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
                                username: member.username,
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
                    let username = (doc.data()["username"] as? String
                                    ?? doc.data()["displayName"] as? String
                                    ?? doc.data()["name"] as? String
                                    ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let role = doc.data()["role"] as? String ?? "member"
                    let active = doc.data()["active"] as? Bool ?? true
                    return MemberEntry(
                        id: doc.documentID,
                        email: email,
                        username: username,
                        role: role,
                        active: active
                    )
                }
                .sorted {
                    let left = $0.hasUsername ? $0.username : $0.email
                    let right = $1.hasUsername ? $1.username : $1.email
                    return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
                }
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
    
    private func sendPasswordResetEmail(to email: String) {

        guard let url = URL(
            string: "https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=\(apiKey)"
        ) else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "requestType": "PASSWORD_RESET",
            "email": email
        ])

        URLSession.shared.dataTask(with: request) { _, _, error in

            DispatchQueue.main.async {

                if let error {
                    self.addError = "Failed to send reset email: \(error.localizedDescription)"
                }
            }

        }.resume()
    }
}
