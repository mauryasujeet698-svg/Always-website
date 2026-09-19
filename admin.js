const FIREBASE_CONFIG={
apiKey:"AIzaSyCopzTF-jwLnzcbCnW5Y9nIHYMkiinaZ28",
authDomain:"allways-web.firebaseapp.com",
projectId:"allways-web",
storageBucket:"allways-web.firebasestorage.app",
messagingSenderId:"869987297351",
appId:"1:869987297351:web:fde91fb46194a141976962",
measurementId:"G-1N2DFFC7BT"};
const ADMIN_EMAIL="mauryasujeet698@gmail.com";
let db=null,allOrders=[],unsubscribe=null,initial=true;

function esc(v){
  return String(v==null?"":v).replace(/[&<>'"]/g,function(c){
    return {"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[c];
  });
}
function isAdmin(u){return u&&String(u.email||"").toLowerCase()===ADMIN_EMAIL.toLowerCase();}
function init(){
  firebase.initializeApp(FIREBASE_CONFIG);
  db=firebase.firestore();
  firebase.auth().onAuthStateChanged(function(user){
    if(!user){showAuth("Sign in with the ALLways admin account.");return;}
    if(!isAdmin(user)){showAuth("This account is not authorized as an ALLways admin.");return;}
    document.getElementById("adminAuth").classList.add("hidden");
    document.getElementById("dashboard").classList.remove("hidden");
    listen();
  });
}
function showAuth(msg){
  document.getElementById("adminAuth").innerHTML="<b>"+esc(msg)+"</b><p>Use the Store page to sign in, then return here.</p><a class=\"primary adminLink\" href=\"index.html\">Open ALLways sign in</a>";
}
function listen(){
  if(unsubscribe)unsubscribe();
  initial=true;
  unsubscribe=db.collection("orders").onSnapshot(function(s){
    allOrders=s.docs.map(function(d){return d.data();}).sort(function(a,b){return (b.createdAt||0)-(a.createdAt||0);});
    render();
    if(!initial){
      s.docChanges().forEach(function(ch){
        if(ch.type==="added"){
          var o=ch.doc.data();
          notify("New ALLways order #"+ch.doc.id,(o.name||"Customer")+" • ₹"+(o.total||0));
        }
      });
    }
    initial=false;
  },function(e){
    document.getElementById("orders").innerHTML="<div class=\"empty\">Cannot read orders. Check Firestore Rules. "+esc(e.code||e.message)+"</div>";
  });
}
function render(){
  var n=allOrders.filter(function(o){return o.status==="New Order";}).length;
  var c=allOrders.filter(function(o){return o.status==="Confirmed";}).length;
  var d=allOrders.filter(function(o){return o.status==="Delivered";}).length;
  var r=allOrders.reduce(function(s,o){return s+Number(o.total||0);},0);
  document.getElementById("summary").innerHTML=
    "<div><b>"+allOrders.length+"</b><small>Total orders</small></div>"+
    "<div><b>"+n+"</b><small>New</small></div>"+
    "<div><b>"+c+"</b><small>Confirmed</small></div>"+
    "<div><b>"+d+"</b><small>Delivered</small></div>"+
    "<div><b>₹"+r+"</b><small>Order value</small></div>";
  document.getElementById("orderCount").textContent=allOrders.length+" total";
  if(!allOrders.length){document.getElementById("orders").innerHTML="<div class=\"empty\">No orders yet.</div>";return;}
  document.getElementById("orders").innerHTML=allOrders.map(function(o){
    var opts=["New Order","Confirmed","Preparing","Out for delivery","Delivered","Cancelled"].map(function(s){
      return "<option "+(s===o.status?"selected":"")+">"+s+"</option>";
    }).join("");
    var items=(o.items||[]).map(function(i){
      return esc(i.name)+" × "+i.qty+" — ₹"+(Number(i.price||0)*Number(i.qty||0));
    }).join("<br>");
    return "<article class=\"adminOrder\">"+
      "<div class=\"adminOrderHead\"><div><b>#"+esc(o.id)+"</b> <span class=\"status\">"+esc(o.status||"New Order")+"</span></div><b>₹"+esc(o.total)+"</b></div>"+
      "<div class=\"adminGrid\"><div><small>Customer</small><b>"+esc(o.name)+"</b><span>"+esc(o.phone)+"</span><span>"+esc(o.email)+"</span></div>"+
      "<div><small>Address</small><span>"+esc(o.address)+"</span>"+(o.note?"<span>📝 "+esc(o.note)+"</span>":"")+"</div></div>"+
      "<p class=\"adminItems\">"+items+"</p>"+
      "<div class=\"adminActions\"><select onchange=\"updateStatus('"+esc(o.id)+"',this.value)\">"+opts+"</select><a href=\"tel:"+esc(o.phone)+"\">📞 Call</a></div>"+
      "<small>"+esc(o.time||"")+"</small></article>";
  }).join("");
}
async function updateStatus(id,status){
  try{await db.collection("orders").doc(id).update({status:status,updatedAt:Date.now()});}
  catch(e){alert("Update failed: "+(e.code||e.message));}
}
async function enableNotifications(){
  if(!("Notification" in window)){alert("Notifications are not supported.");return;}
  var p=await Notification.requestPermission();
  if(p==="granted")notify("ALLways alerts enabled","New orders will alert you while this admin page is open.");
}
function notify(title,body){
  if("Notification" in window&&Notification.permission==="granted")new Notification(title,{body:body});
  try{if(navigator.vibrate)navigator.vibrate([150,80,150]);}catch(e){}
}
document.addEventListener("DOMContentLoaded",function(){
  init();
  document.getElementById("notifyBtn").onclick=enableNotifications;
  document.getElementById("refreshBtn").onclick=listen;
});