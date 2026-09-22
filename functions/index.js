const { initializeApp } = require("firebase-admin/app");
const { getMessaging } = require("firebase-admin/messaging");
const { getFirestore } = require("firebase-admin/firestore");
const { onDocumentUpdated } = require("firebase-functions/v2/firestore");

initializeApp();

exports.onAllwaysOrderUpdated = onDocumentUpdated("orders/{orderId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();

  if (!after) return;

  const oldStatus = String(before.status || "");
  const newStatus = String(after.status || "");

  if (oldStatus === newStatus) return;

  const customerUid = String(
    after.customerUid || after.customerId || ""
  ).trim();

  if (!customerUid) {
    console.log("No customerUid/customerId on order", event.params.orderId);
    return;
  }

  const db = getFirestore();
  const tokenDoc = await db.collection("fcmTokens").doc(customerUid).get();

  if (!tokenDoc.exists) {
    console.log("No FCM token found for customer", customerUid);
    return;
  }

  const token = String(tokenDoc.data().token || "").trim();

  if (!token) {
    console.log("Empty FCM token for customer", customerUid);
    return;
  }

  const message = {
    token,
    notification: {
      title: "Order Update",
      body: "Your order is now " + newStatus
    },
    data: {
      orderId: String(event.params.orderId),
      status: newStatus
    },
    android: {
      priority: "high"
    }
  };

  try {
    const response = await getMessaging().send(message);
    console.log("ALLways order notification sent:", response);
  } catch (error) {
    console.error("ALLways FCM send failed:", error);
  }
});
