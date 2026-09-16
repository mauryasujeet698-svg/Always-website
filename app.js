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
let cart={};let selectedCat="All";let orders=JSON.parse(localStorage.getItem("allwaysOrders")||"[]");

const cats=["All",...new Set(products.map(p=>p.cat))];
function renderCats(){document.getElementById("categories").innerHTML=cats.map(c=>`<button class="cat ${c===selectedCat?"active":""}" onclick="setCat('${c}')">${c}</button>`).join("")}
function renderProducts(){
 let q=document.getElementById("search").value.toLowerCase();
 let list=products.filter(p=>(selectedCat==="All"||p.cat===selectedCat)&&p.name.toLowerCase().includes(q));
 document.getElementById("count").textContent=list.length+" shown";
 document.getElementById("products").innerHTML=list.map(p=>`<article class="product"><div class="pic">${p.icon}</div><h3>${p.name}</h3><small>${p.cat}</small><div class="price">₹${p.price}</div><div class="stock">${p.stock>0?"● In stock":"● Unavailable"}</div><button class="add" ${p.stock<1?"disabled":""} onclick="add(${p.id})">${p.stock<1?"Unavailable":"Add"}</button></article>`).join("")||`<div class="empty">No matching items.</div>`;
}
function setCat(c){selectedCat=c;document.getElementById("categoryTitle").textContent=c==="All"?"All items":c;renderCats();renderProducts()}
function add(id){cart[id]=(cart[id]||0)+1;updateCart()}
function updateCart(){let n=0,total=0;for(const [id,q] of Object.entries(cart)){let p=products.find(x=>x.id==id);n+=q;total+=p.price*q}document.getElementById("cartItems").textContent=n+" item"+(n===1?"":"s");document.getElementById("cartTotal").textContent="₹"+total;document.getElementById("cartBar").classList.toggle("hidden",n===0)}
function openCheckout(){
 let rows="",sub=0;for(const [id,q] of Object.entries(cart)){let p=products.find(x=>x.id==id);let t=p.price*q;sub+=t;rows+=`<div class="checkout-row"><span>${p.name} × ${q}</span><b>₹${t}</b></div>`}
 let delivery=sub>=499?0:20,total=sub+delivery;
 document.getElementById("modalContent").innerHTML=`<h2>Checkout</h2>${rows}<div class="checkout-row"><span>Subtotal</span><b>₹${sub}</b></div><div class="checkout-row"><span>Delivery</span><b>${delivery?"₹"+delivery:"FREE 🎉"}</b></div><div class="checkout-total">Total ₹${total}</div><hr><label>📞 Call me on this number<input id="phone" class="field" type="tel" placeholder="+91 XXXXX XXXXX"></label><label>📍 Delivery address<textarea id="address" class="field" rows="3" placeholder="House no., village/area, landmark"></textarea></label><button class="primary" onclick="placeOrder(${sub},${delivery},${total})">Place Order</button>`;
 document.getElementById("modal").classList.remove("hidden")
}
function placeOrder(sub,delivery,total){
 let phone=document.getElementById("phone").value.trim(),address=document.getElementById("address").value.trim();
 if(!phone||!address){alert("Please enter your phone number and delivery address.");return}
 let order={id:"AW"+Date.now().toString().slice(-6),phone,address,total,status:"Received",time:new Date().toLocaleString("en-IN")};
 orders.unshift(order);localStorage.setItem("allwaysOrders",JSON.stringify(orders));cart={};updateCart();closeModal();showSection("orders");renderOrders()
}
function renderOrders(){document.getElementById("ordersList").innerHTML=orders.length?orders.map(o=>`<div class="product"><b>#${o.id}</b><p>₹${o.total} · ${o.status}</p><small>${o.time}</small><br><small>📞 ${o.phone}</small></div>`).join(""):"<div class='empty'>No orders yet.</div>"}
function showSection(id){document.querySelectorAll(".section").forEach(s=>s.classList.add("hidden"));document.getElementById(id).classList.remove("hidden");document.querySelectorAll(".tab").forEach(t=>t.classList.toggle("active",t.dataset.section===id));if(id==="orders")renderOrders()}
function travelAction(type){const names={ride:"Book a local ride",bus:"Search bus tickets",train:"Search train journeys",rental:"Rent a vehicle"};document.getElementById("travelPanel").querySelector("h3").textContent=names[type]||"Travel";document.getElementById("travelMsg").textContent=type==="ride"?"Enter pickup and destination to find available drivers.":"This travel module is ready to connect to the relevant booking backend."}
function requestRide(){let from=document.getElementById("from").value,to=document.getElementById("to").value;if(!from||!to){alert("Enter pickup and destination.");return}document.getElementById("travelMsg").textContent=`Searching available drivers from ${from} to ${to}…`}
function closeModal(){document.getElementById("modal").classList.add("hidden")}
document.querySelectorAll(".tab").forEach(t=>t.onclick=()=>showSection(t.dataset.section));
document.getElementById("search").addEventListener("input",renderProducts);
renderCats();renderProducts();renderOrders();
