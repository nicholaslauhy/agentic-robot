import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import UserNotifications
import UIKit

enum AdminNotificationKind: String {
    case checklist
    case refuel
    case np299

    var title: String {
        switch self {
        case .checklist: return "Pre-driving checklist"
        case .refuel: return "Refuel form"
        case .np299: return "NP299 report"
        }
    }

    var destinationTitle: String {
        switch self {
        case .checklist: return "Open pre-driving follow-up"
        case .refuel: return "Open refuel follow-up"
        case .np299: return "Open existing reports"
        }
    }

    var icon: String {
        switch self {
        case .checklist: return "checklist.checked"
        case .refuel: return "fuelpump.fill"
        case .np299: return "doc.text.fill"
        }
    }

    var color: Color {
        switch self {
        case .checklist: return HTXTheme.primaryPurple
        case .refuel: return HTXTheme.fuelOrange
        case .np299: return .blue
        }
    }
}

struct AdminNotificationItem: Identifiable {
    let id: String
    let kind: AdminNotificationKind
    let title: String
    let message: String
    let reportID: String
    let reportNumber: String
    let vehicleNumber: String
    let submittedBy: String
    let createdAt: Date?
    let readBy: [String]

    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        guard let rawKind = data["reportType"] as? String,
              let kind = AdminNotificationKind(rawValue: rawKind) else {
            return nil
        }

        id = document.documentID
        self.kind = kind
        title = data["title"] as? String ?? kind.title
        message = data["message"] as? String ?? "A new report was submitted."
        reportID = data["reportId"] as? String ?? ""
        reportNumber = data["reportNo"] as? String ?? ""
        vehicleNumber = data["vehicleNumber"] as? String ?? "-"
        submittedBy = data["submittedBy"] as? String ?? "-"
        createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        readBy = data["readBy"] as? [String] ?? []
    }

    func isRead(by uid: String) -> Bool {
        readBy.contains(uid)
    }

    var dateText: String {
        guard let createdAt else { return "Just now" }
        return createdAt.formatted(date: .abbreviated, time: .shortened)
    }
}

@MainActor
final class AdminNotificationService: ObservableObject {
    static let shared = AdminNotificationService()

    @Published private(set) var notifications: [AdminNotificationItem] = []
    @Published private(set) var unreadCount = 0
    @Published private(set) var loadingError: String?

    private var listener: ListenerRegistration?
    private var activeAdminUID: String?
    private var pendingFCMToken: String?
    private var pendingOpenedNotificationID: String?

    private static let deviceIDKey = "htx.notificationDeviceID"

    private init() {}

    func beginAdminSession(uid: String) {
        guard !uid.isEmpty else { return }

        if activeAdminUID != uid {
            listener?.remove()
            notifications = []
            unreadCount = 0
        }

        activeAdminUID = uid
        startInboxListener(for: uid)
        requestPushPermission()

        if let pendingFCMToken {
            saveDeviceToken(pendingFCMToken, for: uid)
        } else {
            Messaging.messaging().token { [weak self] token, error in
                Task { @MainActor in
                    if let error {
                        print("Could not retrieve the Firebase messaging token: \(error.localizedDescription)")
                        return
                    }
                    self?.receiveFCMToken(token)
                }
            }
        }

        if let pendingOpenedNotificationID {
            self.pendingOpenedNotificationID = nil
            markRead(notificationID: pendingOpenedNotificationID)
        }
    }

    func receiveFCMToken(_ token: String?) {
        guard let token, !token.isEmpty else { return }
        pendingFCMToken = token
        guard let activeAdminUID else { return }
        saveDeviceToken(token, for: activeAdminUID)
    }

    func endSession() {
        listener?.remove()
        listener = nil
        notifications = []
        unreadCount = 0
        loadingError = nil
        updateAppBadge(0)

        if let uid = activeAdminUID {
            deviceTokenReference(uid: uid).delete { error in
                if let error {
                    print("Could not remove the notification device registration: \(error.localizedDescription)")
                }
            }
        }

        activeAdminUID = nil
        pendingFCMToken = nil
        Messaging.messaging().deleteToken { error in
            if let error {
                print("Could not delete the Firebase messaging token: \(error.localizedDescription)")
            }
        }
    }

    func markRead(_ notification: AdminNotificationItem) {
        markRead(notificationID: notification.id)
    }

    func markRead(notificationID: String) {
        guard let uid = activeAdminUID, !notificationID.isEmpty else {
            pendingOpenedNotificationID = notificationID
            return
        }

        Firestore.firestore()
            .collection("admin_notifications")
            .document(notificationID)
            .updateData(["readBy": FieldValue.arrayUnion([uid])]) { error in
                if let error {
                    print("Could not mark the notification as read: \(error.localizedDescription)")
                }
            }
    }

    func markAllRead() {
        guard let uid = activeAdminUID else { return }
        let unread = notifications.filter { !$0.isRead(by: uid) }
        guard !unread.isEmpty else { return }

        let database = Firestore.firestore()
        let batch = database.batch()
        for notification in unread {
            let reference = database.collection("admin_notifications").document(notification.id)
            batch.updateData(["readBy": FieldValue.arrayUnion([uid])], forDocument: reference)
        }
        batch.commit { error in
            if let error {
                print("Could not mark all notifications as read: \(error.localizedDescription)")
            }
        }
    }

    func handleOpenedPush(userInfo: [AnyHashable: Any]) {
        guard let notificationID = userInfo["notificationId"] as? String else { return }
        markRead(notificationID: notificationID)
    }

    private func startInboxListener(for uid: String) {
        listener?.remove()
        loadingError = nil

        listener = Firestore.firestore()
            .collection("admin_notifications")
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self, self.activeAdminUID == uid else { return }

                    if let error {
                        self.notifications = []
                        self.unreadCount = 0
                        self.loadingError = "Could not load notifications: \(error.localizedDescription)"
                        self.updateAppBadge(0)
                        return
                    }

                    self.loadingError = nil
                    self.notifications = (snapshot?.documents ?? []).compactMap(AdminNotificationItem.init)
                    self.unreadCount = self.notifications.filter { !$0.isRead(by: uid) }.count
                    self.updateAppBadge(self.unreadCount)
                }
            }
    }

    private func requestPushPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error {
                print("Notification permission could not be requested: \(error.localizedDescription)")
                return
            }

            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    private func saveDeviceToken(_ token: String, for uid: String) {
        guard activeAdminUID == uid else { return }
        deviceTokenReference(uid: uid).setData(
            [
                "token": token,
                "platform": "ios",
                "deviceName": UIDevice.current.name,
                "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
                "updatedAt": FieldValue.serverTimestamp()
            ],
            merge: true
        ) { error in
            if let error {
                print("Could not save the notification device registration: \(error.localizedDescription)")
            }
        }
    }

    private func deviceTokenReference(uid: String) -> DocumentReference {
        Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("deviceTokens")
            .document(Self.deviceID)
    }

    private static var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: deviceIDKey), !existing.isEmpty {
            return existing
        }
        let value = UUID().uuidString.lowercased()
        UserDefaults.standard.set(value, forKey: deviceIDKey)
        return value
    }

    private func updateAppBadge(_ count: Int) {
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(count)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = count
        }
    }
}

struct AdminNotificationsView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @ObservedObject private var notificationService = AdminNotificationService.shared
    @State private var showUnreadOnly = false

    private var displayedNotifications: [AdminNotificationItem] {
        guard showUnreadOnly, let uid = auth.user?.uid else {
            return notificationService.notifications
        }
        return notificationService.notifications.filter { !$0.isRead(by: uid) }
    }

    var body: some View {
        ZStack {
            SubtleHTXBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                header
                filterBar

                if let loadingError = notificationService.loadingError {
                    Spacer()
                    ContentUnavailableView(
                        "Notifications unavailable",
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text(loadingError)
                    )
                    Spacer()
                } else if displayedNotifications.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        showUnreadOnly ? "No unread notifications" : "No notifications yet",
                        systemImage: "bell.slash.fill",
                        description: Text(
                            showUnreadOnly
                            ? "You have reviewed every notification."
                            : "New member submissions will appear here."
                        )
                    )
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(displayedNotifications) { notification in
                                NavigationLink {
                                    destination(for: notification)
                                } label: {
                                    notificationRow(notification)
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(
                                    TapGesture().onEnded {
                                        notificationService.markRead(notification)
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .requiresRole(.admin)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Administrator alerts")
                    .font(.headline)
                Text("\(notificationService.unreadCount) unread")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if notificationService.unreadCount > 0 {
                Button("Mark all read") {
                    notificationService.markAllRead()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(HTXTheme.primaryPurple)
            }
        }
        .padding(.horizontal)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            filterButton(title: "All", unreadOnly: false)
            filterButton(title: "Unread", unreadOnly: true)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func filterButton(title: String, unreadOnly: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showUnreadOnly = unreadOnly
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(showUnreadOnly == unreadOnly ? .white : .secondary)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(showUnreadOnly == unreadOnly ? HTXTheme.primaryPurple : Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func notificationRow(_ notification: AdminNotificationItem) -> some View {
        let isUnread = !(auth.user.map { notification.isRead(by: $0.uid) } ?? true)

        return HStack(alignment: .top, spacing: 13) {
            Image(systemName: notification.kind.icon)
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 42, height: 42)
                .background(notification.kind.color)
                .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(notification.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    if isUnread {
                        Circle()
                            .fill(HTXTheme.primaryPurple)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(notification.message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(notification.dateText)
                    if !notification.reportNumber.isEmpty {
                        Text("•")
                        Text(notification.reportNumber)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Label(notification.kind.destinationTitle, systemImage: "arrow.right.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(notification.kind.color)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.systemBackground).opacity(isUnread ? 1 : 0.78))
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(isUnread ? HTXTheme.primaryPurple.opacity(0.22) : Color.secondary.opacity(0.10), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func destination(for notification: AdminNotificationItem) -> some View {
        switch notification.kind {
        case .checklist:
            AdminChecklistReviewView()
        case .refuel:
            AdminFuelFollowUpView()
        case .np299:
            ReportsListView()
        }
    }
}
