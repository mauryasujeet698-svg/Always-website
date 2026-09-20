const { initializeApp } = require("firebase-admin/app");
const { getMessaging } = require("firebase-admin/messaging");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");

initializeApp();

function messageForStatus(status) {
  const map = {
    "New Order": ["ALLways order received", "Your order has been received by ALLways."],
    "Confirmed": ["ALLways order confirmed", "Your order has been confirmed."],
    "Preparing": ["ALLways order preparing", "Your order is being prepared."],
    "Out for delivery": ["ALLways order on the way", "Your order is out for delivery."],
    "Delivered": ["ALLways order delivered", "Your ALLways order has been delivered."],
    "Cancelled": ["ALLways order cancelled", "Your ALLways order has been cancelled."]
  };
  return map[status] || ["ALLways order update", "Your order status has been updated."];
}

async function sendOrderNotification(data, fallbackStatus) {
  const token = String(data.fcmToken || "").trim();
  if (!token) return;
  const status = String(data.status || fallbackStatus || "New Order");
  const [title, body] = messageForStatus(status);
  const eta = String(data.estimatedDelivery || "").trim();
  const note = String(data.statusNote || "").trim();
  const extra = eta ? " ETA: " + eta + "." : (note ? " " + note : "");
  try {
    await getMessaging().send({
      token,
      notification: { title, body: body + extra },
      data: {
        orderId: String(data.id || ""),
        status,
        click_action: "FLUTTER_NOTIFICATION_CLICK"
      },
      android: { priority: "high" }
    });
  } catch (e) {
    console.error("ALLways FCM send failed", e);
  }
}

exports.onAllwaysOrderCreated = onDocumentCreated("orders/{orderId}", async (event) => {
  const data = event.data && event.data.data();
  if (!data) return;
  await sendOrderNotification(data, "New Order");
});

exports.onAllwaysOrderUpdated = onDocumentUpdated("orders/{orderId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!after) return;
  const changed = String(before.status || "") !== String(after.status || "") ||
    String(before.estimatedDelivery || "") !== String(after.estimatedDelivery || "") ||
    String(before.statusNote || "") !== String(after.statusNote || "");
  if (changed) await sendOrderNotification(after, before.status);
});
