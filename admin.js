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
    if(!user){showAuth("Sign in to the ALLways admin account.");return;}
    if(!isAdmin(user)){
      showAuth("This Google/email account is not authorized as ALLways admin.");
      return;
    }
    document.getElementById("adminAuth").classList.add("hidden");
    document.getElementById("dashboard").classList.remove("hidden");
    listen();
  });
}

function showAuth(msg){
  var el=document.getElementById("adminAuth");
  el.innerHTML=
    "<div class=\"auth-head\"><span class=\"auth-icon\">🛠</span><h2>ALLways Admin Login</h2><p class=\"muted\">Use "+esc(ADMIN_EMAIL)+"</p></div>"+
    "<div class=\"auth-note\">"+esc(msg)+"</div>"+
    "<button class=\"googleBtn\" id=\"adminGoogleBtn\">G&nbsp; Continue with Google</button>"+
    "<div class=\"orLine\"><span>or use admin password</span></div>"+
    "<label>📧 Email<input id=\"adminEmail\" class=\"field\" type=\"email\" value=\""+esc(ADMIN_EMAIL)+"\" autocomplete=\"email\"></label>"+
    "<label>🔒 Firebase password<input id=\"adminPassword\" class=\"field\" type=\"password\" autocomplete=\"current-password\"></label>"+
    "<button class=\"primary\" id=\"adminLoginBtn\">Sign in to Admin</button>"+
    "<p id=\"adminLoginMsg\" class=\"muted auth-msg\"></p>"+
    "<p class=\"muted\">The Firebase password is separate from your Gmail password.</p>";
  document.getElementById("adminGoogleBtn").onclick=adminGoogleLogin;
  document.getElementById("adminLoginBtn").onclick=adminPasswordLogin;
}

function adminMessage(msg){
  var el=document.getElementById("adminLoginMsg");
  if(el)el.textContent=msg;
}

async function adminPasswordLogin(){
  var email=(document.getElementById("adminEmail").value||"").trim();
  var password=document.getElementById("adminPassword").value||"";
  if(email.toLowerCase()!==ADMIN_EMAIL.toLowerCase()){
    adminMessage("Use the configured admin email: "+ADMIN_EMAIL);
    return;
  }
  if(!password){adminMessage("Enter your Firebase password.");return;}
  adminMessage("Signing in…");
  try{
    await firebase.auth().signInWithEmailAndPassword(email,password);
  }catch(e){
    console.error(e);
    adminMessage(authError(e));
  }
}

async function adminGoogleLogin(){
  adminMessage("Opening Google sign-in…");
  try{
    var provider=new firebase.auth.GoogleAuthProvider();
    provider.setCustomParameters({prompt:"select_account"});
    await firebase.auth().signInWithPopup(provider);
  }catch(e){
    console.error(e);
    adminMessage(authError(e));
  }
}

function authError(error){
  var code=error&&error.code||"";
  var map={
    "auth/invalid-credential":"Wrong email/password, or this Firebase account does not have a password sign-in credential.",
    "auth/wrong-password":"Wrong Firebase password.",
    "auth/user-not-found":"No Firebase user exists with this email.",
    "auth/invalid-email":"Please enter a valid email address.",
    "auth/popup-blocked":"Google sign-in popup was blocked. Allow popups for this site.",
    "auth/popup-closed-by-user":"Google sign-in was cancelled.",
    "auth/operation-not-allowed":"Enable the required sign-in provider in Firebase Authentication → Sign-in method."
  };
  return map[code]||("Sign-in failed: "+code+(error&&error.message?" — "+error.message:""));
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