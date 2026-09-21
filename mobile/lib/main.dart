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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'firebase_options.dart';

const adminEmail='mauryasujeet698@gmail.com';
const shareApkUrl='https://github.com/mauryasujeet698-svg/Always-website/releases/download/allways-latest/allways-v1.4.7.apk';

const inventoryEndpoint='https://script.google.com/macros/s/AKfycbyuAdL6eEIlGiYhoTPFtE70VhyiMLnKgzO1ytctdSCWMtTdw4zIVQvEVwkbYJyJF2Wd/exec';
const updateManifestUrl='https://raw.githubusercontent.com/mauryasujeet698-svg/Always-website/allways-android-app/mobile/update.json';

@pragma('vm:entry-point')
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
    messages=FirebaseMessaging.onMessage.listen((m)async{if(!mounted)return;final title=m.notification?.title??'ALLways';final body=m.notification?.body??'New update';try{await const MethodChannel('com.allways.app/apk_installer').invokeMethod('showNotification',{'title':title,'body':body});}catch(_){}ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(title+': '+body)));});
    if(user!=null){setupNotifications();loadAddresses();}
  }
  @override void dispose(){timer?.cancel();auth?.cancel();messages?.cancel();super.dispose();}

  Future<void> setupNotifications() async {
    try{
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
      if(result=='permission_required')messenger.showSnackBar(const SnackBar(content:Text('Please allow ALLways to install updates, then tap Update again.')));
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
      'subtotal':sub,'delivery':delivery,'total':grand,'paymentMethod':'COD','status':'New Order','estimatedDelivery':'',
      'statusNote':'Order received','cancellationReason':'','rating':null,'fcmToken':(await SharedPreferences.getInstance()).getString('allways_fcm_token')??'','createdAt':DateTime.now().millisecondsSinceEpoch,'updatedAt':DateTime.now().millisecondsSinceEpoch,'time':DateTime.now().toLocal().toString()};
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
      ShopPage(products:products,loading:loading,error:error,onRefresh:loadInventory,onAdd:add,cart:cart,onQty:qty),
      const Center(child:Text('Travel — Coming Soon',style:TextStyle(fontSize:20))),
      OrdersPage(user:user,onCancel:cancelOrder),
      ProfilePage(user:user,addresses:addresses,onLogin:login,onReload:loadAddresses,onDelete:deleteAddress),
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
        NavigationDestination(icon:Icon(Icons.receipt_long_outlined),label:'Orders'),
        NavigationDestination(icon:Icon(Icons.person_outline),label:'Profile')]),
      floatingActionButton:count==0?null:FloatingActionButton.extended(
        onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>CartScreen(cart:cart,addresses:addresses,onQty:qty,onPlace:placeOrder))),
        icon:const Icon(Icons.shopping_cart),label:Text(count.toString()+' • ₹'+total.toStringAsFixed(0))),
    );
  }
}

class ShopPage extends StatefulWidget {
  final List<Product> products;final bool loading;final String? error;final Future<void> Function({bool silent}) onRefresh;final void Function(Product) onAdd;
  final Map<String,CartItem> cart;final void Function(String,int) onQty;
  const ShopPage({super.key,required this.products,required this.loading,required this.error,required this.onRefresh,required this.onAdd,required this.cart,required this.onQty});
  State<ShopPage> createState()=>_ShopPageState();
}
class _ShopPageState extends State<ShopPage>{
  String cat='All',search='';
  Widget build(BuildContext c){
    final cats=<String>{'All',...widget.products.map((p)=>p.category)};final q=search.toLowerCase().trim();
    final list=widget.products.where((p){final text=(p.name+' '+p.category+' '+p.brand+' '+p.description).toLowerCase();return(cat=='All'||p.category==cat)&&(q.isEmpty||text.contains(q));}).toList();
    return RefreshIndicator(onRefresh:()=>widget.onRefresh(),child:ListView(padding:const EdgeInsets.fromLTRB(16,12,16,110),children:[
      const Text('ALLways',style:TextStyle(fontSize:30,fontWeight:FontWeight.w900)),const Text('Closer to You, Always',style:TextStyle(color:Colors.grey)),
      const SizedBox(height:14),Card(color:Colors.black,child:const Padding(padding:EdgeInsets.all(22),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Priority Delivery',style:TextStyle(color:Colors.white70)),SizedBox(height:7),Text('Everything you need, closer to home.',style:TextStyle(color:Colors.white,fontSize:24,fontWeight:FontWeight.w800)),SizedBox(height:7),Text('Shop local essentials. Simple ordering.',style:TextStyle(color:Colors.white70))]))),
      const SizedBox(height:16),TextField(decoration:const InputDecoration(hintText:'Search items',prefixIcon:Icon(Icons.search)),onChanged:(v)=>setState(()=>search=v)),
      const SizedBox(height:10),SizedBox(height:44,child:ListView(scrollDirection:Axis.horizontal,children:cats.map((x)=>Padding(padding:const EdgeInsets.only(right:7),child:ChoiceChip(label:Text(x),selected:cat==x,onSelected:(_)=>setState(()=>cat=x)))).toList())),
      const SizedBox(height:14),
      if(widget.loading)const Padding(padding:EdgeInsets.all(40),child:Center(child:CircularProgressIndicator()))
      else if(widget.error!=null)const InfoCard(title:'Could not load inventory',detail:'Check your connection and pull down to retry.')
      else if(list.isEmpty)const InfoCard(title:'No items found',detail:'Try another category or search.')
      else ...list.map((p)=>Card(margin:const EdgeInsets.only(bottom:9),child:ListTile(
        onTap:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>ProductScreen(product:p,onAdd:()=>widget.onAdd(p)))),
        leading:CircleAvatar(child:Text(p.icon)),title:Text(p.name,style:const TextStyle(fontWeight:FontWeight.w800)),
        subtitle:Text(p.category+' • ₹'+p.price.toString()+'\n'+(p.stock>0?'In stock':'Unavailable')),
        trailing:widget.cart.containsKey(p.id)
          ? Row(mainAxisSize:MainAxisSize.min,children:[IconButton(onPressed:()=>widget.onQty(p.id,-1),icon:const Icon(Icons.remove_circle_outline)),Text(widget.cart[p.id]!.qty.toString(),style:const TextStyle(fontWeight:FontWeight.w800)),IconButton(onPressed:p.stock>widget.cart[p.id]!.qty?()=>widget.onQty(p.id,1):null,icon:const Icon(Icons.add_circle_outline))])
          : IconButton(onPressed:p.stock>0?()=>widget.onAdd(p):null,icon:const Icon(Icons.add_shopping_cart))))),
    ]));
  }
}

class ProductScreen extends StatelessWidget{
  final Product product;final VoidCallback onAdd;const ProductScreen({super.key,required this.product,required this.onAdd});
  Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Product')),body:ListView(padding:const EdgeInsets.all(20),children:[
    CircleAvatar(radius:55,child:Text(product.icon,style:const TextStyle(fontSize:40))),const SizedBox(height:18),
    Text(product.name,style:const TextStyle(fontSize:28,fontWeight:FontWeight.w900)),if(product.brand.isNotEmpty)Text(product.brand,style:const TextStyle(color:Colors.grey)),
    const SizedBox(height:8),Text('₹'+product.price.toString(),style:const TextStyle(fontSize:24,fontWeight:FontWeight.w800)),const SizedBox(height:14),
    Text(product.description.isEmpty?'Available from the shared ALLways inventory.':product.description),const SizedBox(height:10),
    Text(product.stock>0?product.stock.toString()+' available':'Currently unavailable'),const SizedBox(height:24),
    FilledButton.icon(onPressed:product.stock>0?(){onAdd();Navigator.pop(c);}:null,icon:const Icon(Icons.add_shopping_cart),label:const Text('Add to cart'))
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
      if(!await Geolocator.isLocationServiceEnabled()){msg('Please turn on Location/GPS and try again.');return;}
      var permission=await Geolocator.checkPermission();
      if(permission==LocationPermission.denied)permission=await Geolocator.requestPermission();
      if(permission==LocationPermission.denied||permission==LocationPermission.deniedForever){msg('Location permission was not granted. Please enter your address manually.');return;}
      final pos=await Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.high));
      try{
        final marks=await placemarkFromCoordinates(pos.latitude,pos.longitude);
        if(marks.isNotEmpty){final x=marks.first;final parts=[x.name,x.subLocality,x.locality,x.subAdministrativeArea,x.administrativeArea,x.postalCode].whereType<String>().where((v)=>v.trim().isNotEmpty).map((v)=>v.trim()).toList();a.text=parts.toSet().join(', ');}
      }catch(_){ }
      if(a.text.trim().isEmpty)a.text='Current location: '+pos.latitude.toStringAsFixed(6)+', '+pos.longitude.toStringAsFixed(6);
      msg('Current location added. Please add your house number or landmark if needed.');
    }catch(_){msg('Could not get your current location. Please enter the address manually.');}
    finally{if(mounted)setState(()=>locating=false);}
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
              StatusView(status:status),if((o['estimatedDelivery']??'').toString().isNotEmpty)Text('ETA: '+o['estimatedDelivery'].toString(),style:const TextStyle(fontWeight:FontWeight.w700)),
              const SizedBox(height:5),Text((o['statusNote']??'').toString()),const SizedBox(height:8),Text(items),Text('Address: '+(o['address']??'').toString()),
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

class ProfilePage extends StatelessWidget{
  final User? user;final List<Map<String,dynamic>> addresses;final VoidCallback onLogin;final Future<void> Function() onReload;final Future<void> Function(String) onDelete;
  const ProfilePage({super.key,required this.user,required this.addresses,required this.onLogin,required this.onReload,required this.onDelete});
  Future<void> _checkForUpdate(BuildContext c) async {
    try {
      final r=await http.get(Uri.parse(updateManifestUrl)).timeout(const Duration(seconds:8));
      if(r.statusCode!=200)throw Exception();
      final data=jsonDecode(r.body) as Map<String,dynamic>;
      final latest=(data['version']??'').toString();
      final current=await PackageInfo.fromPlatform();
      int v(String x)=>x.split('.').map((e)=>int.tryParse(e)??0).fold(0,(a,b)=>a*1000+b);
      if(latest.isNotEmpty&&v(latest)>v(current.version)){
        if(c.mounted)showDialog(context:c,builder:(_)=>AlertDialog(title:const Text('Update available'),content:Text('ALLways '+latest+' is available. Update now for the latest improvements.'),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Later')),FilledButton(onPressed:()async{Navigator.pop(c);final url=(data['apkUrl']??'').toString();if(url.isNotEmpty)await _downloadAndInstall(c,url);},child:const Text('UPDATE NOW'))]));
      }else if(c.mounted)ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content:Text('You are using the latest ALLways version.')));
    }catch(_){if(c.mounted)ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content:Text('Could not check for updates. Please try again.')));}
  }
  Future<void> _downloadAndInstall(BuildContext c,String u) async {
    final controller=ValueNotifier<double>(0);
    try{
      showDialog(context:c,barrierDismissible:false,builder:(_)=>AlertDialog(
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
      if(c.mounted)Navigator.of(c).pop();
      final result=await const MethodChannel('com.allways.app/apk_installer').invokeMethod<String>('installApk',{'path':file.path});
      if(c.mounted&&result=='permission_required')ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content:Text('Please allow ALLways to install updates, then tap Update again.')));
      else if(c.mounted&&result!='started')ScaffoldMessenger.of(c).showSnackBar(SnackBar(content:Text('Could not start installation: '+(result??'unknown error'))));
    }catch(e){if(c.mounted&&Navigator.of(c).canPop())Navigator.of(c).pop();if(c.mounted)ScaffoldMessenger.of(c).showSnackBar(SnackBar(content:Text('Update failed: '+e.toString())));}
    finally{controller.dispose();}
  }

  Widget build(BuildContext c){
    if(user==null)return Center(child:FilledButton(onPressed:onLogin,child:const Text('Sign in / Sign up')));
    return ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Profile',style:TextStyle(fontSize:28,fontWeight:FontWeight.w900)),const SizedBox(height:12),
      Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.person)),title:Text(user!.displayName??'ALLways customer'),subtitle:Text(user!.email??''))),
      const SizedBox(height:16),Row(children:[const Expanded(child:Text('Saved addresses',style:TextStyle(fontSize:20,fontWeight:FontWeight.w800))),IconButton(onPressed:onReload,icon:const Icon(Icons.refresh))]),
      if(addresses.isEmpty)const InfoCard(title:'No saved addresses',detail:'An address is saved after a successful order.')
      else ...addresses.map((x)=>Card(child:ListTile(title:Text((x['name']??'').toString()),subtitle:Text((x['address']??'').toString()),trailing:IconButton(onPressed:()=>onDelete(x['id'].toString()),icon:const Icon(Icons.delete_outline))))),
      ListTile(leading:const Icon(Icons.share_outlined),title:const Text('Share ALLways'),subtitle:const Text('Share ALLways with friends and family'),onTap:()=>SharePlus.instance.share(ShareParams(text:'Try ALLways — Closer to You, Always. Download ALLways 1.4.7: '+shareApkUrl))),
      ListTile(leading:const Icon(Icons.system_update_outlined),title:const Text('Check for updates'),subtitle:const Text('Check for the latest ALLways version'),onTap:()=>_checkForUpdate(c)),
      ListTile(leading:const Icon(Icons.notifications_outlined),title:const Text('Notifications'),subtitle:const Text('Order and ALLways alerts'),onTap:()async{final s=await FirebaseMessaging.instance.requestPermission(alert:true,badge:true,sound:true);if(c.mounted)ScaffoldMessenger.of(c).showSnackBar(SnackBar(content:Text(s.authorizationStatus==AuthorizationStatus.authorized?'Notifications enabled.':'Permission not granted.')));}),
      ListTile(leading:const Icon(Icons.logout),title:const Text('Log out'),onTap:()=>FirebaseAuth.instance.signOut()),
      const SizedBox(height:20),const Text('ALLways • Closer to You, Always',textAlign:TextAlign.center,style:TextStyle(color:Colors.grey))
    ]);
  }
}

class AdminScreen extends StatefulWidget{
  const AdminScreen({super.key});
  @override State<AdminScreen> createState()=>_AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>{
  final email=TextEditingController(text:adminEmail);
  final pass=TextEditingController();
  bool busy=false;
  bool loggedIn=false;

  @override void initState(){
    super.initState();
    final u=FirebaseAuth.instance.currentUser;
    loggedIn=u?.email?.toLowerCase()==adminEmail.toLowerCase();
  }

  @override void dispose(){email.dispose();pass.dispose();super.dispose();}

  String authError(Object e){
    if(e is FirebaseAuthException){
      if(e.code=='wrong-password'||e.code=='invalid-credential')return'Wrong Firebase admin password.';
      if(e.code=='user-not-found')return'Admin email is not registered in Firebase Authentication.';
      if(e.code=='operation-not-allowed')return'Email/password sign-in is disabled in Firebase.';
      return e.message??'Admin login failed.';
    }
    return'Admin login failed.';
  }

  Future<void> login() async{
    final e=email.text.trim();
    if(e.toLowerCase()!=adminEmail.toLowerCase()){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Use the configured ALLways admin email.')));
      return;
    }
    if(pass.text.isEmpty){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter the Firebase admin password.')));
      return;
    }
    setState(()=>busy=true);
    try{
      final cred=await FirebaseAuth.instance.signInWithEmailAndPassword(email:e,password:pass.text);
      if(cred.user?.email?.toLowerCase()!=adminEmail.toLowerCase()){
        await FirebaseAuth.instance.signOut();
        throw Exception('This account is not the ALLways admin account.');
      }
      if(mounted)setState(()=>loggedIn=true);
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(authError(e))));
    }finally{
      if(mounted)setState(()=>busy=false);
    }
  }

  Future<void> updateOrder(String id,Map<String,dynamic> data) async{
    try{
      await FirebaseFirestore.instance.collection('orders').doc(id).update({
        ...data,'updatedAt':DateTime.now().millisecondsSinceEpoch
      });
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Update failed: '+e.toString())));
    }
  }

  Widget orderCard(QueryDocumentSnapshot<Map<String,dynamic>> d){
    final o=d.data();
    final status=(o['status']??'New Order').toString();
    const statuses=['New Order','Confirmed','Preparing','Out for delivery','Delivered','Cancelled'];
    final eta=TextEditingController(text:(o['estimatedDelivery']??'').toString());
    final note=TextEditingController(text:(o['statusNote']??'').toString());
    return Card(
      child:ExpansionTile(
        title:Text('#'+(o['id']??d.id).toString(),style:const TextStyle(fontWeight:FontWeight.w800)),
        subtitle:Text((o['name']??'Customer').toString()+' • '+status+' • ₹'+(o['total']??0).toString()),
        children:[
          Padding(
            padding:const EdgeInsets.all(14),
            child:Column(
              crossAxisAlignment:CrossAxisAlignment.start,
              children:[
                Text((o['email']??'').toString()),
                Text((o['phone']??'').toString()),
                Text((o['address']??'').toString()),
                const SizedBox(height:8),
                DropdownButtonFormField<String>(
                  value:statuses.contains(status)?status:'New Order',
                  items:statuses.map((x)=>DropdownMenuItem<String>(value:x,child:Text(x))).toList(),
                  onChanged:(v){
                    if(v==null)return;
                    final n=v=='Confirmed'?'Order confirmed':
                      v=='Preparing'?'Your order is being prepared':
                      v=='Out for delivery'?'Your order is on the way':
                      v=='Delivered'?'Order delivered':
                      v=='Cancelled'?'Order cancelled':'Order received';
                    updateOrder(d.id,{'status':v,'statusNote':n});
                  },
                ),
                const SizedBox(height:8),
                TextField(controller:eta,decoration:const InputDecoration(labelText:'Estimated delivery / ETA')),
                const SizedBox(height:6),
                FilledButton(onPressed:()=>updateOrder(d.id,{'estimatedDelivery':eta.text.trim()}),child:const Text('Set ETA')),
                const SizedBox(height:6),
                TextField(controller:note,decoration:const InputDecoration(labelText:'Customer message')),
                const SizedBox(height:6),
                OutlinedButton(onPressed:()=>updateOrder(d.id,{'statusNote':note.text.trim()}),child:const Text('Update customer message')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override Widget build(BuildContext c){
    if(!loggedIn){
      return Scaffold(
        appBar:AppBar(title:const Text('ALLways Admin Login')),
        body:ListView(
          padding:const EdgeInsets.all(20),
          children:[
            const Icon(Icons.admin_panel_settings,size:64),
            const SizedBox(height:12),
            const Text('ALLways Admin',style:TextStyle(fontSize:28,fontWeight:FontWeight.w900)),
            const SizedBox(height:6),
            const Text('Use the Firebase password for the admin account. This is separate from your Gmail password.'),
            const SizedBox(height:20),
            TextField(controller:email,readOnly:true,decoration:const InputDecoration(labelText:'Admin email')),
            const SizedBox(height:12),
            TextField(controller:pass,obscureText:true,decoration:const InputDecoration(labelText:'Firebase admin password')),
            const SizedBox(height:18),
            FilledButton(onPressed:busy?null:login,child:Text(busy?'Signing in…':'Sign in to Admin')),
          ],
        ),
      );
    }

    return Scaffold(
      appBar:AppBar(
        title:const Text('ALLways Admin Dashboard'),
        actions:[
          IconButton(
            onPressed:()async{
              await FirebaseAuth.instance.signOut();
              if(mounted)setState(()=>loggedIn=false);
            },
            icon:const Icon(Icons.logout),
          ),
        ],
      ),
      body:StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
        stream:FirebaseFirestore.instance.collection('orders').snapshots(),
        builder:(c,s){
          if(s.hasError)return Center(child:Padding(padding:const EdgeInsets.all(20),child:Text('Cannot load orders: '+s.error.toString())));
          if(!s.hasData)return const Center(child:CircularProgressIndicator());
          final docs=[...s.data!.docs];
          docs.sort((a,b){
            final av=(a.data()['createdAt']??0) as num;
            final bv=(b.data()['createdAt']??0) as num;
            return bv.compareTo(av);
          });
          if(docs.isEmpty)return const Center(child:Text('No orders yet.'));
          return ListView.builder(
            padding:const EdgeInsets.all(12),
            itemCount:docs.length,
            itemBuilder:(c,i)=>orderCard(docs[i]),
          );
        },
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

