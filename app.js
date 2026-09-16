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

/* =========================================================
   ALLways Firebase Configuration
   ========================================================= */

const FIREBASE_CONFIG={
  apiKey:"AIzaSyBLnjczQY43c8cKzBSteoxPTFBzBFkBgCs",
  authDomain:"allways-a2ac2.firebaseapp.com",
  projectId:"allways-a2ac2",
  storageBucket:"allways-a2ac2.firebasestorage.app",
  messagingSenderId:"696197561195",
  appId:"1:696197561195:web:47e6fb9c52b552d846ea2e",
  measurementId:"G-RXVGPYP96C"
};

/* =========================================================
   ALLways Business Settings
   ========================================================= */

const CONFIG={
  freeDeliveryThreshold:499,
  standardDeliveryFee:30,
  orderEndpoint:""
};

let cart={};
let selectedCat="All";
let orders=JSON.parse(localStorage.getItem("allwaysOrders")||"[]");
let currentUser=null;
let firebaseReady=false;

const cats=["All",...new Set(products.map(p=>p.cat))];

/* =========================================================
   SHOP
   ========================================================= */

function renderCats(){
  const el=document.getElementById("categories");
  if(!el)return;

  el.innerHTML=cats.map(c=>
    `<button class="cat ${c===selectedCat?"active":""}" onclick="setCat('${c}')">${c}</button>`
  ).join("");
}

function renderProducts(){
  const search=document.getElementById("search");
  const productsEl=document.getElementById("products");
  const count=document.getElementById("count");

  if(!search||!productsEl)return;

  let q=search.value.toLowerCase();

  let list=products.filter(p=>
    (selectedCat==="All"||p.cat===selectedCat) &&
    p.name.toLowerCase().includes(q)
  );

  if(count)count.textContent=list.length+" shown";

  productsEl.innerHTML=list.map(p=>
    `<article class="product">
      <div class="pic">${p.icon}</div>
      <h3>${p.name}</h3>
      <small>${p.cat}</small>
      <div class="price">₹${p.price}</div>
      <div class="stock">
        ${p.stock>0?"● In stock":"● Unavailable"}
      </div>
      <button
        class="add"
        ${p.stock<1?"disabled":""}
        onclick="add(${p.id})">
        ${p.stock<1?"Unavailable":"Add"}
      </button>
    </article>`
  ).join("")||`<div class="empty">No matching items.</div>`;
}

function setCat(c){
  selectedCat=c;

  const title=document.getElementById("categoryTitle");
  if(title){
    title.textContent=c==="All"?"All items":c;
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

  const p=products.find(x=>x.id===id);

  if(!p||p.stock<1)return;

  const next=(cart[id]||0)+1;

  if(next>p.stock){
    alert(`Only ${p.stock} ${p.name} available.`);
    return;
  }

  cart[id]=next;
  updateCart();
}

function updateCart(){

  let n=0;
  let total=0;

  for(const [id,q] of Object.entries(cart)){

    const p=products.find(x=>x.id==id);

    if(!p)continue;

    n+=q;
    total+=p.price*q;
  }

  const cartItems=document.getElementById("cartItems");
  const cartTotal=document.getElementById("cartTotal");
  const cartBar=document.getElementById("cartBar");

  if(cartItems){
    cartItems.textContent=n+" item"+(n===1?"":"s");
  }

  if(cartTotal){
    cartTotal.textContent="₹"+total;
  }

  if(cartBar){
    cartBar.classList.toggle("hidden",n===0);
  }
}

/* =========================================================
   CHECKOUT
   ========================================================= */

function openCheckout(){

  if(!currentUser){
    openAuth("Please sign in to continue to checkout.");
    return;
  }

  if(!Object.keys(cart).length)return;

  let rows="";
  let sub=0;

  for(const [id,q] of Object.entries(cart)){

    const p=products.find(x=>x.id==id);

    if(!p)continue;

    const t=p.price*q;

    sub+=t;

    rows+=`
      <div class="checkout-row">
        <span>${escapeHtml(p.name)} × ${q}</span>
        <b>₹${t}</b>
      </div>`;
  }

  const delivery=
    sub>=CONFIG.freeDeliveryThreshold
    ?0
    :CONFIG.standardDeliveryFee;

  const total=sub+delivery;

  const modalContent=document.getElementById("modalContent");
  const modal=document.getElementById("modal");

  if(!modalContent||!modal)return;

  modalContent.innerHTML=`
    <h2>Complete your order</h2>

    <p class="muted">
      Signed in as <b>${escapeHtml(currentUser.email)}</b>
    </p>

    <p class="muted">
      Open-box delivery: please check your items before accepting.
    </p>

    ${rows}

    <div class="checkout-row">
      <span>Subtotal</span>
      <b>₹${sub}</b>
    </div>

    <div class="checkout-row">
      <span>Delivery</span>
      <b>${delivery?"₹"+delivery:"FREE 🎉"}</b>
    </div>

    <div class="checkout-total">
      Total ₹${total}
    </div>

    <hr>

    <label>
      👤 Your name
      <input
        id="customerName"
        class="field"
        placeholder="Full name">
    </label>

    <label>
      📞 Phone number
      <input
        id="phone"
        class="field"
        type="tel"
        inputmode="tel"
        placeholder="10-digit mobile number">
    </label>

    <label>
      📍 Delivery address
      <textarea
        id="address"
        class="field"
        rows="3"
        placeholder="House no., village/area, landmark"></textarea>
    </label>

    <button class="locationBtn" onclick="useCurrentLocation()">
      📍 Use my current location
    </button>

    <p id="locationMsg" class="muted"></p>

    <label>
      📝 Delivery note (optional)
      <textarea
        id="note"
        class="field"
        rows="2"
        placeholder="Any landmark or special instruction"></textarea>
    </label>

    <button
      class="primary"
      onclick="placeOrder(${sub},${delivery},${total})">
      Place Order
    </button>

    <p class="policy">
      Open-box delivery: if an item is damaged, incorrect, expired,
      or otherwise not acceptable on inspection, you may reject the
      affected order at the doorstep without being charged.
      Other cancellations/refunds are handled according to ALLways policy.
    </p>
  `;

  modal.classList.remove("hidden");
}

/* =========================================================
   CURRENT LOCATION
   ========================================================= */

function useCurrentLocation(){

  const msg=document.getElementById("locationMsg");

  if(!msg)return;

  if(!navigator.geolocation){

    msg.textContent=
      "Location is not supported on this device. Please enter your address manually.";

    return;
  }

  msg.textContent="Getting your location…";

  navigator.geolocation.getCurrentPosition(

    async pos=>{

      const latitude=pos.coords.latitude;
      const longitude=pos.coords.longitude;

      try{

        const r=await fetch(
          `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${latitude}&lon=${longitude}&zoom=18&addressdetails=1`,
          {
            headers:{
              Accept:"application/json"
            }
          }
        );

        const d=await r.json();
        const a=d.address||{};

        const address=document.getElementById("address");

        if(address){
          address.value=
            d.display_name||
            `${latitude.toFixed(6)}, ${longitude.toFixed(6)}`;
        }

        msg.textContent=
          `Location found. ${a.village||a.town||a.city||"Area"}`;

      }catch(e){

        const address=document.getElementById("address");

        if(address){
          address.value=
            `Current location: ${latitude.toFixed(6)}, ${longitude.toFixed(6)}`;
        }

        msg.textContent=
          "Location coordinates added. Please add a house number/landmark if needed.";
      }

    },

    ()=>{
      msg.textContent=
        "Location permission was not granted. Please enter your address manually.";
    },

    {
      enableHighAccuracy:true,
      timeout:10000,
      maximumAge:60000
    }
  );
}

/* =========================================================
   PLACE ORDER
   ========================================================= */

function placeOrder(sub,delivery,total){

  const name=document.getElementById("customerName").value.trim();
  const phone=document.getElementById("phone").value.trim();
  const address=document.getElementById("address").value.trim();
  const note=document.getElementById("note").value.trim();

  if(!name||!phone||!address){

    alert(
      "Please enter your name, phone number and delivery address."
    );

    return;
  }

  if(!/^\d{10}$/.test(phone.replace(/\D/g,""))){

    alert("Please enter a valid 10-digit mobile number.");

    return;
  }

  const items=Object.entries(cart).map(([id,q])=>{

    const p=products.find(x=>x.id==id);

    return{
      id:p.id,
      name:p.name,
      qty:q,
      price:p.price
    };

  });

  const order={
    id:"AW"+Date.now().toString().slice(-7),
    customerId:currentUser.uid,
    email:currentUser.email,
    name,
    phone,
    address,
    note,
    items,
    subtotal:sub,
    delivery,
    total,
    status:"New Order",
    time:new Date().toLocaleString("en-IN")
  };

  orders.unshift(order);

  localStorage.setItem(
    "allwaysOrders",
    JSON.stringify(orders)
  );

  if(CONFIG.orderEndpoint){
    sendOrderToBackend(order);
  }

  cart={};

  updateCart();
  closeModal();
  showSection("orders");
  renderOrders();
  showThankYou(order);
}

async function sendOrderToBackend(order){

  try{

    await fetch(
      CONFIG.orderEndpoint,
      {
        method:"POST",
        mode:"no-cors",
        headers:{
          "Content-Type":"text/plain;charset=utf-8"
        },
        body:JSON.stringify(order)
      }
    );

  }catch(e){

    console.log(
      "Backend submission failed",
      e
    );
  }
}

/* =========================================================
   THANK YOU
   ========================================================= */

function showThankYou(order){

  const modalContent=document.getElementById("modalContent");
  const modal=document.getElementById("modal");

  if(!modalContent||!modal)return;

  modalContent.innerHTML=`
    <div class="thankyou">

      <div class="successIcon">✓</div>

      <h2>
        Thank you, ${escapeHtml(order.name)}!
      </h
