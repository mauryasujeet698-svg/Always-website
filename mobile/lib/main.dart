import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'firebase_options.dart';

const inventoryEndpoint='https://script.google.com/macros/s/AKfycbyuAdL6eEIlGiYhoTPFtE70VhyiMLnKgzO1ytctdSCWMtTdw4zIVQvEVwkbYJyJF2Wd/exec';
const updateManifestUrl='https://raw.githubusercontent.com/mauryasujeet698-svg/Always-website/allways-android-app/mobile/update.json';

Future<void> bg(RemoteMessage m) async { await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform); }

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(bg);
  runApp(const AllwaysApp());
}

class AllwaysApp extends StatelessWidget {
  const AllwaysApp({super.key});
  Widget build(BuildContext c)=>MaterialApp(
    debugShowCheckedModeBanner:false,title:'ALLways',
    theme:ThemeData(useMaterial3:true,colorScheme:ColorScheme.fromSeed(seedColor:Colors.black),
      inputDecorationTheme:const InputDecorationTheme(border:OutlineInputBorder())),
    home:const Shell());
}

class Product {
  final String id,name,category,icon,description,brand; final num price,stock;
  const Product({required this.id,required this.name,required this.category,required this.icon,required this.description,required this.brand,required this.price,required this.stock});
  factory Product.fromJson(Map<String,dynamic> j){
    num n(dynamic x)=>x is num?x:num.tryParse(x?.toString()??'')??0;
    return Product(id:(j['id']??'').toString(),name:(j['name']??j['title']??'Item').toString(),
      category:(j['category']??j['cat']??'Other').toString(),icon:(j['icon']??'🛍️').toString(),
      description:(j['description']??'').toString(),brand:(j['brand']??'').toString(),
      price:n(j['price']),stock:n(j['stock']));
  }
}
class CartItem { final Product product; int qty; CartItem(this.product,this.qty); }

class Shell extends StatefulWidget { const Shell({super.key}); State<Shell> createState()=>_ShellState(); }
class _ShellState extends State<Shell> {
  int tab=0; List<Product> products=[]; bool loading=true; String? error; Timer? timer;
  final Map<String,CartItem> cart={}; List<Map<String,dynamic>> addresses=[]; User? user;
  StreamSubscription<User?>? auth; StreamSubscription<RemoteMessage>? messages;
  String? updateVersion;
  String? updateUrl;
  String? updateNotes;

  @override void initState(){
    super.initState(); user=FirebaseAuth.instance.currentUser; loadInventory(); checkForUpdate();
    timer=Timer.periodic(const Duration(seconds:30),(_)=>loadInventory(silent:true));
    auth=FirebaseAuth.instance.authStateChanges().listen((u){setState(()=>user=u);if(u!=null){setupNotifications();loadAddresses();}else{addresses=[];}});
    messages=FirebaseMessaging.onMessage.listen((m){if(!mounted)return;ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text((m.notification?.title??'ALLways')+': '+(m.notification?.body??'New update'))));});
    if(user!=null){setupNotifications();loadAddresses();}
  }
  @override void dispose(){timer?.cancel();auth?.cancel();messages?.cancel();super.dispose();}

  Future<void> setupNotifications() async {
    try{
      await FirebaseMessaging.instance.requestPermission(alert:true,badge:true,sound:true);
      final t=await FirebaseMessaging.instance.getToken();
      if(t!=null){
        final p=await SharedPreferences.getInstance();
        await p.setString('allways_fcm_token',t);
      }
      FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
        final p=await SharedPreferences.getInstance();
        await p.setString('allways_fcm_token',t);
      });
    }catch(_){}
  }

  class ProfilePage extends StatelessWidget{
  final User? user;final List<Map<String,dynamic>> addresses;final VoidCallback onLogin;final Future<void> Function() onReload;final Future<void> Function(String) onDelete;
  const ProfilePage({super.key,required this.user,required this.addresses,required this.onLogin,required this.onReload,required this.onDelete});
  Future<void> _checkForUpdate(BuildContext c) async {
    try {
      final r=await http.get(Uri.parse('https://raw.githubusercontent.com/mauryasujeet698-svg/Always-website/allways-android-app/mobile/update.json')).timeout(const Duration(seconds:8));
      if(r.statusCode!=200)throw Exception();
      final data=jsonDecode(r.body) as Map<String,dynamic>;
      final latest=(data['version']??'').toString();
      final current=await PackageInfo.fromPlatform();
      int v(String x)=>x.split('.').map((e)=>int.tryParse(e)??0).fold(0,(a,b)=>a*1000+b);
      if(latest.isNotEmpty&&v(latest)>v(current.version)){
        if(c.mounted)showDialog(context:c,builder:(_)=>AlertDialog(title:const Text('Update available'),content:Text('ALLways '+latest+' is available. Update now for the latest improvements.'),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Later')),FilledButton(onPressed:()async{Navigator.pop(c);final url=(data['apkUrl']??'').toString();if(url.isNotEmpty)await launchUrl(Uri.parse(url),mode:LaunchMode.externalApplication);},child:const Text('UPDATE NOW'))]));
      }else if(c.mounted)ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content:Text('You are using the latest ALLways version.')));
    }catch(_){if(c.mounted)ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content:Text('Could not check for updates. Please try again.')));}
  }

  Widget build(BuildContext c){
    if(user==null)return Center(child:FilledButton(onPressed:onLogin,child:const Text('Sign in / Sign up')));
    return ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Profile',style:TextStyle(fontSize:28,fontWeight:FontWeight.w900)),const SizedBox(height:12),
      Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.person)),title:Text(user!.displayName??'ALLways customer'),subtitle:Text(user!.email??''))),
      const SizedBox(height:16),Row(children:[const Expanded(child:Text('Saved addresses',style:TextStyle(fontSize:20,fontWeight:FontWeight.w800))),IconButton(onPressed:onReload,icon:const Icon(Icons.refresh))]),
      if(addresses.isEmpty)const InfoCard(title:'No saved addresses',detail:'An address is saved after a successful order.')
      else ...addresses.map((x)=>Card(child:ListTile(title:Text((x['name']??'').toString()),subtitle:Text((x['address']??'').toString()),trailing:IconButton(onPressed:()=>onDelete(x['id'].toString()),icon:const Icon(Icons.delete_outline))))),
      ListTile(leading:const Icon(Icons.share_outlined),title:const Text('Share ALLways'),subtitle:const Text('Share ALLways with friends and family'),onTap:()=>SharePlus.instance.share(ShareParams(text:'Try ALLways — Closer to You, Always. Download the ALLways app: https://github.com/mauryasujeet698-svg/Always-website/releases/download/allways-latest/allways-release.apk'))),
      ListTile(leading:const Icon(Icons.system_update_outlined),title:const Text('Check for updates'),subtitle:const Text('Check for the latest ALLways version'),onTap:()=>_checkForUpdate(c)),
      ListTile(leading:const Icon(Icons.notifications_outlined),title:const Text('Notifications'),subtitle:const Text('Order and ALLways alerts'),onTap:()async{final s=await FirebaseMessaging.instance.requestPermission(alert:true,badge:true,sound:true);if(c.mounted)ScaffoldMessenger.of(c).showSnackBar(SnackBar(content:Text(s.authorizationStatus==AuthorizationStatus.authorized?'Notifications enabled.':'Permission not granted.')));}),
      ListTile(leading:const Icon(Icons.logout),title:const Text('Log out'),onTap:()=>FirebaseAuth.instance.signOut()),
      const SizedBox(height:20),const Text('ALLways • Closer to You, Always',textAlign:TextAlign.center,style:TextStyle(color:Colors.grey))
    ]);
  }
}

class AuthScreen extends StatefulWidget{const AuthScreen({super.key});State<AuthScreen> createState()=>_AuthState();}
class _AuthState extends State<AuthScreen>{
  final email=TextEditingController(),pass=TextEditingController(),name=TextEditingController();bool signup=false,busy=false,hide=true;
  @override void dispose(){email.dispose();pass.dispose();name.dispose();super.dispose();}
  String err(Object e){if(e is FirebaseAuthException){if(e.code=='invalid-credential'||e.code=='wrong-password')return'Email or password is incorrect. Use Forgot password if this is an existing account.';if(e.code=='user-not-found')return'No account exists with this email.';if(e.code=='email-already-in-use')return'An account already exists with this email.';if(e.code=='weak-password')return'Use a stronger password.';if(e.code=='invalid-email')return'Enter a valid email address.';return e.message??'Authentication failed.';}return'Something went wrong.';}
  Future<void> googleSignIn() async {
    setState(() => busy = true);
    try {
      final GoogleSignInAccount? account = await GoogleSignIn(serverClientId: '869987297351-bonithsodhkkhb8a994d6hbiau8a3ltv.apps.googleusercontent.com').signIn();
      if (account == null) {
        if (mounted) setState(() => busy = false);
        return;
      }
      final GoogleSignInAuthentication auth = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err(e))),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit()async{setState(()=>busy=true);try{if(signup){final x=await FirebaseAuth.instance.createUserWithEmailAndPassword(email:email.text.trim(),password:pass.text);if(name.text.trim().isNotEmpty)await x.user?.updateDisplayName(name.text.trim());}else{await FirebaseAuth.instance.signInWithEmailAndPassword(email:email.text.trim(),password:pass.text);}if(mounted)Navigator.pop(context);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(err(e))));}finally{if(mounted)setState(()=>busy=false);}}
  Future<void> reset()async{if(email.text.trim().isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter your email first.')));return;}try{await FirebaseAuth.instance.sendPasswordResetEmail(email:email.text.trim());if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Password reset email sent.')));}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(err(e))));}}
  Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:Text(signup?'Create ALLways account':'Sign in')),body:ListView(padding:const EdgeInsets.all(20),children:[
    const Text('ALLways',style:TextStyle(fontSize:34,fontWeight:FontWeight.w900)),const Text('Closer to You, Always',style:TextStyle(color:Colors.grey)),const SizedBox(height:25),
    if(signup)TextField(controller:name,decoration:const InputDecoration(labelText:'Your name')),if(signup)const SizedBox(height:10),
    TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'Email')),const SizedBox(height:10),
    TextField(controller:pass,obscureText:hide,decoration:InputDecoration(labelText:'Password',suffixIcon:IconButton(onPressed:()=>setState(()=>hide=!hide),icon:Icon(hide?Icons.visibility:Icons.visibility_off)))),const SizedBox(height:16),
    FilledButton(onPressed:busy?null:submit,child:Text(busy?'Please wait…':signup?'Create account':'Sign in')),
    if(!signup) ...[
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: busy ? null : googleSignIn,
        icon: const Icon(Icons.account_circle_outlined),
        label: const Text('Continue with Google'),
      ),
      const SizedBox(height: 4),
    ],
    if(!signup)TextButton(onPressed:busy?null:reset,child:const Text('Forgot password?')),
    TextButton(onPressed:busy?null:()=>setState(()=>signup=!signup),child:Text(signup?'Already have an account? Sign in':'Create a new account'))
  ]));
}

class InfoCard extends StatelessWidget{final String title,detail;const InfoCard({super.key,required this.title,required this.detail});Widget build(BuildContext c)=>Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontWeight:FontWeight.w800)),const SizedBox(height:6),Text(detail,style:const TextStyle(color:Colors.grey))])));}
