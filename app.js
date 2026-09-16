const products=[
{id:1,name:"Amul Milk 1L",cat:"Grocery",price:60,stock:20,icon:"🥛"},
{id:2,name:"Rice 5kg",cat:"Grocery",price:300,stock:15,icon:"🍚"},
{id:3,name:"Eggs 12 pcs",cat:"Grocery",price:72,stock:30,icon:"🥚"},
{id:4,name:"Bread 400g",cat:"Bakery",price:45,stock:0,icon:"🍞"},
{id:5,name:"Biscuits",cat:"Snacks",price:40,stock:30,icon:"🍪"},
{id:6,name:"Fruit Juice",cat:"Beverages",price:80,stock:18,icon:"🧃"},
{id:7,name:"Wheat Flour 5kg",cat:"Grocery",price:260,stock:12,icon:"🌾"},
{id:8,name:"Sugar 1kg",cat:"Grocery",price:50,stock:25,icon:"🧂"}
];

// Firebase Authentication is used for real customer accounts.
// Replace the placeholder values below with the config from your Firebase Web App.
const FIREBASE_CONFIG={
  apiKey:"AIzaSyBLnjczQY43c8cKzBSteoxPTFBzBFkBgCs",
  authDomain:"allways-a2ac2.firebaseapp.com",
  projectId:"allways-a2ac2",
  storageBucket:"allways-a2ac2.firebasestorage.app",
  messagingSenderId:"696197561195",
  appId:"1:696197561195:web:47e6fb9c52b552d846ea2e",
  measurementId:"G-RXVGPYP96C"
};

// Later these values can come from your business dashboard/backend.
const CONFIG={freeDeliveryThreshold:499,standardDeliveryFee:30,orderEndpoint:""};
let cart={};let selectedCat="All";let orders=JSON.parse(localStorage.getItem("allwaysOrders")||"[]");
let currentUser=null;
let firebaseReady=false;
const cats=["All",...new Set(products.map(p=>p.cat))];

function renderCats(){document.getElementById("categories").innerHTML=cats.map(c=>`<button class="cat ${c===selectedCat?"active":""}" onclick="setCat('${c}')">${c}</button>`).join("")}
function renderProducts(){
 let q=document.getElementById("search").value.toLowerCase();
 let list=products.filter(p=>(selectedCat==="All"||p.cat===selectedCat)&&p.name.toLowerCase().includes(q));
 document.getElementById("count").textContent=list.length+" shown";
 document.getElementById("products").innerHTML=list.map(p=>`<article class="product"><div class="pic">${p.icon}</div><h3>${p.name}</h3><small>${p.cat}</small><div class="price">₹${p.price}</div><div class="stock">${p.stock>0?"● In stock":"● Unavailable"}</div><button class="add" ${p.stock<1?"disabled":""} onclick="add(${p.id})">${p.stock<1?"Unavailable":"Add"}</button></article>`).join("")||`<div class="empty">No matching items.</div>`;
}
function setCat(c){selectedCat=c;document.getElementById("categoryTitle").textContent=c==="All"?"All items":c;renderCats();renderProducts()}
function add(id){
 if(!currentUser){openAuth("Please sign in or create an account before adding items to your cart.");return}
 const p=products.find(x=>x.id===id); if(!p||p.stock<1)return;
 const next=(cart[id]||0)+1; if(next>p.stock){alert(`Only ${p.stock} ${p.name} available.`);return}
 cart[id]=next;updateCart()
}
function updateCart(){let n=0,total=0;for(const [id,q] of Object.entries(cart)){let p=products.find(x=>x.id==id);if(!p)continue;n+=q;total+=p.price*q}document.getElementById("cartItems").textContent=n+" item"+(n===1?"":"s");document.getElementById("cartTotal").textContent="₹"+total;document.getElementById("cartBar").classList.toggle("hidden",n===0)}
function openCheckout(){
 if(!currentUser){openAuth("Please sign in to continue to checkout.");return}
 if(!Object.keys(cart).length)return;
 let rows="",sub=0;for(const [id,q] of Object.entries(cart)){let p=products.find(x=>x.id==id);let t=p.price*q;sub+=t;rows+=`<div class="checkout-row"><span>${p.name} × ${q}</span><b>₹${t}</b></div>`}
 let delivery=sub>=CONFIG.freeDeliveryThreshold?0:CONFIG.standardDeliveryFee,total=sub+delivery;
 document.getElementById("modalContent").innerHTML=`<h2>Complete your order</h2><p class="muted">Signed in as <b>${escapeHtml(currentUser.email)}</b></p><p class="muted">Open-box delivery: please check your items before accepting.</p>${rows}<div class="checkout-row"><span>Subtotal</span><b>₹${sub}</b></div><div class="checkout-row"><span>Delivery</span><b>${delivery?"₹"+delivery:"FREE 🎉"}</b></div><div class="checkout-total">Total ₹${total}</div><hr><label>👤 Your name<input id="customerName" class="field" placeholder="Full name"></label><label>📞 Phone number<input id="phone" class="field" type="tel" inputmode="tel" placeholder="10-digit mobile number"></label><label>📍 Delivery address<textarea id="address" class="field" rows="3" placeholder="House no., village/area, landmark"></textarea></label><button class="locationBtn" onclick="useCurrentLocation()">📍 Use my current location</button><p id="locationMsg" class="muted"></p><label>📝 Delivery note (optional)<textarea id="note" class="field" rows="2" placeholder="Any landmark or special instruction"></textarea></label><button class="primary" onclick="placeOrder(${sub},${delivery},${total})">Place Order</button><p class="policy">Open-box delivery: if an item is damaged, incorrect, expired, or otherwise not acceptable on inspection, you may reject the affected order at the doorstep without being charged. Other cancellations/refunds are handled according to ALLways policy.</p>`;
 document.getElementById("modal").classList.remove("hidden")
}
function useCurrentLocation(){
 const msg=document.getElementById("locationMsg");
 if(!navigator.geolocation){msg.textContent="Location is not supported on this device. Please enter your address manually.";return}
 msg.textContent="Getting your location…";
 navigator.geolocation.getCurrentPosition(async pos=>{
   const {latitude,longitude}=pos.coords;
   try{
     const r=await fetch(`https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${latitude}&lon=${longitude}&zoom=18&addressdetails=1`,{headers:{Accept:"application/json"}});
     const d=await r.json(); const a=d.address||{};
     document.getElementById("address").value=d.display_name||`${latitude.toFixed(6)}, ${longitude.toFixed(6)}`;
     msg.textContent=`Location found. ${a.village||a.town||a.city||"Area"}`;
   }catch(e){document.getElementById("address").value=`Current location: ${latitude.toFixed(6)}, ${longitude.toFixed(6)}`;msg.textContent="Location coordinates added. Please add a house number/landmark if needed."}
 },()=>{msg.textContent="Location permission was not granted. Please enter your address manually."},{enableHighAccuracy:true,timeout:10000,maximumAge:60000});
}

function placeOrder(sub,delivery,total){
 let name=document.getElementById("customerName").value.trim(),phone=document.getElementById("phone").value.trim(),address=document.getElementById("address").value.trim(),note=document.getElementById("note").value.trim();
 if(!name||!phone||!address){alert("Please enter your name, phone number and delivery address.");return}
 if(!/^\d{10}$/.test(phone.replace(/\D/g,""))){alert("Please enter a valid 10-digit mobile number.");return}
 let items=Object.entries(cart).map(([id,q])=>{let p=products.find(x=>x.id==id);return {id:p.id,name:p.name,qty:q,price:p.price}});
 let order={id:"AW"+Date.now().toString().slice(-7),customerId:currentUser.uid,email:currentUser.email,name,phone,address,note,items,subtotal:sub,delivery,total,status:"New Order",time:new Date().toLocaleString("en-IN")};
 orders.unshift(order);localStorage.setItem("allwaysOrders",JSON.stringify(orders));
 if(CONFIG.orderEndpoint) sendOrderToBackend(order);
 cart={};updateCart();closeModal();showSection("orders");renderOrders();showThankYou(order)
}
async function sendOrderToBackend(order){try{await fetch(CONFIG.orderEndpoint,{method:"POST",mode:"no-cors",headers:{"Content-Type":"text/plain;charset=utf-8"},body:JSON.stringify(order)})}catch(e){console.log("Backend submission failed",e)}}
function showThankYou(order){document.getElementById("modalContent").innerHTML=`<div class="thankyou"><div class="successIcon">✓</div><h2>Thank you, ${escapeHtml(order.name)}!</h2><p>Your ALLways order <b>#${order.id}</b> has been received.</p><p>We’ll contact you on <b>${escapeHtml(order.phone)}</b> to confirm delivery.</p><div class="thankBox"><b>Order total: ₹${order.total}</b><br><span>Keep your phone available for our delivery confirmation.</span></div><button class="primary" onclick="closeModal()">Continue shopping</button></div>`;document.getElementById("modal").classList.remove("hidden")}
function renderOrders(){document.getElementById("ordersList").innerHTML=orders.length?orders.filter(o=>!currentUser||o.customerId===currentUser.uid).map(o=>`<div class="orderCard"><div><b>#${o.id}</b><span class="status">${o.status}</span></div><p>${o.items.map(i=>`${escapeHtml(i.name)} × ${i.qty}`).join(", ")}</p><b>₹${o.total}</b><small>${o.time}</small></div>`).join("")||"<div class='empty'>No orders yet.</div>":"<div class='empty'>No orders yet.</div>"}
function showSection(id){document.querySelectorAll(".section").forEach(s=>s.classList.add("hidden"));document.getElementById(id).classList.remove("hidden");document.querySelectorAll(".tab").forEach(t=>t.classList.toggle("active",t.dataset.section===id));if(id==="orders")renderOrders()}
function travelAction(type){document.getElementById("travelMsg").innerHTML=`<b>${({ride:"Local rides",bus:"Bus tickets",train:"Train journeys",rental:"Vehicle rentals"})[type]||"Travel"}</b> will be available soon in your area. We’re preparing the ALLways Travel experience.`}
function closeModal(){document.getElementById("modal").classList.add("hidden")}

// ---------- Customer authentication ----------
function firebaseConfigured(){return window.firebase && FIREBASE_CONFIG.apiKey && !FIREBASE_CONFIG.apiKey.startsWith("PASTE_")}
function initAuth(){
 if(!firebaseConfigured()){firebaseReady=false;updateAuthButton();return}
 try{
   if(!firebase.apps.length)firebase.initializeApp(FIREBASE_CONFIG);
   firebaseReady=true;
   firebase.auth().onAuthStateChanged(user=>{currentUser=user;updateAuthButton();renderOrders();});
 }catch(e){console.error(e);firebaseReady=false;updateAuthButton()}
}
function updateAuthButton(){
 const btn=document.getElementById("loginBtn");
 if(!btn)return;
 if(currentUser){btn.textContent="Account";btn.onclick=()=>openAccount();}
 else{btn.textContent="Sign in";btn.onclick=()=>openAuth();}
}
function openAuth(message=""){
 if(currentUser){openAccount();return}
 document.getElementById("authContent").innerHTML=`<div class="auth-head"><span class="auth-icon">👤</span><h2>ALLways Account</h2><p class="muted">Sign in or create your customer account with email.</p></div>${message?`<div class="auth-note">${escapeHtml(message)}</div>`:""}<label>📧 Email<input id="authEmail" class="field" type="email" autocomplete="email" placeholder="you@example.com"></label><label>🔒 Password<input id="authPassword" class="field" type="password" autocomplete="current-password" placeholder="At least 6 characters"></label><button class="primary" onclick="loginCustomer()">Sign in</button><button class="secondary" onclick="signupCustomer()">Create new account</button><button class="textBtn" onclick="resetPassword()">Forgot password?</button><p id="authMsg" class="muted auth-msg"></p><p class="policy">Your account is handled by Firebase Authentication. ALLways does not store your password in the Google Sheet.</p>`;
 document.getElementById("authModal").classList.remove("hidden")
}
function openAccount(){document.getElementById("authContent").innerHTML=`<div class="auth-head"><span class="auth-icon">✓</span><h2>Your ALLways Account</h2><p class="muted">${escapeHtml(currentUser.email)}</p></div><button class="primary" onclick="showSection('orders');closeAuth()">📦 My Orders</button><button class="secondary" onclick="signOutCustomer()">Sign out</button>`;document.getElementById("authModal").classList.remove("hidden")}
function closeAuth(){document.getElementById("authModal").classList.add("hidden")}
function authMessage(text){const el=document.getElementById("authMsg");if(el)el.textContent=text}
async function loginCustomer(){
 if(!firebaseReady){authMessage("Authentication is not connected yet. Add your Firebase web config to app.js first.");return}
 const email=document.getElementById("authEmail").value.trim(),password=document.getElementById("authPassword").value;
 if(!email||!password){authMessage("Enter your email and password.");return}
 try{await firebase.auth().signInWithEmailAndPassword(email,password);closeAuth()}catch(e){authMessage(authError(e))}
}
async function signupCustomer(){
 if(!firebaseReady){authMessage("Authentication is not connected yet. Add your Firebase web config to app.js first.");return}
 const email=document.getElementById("authEmail").value.trim(),password=document.getElementById("authPassword").value;
 if(!email||!password){authMessage("Enter an email and password.");return}
 if(password.length<6){authMessage("Password must be at least 6 characters.");return}
 try{await firebase.auth().createUserWithEmailAndPassword(email,password);closeAuth()}catch(e){authMessage(authError(e))}
}
async function resetPassword(){
 if(!firebaseReady){authMessage("Authentication is not connected yet. Add your Firebase web config to app.js first.");return}
 const email=document.getElementById("authEmail").value.trim();if(!email){authMessage("Enter your email first.");return}
 try{await firebase.auth().sendPasswordResetEmail(email);authMessage("Password reset email sent. Check your inbox.")}catch(e){authMessage(authError(e))}
}
async function signOutCustomer(){if(firebaseReady&&firebase.auth())await firebase.auth().signOut();cart={};updateCart();closeAuth();showSection("shop")}
function authError(e){const code=e&&e.code||"";const map={"auth/invalid-email":"Please enter a valid email address.","auth/weak-password":"Password is too weak. Use at least 6 characters.","auth/email-already-in-use":"An account with this email already exists. Please sign in.","auth/invalid-credential":"Email or password is incorrect.","auth/too-many-requests":"Too many attempts. Please wait and try again."};return map[code]||"Something went wrong. Please try again."}
function escapeHtml(v){return String(v??"").replace(/[&<>'"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;","\"":"&quot;"}[c]))}

document.querySelectorAll(".tab").forEach(t=>t.onclick=()=>showSection(t.dataset.section));
document.getElementById("search").addEventListener("input",renderProducts);
renderCats();renderProducts();renderOrders();initAuth();
