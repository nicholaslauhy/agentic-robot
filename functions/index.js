const {onRequest} = require("firebase-functions/v2/https");
const {onDocumentCreated} = require("firebase-functions/v2/firestore");
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");

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

async function createAdminNotification(event, reportType) {
  const snapshot = event.data;
  if (!snapshot) {
    console.log("No report data was provided for the notification trigger.");
    return;
  }

  const report = snapshot.data();
  const submitterUid = cleanText(report.createdByUid, "");

  // Administrators can generate an NP299 while escalating a member's
  // checklist. The original checklist notification already brought that work
  // to the admin queue, so do not create a second notification for an action
  // performed by an administrator.
  if (submitterUid) {
    const submitterProfile = await getFirestore()
        .collection("users")
        .doc(submitterUid)
        .get();
    if (submitterProfile.data()?.role === "admin") {
      console.log(
          `Skipping ${reportType} notification created by administrator ${submitterUid}.`,
      );
      return;
    }
  }

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
