const {onRequest} = require("firebase-functions/v2/https");
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore} = require("firebase-admin/firestore");

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
