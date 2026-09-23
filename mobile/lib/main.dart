import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'travel_teaser_screen.dart';
import 'firebase_options.dart';

const adminEmail='mauryasujeet698@gmail.com';
const allwaysStorageBucket='gs://allways-web.firebasestorage.app';
final FirebaseStorage allwaysStorage=FirebaseStorage.instanceFor(bucket:allwaysStorageBucket);
const shareApkUrl='https://github.com/mauryasujeet698-svg/Always-website/releases/download/allways-latest/allways-v1.4.7.apk';

const inventoryEndpoint='https://script.google.com/macros/s/AKfycbyuAdL6eEIlGiYhoTPFtE70VhyiMLnKgzO1ytctdSCWMtTdw4zIVQvEVwkbYJyJF2Wd/exec';
const updateManifestUrl='https://raw.githubusercontent.com/mauryasujeet698-svg/Always-website/allways-android-app/mobile/update.json';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

@pragma('vm:entry-point')
Future<void> bg(RemoteMessage m) async { await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform); }

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(bg);
  final prefs = await SharedPreferences.getInstance();
  final savedTheme = prefs.getString('allways_theme_mode');
  if (savedTheme == 'light') {
    themeNotifier.value = ThemeMode.light;
  } else if (savedTheme == 'dark') {
    themeNotifier.value = ThemeMode.dark;
  } else {
    themeNotifier.value = ThemeMode.system;
  }
  runApp(const AllwaysApp());
}

class AllwaysApp extends StatelessWidget {
  const AllwaysApp({super.key});
  Widget build(BuildContext c)=>ValueListenableBuilder<ThemeMode>(
    valueListenable:themeNotifier,
    builder:(context,mode,_)=>
      MaterialApp(
        debugShowCheckedModeBanner:false,
        title:'ALLways',
        theme:ThemeData(
          useMaterial3:true,
          colorScheme:ColorScheme.fromSeed(seedColor:Colors.black),
          textTheme:GoogleFonts.interTextTheme(),
          inputDecorationTheme:const InputDecorationTheme(
            border:OutlineInputBorder(),
          ),
        ),
        darkTheme:ThemeData.dark(useMaterial3:true).copyWith(
          textTheme:GoogleFonts.interTextTheme(ThemeData.dark(useMaterial3:true).textTheme),
        ),
        themeMode:mode,
        home:const Shell(),
      ),
  );
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
  final Map<String,CartItem> cart={}; List<Map<String,dynamic>> addresses=[]; User? user; final Set<String> wishlistIds={};
  StreamSubscription<User?>? auth; StreamSubscription<RemoteMessage>? messages;
  String? updateVersion;
  String? updateUrl;
  String? updateNotes;

  @override void initState(){
    super.initState(); user=FirebaseAuth.instance.currentUser; loadInventory(); checkForUpdate();
    timer=Timer.periodic(const Duration(seconds:30),(_)=>loadInventory(silent:true));
    auth=FirebaseAuth.instance.authStateChanges().listen((u){setState(()=>user=u);if(u!=null){setupNotifications();loadAddresses();loadWishlist();}else{addresses=[];wishlistIds.clear();}});
    messages=FirebaseMessaging.onMessage.listen((m)async{final title=m.notification?.title??'ALLways';final body=m.notification?.body??'New update';await saveIncomingNotification(title,body);if(!mounted)return;try{await const MethodChannel('com.allways.app/apk_installer').invokeMethod('showNotification',{'title':title,'body':body});}catch(_){}ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(title+': '+body)));});
    if(user!=null){setupNotifications();loadAddresses();loadWishlist();}
  }
  @override void dispose(){timer?.cancel();auth?.cancel();messages?.cancel();super.dispose();}

  Future<void> setupNotifications() async {
    try{
      final prefs=await SharedPreferences.getInstance();
      if(prefs.getBool('allways_notifications_enabled')==false)return;
      await FirebaseMessaging.instance.requestPermission(alert:true,badge:true,sound:true);
      final t=await FirebaseMessaging.instance.getToken();
      Future<void> save(String token) async {
        final p=await SharedPreferences.getInstance();
        await p.setString('allways_fcm_token',token);
        if(user!=null){
          try{
            await FirebaseFirestore.instance.collection('fcmTokens').doc(user!.uid).set({
              'uid':user!.uid,'email':user!.email??'','token':token,'updatedAt':FieldValue.serverTimestamp()
            },SetOptions(merge:true));
          }catch(_){}
        }
      }
      if(t!=null)await save(t);
      FirebaseMessaging.instance.onTokenRefresh.listen((t) async { await save(t); });
    }catch(_){}
  }

  Future<void> saveIncomingNotification(String title,String body) async {
    try{
      final prefs=await SharedPreferences.getInstance();
      final raw=prefs.getStringList('allways_notifications')??<String>[];
      raw.insert(0,jsonEncode({'title':title,'body':body,'timestamp':DateTime.now().millisecondsSinceEpoch}));
      if(raw.length>50)raw.removeRange(50,raw.length);
      await prefs.setStringList('allways_notifications',raw);
    }catch(_){}
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs=await SharedPreferences.getInstance();
    await prefs.setBool('allways_notifications_enabled',enabled);
    if(enabled){
      await setupNotifications();
    }else{
      try{await FirebaseMessaging.instance.deleteToken();}catch(_){}
      if(user!=null){
        try{await FirebaseFirestore.instance.collection('fcmTokens').doc(user!.uid).delete();}catch(_){}
      }
      await prefs.remove('allways_fcm_token');
    }
  }

  Future<void> checkForUpdate() async {
    try {
      final r=await http.get(Uri.parse(updateManifestUrl)).timeout(const Duration(seconds:8));
      if(r.statusCode!=200)return;
      final data=jsonDecode(r.body);
      if(data is! Map)return;
      final remote=(data['version']??'').toString();
      final url=(data['apkUrl']??'').toString();
      if(remote.isEmpty||url.isEmpty)return;
      final info=await PackageInfo.fromPlatform();
      if(_versionGreater(remote,info.version)){
        if(!mounted)return;
        setState((){updateVersion=remote;updateUrl=url;updateNotes=(data['notes']??'').toString();});
      }
    }catch(_){}
  }

  bool _versionGreater(String remote,String local){
    List<int> p(String v)=>v.split('.').map((x)=>int.tryParse(x.replaceAll(RegExp(r'[^0-9]'),''))??0).toList();
    final a=p(remote),b=p(local);
    for(var i=0;i<3;i++){final x=i<a.length?a[i]:0,y=i<b.length?b[i]:0;if(x!=y)return x>y;}
    return false;
  }

  Future<void> openUpdate() async {
    final u=updateUrl;
    if(u==null||u.isEmpty)return;
    final messenger=ScaffoldMessenger.of(context);
    final controller=ValueNotifier<double>(0);
    try {
      showDialog(context:context,barrierDismissible:false,builder:(_)=>AlertDialog(
        title:const Text('Updating ALLways'),
        content:ValueListenableBuilder<double>(valueListenable:controller,builder:(_,p,__)=>Column(
          mainAxisSize:MainAxisSize.min,
          children:[LinearProgressIndicator(value:p>0?p:null),const SizedBox(height:12),
            Text(p>0?'Downloading '+(p*100).toStringAsFixed(0)+'%':'Starting download…')]
        )),
      ));
      final file=File(Directory.systemTemp.path+'/allways_update_'+DateTime.now().millisecondsSinceEpoch.toString()+'.apk');
      final downloadUrl=u+(u.contains('?')?'&':'?')+'cacheBust='+DateTime.now().millisecondsSinceEpoch.toString();
      await Dio().download(downloadUrl,file.path,deleteOnError:true,onReceiveProgress:(received,total){if(total>0)controller.value=received/total;});
      if(mounted)Navigator.of(context).pop();
      final result=await const MethodChannel('com.allways.app/apk_installer').invokeMethod<String>('installApk',{'path':file.path});
      if(result=='permission_required'){
        try{
          await const MethodChannel('com.allways.app/apk_installer').invokeMethod('openInstallSettings');
        }catch(_){}
        messenger.showSnackBar(const SnackBar(content:Text('Please allow ALLways to install updates, then tap Update again.')));
      }
      else if(result!='started')messenger.showSnackBar(SnackBar(content:Text('Could not start installation: '+(result??'unknown error'))));
    }catch(e){
      if(mounted&&Navigator.of(context).canPop())Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content:Text('Update failed: '+e.toString())));
    }finally{controller.dispose();}
  }
  Future<void> loadInventory({bool silent=false}) async {
    if(!silent&&mounted)setState(()=>loading=true);
    try{
      final r=await http.get(Uri.parse(inventoryEndpoint+'?_='+DateTime.now().millisecondsSinceEpoch.toString())).timeout(const Duration(seconds:15));
      if(r.statusCode<200||r.statusCode>=300)throw Exception('Inventory server error');
      final d=jsonDecode(r.body); final raw=d is Map?(d['products']??d):d;
      if(raw is! List)throw Exception('Invalid inventory response');
      final list=raw.whereType<Map>().map((x)=>Product.fromJson(Map<String,dynamic>.from(x))).toList();
      if(mounted)setState((){products=list;loading=false;error=null;});
    }catch(e){if(mounted&&!silent)setState((){loading=false;error=e.toString();});}
  }
  int get count=>cart.values.fold(0,(s,x)=>s+x.qty);
  num get total=>cart.values.fold(0,(s,x)=>s+x.product.price*x.qty);

  void add(Product p){
    if(user==null){login();return;} if(p.stock<=0)return;
    final q=cart[p.id]?.qty??0;
    if(q>=p.stock){msg('Only '+p.stock.toString()+' available.');return;}
    setState(()=>cart[p.id]=CartItem(p,q+1));msg(p.name+' added to cart');
  }
  void qty(String id,int d){
    final x=cart[id];if(x==null)return;final n=x.qty+d;
    if(n<=0)setState(()=>cart.remove(id));else if(n<=x.product.stock)setState(()=>x.qty=n);else msg('Only '+x.product.stock.toString()+' available.');
  }
  void msg(String s){if(!mounted)return;ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  void login(){Navigator.push(context,MaterialPageRoute(builder:(_)=>const AuthScreen()));}

  Future<void> loadWishlist() async {
    if(user==null)return;
    try{
      final snap=await FirebaseFirestore.instance.collection('customers').doc(user!.uid).collection('wishlist').get();
      wishlistIds..clear()..addAll(snap.docs.map((d)=>d.id));
      if(mounted)setState((){});
    }catch(_){}
  }

  Future<void> toggleWishlist(Product p) async {
    if(user==null){login();return;}
    final ref=FirebaseFirestore.instance.collection('customers').doc(user!.uid).collection('wishlist').doc(p.id);
    final adding=!wishlistIds.contains(p.id);
    setState((){if(adding)wishlistIds.add(p.id);else wishlistIds.remove(p.id);});
    try{
      if(adding){
        await ref.set({'id':p.id,'name':p.name,'category':p.category,'icon':p.icon,'description':p.description,'brand':p.brand,'price':p.price,'stock':p.stock,'addedAt':FieldValue.serverTimestamp()});
        msg('Added to wishlist');
      }else{
        await ref.delete();
        msg('Removed from wishlist');
      }
    }catch(_){
      setState((){if(adding)wishlistIds.remove(p.id);else wishlistIds.add(p.id);});
      msg('Could not update wishlist. Please try again.');
    }
  }

  Future<void> cancelOrder(String payload) async {
    if(user==null)return;
    final parts=payload.split('||');final orderId=parts.first;final reason=parts.length>1&&parts[1].trim().isNotEmpty?parts.sublist(1).join('||').trim():'Customer requested cancellation';
    try{
      final snap=await FirebaseFirestore.instance.collection('orders').doc(orderId).get();
      if(!snap.exists){msg('Order not found.');return;}
      final o=snap.data()??{};if(o['customerId']!=user!.uid){msg('You cannot cancel this order.');return;}
      final status=(o['status']??'').toString();if(status!='New Order'&&status!='Confirmed'){msg('This order can no longer be cancelled.');return;}
      await FirebaseFirestore.instance.collection('orders').doc(orderId).update({'status':'Cancelled','statusNote':'Cancelled by customer','cancellationReason':reason,'updatedAt':DateTime.now().millisecondsSinceEpoch});
      msg('Order #'+orderId+' cancelled.');
    }catch(e){msg('Could not cancel the order. Please try again.');}
  }

  Future<void> loadAddresses() async {
    if(user==null)return;
    try{
      final s=await FirebaseFirestore.instance.collection('customers').doc(user!.uid).collection('addresses').orderBy('createdAt',descending:true).get();
      addresses=s.docs.map((d)=>{'id':d.id,...d.data()}).toList();
      if(mounted)setState((){});
    }catch(_){addresses=[];}
  }
  Future<void> saveAddress(String n,String ph,String a) async {
    if(user==null)return;
    try{
      await FirebaseFirestore.instance.collection('customers').doc(user!.uid).collection('addresses').add({'name':n,'phone':ph,'address':a,'createdAt':FieldValue.serverTimestamp()});
      await loadAddresses();
    }catch(_){}
  }
  Future<void> deleteAddress(String id) async {
    if(user==null)return;
    try{await FirebaseFirestore.instance.collection('customers').doc(user!.uid).collection('addresses').doc(id).delete();await loadAddresses();}catch(_){}
  }

  Future<void> placeOrder(String name,String phone,String address,String note) async {
    if(user==null){login();return;} if(cart.isEmpty)return;
    await setupNotifications();
    final ph=phone.replaceAll(RegExp(r'\D'),'');
    if(name.trim().isEmpty||!RegExp(r'^\d{10}$').hasMatch(ph)||address.trim().isEmpty){msg('Enter name, valid 10-digit phone and address.');return;}
    for(final x in cart.values){final p=products.where((z)=>z.id==x.product.id).firstOrNull;if(p==null||p.stock<x.qty){msg(x.product.name+' is no longer available.');await loadInventory();return;}}
    final sub=total;final delivery=sub>=499?0:30;final grand=sub+delivery;final id='AW'+DateTime.now().millisecondsSinceEpoch.toString().substring(4);
    final order={'id':id,'customerId':user!.uid,'email':user!.email??'','name':name.trim(),'phone':ph,'address':address.trim(),'note':note.trim(),
      'items':cart.values.map((x)=>{'id':x.product.id,'name':x.product.name,'qty':x.qty,'price':x.product.price}).toList(),
      'subtotal':sub,'delivery':delivery,'total':grand,'paymentMethod':'COD','status':'New Order','estimatedDelivery':'','eta':'',
      'statusNote':'Order received','customerMessage':'Order received','cancellationReason':'','rating':null,'fcmToken':(await SharedPreferences.getInstance()).getString('allways_fcm_token')??'','createdAt':DateTime.now().millisecondsSinceEpoch,'updatedAt':DateTime.now().millisecondsSinceEpoch,'time':DateTime.now().toLocal().toString()};
    try{
      await FirebaseFirestore.instance.collection('orders').doc(id).set(order);
      await saveAddress(name.trim(),ph,address.trim());
      setState(()=>cart.clear());
      if(mounted){
        Navigator.of(context).pop();
        setState(()=>tab=0);
        await showDialog(context:context,builder:(_)=>AlertDialog(title:const Text('Thank you for your order!'),content:Text('Your order #'+id+' has been placed successfully. We will contact you to confirm delivery.'),actions:[FilledButton(onPressed:()=>Navigator.pop(context),child:const Text('Continue shopping'))]));
      }
    }catch(e){msg('Order could not be saved. Please try again.');}
  }

  Widget build(BuildContext c){
    final pages=[
      ShopPage(products:products,loading:loading,error:error,onRefresh:loadInventory,onAdd:add,cart:cart,onQty:qty,user:user,wishlistIds:wishlistIds,onWishlist:toggleWishlist),
      const TravelTeaserScreen(),
      const LocalSellersPage(),
      ProfilePage(user:user,addresses:addresses,onLogin:login,onReload:loadAddresses,onDelete:deleteAddress,onCancel:cancelOrder),
    ];
    return Scaffold(
      body:SafeArea(child:Column(children:[
        if(updateVersion!=null)
          MaterialBanner(
            content:Text('New ALLways update '+updateVersion!+(updateNotes!.isEmpty?'':' — '+updateNotes!)),
            leading:const Icon(Icons.system_update),
            actions:[TextButton(onPressed:openUpdate,child:const Text('UPDATE NOW'))],
          ),
        Expanded(child:pages[tab]),
      ])),
      bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const[
        NavigationDestination(icon:Icon(Icons.shopping_bag_outlined),label:'Shop'),
        NavigationDestination(icon:Icon(Icons.directions_car_outlined),label:'Travel'),
        NavigationDestination(icon:Icon(Icons.storefront_outlined),label:'Local sellers'),
        NavigationDestination(icon:Icon(Icons.person_outline),label:'Profile')]),
      floatingActionButton:count==0?null:FloatingActionButton.extended(
        onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>CartScreen(cart:cart,addresses:addresses,onQty:qty,onPlace:placeOrder))),
        icon:const Icon(Icons.shopping_cart),label:Text(count.toString()+' • ₹'+total.toStringAsFixed(0))),
    );
  }
}

class ShopPage extends StatefulWidget{
  final List<Product> products;final bool loading;final String? error;
  final Future<void> Function({bool silent}) onRefresh;final void Function(Product) onAdd;
  final Map<String,CartItem> cart;final void Function(String,int) onQty;
  final User? user;final Set<String> wishlistIds;final Future<void> Function(Product) onWishlist;
  const ShopPage({super.key,required this.products,required this.loading,required this.error,required this.onRefresh,required this.onAdd,required this.cart,required this.onQty,required this.user,required this.wishlistIds,required this.onWishlist});
  @override State<ShopPage> createState()=>_ShopPageState();
}
class _ShopPageState extends State<ShopPage>{
  String cat='All',search='';
  Widget _productCard(BuildContext c,Product p){
    final liked=widget.wishlistIds.contains(p.id);
    Widget cartAction;
    if(widget.cart.containsKey(p.id)){
      cartAction=Row(mainAxisSize:MainAxisSize.min,children:[
        IconButton(onPressed:()=>widget.onQty(p.id,-1),icon:const Icon(Icons.remove_circle_outline)),
        Text(widget.cart[p.id]!.qty.toString(),style:const TextStyle(fontWeight:FontWeight.w800)),
        IconButton(onPressed:p.stock>widget.cart[p.id]!.qty?()=>widget.onQty(p.id,1):null,icon:const Icon(Icons.add_circle_outline)),
      ]);
    }else{
      cartAction=IconButton(onPressed:p.stock>0?()=>widget.onAdd(p):null,icon:const Icon(Icons.add_shopping_cart));
    }
    return Card(
      margin:const EdgeInsets.only(bottom:9),
      child:ListTile(
        onTap:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>ProductScreen(product:p,onAdd:()=>widget.onAdd(p),liked:liked,onWishlist:()=>widget.onWishlist(p)))),
        leading:CircleAvatar(child:Text(p.icon)),
        title:Text(p.name,style:const TextStyle(fontWeight:FontWeight.w800)),
        subtitle:Text(p.category+' • ₹'+p.price.toString()+'\n'+(p.stock>0?'In stock':'Unavailable')),
        trailing:Row(mainAxisSize:MainAxisSize.min,children:[
          IconButton(onPressed:()=>widget.onWishlist(p),icon:Icon(liked?Icons.favorite:Icons.favorite_border)),
          cartAction,
        ]),
      ),
    );
  }
  @override Widget build(BuildContext c){
    final cats=<String>{'All',...widget.products.map((p)=>p.category)};
    final q=search.toLowerCase().trim();
    final list=widget.products.where((p){
      final text=(p.name+' '+p.category+' '+p.brand+' '+p.description).toLowerCase();
      return(cat=='All'||p.category==cat)&&(q.isEmpty||text.contains(q));
    }).toList();
    return RefreshIndicator(
      onRefresh:()=>widget.onRefresh(),
      child:ListView(
        padding:const EdgeInsets.fromLTRB(16,12,16,110),
        children:[
          const Text('ALLways',style:TextStyle(fontSize:30,fontWeight:FontWeight.w900)),
          const Text('Closer to You, Always',style:TextStyle(color:Colors.grey)),
          const SizedBox(height:14),
          Card(color:Colors.black,child:const Padding(padding:EdgeInsets.all(22),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('Priority Delivery',style:TextStyle(color:Colors.white70)),
            SizedBox(height:7),
            Text('Everything you need, closer to home.',style:TextStyle(color:Colors.white,fontSize:24,fontWeight:FontWeight.w800)),
            SizedBox(height:7),
            Text('Shop local essentials. Simple ordering.',style:TextStyle(color:Colors.white70)),
          ]))),
          const SizedBox(height:16),
          TextField(decoration:const InputDecoration(hintText:'Search items',prefixIcon:Icon(Icons.search)),onChanged:(v)=>setState(()=>search=v)),
          const SizedBox(height:10),
          SizedBox(height:44,child:ListView(scrollDirection:Axis.horizontal,children:cats.map((x)=>Padding(padding:const EdgeInsets.only(right:7),child:ChoiceChip(label:Text(x),selected:cat==x,onSelected:(_)=>setState(()=>cat=x)))).toList())),
          const SizedBox(height:14),
          if(widget.loading)const Padding(padding:EdgeInsets.all(40),child:Center(child:CircularProgressIndicator()))
          else if(widget.error!=null)const InfoCard(title:'Could not load inventory',detail:'Check your connection and pull down to retry.')
          else if(list.isEmpty)const InfoCard(title:'No items found',detail:'Try another category or search.')
          else for(final p in list)_productCard(c,p),
        ],
      ),
    );
  }
}

class ProductScreen extends StatelessWidget{
  final Product product; final VoidCallback onAdd; final bool liked; final VoidCallback onWishlist;
  const ProductScreen({super.key,required this.product,required this.onAdd,required this.liked,required this.onWishlist});
  @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:Text(product.name),actions:[IconButton(onPressed:onWishlist,icon:Icon(liked?Icons.favorite:Icons.favorite_border))]),body:ListView(padding:const EdgeInsets.all(20),children:[
    CircleAvatar(radius:54,child:Text(product.icon,style:const TextStyle(fontSize:44))),const SizedBox(height:20),
    Text(product.name,style:const TextStyle(fontSize:28,fontWeight:FontWeight.w900)),const SizedBox(height:8),Text(product.category,style:const TextStyle(color:Colors.grey)),
    if(product.brand.isNotEmpty)Text(product.brand,style:const TextStyle(color:Colors.grey)),const SizedBox(height:14),
    Text('₹'+product.price.toString(),style:const TextStyle(fontSize:24,fontWeight:FontWeight.w800)),const SizedBox(height:14),
    Text(product.description.isEmpty?'No description available.':product.description),const SizedBox(height:22),
    FilledButton.icon(onPressed:product.stock>0?onAdd:null,icon:const Icon(Icons.shopping_cart),label:Text(product.stock>0?'Add to cart':'Unavailable')),
  ]));
}

class CartScreen extends StatefulWidget{
  final Map<String,CartItem> cart;final List<Map<String,dynamic>> addresses;final void Function(String,int) onQty;final Future<void> Function(String,String,String,String) onPlace;
  const CartScreen({super.key,required this.cart,required this.addresses,required this.onQty,required this.onPlace});
  State<CartScreen> createState()=>_CartScreenState();
}
class _CartScreenState extends State<CartScreen>{
  final n=TextEditingController(),p=TextEditingController(),a=TextEditingController(),note=TextEditingController();bool placing=false,locating=false;
  @override void dispose(){n.dispose();p.dispose();a.dispose();note.dispose();super.dispose();}
  void use(Map<String,dynamic> x){n.text=(x['name']??'').toString();p.text=(x['phone']??'').toString();a.text=(x['address']??'').toString();setState((){});}
  Future<void> useCurrentLocation() async {
    setState(()=>locating=true);
    try{
      if(!await Geolocator.isLocationServiceEnabled()){
        msg('Please turn on Location/GPS and try again.');
        return;
      }
      var permission=await Geolocator.checkPermission();
      if(permission==LocationPermission.denied){
        permission=await Geolocator.requestPermission();
      }
      if(permission==LocationPermission.denied||permission==LocationPermission.deniedForever){
        msg('Location permission was not granted. Please enter your address manually.');
        return;
      }
      final pos=await Geolocator.getCurrentPosition(
        locationSettings:const LocationSettings(accuracy:LocationAccuracy.high),
      ).timeout(const Duration(seconds:10));
      try{
        final marks=await placemarkFromCoordinates(pos.latitude,pos.longitude);
        if(marks.isNotEmpty){
          final x=marks.first;
          final parts=[
            x.street,
            x.subLocality,
            x.thoroughfare,
          ].whereType<String>()
           .where((v)=>v.trim().isNotEmpty)
           .map((v)=>v.trim())
           .toList();
          if(parts.isEmpty){
            final fallback=[
              x.locality,
              x.subAdministrativeArea,
              x.administrativeArea,
              x.postalCode,
            ].whereType<String>()
             .where((v)=>v.trim().isNotEmpty)
             .map((v)=>v.trim())
             .toList();
            parts.addAll(fallback);
          }
          a.text=parts.toSet().join(', ');
        }
      }catch(_){
        // Geocoding is isolated so a geocoder failure never reaches the
        // general location catch block.
      }
      if(a.text.trim().isEmpty){
        a.text='Latitude: '+pos.latitude.toString()+
            ', Longitude: '+pos.longitude.toString();
      }
      msg('Current location added. Please add your house number or landmark if needed.');
    }catch(e){
      if(e is TimeoutException){
        msg('Location request timed out after 10 seconds. GPS may be slow; please try again or enter the address manually.');
      }else{
        msg('Could not get your current location: '+e.toString());
      }
    }finally{
      if(mounted)setState(()=>locating=false);
    }
  }
  void msg(String text){if(!mounted)return;ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));}
  Widget build(BuildContext c){
    final sub=widget.cart.values.fold<num>(0,(s,x)=>s+x.product.price*x.qty);final fee=sub>=499?0:30;final grand=sub+fee;
    return Scaffold(appBar:AppBar(title:const Text('Cart & Checkout')),body:ListView(padding:const EdgeInsets.all(16),children:[
      ...widget.cart.values.map((x)=>Card(child:ListTile(leading:CircleAvatar(child:Text(x.product.icon)),title:Text(x.product.name),subtitle:Text('₹'+x.product.price.toString()+' × '+x.qty.toString()),trailing:Wrap(children:[
        IconButton(onPressed:()=>widget.onQty(x.product.id,-1),icon:const Icon(Icons.remove)),Text(x.qty.toString()),IconButton(onPressed:()=>widget.onQty(x.product.id,1),icon:const Icon(Icons.add))])))),
      const Divider(height:25),const Text('Delivery details',style:TextStyle(fontSize:20,fontWeight:FontWeight.w800)),const SizedBox(height:10),
      if(widget.addresses.isNotEmpty) ...[const Text('Saved addresses'),...widget.addresses.map((x)=>Card(child:ListTile(onTap:()=>use(x),leading:const Icon(Icons.location_on_outlined),title:Text((x['name']??'').toString()),subtitle:Text((x['address']??'').toString()),trailing:const Icon(Icons.arrow_forward_ios,size:15))))],
      TextField(controller:n,decoration:const InputDecoration(labelText:'Full name')),const SizedBox(height:9),
      TextField(controller:p,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'10-digit phone number')),const SizedBox(height:9),
      TextField(controller:a,maxLines:3,decoration:const InputDecoration(labelText:'Delivery address')),
      const SizedBox(height:6),
      OutlinedButton.icon(onPressed:locating?null:useCurrentLocation,icon:locating?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.my_location),label:Text(locating?'Getting location…':'Use current location')),
      const SizedBox(height:9),
      TextField(controller:note,maxLines:2,decoration:const InputDecoration(labelText:'Delivery note (optional)')),const SizedBox(height:14),
      Card(child:Padding(padding:const EdgeInsets.all(15),child:Column(children:[Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('Subtotal'),Text('₹'+sub.toStringAsFixed(0))]),Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('Delivery'),Text(fee==0?'FREE':'₹'+fee.toString())]),const Divider(),Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('Total',style:TextStyle(fontWeight:FontWeight.w900)),Text('₹'+grand.toStringAsFixed(0),style:const TextStyle(fontWeight:FontWeight.w900))]),const SizedBox(height:7),const Align(alignment:Alignment.centerLeft,child:Text('Payment: Cash on Delivery (COD)',style:TextStyle(fontWeight:FontWeight.w700)))]))),
      const SizedBox(height:12),FilledButton(onPressed:placing?null:()async{setState(()=>placing=true);await widget.onPlace(n.text,p.text,a.text,note.text);if(mounted)setState(()=>placing=false);},child:Text(placing?'Placing order…':'Place COD Order'))
    ]));
  }
}

class OrdersPage extends StatelessWidget{
  final User? user;final Future<void> Function(String) onCancel;
  const OrdersPage({super.key,required this.user,required this.onCancel});
  Widget build(BuildContext c){
    if(user==null)return const InfoCard(title:'Your orders',detail:'Sign in to place and track your ALLways orders.');
    return StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:FirebaseFirestore.instance.collection('orders').where('customerId',isEqualTo:user!.uid).snapshots(),builder:(c,s){
      if(s.hasError)return const InfoCard(title:'Orders unavailable',detail:'Please check your connection.');
      if(!s.hasData)return const Center(child:CircularProgressIndicator());
      final docs=[...s.data!.docs]..sort((a,b)=>((b.data()['createdAt']??0)as num).compareTo(((a.data()['createdAt']??0)as num)));
      return ListView(padding:const EdgeInsets.all(16),children:[
        const Text('Your Orders',style:TextStyle(fontSize:28,fontWeight:FontWeight.w900)),const SizedBox(height:12),
        if(docs.isEmpty)const InfoCard(title:'No orders yet',detail:'Your placed orders will appear here.'),
        ...docs.map((d){final o=d.data();final status=(o['status']??'New Order').toString();final canCancel=status=='New Order'||status=='Confirmed';final items=(o['items'] as List? ?? []).map((x)=>x['name'].toString()+' × '+x['qty'].toString()).join(', ');
          return Card(child:ExpansionTile(title:Text('#'+(o['id']??d.id).toString(),style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text(status+' • ₹'+(o['total']??0).toString()),children:[
            Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              StatusView(status:status),
              if((o['eta']??o['estimatedDelivery']??'').toString().isNotEmpty)Card(margin:const EdgeInsets.only(top:10,bottom:8),child:ListTile(leading:const Icon(Icons.schedule),title:const Text('Estimated delivery',style:TextStyle(fontWeight:FontWeight.w800)),subtitle:Text((o['eta']??o['estimatedDelivery']).toString(),style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900)))),
              if((o['customerMessage']??o['statusNote']??'').toString().isNotEmpty)Card(margin:const EdgeInsets.only(bottom:10),child:ListTile(leading:const Icon(Icons.message_outlined),title:const Text('Message from ALLways',style:TextStyle(fontWeight:FontWeight.w800)),subtitle:Text((o['customerMessage']??o['statusNote']).toString(),style:const TextStyle(fontSize:16,fontWeight:FontWeight.w700)))),
              const SizedBox(height:3),Text(items),Text('Address: '+(o['address']??'').toString()),
              if((o['cancellationReason']??'').toString().isNotEmpty)Padding(padding:const EdgeInsets.only(top:8),child:Text('Cancellation reason: '+o['cancellationReason'].toString())),
              if(canCancel)Padding(padding:const EdgeInsets.only(top:12),child:OutlinedButton.icon(onPressed:()=>_confirmCancel(c,o['id']?.toString()??d.id,onCancel),icon:const Icon(Icons.cancel_outlined),label:const Text('Cancel order')))
            ]))]));})
      ]);
    });
  }
  Future<void> _confirmCancel(BuildContext c,String id,Future<void> Function(String) cancel) async {
    final reason=TextEditingController();
    final ok=await showDialog<bool>(context:c,builder:(_)=>AlertDialog(title:const Text('Cancel order?'),content:TextField(controller:reason,maxLines:3,decoration:const InputDecoration(labelText:'Reason for cancellation')),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Keep order')),FilledButton(onPressed:()=>Navigator.pop(c,reason.text.trim().isNotEmpty),child:const Text('Cancel order'))]))??false;
    final clean=reason.text.trim();reason.dispose();if(ok)await cancel(id+'||'+clean);
  }
}
class StatusView extends StatelessWidget{final String status;const StatusView({super.key,required this.status});Widget build(BuildContext c){
  const s=['New Order','Confirmed','Preparing','Out for delivery','Delivered'];final i=s.indexOf(status)<0?0:s.indexOf(status);
  return Column(children:[for(int x=0;x<s.length;x++)ListTile(dense:true,contentPadding:EdgeInsets.zero,leading:Icon(x<=i?Icons.check_circle:Icons.radio_button_unchecked,color:x<=i?Colors.green:Colors.grey),title:Text(s[x]))]);
}}


class ProfilePage extends StatefulWidget{
  final User? user; final List<Map<String,dynamic>> addresses; final VoidCallback onLogin;
  final Future<void> Function() onReload; final Future<void> Function(String) onDelete; final Future<void> Function(String) onCancel;
  const ProfilePage({super.key,required this.user,required this.addresses,required this.onLogin,required this.onReload,required this.onDelete,required this.onCancel});
  @override State<ProfilePage> createState()=>_ProfilePageState();
}
class _ProfilePageState extends State<ProfilePage>{
  Future<void> _checkForUpdate(BuildContext c) async {
    try{
      final r=await http.get(Uri.parse(updateManifestUrl)).timeout(const Duration(seconds:8));
      if(!c.mounted)return;
      if(r.statusCode==200){
        final d=jsonDecode(r.body);
        if(d is Map&&(d['version']??'').toString().isNotEmpty){
          ScaffoldMessenger.of(c).showSnackBar(SnackBar(content:Text('Latest version: '+d['version'].toString())));
          return;
        }
      }
      ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content:Text('Could not check for updates.')));
    }catch(_){
      if(c.mounted)ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content:Text('Could not check for updates.')));
    }
  }

  Future<void> _chooseAppearance(BuildContext c) async {
    await showDialog<void>(
      context:c,
      builder:(dialogContext)=>ValueListenableBuilder<ThemeMode>(
        valueListenable:themeNotifier,
        builder:(context,mode,_)=>AlertDialog(
          title:const Text('Appearance'),
          content:Column(mainAxisSize:MainAxisSize.min,children:[
            RadioListTile<ThemeMode>(title:const Text('Light'),value:ThemeMode.light,groupValue:mode,onChanged:(v)async{if(v==null)return;themeNotifier.value=v;final p=await SharedPreferences.getInstance();await p.setString('allways_theme_mode','light');if(dialogContext.mounted)Navigator.pop(dialogContext);}),
            RadioListTile<ThemeMode>(title:const Text('Dark'),value:ThemeMode.dark,groupValue:mode,onChanged:(v)async{if(v==null)return;themeNotifier.value=v;final p=await SharedPreferences.getInstance();await p.setString('allways_theme_mode','dark');if(dialogContext.mounted)Navigator.pop(dialogContext);}),
            RadioListTile<ThemeMode>(title:const Text('System'),value:ThemeMode.system,groupValue:mode,onChanged:(v)async{if(v==null)return;themeNotifier.value=v;final p=await SharedPreferences.getInstance();await p.setString('allways_theme_mode','system');if(dialogContext.mounted)Navigator.pop(dialogContext);}),
          ]),
        ),
      ),
    );
  }

  Widget _menuCard(BuildContext c,{required IconData icon,required String title,required String subtitle,required VoidCallback onTap,bool danger=false}){
    final scheme=Theme.of(c).colorScheme;
    final accent=danger?scheme.error:scheme.primary;
    return Card(
      margin:const EdgeInsets.symmetric(horizontal:16,vertical:6),
      elevation:0,
      color:scheme.surface,
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)),
      child:InkWell(
        onTap:onTap,
        borderRadius:BorderRadius.circular(16),
        child:Padding(
          padding:const EdgeInsets.symmetric(horizontal:14,vertical:14),
          child:Row(children:[
            Container(
              width:48,height:48,
              decoration:BoxDecoration(color:danger?scheme.errorContainer:scheme.primaryContainer,borderRadius:BorderRadius.circular(14)),
              child:Icon(icon,color:danger?scheme.onErrorContainer:scheme.onPrimaryContainer),
            ),
            const SizedBox(width:14),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(title,style:TextStyle(fontSize:16,fontWeight:FontWeight.w800,color:danger?scheme.error:null)),
              const SizedBox(height:3),
              Text(subtitle,style:TextStyle(color:scheme.onSurfaceVariant,fontSize:13)),
            ])),
            Icon(Icons.chevron_right,color:accent),
          ]),
        ),
      ),
    );
  }

  Future<void> _openNotifications(BuildContext c) async {
    await showModalBottomSheet<void>(context:c,isScrollControlled:true,showDragHandle:true,builder:(_)=>const NotificationsPage());
  }

  @override Widget build(BuildContext c){
    final u=widget.user;
    if(u==null)return Center(child:FilledButton(onPressed:widget.onLogin,child:const Text('Sign in / Sign up')));
    return ListView(
      padding:const EdgeInsets.only(top:12,bottom:24),
      children:[
        const Padding(padding:EdgeInsets.fromLTRB(16,0,16,6),child:Text('Profile',style:TextStyle(fontSize:28,fontWeight:FontWeight.w900))),
        Card(
          margin:const EdgeInsets.symmetric(horizontal:16,vertical:6),
          elevation:0,
          shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)),
          child:Padding(padding:const EdgeInsets.all(16),child:Row(children:[
            CircleAvatar(radius:30,child:Text((u.displayName??'A').trim().isEmpty?'A':(u.displayName??'A').trim()[0].toUpperCase())),
            const SizedBox(width:14),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(u.displayName??'ALLways customer',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
              const SizedBox(height:3),
              Text(u.email??'',style:TextStyle(color:Theme.of(c).colorScheme.onSurfaceVariant)),
            ])),
          ])),
        ),
        FutureBuilder<DocumentSnapshot<Map<String,dynamic>>>(
          future:FirebaseFirestore.instance.collection('customers').doc(u.uid).get(),
          builder:(context,snapshot){
            final role=(snapshot.data?.data()?['role']??'customer').toString();
            return Column(children:[
              if(role=='admin')Card(
                margin:const EdgeInsets.symmetric(horizontal:16,vertical:6),
                color:Theme.of(c).colorScheme.primaryContainer,
                shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)),
                child:ListTile(
                  leading:Icon(Icons.admin_panel_settings_outlined,color:Theme.of(c).colorScheme.onPrimaryContainer),
                  title:const Text('Admin Dashboard',style:TextStyle(fontWeight:FontWeight.w800)),
                  subtitle:const Text('Manage orders, roles and banners'),
                  trailing:const Icon(Icons.chevron_right),
                  onTap:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const AdminScreen())),
                ),
              ),
              if(role=='seller')SellerDashboard(user:u),
              if(role=='carrier')CarrierDashboard(user:u),
            ]);
          },
        ),
        _menuCard(c,icon:Icons.receipt_long_outlined,title:'Orders',subtitle:'View and track your ALLways orders',onTap:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>OrdersPage(user:u,onCancel:widget.onCancel)))),
        _menuCard(c,icon:Icons.location_on_outlined,title:'Saved Addresses',subtitle:'Add, edit or manage your delivery addresses',onTap:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>SavedAddressesPage(userId:u.uid,addresses:widget.addresses,onReload:widget.onReload,onDelete:widget.onDelete)))),
        _menuCard(c,icon:Icons.favorite_border,title:'Wishlist',subtitle:'Your saved products and favourites',onTap:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const WishlistPage()))),
        _menuCard(c,icon:Icons.local_shipping_outlined,title:'ALLways Carrier',subtitle:'Become a Seller or Delivery Partner',onTap:()=>_openCarrier(c,u)),
        _menuCard(c,icon:Icons.notifications_outlined,title:'Notifications',subtitle:'Alerts, order updates and push settings',onTap:()=>_openNotifications(c)),
        _menuCard(c,icon:Icons.brightness_6_outlined,title:'Appearance',subtitle:'Light, Dark or System theme',onTap:()=>_chooseAppearance(c)),
        _menuCard(c,icon:Icons.share_outlined,title:'Share ALLways',subtitle:'Share ALLways with friends and family',onTap:()=>SharePlus.instance.share(ShareParams(text:'Try ALLways — Closer to You, Always. Download ALLways 1.4.7: '+shareApkUrl))),
        _menuCard(c,icon:Icons.system_update_outlined,title:'Check for Updates',subtitle:'Check for the latest ALLways version',onTap:()=>_checkForUpdate(c)),
        _menuCard(c,icon:Icons.privacy_tip_outlined,title:'Privacy Policy',subtitle:'How ALLways handles your information',onTap:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const PrivacyPolicyPage()))),
        _menuCard(c,icon:Icons.logout_outlined,title:'Log Out',subtitle:'Sign out of your ALLways account',danger:true,onTap:()=>FirebaseAuth.instance.signOut()),
        const SizedBox(height:12),
        const Text('ALLways • Closer to You, Always',textAlign:TextAlign.center,style:TextStyle(color:Colors.grey)),
      ],
    );
  }

  void _openCarrier(BuildContext c,User u){
    showModalBottomSheet<void>(
      context:c,
      builder:(sheet)=>SafeArea(child:Wrap(children:[
        ListTile(
          leading:const Icon(Icons.storefront_outlined),
          title:const Text('Become a Seller'),
          subtitle:const Text('Create your ALLways seller profile'),
          onTap:(){Navigator.pop(sheet);showDialog(context:c,builder:(_)=>CarrierApplicationDialog(user:u,type:'seller'));},
        ),
        ListTile(
          leading:const Icon(Icons.delivery_dining_outlined),
          title:const Text('Become a Delivery Partner'),
          subtitle:const Text('Apply to deliver ALLways orders'),
          onTap:(){Navigator.pop(sheet);showDialog(context:c,builder:(_)=>CarrierApplicationDialog(user:u,type:'delivery_partner'));},
        ),
      ])),
    );
  }
}

class NotificationsPage extends StatefulWidget{
  const NotificationsPage({super.key});
  @override State<NotificationsPage> createState()=>_NotificationsPageState();
}
class _NotificationsPageState extends State<NotificationsPage>{
  bool enabled=true;
  bool loading=true;
  List<Map<String,dynamic>> notifications=[];

  @override void initState(){super.initState();_load();}

  Future<void> _load() async {
    try{
      final prefs=await SharedPreferences.getInstance();
      enabled=prefs.getBool('allways_notifications_enabled')??true;
      final raw=prefs.getStringList('allways_notifications')??<String>[];
      notifications=raw.map((x){
        final d=jsonDecode(x);
        return d is Map?Map<String,dynamic>.from(d):<String,dynamic>{};
      }).where((x)=>x.isNotEmpty).toList();
    }catch(_){}
    if(mounted)setState(()=>loading=false);
  }

  Future<void> _toggle(bool value) async {
    setState(()=>enabled=value);
    try{
      final prefs=await SharedPreferences.getInstance();
      await prefs.setBool('allways_notifications_enabled',value);
      if(value){
        final status=await FirebaseMessaging.instance.requestPermission(alert:true,badge:true,sound:true);
        if(status.authorizationStatus==AuthorizationStatus.denied){
          if(mounted)setState(()=>enabled=false);
          await prefs.setBool('allways_notifications_enabled',false);
          return;
        }
        final token=await FirebaseMessaging.instance.getToken();
        final u=FirebaseAuth.instance.currentUser;
        if(token!=null&&u!=null){
          await FirebaseFirestore.instance.collection('fcmTokens').doc(u.uid).set({
            'uid':u.uid,'email':u.email??'','token':token,'updatedAt':FieldValue.serverTimestamp()
          },SetOptions(merge:true));
          await prefs.setString('allways_fcm_token',token);
        }
      }else{
        try{await FirebaseMessaging.instance.deleteToken();}catch(_){}
        final u=FirebaseAuth.instance.currentUser;
        if(u!=null){
          try{await FirebaseFirestore.instance.collection('fcmTokens').doc(u.uid).delete();}catch(_){}
        }
        await prefs.remove('allways_fcm_token');
      }
    }catch(_){
      if(mounted)setState(()=>enabled=!value);
    }
    if(mounted)setState((){});
  }

  String _time(dynamic value){
    final ms=value is num?value.toInt():int.tryParse(value?.toString()??'')??0;
    if(ms<=0)return'';
    final d=DateTime.fromMillisecondsSinceEpoch(ms);
    final diff=DateTime.now().difference(d);
    if(diff.inMinutes<1)return'Just now';
    if(diff.inHours<1)return diff.inMinutes.toString()+' min ago';
    if(diff.inDays<1)return diff.inHours.toString()+' hr ago';
    return d.day.toString().padLeft(2,'0')+'/'+d.month.toString().padLeft(2,'0')+'/'+d.year.toString();
  }

  @override Widget build(BuildContext context){
    return SafeArea(child:Column(children:[
      Padding(
        padding:const EdgeInsets.fromLTRB(20,4,20,8),
        child:Row(children:[
          const Icon(Icons.notifications_outlined),
          const SizedBox(width:10),
          const Expanded(child:Text('Notifications',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900))),
          IconButton(onPressed:()=>Navigator.pop(context),icon:const Icon(Icons.close)),
        ]),
      ),
      Card(
        margin:const EdgeInsets.fromLTRB(16,0,16,10),
        child:SwitchListTile(
          title:const Text('Enable Notifications',style:TextStyle(fontWeight:FontWeight.w800)),
          subtitle:const Text('Receive order, delivery and ALLways alerts'),
          value:enabled,
          onChanged:loading?null:_toggle,
        ),
      ),
      const Divider(height:1),
      Expanded(
        child:loading?const Center(child:CircularProgressIndicator()):notifications.isEmpty
          ?const Center(child:Padding(padding:EdgeInsets.all(30),child:Column(mainAxisSize:MainAxisSize.min,children:[
              Icon(Icons.notifications_none,size:64),
              SizedBox(height:12),
              Text('No notifications yet.',style:TextStyle(fontSize:18,fontWeight:FontWeight.w700)),
            ])))
          :ListView.separated(
            padding:const EdgeInsets.fromLTRB(16,12,16,24),
            itemCount:notifications.length,
            separatorBuilder:(_,__)=>const SizedBox(height:8),
            itemBuilder:(context,index){
              final n=notifications[index];
              final title=(n['title']??'ALLways').toString();
              final body=(n['body']??'').toString();
              final time=_time(n['timestamp']);
              return Card(margin:EdgeInsets.zero,child:ListTile(
                leading:const CircleAvatar(child:Icon(Icons.notifications_outlined)),
                title:Text(title,style:const TextStyle(fontWeight:FontWeight.w800)),
                subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text(body),
                  if(time.isNotEmpty)Padding(padding:const EdgeInsets.only(top:4),child:Text(time,style:const TextStyle(fontSize:12,color:Colors.grey))),
                ]),
              ));
            },
          ),
      ),
    ]));
  }
}



class CarrierOnboardingTile extends StatelessWidget {
  final User user;
  const CarrierOnboardingTile({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.local_shipping_outlined),
        title: const Text('ALLways Carrier', style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: const Text('Become a seller or delivery partner'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          showModalBottomSheet<void>(
            context: context,
            builder: (sheet) => SafeArea(
              child: Wrap(
                children: [
                  ListTile(
                    leading: const Icon(Icons.storefront_outlined),
                    title: const Text('Become a Seller'),
                    onTap: () {
                      Navigator.pop(sheet);
                      showDialog(
                        context: context,
                        builder: (_) => CarrierApplicationDialog(user: user, type: 'seller'),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delivery_dining_outlined),
                    title: const Text('Become a Delivery Partner'),
                    onTap: () {
                      Navigator.pop(sheet);
                      showDialog(
                        context: context,
                        builder: (_) => CarrierApplicationDialog(user: user, type: 'delivery_partner'),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class CarrierApplicationDialog extends StatefulWidget {
  final User user;
  final String type;
  const CarrierApplicationDialog({super.key, required this.user, required this.type});

  @override
  State<CarrierApplicationDialog> createState() => _CarrierApplicationDialogState();
}

class _CarrierApplicationDialogState extends State<CarrierApplicationDialog> {
  final fullName = TextEditingController();
  final shopName = TextEditingController();
  final dob = TextEditingController();
  XFile? photo;
  bool busy = false;

  bool get seller => widget.type == 'seller';

  @override
  void dispose() {
    fullName.dispose();
    shopName.dispose();
    dob.dispose();
    super.dispose();
  }

  Future<void> pickPhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 82);
    if (x != null && mounted) setState(() => photo = x);
  }

  Future<void> submit() async {
    if (fullName.text.trim().isEmpty || photo == null || (seller && shopName.text.trim().isEmpty) || (!seller && dob.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(seller ? 'Full name, shop name and photo are required.' : 'Full name, DOB and bike/number plate photo are required.')),
      );
      return;
    }
    setState(() => busy = true);
    try {
      final path = 'onboarding/' + widget.user.uid + '/' + widget.type + '_' + DateTime.now().millisecondsSinceEpoch.toString() + '.jpg';
      final ref = allwaysStorage.ref().child(path);
      await ref.putFile(File(photo!.path), SettableMetadata(contentType:'image/jpeg'));
      final url = await ref.getDownloadURL();

      final data = <String, dynamic>{
        'uid': widget.user.uid,
        'email': widget.user.email ?? '',
        'type': widget.type,
        'fullName': fullName.text.trim(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      };
      if (seller) {
        data['shopName'] = shopName.text.trim();
        data['photoUrl'] = url;
      } else {
        data['dob'] = dob.text.trim();
        data['bikePhotoUrl'] = url;
      }

      await FirebaseFirestore.instance.collection('onboarding_requests').add(data);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(seller ? 'Seller request submitted.' : 'Delivery partner request submitted.')),
      );
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() => busy = false);
        final detail=e.code=='object-not-found'
          ? 'Firebase Storage bucket/object was not found. Verify the ALLways Storage bucket exists and matches gs://allways-web.firebasestorage.app.'
          : 'Firebase error ['+e.code+']: '+(e.message??'Unknown Firebase error');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not submit request: '+detail)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not submit request: ' + e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(seller ? 'Become a Seller' : 'Become a Delivery Partner'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: fullName, decoration: const InputDecoration(labelText: 'Full name')),
            if (seller) ...[
              const SizedBox(height: 10),
              TextField(controller: shopName, decoration: const InputDecoration(labelText: 'Shop name')),
            ],
            if (!seller) ...[
              const SizedBox(height: 10),
              TextField(controller: dob, decoration: const InputDecoration(labelText: 'Date of birth (DD/MM/YYYY)')),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: busy ? null : pickPhoto,
              icon: const Icon(Icons.photo_camera),
              label: Text(photo == null ? (seller ? 'Upload shop/photo' : 'Upload bike/number plate photo') : 'Photo selected'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Submitting…' : 'Submit')),
      ],
    );
  }
}

class SellerDashboard extends StatefulWidget {
  final User user;
  const SellerDashboard({super.key, required this.user});

  @override
  State<SellerDashboard> createState() => _SellerDashboardState();
}

class _SellerDashboardState extends State<SellerDashboard> {
  final description = TextEditingController();
  final offers = TextEditingController();
  List<Map<String, dynamic>> items = [];
  bool saving = false;

  @override
  void initState() {
    super.initState();
    loadSeller();
  }

  @override
  void dispose() {
    description.dispose();
    offers.dispose();
    super.dispose();
  }

  Future<void> loadSeller() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('sellers').doc(widget.user.uid).get();
      final data = snap.data() ?? {};
      description.text = (data['description'] ?? '').toString();
      offers.text = (data['dailyOffers'] ?? '').toString();
      final raw = data['items'];
      if (raw is List) {
        items = raw.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList();
        if (items.length > 10) items = items.take(10).toList();
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<String> uploadItemImage(XFile image) async {
    final path = 'sellers/' + widget.user.uid + '/item_' + DateTime.now().millisecondsSinceEpoch.toString() + '.jpg';
    final ref = allwaysStorage.ref().child(path);
    await ref.putFile(File(image.path), SettableMetadata(contentType:'image/jpeg'));
    return ref.getDownloadURL();
  }

  Future<void> addItem() async {
    if (items.length >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You can list up to 10 items.')));
      return;
    }

    final name = TextEditingController();
    final price = TextEditingController();
    XFile? image;

    final added = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add seller item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Item name')),
              const SizedBox(height: 10),
              TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Price')),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 82);
                  if (x != null) setDialogState(() => image = x);
                },
                icon: const Icon(Icons.image_outlined),
                label: Text(image == null ? 'Choose image' : 'Image selected'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final parsed = num.tryParse(price.text.trim());
                if (name.text.trim().isEmpty || parsed == null || parsed < 0 || image == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name, price and image are required.')));
                  return;
                }
                try {
                  final url = await uploadItemImage(image!);
                  if (!mounted) return;
                  setState(() => items.add({'name': name.text.trim(), 'price': parsed, 'imageUrl': url}));
                  Navigator.pop(dialog, true);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Image upload failed: ' + e.toString())));
                  }
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    price.dispose();
    if (added == true && mounted) setState(() {});
  }

  Future<void> saveSeller() async {
    setState(() => saving = true);
    try {
      await FirebaseFirestore.instance.collection('sellers').doc(widget.user.uid).set({
        'uid': widget.user.uid,
        'name': widget.user.displayName ?? '',
        'description': description.text.trim(),
        'dailyOffers': offers.text.trim(),
        'items': items,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seller dashboard saved.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save seller dashboard: ' + e.toString())));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.storefront),
        title: const Text('Seller Dashboard', style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: const Text('Manage your shop, offers and up to 10 items'),
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                TextField(controller: description, maxLines: 3, decoration: const InputDecoration(labelText: 'Shop description')),
                const SizedBox(height: 10),
                TextField(controller: offers, maxLines: 2, decoration: const InputDecoration(labelText: 'Daily offers')),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: Text('Items (' + items.length.toString() + '/10)', style: const TextStyle(fontWeight: FontWeight.w800))),
                ...items.asMap().entries.map(
                  (entry) => Card(
                    child: ListTile(
                      leading: (entry.value['imageUrl'] ?? '').toString().isEmpty
                          ? const Icon(Icons.image)
                          : Image.network(entry.value['imageUrl'].toString(), width: 48, height: 48, fit: BoxFit.cover),
                      title: Text((entry.value['name'] ?? '').toString()),
                      subtitle: Text('₹' + (entry.value['price'] ?? 0).toString()),
                      trailing: IconButton(onPressed: () => setState(() => items.removeAt(entry.key)), icon: const Icon(Icons.delete_outline)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(onPressed: addItem, icon: const Icon(Icons.add), label: const Text('Add item')),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: FilledButton(onPressed: saving ? null : saveSeller, child: Text(saving ? 'Saving…' : 'Save seller profile'))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CarrierDashboard extends StatelessWidget {
  final User user;
  const CarrierDashboard({super.key, required this.user});

  Future<void> openMaps(BuildContext context, String address) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=' + Uri.encodeComponent(address));
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open Google Maps.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.delivery_dining),
        title: const Text('Carrier Dashboard', style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: const Text('Active assigned orders'),
        children: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('orders').where('carrierUid', isEqualTo: user.uid).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Padding(padding: const EdgeInsets.all(14), child: Text('Could not load assigned orders: ' + snapshot.error.toString()));
              if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator());

              final docs = snapshot.data!.docs.where((d) {
                final status = (d.data()['status'] ?? '').toString();
                return status != 'Delivered' && status != 'Cancelled';
              }).toList();

              if (docs.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('No active assigned orders.'));

              return Column(
                children: docs.map((d) {
                  final order = d.data();
                  final rawItems = order['items'];
                  final itemText = rawItems is List
                      ? rawItems.map((x) => x is Map ? (x['name'].toString() + ' × ' + x['qty'].toString()) : x.toString()).join(', ')
                      : '';
                  return Card(
                    child: ListTile(
                      title: Text('#' + (order['id'] ?? d.id).toString()),
                      subtitle: Text((order['phone'] ?? '').toString() + '\n' + itemText),
                      isThreeLine: true,
                      trailing: IconButton(
                        onPressed: () => openMaps(context, (order['address'] ?? '').toString()),
                        icon: const Icon(Icons.map_outlined),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: const [
          Text('ALLways Privacy Policy', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
          SizedBox(height: 12),
          Text('ALLways uses account information to authenticate customers, process orders, provide delivery updates and support seller or delivery-partner onboarding. Delivery addresses and order details are used to fulfill orders. Wishlist and saved-address data are stored under your customer account. Photos submitted for onboarding or seller listings are stored in Firebase Storage.'),
          SizedBox(height: 14),
          Text('Information sharing', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          Text('ALLways shares order information with people who need it to fulfill an order, such as authorized delivery partners and administrators. Local sellers receive only the information needed for a customer to contact them.'),
          SizedBox(height: 14),
          Text('Your choices', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          Text('You can manage saved addresses and wishlist items in the app, and you can request account-related changes through ALLways support.'),
        ],
      ),
    );
  }
}

class SavedAddressesPage extends StatefulWidget {
  final String userId;
  final List<Map<String, dynamic>> addresses;
  final Future<void> Function() onReload;
  final Future<void> Function(String) onDelete;
  const SavedAddressesPage({super.key, required this.userId, required this.addresses, required this.onReload, required this.onDelete});

  @override
  State<SavedAddressesPage> createState() => _SavedAddressesPageState();
}

class _SavedAddressesPageState extends State<SavedAddressesPage> {
  bool saving=false;

  Future<void> _editAddress(Map<String,dynamic> item) async {
    final name=TextEditingController(text:(item['name']??'').toString());
    final phone=TextEditingController(text:(item['phone']??'').toString());
    final address=TextEditingController(text:(item['address']??'').toString());
    final formKey=GlobalKey<FormState>();
    final id=(item['id']??'').toString();
    if(widget.userId.isEmpty || id.isEmpty){
      name.dispose();phone.dispose();address.dispose();
      return;
    }
    try{
      final save=await showDialog<bool>(
        context:context,
        builder:(dialogContext)=>AlertDialog(
          title:const Text('Edit address'),
          content:Form(
            key:formKey,
            child:SingleChildScrollView(
              child:Column(
                mainAxisSize:MainAxisSize.min,
                children:[
                  TextFormField(controller:name,decoration:const InputDecoration(labelText:'Name'),validator:(v)=>v==null||v.trim().isEmpty?'Enter a name':null),
                  const SizedBox(height:10),
                  TextFormField(controller:phone,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'Phone'),validator:(v)=>v==null||!RegExp(r'^\d{10}$').hasMatch(v.replaceAll(RegExp(r'\D'),'').trim())?'Enter a valid 10-digit phone':null),
                  const SizedBox(height:10),
                  TextFormField(controller:address,maxLines:3,decoration:const InputDecoration(labelText:'Address'),validator:(v)=>v==null||v.trim().isEmpty?'Enter an address':null),
                ],
              ),
            ),
          ),
          actions:[
            TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),
            FilledButton(onPressed:(){if(formKey.currentState?.validate()??false)Navigator.pop(dialogContext,true);},child:const Text('Save changes')),
          ],
        ),
      );
      if(save!=true)return;
      setState(()=>saving=true);
      final cleanPhone=phone.text.replaceAll(RegExp(r'\D'),'').trim();
      await FirebaseFirestore.instance.collection('customers').doc(widget.userId).collection('addresses').doc(id).update({
        'name':name.text.trim(),
        'phone':cleanPhone,
        'address':address.text.trim(),
      });
      await widget.onReload();
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Address updated.')));
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not update address: '+e.toString())));
    }finally{
      name.dispose();phone.dispose();address.dispose();
      if(mounted)setState(()=>saving=false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:AppBar(title:const Text('Saved addresses')),
      body:RefreshIndicator(
        onRefresh:widget.onReload,
        child:ListView(
          padding:const EdgeInsets.all(16),
          children:[
            if(widget.addresses.isEmpty)
              const InfoCard(title:'No saved addresses',detail:'An address is saved after a successful order.')
            else
              ...widget.addresses.map((x)=>Card(
                child:ListTile(
                  title:Text((x['name']??'').toString()),
                  subtitle:Text((x['address']??'').toString()),
                  trailing:Row(
                    mainAxisSize:MainAxisSize.min,
                    children:[
                      IconButton(tooltip:'Edit',onPressed:saving?null:()=>_editAddress(x),icon:const Icon(Icons.edit)),
                      IconButton(tooltip:'Delete',onPressed:saving?null:()=>widget.onDelete(x['id'].toString()),icon:const Icon(Icons.delete_outline)),
                    ],
                  ),
                ),
              )),
          ],
        ),
      ),
    );
  }
}

class LocalSellersPage extends StatelessWidget {
  const LocalSellersPage({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('localSellers').where('active', isEqualTo: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const InfoCard(title: 'Local sellers unavailable', detail: 'Please check your connection and try again.');
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final sellers = snapshot.data!.docs;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            const Text('Local sellers', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('Discover sellers near you and contact them directly.', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            if (sellers.isEmpty)
              const InfoCard(title: 'No local sellers yet', detail: 'Local sellers will appear here when they are onboarded.')
            else
              ...sellers.map(
                (d) {
                  final x = d.data();
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.storefront)),
                      title: Text((x['name'] ?? x['businessName'] ?? 'Local seller').toString()),
                      subtitle: Text((x['category'] ?? x['address'] ?? 'Local seller').toString()),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class WishlistPage extends StatefulWidget {
  const WishlistPage({super.key});
  @override State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> {
  bool loading = true;
  String? error;
  List<Product> items = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      if (mounted) setState(() => loading = false);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance.collection('customers').doc(u.uid).collection('wishlist').orderBy('addedAt', descending: true).get();
      final list = snap.docs.map((d) => Product.fromJson(d.data())).toList();
      if (mounted) setState(() { items = list; loading = false; error = null; });
    } catch (_) {
      if (mounted) setState(() { loading = false; error = 'Could not load wishlist.'; });
    }
  }

  Future<void> remove(Product product) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    try {
      await FirebaseFirestore.instance.collection('customers').doc(u.uid).collection('wishlist').doc(product.id).delete();
      if (mounted) setState(() => items.removeWhere((x) => x.id == product.id));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not remove item.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (error != null) {
      body = Center(child: Text(error!));
    } else if (items.isEmpty) {
      body = ListView(
        children: const [
          SizedBox(height: 80),
          Icon(Icons.favorite_border, size: 72),
          SizedBox(height: 12),
          Center(child: Text('Your wishlist is empty', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        ],
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: items.map(
          (p) => Card(
            child: ListTile(
              leading: CircleAvatar(child: Text(p.icon)),
              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('₹' + p.price.toString() + ' • ' + p.category),
              trailing: IconButton(onPressed: () => remove(p), icon: const Icon(Icons.favorite)),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ProductScreen(product: p, onAdd: () {}, liked: true, onWishlist: () => remove(p))),
              ),
            ),
          ),
        ).toList(),
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('Wishlist')), body: RefreshIndicator(onRefresh: load, child: body));
  }
}

class AdminRolesPanel extends StatelessWidget {
  const AdminRolesPanel({super.key});

  Future<void> onboard(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc, String role) async {
    final data = doc.data();
    final uid = (data['uid'] ?? '').toString();
    if (uid.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('customers').doc(uid).set({
        'uid': uid,
        'email': data['email'] ?? '',
        'displayName': data['fullName'] ?? '',
        'role': role,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (role == 'seller') {
        await FirebaseFirestore.instance.collection('sellers').doc(uid).set({
          'uid': uid,
          'name': data['fullName'] ?? '',
          'businessName': data['shopName'] ?? '',
          'photoUrl': data['photoUrl'] ?? '',
        }, SetOptions(merge: true));
      }

      await doc.reference.update({'status': 'approved', 'approvedRole': role, 'reviewedAt': FieldValue.serverTimestamp()});
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Onboarded as ' + role + '.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Onboard failed: ' + e.toString())));
    }
  }

  Future<void> reject(BuildContext context, String id) async {
    try {
      await FirebaseFirestore.instance.collection('onboarding_requests').doc(id).update({'status': 'rejected', 'reviewedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reject failed: ' + e.toString())));
    }
  }

  Future<void> remove(BuildContext context, String uid) async {
    try {
      await FirebaseFirestore.instance.collection('customers').doc(uid).set({'role': 'customer', 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Role removed.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Remove failed: ' + e.toString())));
    }
  }

  Widget roleTab(BuildContext context, String type, String role) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('onboarding_requests').where('type', isEqualTo: type).where('status', isEqualTo: 'pending').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Padding(padding: const EdgeInsets.all(12), child: Text('Could not load requests: ' + snapshot.error.toString()));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final requests = snapshot.data!.docs;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Text('Pending requests', style: TextStyle(fontWeight: FontWeight.w800)),
            if (requests.isEmpty) const ListTile(title: Text('No pending requests.')),
            ...requests.map(
              (d) {
                final x = d.data();
                return Card(
                  child: ListTile(
                    title: Text((x['fullName'] ?? 'Applicant').toString()),
                    subtitle: Text((x['shopName'] ?? x['dob'] ?? x['email'] ?? '').toString()),
                    trailing: Wrap(
                      children: [
                        TextButton(onPressed: () => onboard(context, d, role), child: const Text('Onboard')),
                        TextButton(onPressed: () => reject(context, d.id), child: const Text('Reject')),
                      ],
                    ),
                  ),
                );
              },
            ),
            const Divider(),
            const Text('Active roles', style: TextStyle(fontWeight: FontWeight.w800)),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('customers').where('role', isEqualTo: role).snapshots(),
              builder: (context, active) {
                if (active.hasError) return Text('Could not load active roles: ' + active.error.toString());
                if (!active.hasData) return const Center(child: CircularProgressIndicator());
                final users = active.data!.docs;
                if (users.isEmpty) return const ListTile(title: Text('No active users.'));
                return Column(
                  children: users.map(
                    (d) {
                      final x = d.data();
                      return ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text((x['displayName'] ?? x['email'] ?? d.id).toString()),
                        subtitle: Text((x['email'] ?? '').toString()),
                        trailing: TextButton(onPressed: () => remove(context, d.id), child: const Text('Remove')),
                      );
                    },
                  ).toList(),
                );
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.manage_accounts_outlined),
        title: const Text('Manage Roles', style: TextStyle(fontWeight: FontWeight.w800)),
        children: [
          DefaultTabController(
            length: 2,
            child: SizedBox(
              height: 420,
              child: Column(
                children: [
                  const TabBar(tabs: [Tab(text: 'Manage Sellers'), Tab(text: 'Manage Delivery Partners')]),
                  Expanded(child: TabBarView(children: [roleTab(context, 'seller', 'seller'), roleTab(context, 'delivery_partner', 'carrier')])),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final email = TextEditingController(text: adminEmail);
  final pass = TextEditingController();
  bool busy = false;
  bool loggedIn = false;
  String selectedOrderStatusFilter = 'pending';

  static const List<Map<String, String>> orderStatusFilters = [
    {'label': 'New', 'value': 'pending'},
    {'label': 'Confirmed', 'value': 'confirmed'},
    {'label': 'Preparing', 'value': 'preparing'},
    {'label': 'Assigned', 'value': 'assigned'},
    {'label': 'Out for delivery', 'value': 'out_for_delivery'},
    {'label': 'Delivered', 'value': 'delivered'},
    {'label': 'Cancelled', 'value': 'cancelled'},
  ];

  String normalizeOrderStatus(String raw) {
    final value = raw.trim().toLowerCase().replaceAll(' ', '_');
    switch (value) {
      case 'pending':
      case 'new':
      case 'new_order':
        return 'pending';
      case 'confirmed':
        return 'confirmed';
      case 'preparing':
        return 'preparing';
      case 'assigned':
        return 'assigned';
      case 'out_for_delivery':
        return 'out_for_delivery';
      case 'delivered':
        return 'delivered';
      case 'cancelled':
      case 'canceled':
        return 'cancelled';
      default:
        return value;
    }
  }

  @override
  void initState() {
    super.initState();
    final u = FirebaseAuth.instance.currentUser;
    loggedIn = u?.email?.toLowerCase() == adminEmail.toLowerCase();
  }

  @override
  void dispose() {
    email.dispose();
    pass.dispose();
    super.dispose();
  }

  String authError(Object e) {
    if (e is FirebaseAuthException) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') return 'Wrong Firebase admin password.';
      if (e.code == 'user-not-found') return 'Admin email is not registered in Firebase Authentication.';
      if (e.code == 'operation-not-allowed') return 'Email/password sign-in is disabled in Firebase.';
      return e.message ?? 'Admin login failed.';
    }
    return 'Admin login failed.';
  }

  Future<void> login() async {
    final e = email.text.trim();
    if (e.toLowerCase() != adminEmail.toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Use the configured ALLways admin email.')));
      return;
    }
    if (pass.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter the Firebase admin password.')));
      return;
    }
    setState(() => busy = true);
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(email: e, password: pass.text);
      if (cred.user?.email?.toLowerCase() != adminEmail.toLowerCase()) {
        await FirebaseAuth.instance.signOut();
        throw Exception('This account is not the ALLways admin account.');
      }
      if (mounted) setState(() => loggedIn = true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(authError(e))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<String?> pickQuickOption(BuildContext context, {required String title, required List<String> options, required String current}) async {
    final preset = options.contains(current) ? current : 'Other';
    final controller = TextEditingController(text: preset == 'Other' && current.isNotEmpty ? current : '');
    String selected = preset;
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: options.map((option) => ChoiceChip(label: Text(option), selected: selected == option, onSelected: (_) => setSheetState(() => selected = option))).toList(),
              ),
              if (selected == 'Other') ...[
                const SizedBox(height: 12),
                TextField(controller: controller, maxLines: title.toLowerCase().contains('message') ? 3 : 1, decoration: InputDecoration(labelText: title.toLowerCase().contains('eta') ? 'Enter ETA' : 'Enter customer message')),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final result = selected == 'Other' ? controller.text.trim() : selected;
                    if (result.isNotEmpty) Navigator.pop(sheet, result);
                  },
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> updateEta(QueryDocumentSnapshot<Map<String, dynamic>> doc, String current) async {
    final value = await pickQuickOption(context, title: 'Update ETA', options: const ['5 mins', '10 mins', '15 mins', 'Delayed', 'Other'], current: current);
    if (value == null) return;
    try {
      await doc.reference.update({'eta': value, 'estimatedDelivery': value, 'updatedAt': DateTime.now().millisecondsSinceEpoch});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ETA updated successfully.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ETA update failed: ' + e.toString())));
    }
  }

  Future<void> updateCustomerMessage(QueryDocumentSnapshot<Map<String, dynamic>> doc, String current) async {
    final value = await pickQuickOption(context, title: 'Update customer message', options: const ['Preparing your order', 'Out for delivery', 'Arriving in 2 mins', 'Item out of stock', 'Other'], current: current);
    if (value == null) return;
    try {
      await doc.reference.update({'customerMessage': value, 'statusNote': value, 'updatedAt': DateTime.now().millisecondsSinceEpoch});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Customer message updated successfully.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Customer message update failed: ' + e.toString())));
    }
  }

  Widget bannerManager() {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.view_carousel_outlined),
        title: const Text('Manage Banners', style: TextStyle(fontWeight: FontWeight.w800)),
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('settings').doc('banners').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Padding(padding: EdgeInsets.all(16), child: Text('Could not load banners.'));
              final urls = List<String>.from(snapshot.data?.data()?['imageUrls'] ?? const []);
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    if (urls.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No banners uploaded yet.')),
                    ...urls.asMap().entries.map(
                      (entry) => Card(
                        child: ListTile(
                          leading: SizedBox(width: 72, height: 48, child: Image.network(entry.value, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image))),
                          title: Text('Banner ' + (entry.key + 1).toString()),
                          trailing: IconButton(onPressed: () => removeBanner(entry.value), icon: const Icon(Icons.delete_outline)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: addBanner, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('Add Banner'))),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> addBanner() async {
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (image == null) return;
      final ref = allwaysStorage.ref().child('banners/banner_' + DateTime.now().millisecondsSinceEpoch.toString() + '.jpg');
      await ref.putFile(File(image.path), SettableMetadata(contentType:'image/jpeg'));
      final url = await ref.getDownloadURL();
      final doc = FirebaseFirestore.instance.collection('settings').doc('banners');
      final snap = await doc.get();
      final urls = List<String>.from(snap.data()?['imageUrls'] ?? const []);
      urls.add(url);
      await doc.set({'imageUrls': urls, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Banner added successfully.')));
    } on FirebaseException catch (e) {
      if (mounted) {
        final detail=e.code=='object-not-found'
          ? 'Firebase Storage bucket/object was not found. Verify the ALLways Storage bucket exists and matches gs://allways-web.firebasestorage.app.'
          : 'Firebase Storage error ['+e.code+']: '+(e.message??'Unknown Storage error');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Banner upload failed: '+detail)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Banner upload failed: ' + e.toString())));
    }
  }

  Future<void> removeBanner(String url) async {
    try {
      final doc = FirebaseFirestore.instance.collection('settings').doc('banners');
      final snap = await doc.get();
      final urls = List<String>.from(snap.data()?['imageUrls'] ?? const []);
      urls.remove(url);
      await doc.set({'imageUrls': urls, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Banner removed.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not remove banner: ' + e.toString())));
    }
  }

  Widget orderCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final order = doc.data();
    final status = (order['status'] ?? 'New Order').toString();
    const statuses = ['New Order', 'Confirmed', 'Preparing', 'Assigned', 'Out for delivery', 'Delivered', 'Cancelled'];
    final eta = (order['eta'] ?? order['estimatedDelivery'] ?? '').toString();
    final note = (order['customerMessage'] ?? order['statusNote'] ?? '').toString();

    return Card(
      child: ExpansionTile(
        title: Text('#' + (order['id'] ?? doc.id).toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text((order['name'] ?? 'Customer').toString() + ' • ' + status + ' • ₹' + (order['total'] ?? 0).toString()),
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((order['email'] ?? '').toString()),
                Text((order['phone'] ?? '').toString()),
                Text((order['address'] ?? '').toString()),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: statuses.contains(status) ? status : 'New Order',
                  items: statuses.map((x) => DropdownMenuItem<String>(value: x, child: Text(x))).toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    final message = value == 'Confirmed'
                        ? 'Order confirmed'
                        : value == 'Preparing'
                            ? 'Your order is being prepared'
                            : value == 'Out for delivery'
                                ? 'Your order is on the way'
                                : value == 'Delivered'
                                    ? 'Order delivered'
                                    : value == 'Cancelled'
                                        ? 'Order cancelled'
                                        : 'Order received';
                    doc.reference.update({'status': value, 'statusNote': message, 'customerMessage': message, 'updatedAt': DateTime.now().millisecondsSinceEpoch});
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('ETA', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(eta.isEmpty ? 'Not set' : eta),
                  trailing: const Icon(Icons.schedule),
                  onTap: () => updateEta(doc, eta),
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Customer message', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(note.isEmpty ? 'Not set' : note),
                  trailing: const Icon(Icons.message_outlined),
                  onTap: () => updateCustomerMessage(doc, note),
                ),
                const Divider(),
                const Text('Customer last 3 past orders', style: TextStyle(fontWeight: FontWeight.w800)),
                FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  future: FirebaseFirestore.instance.collection('orders').where('customerId', isEqualTo: (order['customerId'] ?? '').toString()).get(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator());
                    if (snapshot.hasError) return const Text('Past orders unavailable.');
                    final past = [...snapshot.data?.docs ?? const []]
                      ..sort((a, b) => ((b.data()['createdAt'] ?? 0) as num).compareTo((a.data()['createdAt'] ?? 0) as num));
                    final previous = past.where((x) => x.id != doc.id).take(3).toList();
                    if (previous.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No previous orders.'));
                    return Column(
                      children: previous.map(
                        (pastDoc) {
                          final x = pastDoc.data();
                          final rawItems = x['items'];
                          final itemText = rawItems is List
                              ? rawItems.map((i) => i is Map ? (i['name'].toString() + ' × ' + i['qty'].toString() + ' • ₹' + i['price'].toString()) : i.toString()).join(', ')
                              : '';
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('#' + (x['id'] ?? pastDoc.id).toString()),
                            subtitle: Text((x['status'] ?? '').toString() + ' • ₹' + (x['total'] ?? 0).toString() + '\n' + itemText),
                            isThreeLine: true,
                          );
                        },
                      ).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!loggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('ALLways Admin Login')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(Icons.admin_panel_settings, size: 64),
            const SizedBox(height: 12),
            const Text('ALLways Admin', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('Use the Firebase password for the admin account. This is separate from your Gmail password.'),
            const SizedBox(height: 20),
            TextField(controller: email, readOnly: true, decoration: const InputDecoration(labelText: 'Admin email')),
            const SizedBox(height: 12),
            TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Firebase admin password')),
            const SizedBox(height: 18),
            FilledButton(onPressed: busy ? null : login, child: Text(busy ? 'Signing in…' : 'Sign in to Admin')),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('ALLways Admin Dashboard'),
        actions: [
          IconButton(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) setState(() => loggedIn = false);
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('orders').snapshots(),
            builder: (context, snapshot) {
              final pending = snapshot.data?.docs.where((d) {
                final s = (d.data()['status'] ?? '').toString();
                return s != 'Delivered' && s != 'Cancelled';
              }).length ?? 0;
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Align(alignment: Alignment.centerLeft, child: Text('Pending Orders: ' + pending.toString(), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              );
            },
          ),
          const AdminRolesPanel(),
          bannerManager(),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Order Management', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ),
          SizedBox(
            height: 54,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemCount: orderStatusFilters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = orderStatusFilters[index];
                final value = filter['value']!;
                return ChoiceChip(
                  label: Text(filter['label']!),
                  selected: selectedOrderStatusFilter == value,
                  onSelected: (selected) {
                    if (selected) setState(() => selectedOrderStatusFilter = value);
                  },
                );
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('orders').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('Cannot load orders: ' + snapshot.error.toString())));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final docs = [...snapshot.data!.docs]
                  ..sort((a, b) => ((b.data()['createdAt'] ?? 0) as num).compareTo((a.data()['createdAt'] ?? 0) as num));
                final filteredDocs = docs.where((doc) {
                  final rawStatus = (doc.data()['status'] ?? '').toString();
                  return normalizeOrderStatus(rawStatus) == selectedOrderStatusFilter;
                }).toList();
                if (filteredDocs.isEmpty) {
                  final label = orderStatusFilters.firstWhere((x) => x['value'] == selectedOrderStatusFilter)['label']!;
                  return Center(child: Text('No ' + label.toLowerCase() + ' orders.'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) => orderCard(filteredDocs[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
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
      final signIn = GoogleSignIn.instance;
      // Initialize Google Sign-In only when the user actually chooses Google.
      // Keeping this out of app startup prevents an auth-plugin initialization
      // failure from preventing the entire ALLways app from opening.
      await signIn.initialize(
        serverClientId: '869987297351-bonithsodhkkhb8a994d6hbiau8a3ltv.apps.googleusercontent.com',
      );
      // Do not sign out immediately before authentication. With Android's
      // Credential Manager flow this can force an unnecessary account reauth
      // and surface as [16] Account reauth failed. authenticate() can show
      // the account chooser itself when needed.
      final GoogleSignInAccount account = await signIn.authenticate();
      final GoogleSignInAuthentication auth = account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception('Google did not return an ID token.');
      }
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      await FirebaseAuth.instance.signInWithCredential(credential);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is FirebaseAuthException ? err(e) : 'Google sign-in failed: '+e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit()async{setState(()=>busy=true);try{if(signup){final x=await FirebaseAuth.instance.createUserWithEmailAndPassword(email:email.text.trim(),password:pass.text);if(name.text.trim().isNotEmpty)await x.user?.updateDisplayName(name.text.trim());}else{await FirebaseAuth.instance.signInWithEmailAndPassword(email:email.text.trim().toLowerCase(),password:pass.text.trim());}if(mounted)Navigator.pop(context);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(err(e))));}finally{if(mounted)setState(()=>busy=false);}}
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

