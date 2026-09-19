/* =========================================================
   LIVE INVENTORY STATE
   ========================================================= */

let products = [];
let cats = ["All"];
let inventoryLoaded = false;


/* =========================================================
   FIREBASE CONFIGURATION — ALLways web
   ========================================================= */

const FIREBASE_CONFIG = {
  apiKey: "AIzaSyCopzTF-jwLnzcbCnW5Y9nIHYMkiinaZ28",
  authDomain: "allways-web.firebaseapp.com",
  projectId: "allways-web",
  storageBucket: "allways-web.firebasestorage.app",
  messagingSenderId: "869987297351",
  appId: "1:869987297351:web:fde91fb46194a141976962",
  measurementId: "G-1N2DFFC7BT"
};


/* =========================================================
   BUSINESS SETTINGS
   ========================================================= */

const CONFIG = {
  freeDeliveryThreshold: 499,
  standardDeliveryFee: 30,
  orderEndpoint: "https://script.google.com/macros/s/AKfycbyuAdL6eEIlGiYhoTPFtE70VhyiMLnKgzO1ytctdSCWMtTdw4zIVQvEVwkbYJyJF2Wd/exec"
};


/* =========================================================
   APP STATE
   ========================================================= */

let cart = {};
let selectedCat = "All";
let currentUser = null;
let firebaseReady = false;
let firestoreReady = false;
let orders = [];

try {
  orders = JSON.parse(localStorage.getItem("allwaysOrders") || "[]");
} catch(e) {
  orders = [];
}


/* =========================================================
   FETCH INVENTORY FROM GOOGLE SHEETS
   ========================================================= */

async function loadInventory(){
  try {
    const response = await fetch(
      CONFIG.orderEndpoint + (CONFIG.orderEndpoint.includes("?") ? "&" : "?") + "_=" + Date.now(),
      { cache: "no-store" }
    );
    const data = await response.json();
    let fetchedProducts = data.products || data;

    products = fetchedProducts.map(function(p){
      return Object.assign({}, p, {
        cat: p.category || p.cat,
        price: Number(p.price) || 0,
        stock: Math.max(0, Number(p.stock) || 0)
      });
    });

    cats = ["All"].concat(Array.from(new Set(products.map(function(p){ return p.cat; }).filter(Boolean))));
    inventoryLoaded = true;

    renderCats();
    renderProducts();
    updateCart();
  } catch (error) {
    console.error("Error loading inventory from Google Sheets:", error);
  }
}


/* =========================================================
   SAFE HTML
   ========================================================= */

function escapeHtml(value){
  return String(value ?? "").replace(/[&<>'"]/g, function(c){
    return {"&":"&amp;", "<":"&lt;", ">":"&gt;", "'":"&#39;", '"':"&#quot;" === "&#quot;" ? "&#34;" : "&#34;"}[c];
  });
}


/* =========================================================
   SHOP
   ========================================================= */

function renderCats(){
  const el = document.getElementById("categories");
  if(!el) return;

  el.innerHTML = cats.map(function(c){
    return '<button class="cat ' + (c === selectedCat ? "active" : "") + '" data-cat="' + escapeHtml(c) + '">' + escapeHtml(c) + '</button>';
  }).join("");

  el.querySelectorAll(".cat").forEach(function(btn){
    btn.addEventListener("click", function(){ setCat(btn.dataset.cat); });
  });
}

function renderProducts(){
  const search = document.getElementById("search");
  const productsEl = document.getElementById("products");
  const count = document.getElementById("count");
  if(!productsEl) return;

  const q = search ? search.value.toLowerCase().trim() : "";
  const list = products.filter(function(p){
    const categoryMatch = selectedCat === "All" || p.cat === selectedCat;
    const searchMatch = String(p.name || "").toLowerCase().includes(q);
    return categoryMatch && searchMatch;
  });

  if(count) count.textContent = list.length + " shown";

  if(!list.length){
    productsEl.innerHTML = '<div class="empty">' + (inventoryLoaded ? "No matching items." : "Loading inventory…") + '</div>';
    return;
  }

  productsEl.innerHTML = list.map(function(p){
    const inCart = Number(cart[p.id] || 0);
    const maxStock = Number(p.stock) || 0;
    return `
      <article class="product">
        <div class="pic">${escapeHtml(p.icon)}</div>
        <h3>${escapeHtml(p.name)}</h3>
        <small>${escapeHtml(p.cat)}</small>
        <div class="price">₹${p.price}</div>
        <div class="stock">${maxStock > 0 ? "● " + maxStock + " available" : "● Unavailable"}</div>
        <div class="qty-control">
          <button class="qty-btn" data-action="minus" data-id="${escapeHtml(String(p.id))}" ${inCart < 1 ? "disabled" : ""}>−</button>
          <span class="qty-value">${inCart}</span>
          <button class="qty-btn" data-action="plus" data-id="${escapeHtml(String(p.id))}" ${inCart >= maxStock ? "disabled" : ""}>+</button>
        </div>
        <button class="add" data-id="${escapeHtml(String(p.id))}" ${maxStock < 1 || inCart >= maxStock ? "disabled" : ""}>
          ${maxStock < 1 ? "Unavailable" : inCart ? "Add another" : "Add to cart"}
        </button>
      </article>
    `;
  }).join("");

  productsEl.querySelectorAll(".qty-btn").forEach(function(btn){
    btn.addEventListener("click", function(){
      changeQuantity(btn.dataset.id, btn.dataset.action === "plus" ? 1 : -1);
    });
  });

  productsEl.querySelectorAll(".add").forEach(function(btn){
    btn.addEventListener("click", function(){ add(btn.dataset.id); });
  });
}

function setCat(category){
  selectedCat = category;
  const title = document.getElementById("categoryTitle");
  if(title) title.textContent = category === "All" ? "All items" : category;
  renderCats();
  renderProducts();
}


/* =========================================================
   CART
   ========================================================= */

function add(id){
  changeQuantity(id, 1);
}

function changeQuantity(id, delta){
  if(!inventoryLoaded){
    alert("Inventory is still loading — please try again in a moment.");
    return;
  }

  if(!currentUser){
    openAuth("Please sign in or create an account before adding items to your cart.");
    return;
  }

  const product = products.find(function(p){ return p.id == id; });
  if(!product || Number(product.stock) < 1) return;

  const current = Number(cart[id] || 0);
  const next = current + delta;

  if(next < 0) return;

  if(next > Number(product.stock)){
    alert("Only " + product.stock + " " + product.name + " available.");
    return;
  }

  if(next === 0) delete cart[id];
  else cart[id] = next;

  updateCart();
  renderProducts();
}

function removeFromCart(id){
  delete cart[id];
  updateCart();
  renderProducts();
}

function getCartSummary(){
  let count = 0;
  let total = 0;

  Object.entries(cart).forEach(function([id, quantity]){
    const product = products.find(function(p){ return p.id == id; });
    if(!product) return;
    count += Number(quantity);
    total += Number(product.price) * Number(quantity);
  });

  return {count: count, total: total};
}

function updateCart(){
  const summary = getCartSummary();
  const cartItems = document.getElementById("cartItems");
  const cartTotal = document.getElementById("cartTotal");
  const cartBar = document.getElementById("cartBar");

  if(cartItems) cartItems.textContent = summary.count + " item" + (summary.count === 1 ? "" : "s");
  if(cartTotal) cartTotal.textContent = "₹" + summary.total;
  if(cartBar) cartBar.classList.toggle("hidden", summary.count === 0);
}


/* =========================================================
   CHECKOUT
   ========================================================= */

function openCheckout(){
  if(!currentUser){
    openAuth("Please sign in to continue to checkout.");
    return;
  }

  const summary = getCartSummary();
  if(!summary.count) return;

  let rows = "";
  let subtotal = 0;

  Object.entries(cart).forEach(function([id, quantity]){
    const product = products.find(function(p){ return p.id == id; });
    if(!product) return;

    const itemTotal = Number(product.price) * Number(quantity);
    subtotal += itemTotal;

    rows += `
      <div class="checkout-row cart-checkout-row">
        <div>
          <b>${escapeHtml(product.name)}</b>
          <div class="checkout-qty">
            <button class="qty-btn checkout-minus" data-id="${escapeHtml(String(id))}">−</button>
            <span>${quantity}</span>
            <button class="qty-btn checkout-plus" data-id="${escapeHtml(String(id))}">+</button>
            <button class="remove-btn" data-id="${escapeHtml(String(id))}">Remove</button>
          </div>
        </div>
        <b>₹${itemTotal}</b>
      </div>
    `;
  });

  const delivery = subtotal >= CONFIG.freeDeliveryThreshold ? 0 : CONFIG.standardDeliveryFee;
  const total = subtotal + delivery;
  const modalContent = document.getElementById("modalContent");
  const modal = document.getElementById("modal");

  if(!modalContent || !modal) return;

  modalContent.innerHTML = `
    <h2>Your cart</h2>
    <p class="muted">Signed in as <b>${escapeHtml(currentUser.email || "")}</b></p>
    ${rows}
    <div class="checkout-row"><span>Subtotal</span><b>₹${subtotal}</b></div>
    <div class="checkout-row"><span>Delivery</span><b>${delivery ? "₹" + delivery : "FREE 🎉"}</b></div>
    <div class="checkout-total">Total ₹${total}</div>
    <hr>
    <h3>Delivery details</h3>
    <label>👤 Your name<input id="customerName" class="field" placeholder="Full name"></label>
    <label>📞 Phone number<input id="phone" class="field" type="tel" inputmode="tel" placeholder="10-digit mobile number"></label>
    <label>📍 Delivery address<textarea id="address" class="field" rows="3" placeholder="House no., village/area, landmark"></textarea></label>
    <button class="locationBtn" onclick="useCurrentLocation()">📍 Use my current location</button>
    <p id="locationMsg" class="muted"></p>
    <label>📝 Delivery note (optional)<textarea id="note" class="field" rows="2" placeholder="Any landmark or special instruction"></textarea></label>
    <button class="primary" id="placeOrderBtn">Place Order · ₹${total}</button>
    <p class="policy">Open-box delivery: if an item is damaged, incorrect, expired, or otherwise not acceptable on inspection, you may reject the affected order at the doorstep without being charged.</p>
  `;

  modalContent.querySelectorAll(".checkout-minus").forEach(function(btn){
    btn.addEventListener("click", function(){ changeQuantity(btn.dataset.id, -1); openCheckout(); });
  });
  modalContent.querySelectorAll(".checkout-plus").forEach(function(btn){
    btn.addEventListener("click", function(){ changeQuantity(btn.dataset.id, 1); openCheckout(); });
  });
  modalContent.querySelectorAll(".remove-btn").forEach(function(btn){
    btn.addEventListener("click", function(){ removeFromCart(btn.dataset.id); openCheckout(); });
  });

  const placeOrderBtn = document.getElementById("placeOrderBtn");
  if(placeOrderBtn){
    placeOrderBtn.addEventListener("click", function(){ placeOrder(subtotal, delivery, total); });
  }

  modal.classList.remove("hidden");
}


/* =========================================================
   CURRENT LOCATION
   ========================================================= */

function useCurrentLocation(){
  const message = document.getElementById("locationMsg");
  if(!message) return;

  if(!navigator.geolocation){
    message.textContent = "Location is not supported on this device. Please enter your address manually.";
    return;
  }

  message.textContent = "Getting your location…";

  navigator.geolocation.getCurrentPosition(
    async function(position){
      const latitude = position.coords.latitude;
      const longitude = position.coords.longitude;
      const address = document.getElementById("address");

      try {
        const response = await fetch("https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=" + latitude + "&lon=" + longitude + "&zoom=18&addressdetails=1", {headers:{"Accept":"application/json"}});
        const data = await response.json();
        const locationAddress = data.address || {};
        if(address) address.value = data.display_name || (latitude.toFixed(6) + ", " + longitude.toFixed(6));
        message.textContent = "Location found. " + (locationAddress.village || locationAddress.town || locationAddress.city || "Area");
      } catch(error) {
        if(address) address.value = "Current location: " + latitude.toFixed(6) + ", " + longitude.toFixed(6);
        message.textContent = "Coordinates added. Please add your house number or landmark.";
      }
    },
    function(){
      message.textContent = "Location permission was not granted. Please enter your address manually.";
    },
    {enableHighAccuracy:true, timeout:10000, maximumAge:60000}
  );
}


/* =========================================================
   PLACE ORDER
   ========================================================= */

async function placeOrder(subtotal, delivery, total){
  if(!currentUser){
    openAuth("Please sign in before placing your order.");
    return;
  }

  const nameInput = document.getElementById("customerName");
  const phoneInput = document.getElementById("phone");
  const addressInput = document.getElementById("address");
  const noteInput = document.getElementById("note");

  if(!nameInput || !phoneInput || !addressInput || !noteInput) return;

  const name = nameInput.value.trim();
  const phone = phoneInput.value.trim();
  const address = addressInput.value.trim();
  const note = noteInput.value.trim();

  if(!name || !phone || !address){
    alert("Please enter your name, phone number and delivery address.");
    return;
  }

  const cleanPhone = phone.replace(/\D/g, "");
  if(!/^\d{10}$/.test(cleanPhone)){
    alert("Please enter a valid 10-digit mobile number.");
    return;
  }

  const items = Object.entries(cart).map(function([id, quantity]){
    const product = products.find(function(p){ return p.id == id; });
    return {
      id: product.id,
      name: product.name,
      qty: Number(quantity),
      price: Number(product.price)
    };
  });

  const order = {
    id: "AW" + Date.now().toString().slice(-7),
    customerId: currentUser.uid,
    email: currentUser.email || "",
    name: name,
    phone: cleanPhone,
    address: address,
    note: note,
    items: items,
    subtotal: subtotal,
    delivery: delivery,
    total: total,
    paymentMethod: "COD",
    status: "New Order",
    time: new Date().toLocaleString("en-IN"),
    createdAt: new Date().toISOString()
  };

  // Save locally as an offline fallback.
  orders.unshift(order);
  try {
    localStorage.setItem("allwaysOrders", JSON.stringify(orders));
  } catch(error) {
    console.log("Could not save order locally.", error);
  }

  // Primary persistent order record.
  const savedToFirebase = await saveOrderToFirestore(order);
  if(!savedToFirebase){
    console.warn("Order could not be saved to Firestore; keeping local/Sheet fallback.");
  }

  // Keep the existing Google Sheets/Apps Script integration.
  sendOrderToBackend(order);

  cart = {};
  updateCart();
  renderProducts();
  closeModal();
  showSection("orders");
  renderOrders();
  showThankYou(order);
}


/* =========================================================
   FIRESTORE ORDERS
   ========================================================= */

async function saveOrderToFirestore(order){
  if(!firestoreReady || !window.firebase || !firebase.firestore) return false;

  try {
    await firebase.firestore().collection("orders").doc(order.id).set({
      ...order,
      createdAt: firebase.firestore.FieldValue.serverTimestamp()
    });
    return true;
  } catch(error) {
    console.error("ALLways Firestore order save failed:", error);
    return false;
  }
}


/* =========================================================
   GOOGLE APPS SCRIPT BACKEND
   ========================================================= */

async function sendOrderToBackend(order){
  try {
    await fetch(CONFIG.orderEndpoint, {
      method: "POST",
      mode: "no-cors",
      headers: { "Content-Type": "text/plain;charset=utf-8" },
      body: JSON.stringify(order)
    });
    console.log("ALLways: order sent to Google Apps Script.");
  } catch(error) {
    console.error("ALLways: Google Apps Script submission failed:", error);
  }
}


/* =========================================================
   THANK YOU
   ========================================================= */

function showThankYou(order){
  const modalContent = document.getElementById("modalContent");
  const modal = document.getElementById("modal");
  if(!modalContent || !modal) return;

  modalContent.innerHTML = `
    <div class="thankyou">
      <div class="successIcon">✓</div>
      <h2>Thank you, ${escapeHtml(order.name)}!</h2>
      <p>Your ALLways order <b>#${escapeHtml(order.id)}</b> has been received.</p>
      <p>We’ll contact you on <b>${escapeHtml(order.phone)}</b> to confirm delivery.</p>
      <div class="thankBox">
        <b>Order total: ₹${order.total}</b><br>
        <span>Keep your phone available for our delivery confirmation.</span>
      </div>
      <button class="primary" id="continueShoppingBtn">Continue shopping</button>
    </div>
  `;

  const continueBtn = document.getElementById("continueShoppingBtn");
  if(continueBtn) continueBtn.addEventListener("click", closeModal);
  modal.classList.remove("hidden");
}


/* =========================================================
   ORDERS
   ========================================================= */

function renderOrders(){
  const ordersList = document.getElementById("ordersList");
  if(!ordersList) return;

  if(!currentUser){
    ordersList.innerHTML = '<div class="empty">Please sign in to view your orders.</div>';
    return;
  }

  const myOrders = orders.filter(function(order){
    return order.customerId === currentUser.uid;
  });

  if(!myOrders.length){
    ordersList.innerHTML = '<div class="empty">No orders yet.</div>';
    return;
  }

  ordersList.innerHTML = myOrders.map(function(order){
    const itemText = (order.items || []).map(function(item){
      return escapeHtml(item.name) + " × " + item.qty;
    }).join(", ");

    return `
      <div class="orderCard">
        <div><b>#${escapeHtml(order.id)}</b><span class="status">${escapeHtml(order.status)}</span></div>
        <p>${itemText}</p>
        <b>₹${order.total}</b>
        <small>${escapeHtml(order.time)}</small>
      </div>
    `;
  }).join("");
}


/* =========================================================
   SECTIONS
   ========================================================= */

function showSection(id){
  document.querySelectorAll(".section").forEach(function(section){ section.classList.add("hidden"); });
  const target = document.getElementById(id);
  if(target) target.classList.remove("hidden");
  document.querySelectorAll(".tab").forEach(function(tab){
    tab.classList.toggle("active", tab.dataset.section === id);
  });
  if(id === "orders") renderOrders();
}


/* =========================================================
   TRAVEL
   ========================================================= */

function travelAction(type){
  const names = { ride: "Local rides", bus: "Bus tickets", train: "Train journeys", rental: "Vehicle rentals" };
  const message = document.getElementById("travelMsg");
  if(!message) return;
  message.innerHTML = "<b>" + escapeHtml(names[type] || "Travel") + "</b> will be available soon in your area. We’re preparing the ALLways Travel experience.";
}


/* =========================================================
   MODALS
   ========================================================= */

function closeModal(){
  const modal = document.getElementById("modal");
  if(modal) modal.classList.add("hidden");
}


/* =========================================================
   FIREBASE AUTHENTICATION
   ========================================================= */

function firebaseConfigured(){
  return !!(window.firebase && FIREBASE_CONFIG && FIREBASE_CONFIG.apiKey && FIREBASE_CONFIG.projectId);
}

function initAuth(){
  console.log("ALLways: starting Firebase authentication...");

  if(!firebaseConfigured()){
    firebaseReady = false;
    updateAuthButton();
    console.error("ALLways Firebase SDK was not loaded.");
    return;
  }

  try {
    if(!firebase.apps || firebase.apps.length === 0){
      firebase.initializeApp(FIREBASE_CONFIG);
    }

    const auth = firebase.auth();
    if(!auth) throw new Error("Firebase Auth is unavailable.");

    firebaseReady = true;
    firestoreReady = !!firebase.firestore;

    console.log("ALLways Firebase connected to project:", FIREBASE_CONFIG.projectId);

    auth.onAuthStateChanged(function(user){
      currentUser = user || null;
      console.log("ALLways auth state:", currentUser ? currentUser.email : "signed out");
      updateAuthButton();
      renderOrders();
      closeAuth();
    });
  } catch(error) {
    firebaseReady = false;
    firestoreReady = false;
    console.error("ALLways Firebase initialization failed:", error);
    updateAuthButton();
  }
}


/* =========================================================
   AUTH BUTTON
   ========================================================= */

function updateAuthButton(){
  const button = document.getElementById("loginBtn");
  if(!button) return;

  if(currentUser){
    button.textContent = "Account";
    button.onclick = function(){ openAccount(); };
  } else {
    button.textContent = "Sign in";
    button.onclick = function(){ openAuth(); };
  }
}


/* =========================================================
   AUTH MODAL
   ========================================================= */

function openAuth(message=""){
  if(currentUser){
    openAccount();
    return;
  }

  const content = document.getElementById("authContent");
  const modal = document.getElementById("authModal");
  if(!content || !modal) return;

  content.innerHTML = `
    <div class="auth-head">
      <span class="auth-icon">👤</span>
      <h2>ALLways Account</h2>
      <p class="muted">Sign in or create your customer account.</p>
    </div>
    ${message ? '<div class="auth-note">' + escapeHtml(message) + '</div>' : ""}
    <label>📧 Email<input id="authEmail" class="field" type="email" autocomplete="email" placeholder="you@example.com"></label>
    <label>🔒 Password<input id="authPassword" class="field" type="password" autocomplete="current-password" placeholder="At least 6 characters"></label>
    <button class="primary" id="loginSubmitBtn">Sign in</button>
    <button class="googleBtn" id="googleSignInBtn">🔵 Continue with Google</button>
    <button class="secondary" id="signupSubmitBtn">Create new account</button>
    <button class="textBtn" id="resetPasswordBtn">Forgot password?</button>
    <p id="authMsg" class="muted auth-msg"></p>
    <p class="policy">Your account is handled by Firebase Authentication. ALLways does not store your password in Google Sheets.</p>
  `;

  const loginBtn = document.getElementById("loginSubmitBtn");
  const signupBtn = document.getElementById("signupSubmitBtn");
  const googleBtn = document.getElementById("googleSignInBtn");
  const resetBtn = document.getElementById("resetPasswordBtn");

  if(loginBtn) loginBtn.addEventListener("click", loginCustomer);
  if(signupBtn) signupBtn.addEventListener("click", signupCustomer);
  if(googleBtn) googleBtn.addEventListener("click", signInWithGoogle);
  if(resetBtn) resetBtn.addEventListener("click", resetPassword);

  modal.classList.remove("hidden");
}


/* =========================================================
   GOOGLE SIGN-IN
   ========================================================= */

async function signInWithGoogle(){
  if(!firebaseReady){
    authMessage("Firebase is not connected. Please refresh the page and try again.");
    return;
  }

  authMessage("Opening Google sign-in…");

  try {
    const provider = new firebase.auth.GoogleAuthProvider();
    provider.setCustomParameters({ prompt: "select_account" });
    await firebase.auth().signInWithPopup(provider);
    closeAuth();
  } catch(error) {
    console.error("ALLways Google sign-in error:", error);

    if(error && error.code === "auth/popup-blocked"){
      authMessage("Your browser blocked the Google sign-in popup. Please allow popups for this site and try again.");
    } else if(error && error.code === "auth/popup-closed-by-user"){
      authMessage("Google sign-in was cancelled.");
    } else if(error && error.code === "auth/unauthorized-domain"){
      authMessage("This website domain is not authorized in Firebase yet.");
    } else {
      authMessage(authError(error));
    }
  }
}


/* =========================================================
   SIGN IN
   ========================================================= */

async function loginCustomer(){
  if(!firebaseReady){
    authMessage("Firebase is not connected. Please refresh the page and try again.");
    return;
  }

  const emailElement = document.getElementById("authEmail");
  const passwordElement = document.getElementById("authPassword");
  if(!emailElement || !passwordElement) return;

  const email = emailElement.value.trim();
  const password = passwordElement.value;

  if(!email || !password){
    authMessage("Enter your email and password.");
    return;
  }

  authMessage("Signing in…");

  try {
    await firebase.auth().signInWithEmailAndPassword(email, password);
    closeAuth();
  } catch(error) {
    console.error("ALLways sign-in error:", error);
    authMessage(authError(error));
  }
}


/* =========================================================
   CREATE ACCOUNT
   ========================================================= */

async function signupCustomer(){
  if(!firebaseReady){
    authMessage("Firebase is not connected. Please refresh the page and try again.");
    return;
  }

  const emailElement = document.getElementById("authEmail");
  const passwordElement = document.getElementById("authPassword");
  if(!emailElement || !passwordElement) return;

  const email = emailElement.value.trim();
  const password = passwordElement.value;

  if(!email || !password){
    authMessage("Enter an email and password.");
    return;
  }

  if(password.length < 6){
    authMessage("Password must be at least 6 characters.");
    return;
  }

  authMessage("Creating your account…");

  try {
    await firebase.auth().createUserWithEmailAndPassword(email, password);
    closeAuth();
  } catch(error) {
    console.error("ALLways account creation error:", error);
    authMessage(authError(error));
  }
}


/* =========================================================
   PASSWORD RESET
   ========================================================= */

async function resetPassword(){
  if(!firebaseReady){
    authMessage("Firebase is not connected. Please refresh the page and try again.");
    return;
  }

  const emailElement = document.getElementById("authEmail");
  if(!emailElement) return;

  const email = emailElement.value.trim();
  if(!email){
    authMessage("Enter your email first.");
    return;
  }

  try {
    await firebase.auth().sendPasswordResetEmail(email);
    authMessage("Password reset email sent. Check your inbox.");
  } catch(error) {
    console.error("ALLways password reset error:", error);
    authMessage(authError(error));
  }
}


/* =========================================================
   ACCOUNT
   ========================================================= */

function openAccount(){
  if(!currentUser){
    openAuth();
    return;
  }

  const content = document.getElementById("authContent");
  const modal = document.getElementById("authModal");
  if(!content || !modal) return;

  content.innerHTML = `
    <div class="auth-head">
      <span class="auth-icon">✓</span>
      <h2>Your ALLways Account</h2>
      <p class="muted">${escapeHtml(currentUser.email || "")}</p>
    </div>
    <button class="primary" id="myOrdersBtn">📦 My Orders</button>
    <button class="secondary" id="signOutBtn">Sign out</button>
  `;

  const myOrdersBtn = document.getElementById("myOrdersBtn");
  const signOutBtn = document.getElementById("signOutBtn");

  if(myOrdersBtn){
    myOrdersBtn.addEventListener("click", function(){
      showSection("orders");
      closeAuth();
    });
  }

  if(signOutBtn) signOutBtn.addEventListener("click", signOutCustomer);
  modal.classList.remove("hidden");
}


/* =========================================================
   SIGN OUT
   ========================================================= */

async function signOutCustomer(){
  try {
    if(firebaseReady) await firebase.auth().signOut();
  } catch(error) {
    console.error("ALLways sign-out error:", error);
  }

  cart = {};
  updateCart();
  renderProducts();
  closeAuth();
  showSection("shop");
}


/* =========================================================
   FIREBASE ERROR MESSAGES
   ========================================================= */

function authError(error){
  const code = error && error.code ? error.code : "";

  const messages = {
    "auth/invalid-email": "Please enter a valid email address.",
    "auth/user-disabled": "This account has been disabled.",
    "auth/user-not-found": "No account exists with this email. Use Create new account first.",
    "auth/wrong-password": "Incorrect password.",
    "auth/invalid-credential": "Email or password is incorrect.",
    "auth/weak-password": "Password is too weak. Use at least 6 characters.",
    "auth/email-already-in-use": "An account with this email already exists. Please sign in.",
    "auth/operation-not-allowed": "Email/password login is not enabled in Firebase.",
    "auth/too-many-requests": "Too many attempts. Please wait and try again.",
    "auth/network-request-failed": "Network error. Check your internet connection.",
    "auth/internal-error": "Firebase returned an internal error. Please try again.",
    "auth/account-exists-with-different-credential": "This email already has an account using another sign-in method. Use that method first.",
    "auth/cancelled-popup-request": "Another sign-in window is already open."
  };

  return messages[code] || (code ? "Firebase error: " + code : "Something went wrong. Please try again.");
}


/* =========================================================
   START APP
   ========================================================= */

function startALLways(){
  console.log("ALLways application starting...");

  document.querySelectorAll(".tab").forEach(function(tab){
    tab.onclick = function(){ showSection(tab.dataset.section); };
  });

  const search = document.getElementById("search");
  if(search) search.addEventListener("input", renderProducts);

  const checkoutBtn = document.getElementById("checkoutBtn");
  if(checkoutBtn) checkoutBtn.addEventListener("click", openCheckout);

  updateCart();
  renderOrders();
  loadInventory();
  initAuth();
}


/* =========================================================
   DOM READY
   ========================================================= */

if(document.readyState === "loading"){
  document.addEventListener("DOMContentLoaded", startALLways);
} else {
  startALLways();
}
