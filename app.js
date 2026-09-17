/* =========================================================
   LIVE INVENTORY STATE
   ========================================================= */

let products = [];
let cats = ["All"];


/* =========================================================
   FIREBASE CONFIGURATION
   ========================================================= */

const FIREBASE_CONFIG = {
  apiKey: "AIzaSyBLnjczQY43c8cKzBSteoxPTFBzBFkBgCs",
  authDomain: "allways-a2ac2.firebaseapp.com",
  projectId: "allways-a2ac2",
  storageBucket: "allways-a2ac2.firebasestorage.app",
  messagingSenderId: "696197561195",
  appId: "1:696197561195:web:47e6fb9c52b552d846ea2e",
  measurementId: "G-RXVGPYP96C"
};


/* =========================================================
   BUSINESS SETTINGS
   ========================================================= */

const CONFIG = {
  freeDeliveryThreshold: 499,
  standardDeliveryFee: 30,
  /* GOOGLE APPS SCRIPT WEB APP */
  orderEndpoint: "https://script.google.com/macros/s/AKfycbyuAdL6eEIlGiYhoTPFtE70VhyiMLnKgzO1ytctdSCWMtTdw4zIVQvEVwkbYJyJF2Wd/exec"
};


/* =========================================================
   APP STATE
   ========================================================= */

let cart = {};
let selectedCat = "All";
let currentUser = null;
let firebaseReady = false;
let orders = [];

try {
  orders = JSON.parse(localStorage.getItem("allwaysOrders") || "[]");
} catch(e) {
  orders = [];
}


/* =========================================================
   FETCH INVENTORY FROM GOOGLE SHEETS
   ========================================================= */

async function loadInventory() {
  try {
    const response = await fetch(CONFIG.orderEndpoint);
    const data = await response.json();
    
    // Extract products from your JSON format
    let fetchedProducts = data.products || data;
    
    // Ensure the app reads 'category' as 'cat'
    products = fetchedProducts.map(p => ({
      ...p,
      cat: p.category || p.cat
    }));
    
    cats = ["All", ...new Set(products.map(p => p.cat))];
    
    renderCats();
    renderProducts();
  } catch (error) {
    console.error("Error loading inventory from Google Sheets:", error);
  }
}


/* =========================================================
   SAFE HTML
   ========================================================= */

function escapeHtml(value){
  return String(value ?? "").replace(/[&<>'"]/g, function(c){
    return {"&":"&amp;", "<":"&lt;", ">":"&gt;", "'":"&#39;", '"':"&quot;"}[c];
  });
}


/* =========================================================
   SHOP
   ========================================================= */

function renderCats(){
  const el = document.getElementById("categories");
  if(!el) return;
  el.innerHTML = cats.map(function(c){
    return `<button class="cat ${c === selectedCat ? "active" : ""}" onclick="setCat('${escapeHtml(c)}')">${escapeHtml(c)}</button>`;
  }).join("");
}

function renderProducts(){
  const search = document.getElementById("search");
  const productsEl = document.getElementById("products");
  const count = document.getElementById("count");

  if(!productsEl) return;

  const q = search ? search.value.toLowerCase().trim() : "";
  const list = products.filter(function(p){
    const categoryMatch = selectedCat === "All" || p.cat === selectedCat;
    const searchMatch = p.name.toLowerCase().includes(q);
    return categoryMatch && searchMatch;
  });

  if(count){
    count.textContent = list.length + " shown";
  }

  if(!list.length){
    productsEl.innerHTML = `<div class="empty">No matching items.</div>`;
    return;
  }

  productsEl.innerHTML = list.map(function(p){
    return `
      <article class="product">
        <div class="pic">${p.icon}</div>
        <h3>${escapeHtml(p.name)}</h3>
        <small>${escapeHtml(p.cat)}</small>
        <div class="price">₹${p.price}</div>
        <div class="stock">${p.stock > 0 ? "● In stock" : "● Unavailable"}</div>
        <button class="add" ${p.stock < 1 ? "disabled" : ""} onclick="add(${p.id})">
          ${p.stock < 1 ? "Unavailable" : "Add"}
        </button>
      </article>
    `;
  }).join("");
}

function setCat(category){
  selectedCat = category;
  const title = document.getElementById("categoryTitle");
  if(title){
    title.textContent = category === "All" ? "All items" : category;
  }
  renderCats();
  renderProducts();
}


/* =========================================================
   CART
   ========================================================= */

function add(id){
  if(!currentUser){
    openAuth("Please sign in or create an account before adding items to your cart.");
    return;
  }
  const product = products.find(function(p){ return p.id == id; });
  if(!product || product.stock < 1){ return; }

  const next = (cart[id] || 0) + 1;
  if(next > product.stock){
    alert(`Only ${product.stock} ${product.name} available.`);
    return;
  }

  cart[id] = next;
  updateCart();
}

function updateCart(){
  let count = 0;
  let total = 0;

  Object.entries(cart).forEach(function([id, quantity]){
    const product = products.find(function(p){ return p.id == id; });
    if(!product) return;
    count += quantity;
    total += product.price * quantity;
  });

  const cartItems = document.getElementById("cartItems");
  const cartTotal = document.getElementById("cartTotal");
  const cartBar = document.getElementById("cartBar");

  if(cartItems) cartItems.textContent = count + " item" + (count === 1 ? "" : "s");
  if(cartTotal) cartTotal.textContent = "₹" + total;
  if(cartBar) cartBar.classList.toggle("hidden", count === 0);
}


/* =========================================================
   CHECKOUT
   ========================================================= */

function openCheckout(){
  if(!currentUser){
    openAuth("Please sign in to continue to checkout.");
    return;
  }
  if(!Object.keys(cart).length) return;

  let rows = "";
  let subtotal = 0;

  Object.entries(cart).forEach(function([id, quantity]){
    const product = products.find(function(p){ return p.id == id; });
    if(!product) return;
    const itemTotal = product.price * quantity;
    subtotal += itemTotal;
    rows += `
      <div class="checkout-row">
        <span>${escapeHtml(product.name)} × ${quantity}</span>
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
    <h2>Complete your order</h2>
    <p class="muted">Signed in as <b>${escapeHtml(currentUser.email)}</b></p>
    <p class="muted">Open-box delivery: please check your items before accepting.</p>
    ${rows}
    <div class="checkout-row"><span>Subtotal</span><b>₹${subtotal}</b></div>
    <div class="checkout-row"><span>Delivery</span><b>${delivery ? "₹" + delivery : "FREE 🎉"}</b></div>
    <div class="checkout-total">Total ₹${total}</div>
    <hr>
    <label>👤 Your name<input id="customerName" class="field" placeholder="Full name"></label>
    <label>📞 Phone number<input id="phone" class="field" type="tel" inputmode="tel" placeholder="10-digit mobile number"></label>
    <label>📍 Delivery address<textarea id="address" class="field" rows="3" placeholder="House no., village/area, landmark"></textarea></label>
    <button class="locationBtn" onclick="useCurrentLocation()">📍 Use my current location</button>
    <p id="locationMsg" class="muted"></p>
    <label>📝 Delivery note (optional)<textarea id="note" class="field" rows="2" placeholder="Any landmark or special instruction"></textarea></label>
    <button class="primary" onclick="placeOrder(${subtotal},${delivery},${total})">Place Order</button>
    <p class="policy">Open-box delivery: if an item is damaged, incorrect, expired, or otherwise not acceptable on inspection, you may reject the affected order at the doorstep without being charged.</p>
  `;

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
        const response = await fetch(`https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${latitude}&lon=${longitude}&zoom=18&addressdetails=1`, {headers:{"Accept":"application/json"}});
        const data = await response.json();
        const locationAddress = data.address || {};
        if(address) address.value = data.display_name || `${latitude.toFixed(6)}, ${longitude.toFixed(6)}`;
        message.textContent = `Location found. ${locationAddress.village || locationAddress.town || locationAddress.city || "Area"}`;
      } catch(error) {
        if(address) address.value = `Current location: ${latitude.toFixed(6)}, ${longitude.toFixed(6)}`;
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

function placeOrder(subtotal, delivery, total){
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
    return { id: product.id, name: product.name, qty: quantity, price: product.price };
  });

  const order = {
    id: "AW" + Date.now().toString().slice(-7),
    customerId: currentUser.uid,
    email: currentUser.email,
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
    time: new Date().toLocaleString("en-IN")
  };

  orders.unshift(order);

  try {
    localStorage.setItem("allwaysOrders", JSON.stringify(orders));
  } catch(error) {
    console.log("Could not save order locally.", error);
  }

  /* SEND ORDER TO GOOGLE APPS SCRIPT */
  if(CONFIG.orderEndpoint){
    sendOrderToBackend(order);
  }

  cart = {};
  updateCart();
  closeModal();
  showSection("orders");
  renderOrders();
  showThankYou(order);
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
      <button class="primary" onclick="closeModal()">Continue shopping</button>
    </div>
  `;
  modal.classList.remove("hidden");
}


/* =========================================================
   ORDERS
   ========================================================= */

function renderOrders(){
  const ordersList = document.getElementById("ordersList");
  if(!ordersList) return;

  if(!currentUser){
    ordersList.innerHTML = `<div class="empty">Please sign in to view your orders.</div>`;
    return;
  }

  const myOrders = orders.filter(function(order){
    return order.customerId === currentUser.uid;
  });

  if(!myOrders.length){
    ordersList.innerHTML = `<div class="empty">No orders yet.</div>`;
    return;
  }

  ordersList.innerHTML = myOrders.map(function(order){
    const itemText = (order.items || []).map(function(item){
      return `${escapeHtml(item.name)} × ${item.qty}`;
    }).join(", ");

    return `
      <div class="orderCard">
        <div>
          <b>#${escapeHtml(order.id)}</b>
          <span class="status">${escapeHtml(order.status)}</span>
        </div>
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
  document.querySelectorAll(".section").forEach(function(section){
    section.classList.add("hidden");
  });
  const target = document.getElementById(id);
  if(target){
    target.classList.remove("hidden");
  }
  document.querySelectorAll(".tab").forEach(function(tab){
    tab.classList.toggle("active", tab.dataset.section === id);
  });
  if(id === "orders"){
    renderOrders();
  }
}


/* =========================================================
   TRAVEL
   ========================================================= */

function travelAction(type){
  const names = { ride: "Local rides", bus: "Bus tickets", train: "Train journeys", rental: "Vehicle rentals" };
  const message = document.getElementById("travelMsg");
  if(!message) return;
  message.innerHTML = `<b>${escapeHtml(names[type] || "Travel")}</b> will be available soon in your area. We’re preparing the ALLways Travel experience.`;
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
    console.log("ALLways Firebase authentication connected.");

    auth.onAuthStateChanged(function(user){
      currentUser = user || null;
      console.log("ALLways auth state:", currentUser ? currentUser.email : "signed out");
      updateAuthButton();
      renderOrders();
    });
  } catch(error) {
    firebaseReady = false;
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
      <p class="muted">Sign in or create your customer account with email.</p>
    </div>
    ${message ? `<div class="auth-note">${escapeHtml(message)}</div>` : ""}
    <label>📧 Email<input id="authEmail" class="field" type="email" autocomplete="email" placeholder="you@example.com"></label>
    <label>🔒 Password<input id="authPassword" class="field" type="password" autocomplete="current-password" placeholder="At least 6 characters"></label>
    <button class="primary" onclick="loginCustomer()">Sign in</button>
    <button class="secondary" onclick="signupCustomer()">Create new account</button>
    <button class="textBtn" onclick="resetPassword()">Forgot password?</button>
    <p id="authMsg" class="muted auth-msg"></p>
    <p class="policy">Your account is handled by Firebase Authentication. ALLways does not store your password in the Google Sheet.</p>
  `;
  modal.classList.remove("hidden");
}

function closeAuth(){
  const modal = document.getElementById("authModal");
  if(modal) modal.classList.add("hidden");
}

function authMessage(message){
  const element = document.getElementById("authMsg");
  if(element) element.textContent = message;
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
      <p class="muted">${escapeHtml(currentUser.email)}</p>
    </div>
    <button class="primary" onclick="showSection('orders');closeAuth()">📦 My Orders</button>
    <button class="secondary" onclick="signOutCustomer()">Sign out</button>
  `;
  modal.classList.remove("hidden");
}


/* =========================================================
   SIGN OUT
   ========================================================= */

async function signOutCustomer(){
  try {
    if(firebaseReady){
      await firebase.auth().signOut();
    }
  } catch(error) {
    console.error("ALLways sign-out error:", error);
  }
  cart = {};
  updateCart();
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
    "auth/user-not-found": "No account exists with this email.",
    "auth/wrong-password": "Incorrect password.",
    "auth/invalid-credential": "Email or password is incorrect.",
    "auth/weak-password": "Password is too weak. Use at least 6 characters.",
    "auth/email-already-in-use": "An account with this email already exists. Please sign in.",
    "auth/operation-not-allowed": "Email/password login is not enabled in Firebase.",
    "auth/too-many-requests": "Too many attempts. Please wait and try again.",
    "auth/network-request-failed": "Network error. Check your internet connection.",
    "auth/internal-error": "Firebase returned an internal error. Please try again."
  };

  if(messages[code]){
    return messages[code];
  }
  console.error("Unknown Firebase error code:", code, error);
  return code ? `Firebase error: ${code}` : "Something went wrong. Please try again.";
}


/* =========================================================
   START APP
   ========================================================= */

function startALLways(){
  console.log("ALLways application starting...");

  document.querySelectorAll(".tab").forEach(function(tab){
    tab.onclick = function(){
      showSection(tab.dataset.section);
    };
  });

  const search = document.getElementById("search");
  if(search){
    search.addEventListener("input", renderProducts);
  }

  updateCart();
  renderOrders();
  
  // FETCH LIVE DATA FROM GOOGLE SHEETS
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
