const {onRequest} = require("firebase-functions/v2/https");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

initializeApp();

function sendError(response, status, message) {
  response.status(status).json({error: message});
}

exports.deleteUser = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    sendError(response, 405, "Method not allowed.");
    return;
  }

  const authorization = request.get("Authorization") || "";
  if (!authorization.startsWith("Bearer ")) {
    sendError(response, 401, "You must be signed in to delete an account.");
    return;
  }

  const idToken = authorization.slice("Bearer ".length).trim();
  let caller;
  try {
    caller = await getAuth().verifyIdToken(idToken, true);
  } catch (error) {
    console.warn("deleteUser rejected an invalid session", error.code);
    sendError(response, 401, "Your admin session has expired. Please sign in again.");
    return;
  }

  try {
    const callerProfile = await getFirestore()
        .collection("users")
        .doc(caller.uid)
        .get();
    const callerData = callerProfile.data();

    if (!callerProfile.exists ||
        callerData?.role !== "admin" ||
        callerData?.active === false) {
      sendError(response, 403, "Only an active administrator can delete accounts.");
      return;
    }

    const uid = typeof request.body?.uid === "string" ? request.body.uid.trim() : "";
    if (!uid) {
      sendError(response, 400, "A user ID is required.");
      return;
    }

    if (uid === caller.uid) {
      sendError(response, 400, "You cannot delete the account you are currently using.");
      return;
    }

    try {
      await getAuth().deleteUser(uid);
    } catch (error) {
      if (error.code !== "auth/user-not-found") {
        throw error;
      }
    }

    // Delete the profile and private subcollections such as device tokens.
    // Reports remain intact as audit records and use their own admin deletion flow.
    await getFirestore().recursiveDelete(
        getFirestore().collection("users").doc(uid),
    );

    response.status(200).json({success: true});
  } catch (error) {
    console.error("deleteUser failed", error);
    sendError(response, 500, "The account could not be deleted. Please try again.");
  }
});

function cleanText(value, fallback = "-") {
  if (typeof value !== "string") {
    return fallback;
  }
  const cleaned = value.trim();
  return cleaned || fallback;
}

function notificationDetails(reportType, data) {
  const vehicleNumber = cleanText(
      data.plate || data.vehicleNumber,
      "Unknown vehicle",
  );
  const submittedBy = cleanText(
      data.createdByName || data.generatedBy || data.driverName,
      "A member",
  );

  switch (reportType) {
    case "checklist":
      return {
        title: "New pre-driving checklist",
        message: `${submittedBy} submitted a checklist for ${vehicleNumber}.`,
        vehicleNumber,
        submittedBy,
      };
    case "refuel":
      return {
        title: "New refuel form",
        message: `${submittedBy} submitted a refuel form for ${vehicleNumber}.`,
        vehicleNumber,
        submittedBy,
      };
    default:
      return {
        title: "New NP299 report",
        message: `${submittedBy} generated an NP299 report for ${vehicleNumber}.`,
        vehicleNumber,
        submittedBy,
      };
  }
}

async function activeAdminDevices() {
  const database = getFirestore();
  const admins = await database.collection("users")
      .where("role", "==", "admin")
      .get();
  const activeAdmins = admins.docs.filter((document) => {
    return document.data().active !== false;
  });

  const deviceSnapshots = await Promise.all(activeAdmins.map((admin) => {
    return admin.ref.collection("deviceTokens").get();
  }));

  return deviceSnapshots.flatMap((snapshot) => {
    return snapshot.docs.flatMap((document) => {
      const token = cleanText(document.data().token, "");
      return token ? [{token, reference: document.ref}] : [];
    });
  });
}

async function sendAdminPush(notificationId, reportType, details) {
  const devices = await activeAdminDevices();
  if (devices.length === 0) {
    console.log("No active administrator devices are registered for push alerts.");
    return;
  }

  for (let start = 0; start < devices.length; start += 500) {
    const group = devices.slice(start, start + 500);
    const result = await getMessaging().sendEachForMulticast({
      tokens: group.map((device) => device.token),
      notification: {
        title: details.title,
        body: details.message,
      },
      data: {
        notificationId,
        reportType,
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
          },
        },
      },
    });

    const invalidReferences = [];
    result.responses.forEach((response, index) => {
      if (response.success) {
        return;
      }
      const code = response.error?.code || "";
      console.warn("Administrator push delivery failed", code);
      if (code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token") {
        invalidReferences.push(group[index].reference);
      }
    });

    if (invalidReferences.length > 0) {
      const cleanup = getFirestore().batch();
      invalidReferences.forEach((reference) => cleanup.delete(reference));
      await cleanup.commit();
    }
  }
}

async function createAdminNotification(event, reportType) {
  const snapshot = event.data;
  if (!snapshot) {
    console.log("No report data was provided for the notification trigger.");
    return;
  }

  const report = snapshot.data();
  const details = notificationDetails(reportType, report);
  const notificationId = `${reportType}_${snapshot.id}`;
  const notificationReference = getFirestore()
      .collection("admin_notifications")
      .doc(notificationId);

  await notificationReference.set({
    title: details.title,
    message: details.message,
    reportType,
    reportId: snapshot.id,
    reportNo: cleanText(report.reportNo, ""),
    vehicleNumber: details.vehicleNumber,
    submittedBy: details.submittedBy,
    submittedByUid: cleanText(report.createdByUid, ""),
    createdAt: report.createdAt || FieldValue.serverTimestamp(),
    readBy: [],
  }, {merge: false});

  try {
    await sendAdminPush(notificationId, reportType, details);
  } catch (error) {
    // The inbox notification remains available even when APNs/FCM has not yet
    // been configured or a transient push-delivery error occurs.
    console.error("Administrator push delivery failed", error);
  }
}

exports.notifyChecklistSubmitted = onDocumentCreated(
    "seccom_checklists/{reportId}",
    (event) => createAdminNotification(event, "checklist"),
);

exports.notifyRefuelSubmitted = onDocumentCreated(
    "fuel_refuel_reports/{reportId}",
    (event) => createAdminNotification(event, "refuel"),
);

exports.notifyNP299Submitted = onDocumentCreated(
    "reports/{reportId}",
    (event) => createAdminNotification(event, "np299"),
);
