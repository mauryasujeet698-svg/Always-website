const { initializeApp } = require("firebase-admin/app");
const { getMessaging } = require("firebase-admin/messaging");
const { getFirestore } = require("firebase-admin/firestore");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");

initializeApp();
const db = getFirestore();

async function sendToUser(uid, title, body, data = {}) {
  if (!uid) return;
  try {
    const tokenDoc = await db.collection("fcmTokens").doc(String(uid)).get();
    if (!tokenDoc.exists) return;
    const token = String(tokenDoc.data().token || "").trim();
    if (!token) return;
    await getMessaging().send({
      token,
      notification: { title, body },
      data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
      android: { priority: "high" }
    });
  } catch (error) {
    console.error("ALLways notification failed:", error);
  }
}

async function assignmentMode() {
  const snap = await db.collection("settings").doc("deliveryAssignment").get();
  return snap.exists && snap.data().mode === "automatic" ? "automatic" : "manual";
}

async function assignAvailableCarrier(orderId) {
  if (await assignmentMode() !== "automatic") return false;

  const orderRef = db.collection("orders").doc(orderId);
  const first = await orderRef.get();
  if (!first.exists) return false;
  const order = first.data();
  if (order.carrierUid) return false;

  const attempts = Array.isArray(order.assignmentAttempts) ? order.assignmentAttempts : [];
  const carriers = await db.collection("customers").where("role", "==", "carrier").get();
  const candidates = carriers.docs
    .filter((doc) => {
      const x = doc.data();
      return x.deliveryAvailable === true && !x.activeOrderId && !attempts.includes(doc.id);
    })
    .sort((a, b) => {
      const ax = a.data().lastAssignedAt?.toMillis?.() || 0;
      const bx = b.data().lastAssignedAt?.toMillis?.() || 0;
      return ax - bx;
    });

  for (const carrier of candidates) {
    let assigned = false;
    await db.runTransaction(async (tx) => {
      const latestOrder = await tx.get(orderRef);
      const latestCarrier = await tx.get(carrier.ref);
      if (!latestOrder.exists || latestOrder.data().carrierUid) return;
      const c = latestCarrier.data() || {};
      if (c.deliveryAvailable !== true || c.activeOrderId) return;

      const name = String(c.displayName || c.email || carrier.id);
      const phone = String(c.phone || "");
      tx.update(orderRef, {
        carrierUid: carrier.id,
        carrierName: name,
        carrierPhone: phone,
        carrierAccepted: false,
        assignmentMode: "automatic",
        assignedAt: new Date(),
        status: "Assigned",
        statusNote: "Delivery partner assigned",
        customerMessage: "Delivery partner assigned",
        updatedAt: Date.now()
      });
      tx.set(carrier.ref, {
        deliveryAvailable: false,
        activeOrderId: orderId,
        lastAssignedAt: new Date(),
        updatedAt: new Date()
      }, { merge: true });
      assigned = true;
    });

    if (assigned) {
      await sendToUser(carrier.id, "New delivery", "You have a new ALLways delivery request.", {
        orderId,
        type: "delivery_assignment"
      });
      return true;
    }
  }
  return false;
}

exports.onAllwaysOrderCreated = onDocumentCreated("orders/{orderId}", async (event) => {
  if (!event.data) return;
  await assignAvailableCarrier(event.params.orderId);
});

exports.onAllwaysOrderUpdated = onDocumentUpdated("orders/{orderId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!after) return;

  const orderId = event.params.orderId;
  const oldStatus = String(before.status || "");
  const newStatus = String(after.status || "");
  const oldCarrier = String(before.carrierUid || "");
  const newCarrier = String(after.carrierUid || "");

  if (!newCarrier && oldCarrier && newStatus !== "Cancelled" && newStatus !== "Delivered") {
    await assignAvailableCarrier(orderId);
  }

  if (newCarrier && newCarrier !== oldCarrier) {
    await sendToUser(newCarrier, "Delivery assigned", "You have been assigned ALLways order #" + orderId + ".", {
      orderId,
      type: "delivery_assignment"
    });
  }

  if (oldCarrier && (newStatus === "Delivered" || newStatus === "Cancelled")) {
    await db.collection("customers").doc(oldCarrier).set({
      deliveryAvailable: true,
      activeOrderId: null,
      updatedAt: new Date()
    }, { merge: true });
  }

  if (oldStatus !== newStatus) {
    const customerUid = String(after.customerUid || after.customerId || "").trim();
    await sendToUser(customerUid, "Order Update", "Your order is now " + newStatus, {
      orderId,
      status: newStatus
    });
  }
});
