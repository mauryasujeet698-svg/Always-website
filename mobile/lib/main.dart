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

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'firebase_options.dart';

const adminEmail='mauryasujeet698@gmail.com';

const sellerCategories = <String>[
  'Grocery','Dairy','Bakery','Snacks','Fruits & Vegetables','Meat & Poultry','Fish & Seafood','Sweets & Desserts','Beverages',
  'Restaurant & Food','Fast Food','Tiffin & Home Food','Pharmacy & Wellness','Cosmetics & Beauty','Clothing','Footwear',
  'Jewellery & Accessories','Electronics','Mobile & Accessories','Home Appliances','Furniture','Home Decor','Kitchen & Dining',
  'Hardware','Electrical','Plumbing','Paint & Tools','Stationery & Books','Toys & Games','Sports & Fitness','Auto Parts & Accessories',
  'Bike & Car Services','Fuel & Lubricants','Agriculture & Seeds','Fertilizers & Pesticides','Dairy Farming Supplies','Pet Supplies',
  'Flowers & Plants','Gifts & Handicrafts','Tailoring & Boutique','Laundry & Dry Cleaning','Repair Services','Photocopy & Printing',
  'Travel & Transport','Local Services','Construction Materials','Solar & Inverter','Water & Gas Services','Wholesale & Distribution','Other',
];

const cloudinaryCloudName='busdtvia';
const cloudinaryUploadPreset='allways_preset';

String cloudinaryImageUrl(String url, {required double width, required double height}) {
  final value = url.trim();
  if (value.isEmpty || !value.contains('res.cloudinary.com/')) return value;
  final safeW = width.isFinite && width > 0 ? width.round() : 1;
  final safeH = height.isFinite && height > 0 ? height.round() : 1;
  final uploadMarker = '/image/upload/';
  final markerIndex = value.indexOf(uploadMarker);
  if (markerIndex < 0) return value;
  final transform = 'w_$safeW,h_$safeH,c_fill,g_auto,f_auto,q_auto,e_sharpen:100';
  final after = markerIndex + uploadMarker.length;
  // Avoid stacking another ALLways-generated transformation if the URL was
  // already formatted for a previous display container.
  var rest = value.substring(after);
  if (rest.contains('/')) {
    final firstSegment = rest.substring(0, rest.indexOf('/'));
    final isTransformation = firstSegment.contains('w_') || firstSegment.contains('h_') ||
        firstSegment.contains('c_fill') || firstSegment.contains('g_auto') ||
        firstSegment.contains('f_auto') || firstSegment.contains('q_auto');
    if (isTransformation) rest = rest.substring(rest.indexOf('/') + 1);
  }
  return value.substring(0, after) + transform + '/' + rest;
}

String cloudinarySmartCropUrl(String url) {
  final value = url.trim();
  if (value.isEmpty || !value.contains('res.cloudinary.com/')) return value;
  const uploadMarker = '/image/upload/';
  final markerIndex = value.indexOf(uploadMarker);
  if (markerIndex < 0) return value;
  final after = markerIndex + uploadMarker.length;
  final rest = value.substring(after);
  if (rest.startsWith('c_fill,g_auto/')) return value;
  return value.substring(0, after) + 'c_fill,g_auto/' + rest;
}

Future<String> uploadImageToCloudinary(XFile image, {String? folder}) async {
  if (cloudinaryCloudName.isEmpty || cloudinaryUploadPreset.isEmpty) {
    throw Exception('Cloudinary is not configured. Set cloudinaryCloudName and cloudinaryUploadPreset.');
  }

  final endpoint = Uri.parse(
    'https://api.cloudinary.com/v1_1/' + cloudinaryCloudName + '/image/upload',
  );
  final request = http.MultipartRequest('POST', endpoint);
  request.fields['upload_preset'] = cloudinaryUploadPreset;
  if (folder != null && folder.isNotEmpty) {
    request.fields['folder'] = folder;
  }
  request.files.add(await http.MultipartFile.fromPath('file', image.path));

  final response = await request.send();
  final body = await response.stream.bytesToString();

  Map<String, dynamic> data = {};
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      data = Map<String, dynamic>.from(decoded);
    }
  } catch (_) {}

  if (response.statusCode < 200 || response.statusCode >= 300) {
    final error = data['error'];
    final message = error is Map
        ? (error['message'] ?? 'Unknown Cloudinary error').toString()
        : body;
    throw Exception('Cloudinary upload failed [HTTP ${response.statusCode}]: $message');
  }

  final secureUrl = (data['secure_url'] ?? '').toString();
  if (secureUrl.isEmpty) {
    throw Exception('Cloudinary upload succeeded but no secure_url was returned.');
  }
  return secureUrl;
}
const shareApkUrl='https://github.com/mauryasujeet698-svg/Always-website/releases/download/allways-latest/allways-v1.4.7.apk';

const inventoryEndpoint='https://script.google.com/macros/s/AKfycbyuAdL6eEIlGiYhoTPFtE70VhyiMLnKgzO1ytctdSCWMtTdw4zIVQvEVwkbYJyJF2Wd/exec';
const updateManifestUrl='https://raw.githubusercontent.com/mauryasujeet698-svg/Always-website/allways-android-app/mobile/update.json';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);
final ValueNotifier<bool> unreadNotificationNotifier = ValueNotifier(false);
final ValueNotifier<String> languageNotifier = ValueNotifier('English');

const Map<String,Map<String,String>> _translations = {
  'Hindi': {
    'Shop':'दुकान','Travel':'यात्रा','Local sellers':'स्थानीय विक्रेता','Profile':'प्रोफ़ाइल','Notifications':'सूचनाएँ','Appearance':'दिखावट','Language':'भाषा','Share ALLways':'ALLways साझा करें','Check for Updates':'अपडेट जाँचें','Log Out':'लॉग आउट','Book vehicle':'वाहन बुक करें','Book a ride partner':'राइड पार्टनर बुक करें','Search products':'उत्पाद खोजें','Orders':'ऑर्डर','Cart':'कार्ट','Add to cart':'कार्ट में जोड़ें','New Order':'नया ऑर्डर','Confirmed':'पुष्टि','Preparing':'तैयारी में','Out for delivery':'डिलीवरी के लिए रवाना','Delivered':'डिलीवर हो गया','Cancelled':'रद्द','Save changes':'बदलाव सहेजें','Close':'बंद करें','Edit seller profile':'सेलर प्रोफ़ाइल संपादित करें','Your name':'आपका नाम','Shop name':'दुकान का नाम','Change shop image':'दुकान की फोटो बदलें'
  },
  'Hinglish': {
    'Shop':'Shop','Travel':'Travel','Local sellers':'Local Sellers','Profile':'Profile','Notifications':'Notifications','Appearance':'Appearance','Language':'Language','Share ALLways':'ALLways Share Karein','Check for Updates':'Update Check Karein','Log Out':'Logout','Book vehicle':'Vehicle Book Karein','Book a ride partner':'Ride Partner Book Karein','Search products':'Products Search Karein','Orders':'Orders','Cart':'Cart','Add to cart':'Cart mein add karein','New Order':'Naya Order','Confirmed':'Confirmed','Preparing':'Preparing','Out for delivery':'Delivery ke liye nikla','Delivered':'Delivered','Cancelled':'Cancelled','Save changes':'Changes Save Karein','Close':'Close','Edit seller profile':'Seller Profile Edit Karein','Your name':'Aapka naam','Shop name':'Shop ka naam','Change shop image':'Shop ki photo badlein'
  },
  'Bhojpuri': {
    'Shop':'दुकान','Travel':'यात्रा','Local sellers':'लोकल दुकानदार','Profile':'प्रोफाइल','Notifications':'सूचना','Appearance':'दिखावट','Language':'भाषा','Share ALLways':'ALLways साझा करीं','Check for Updates':'अपडेट देखीं','Log Out':'लॉग आउट','Book vehicle':'गाड़ी बुक करीं','Book a ride partner':'राइड पार्टनर बुक करीं','Search products':'सामान खोजीं','Orders':'ऑर्डर','Cart':'कार्ट','Add to cart':'कार्ट में डालीं','New Order':'नया ऑर्डर','Confirmed':'पक्का','Preparing':'तैयार हो रहल','Out for delivery':'डिलीवरी खातिर निकलल','Delivered':'पहुंच गइल','Cancelled':'रद्द','Save changes':'बदलाव सेव करीं','Close':'बंद करीं','Edit seller profile':'सेलर प्रोफाइल बदलीं','Your name':'रउरा के नाम','Shop name':'दुकान के नाम','Change shop image':'दुकान के फोटो बदलीं'
  },
  'Awadhi': {
    'Shop':'दुकान','Travel':'यात्रा','Local sellers':'स्थानीय दुकानदार','Profile':'प्रोफाइल','Notifications':'सूचना','Appearance':'दिखावट','Language':'भाषा','Share ALLways':'ALLways साझा करौ','Check for Updates':'अपडेट देखौ','Log Out':'लॉग आउट','Book vehicle':'गाड़ी बुक करौ','Book a ride partner':'राइड पार्टनर बुक करौ','Search products':'सामान खोजौ','Orders':'ऑर्डर','Cart':'कार्ट','Add to cart':'कार्ट मा डालौ','New Order':'नवा ऑर्डर','Confirmed':'पक्का','Preparing':'तैयार होत','Out for delivery':'डिलीवरी खातिर निकर गवा','Delivered':'पहुंच गवा','Cancelled':'रद्द','Save changes':'बदलाव सेव करौ','Close':'बंद करौ','Edit seller profile':'सेलर प्रोफाइल बदलीं','Your name':'आपका नाउँ','Shop name':'दुकान का नाउँ','Change shop image':'दुकान की फोटो बदलीं'
  },
};

String tr(String key) => _translations[languageNotifier.value]?[key] ?? key;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Notification messages are displayed by Android when the app is backgrounded
  // or terminated. Keep this handler top-level for Flutter's background isolate.
  print('ALLways background FCM: ${message.messageId}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  final prefs = await SharedPreferences.getInstance();
  final savedNotifications = prefs.getStringList('allways_notifications') ?? <String>[];
  unreadNotificationNotifier.value = savedNotifications.isNotEmpty;
  final savedLanguage = prefs.getString('allways_language') ?? 'English';
  languageNotifier.value = _translations.containsKey(savedLanguage) ? savedLanguage : 'English';
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


class LiveLocationBroadcaster {
  StreamSubscription<Position>? _subscription;
  Future<bool> start({required String collection,required String docId,required String prefix}) async {
    await stop();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return false;
      _subscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
      ).listen((position) async {
        try {
          await FirebaseFirestore.instance.collection(collection).doc(docId).set({
            '\${prefix}Lat': position.latitude,
            '\${prefix}Lng': position.longitude,
            '\${prefix}LocationUpdatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (_) {}
      });
      return true;
    } catch (_) { return false; }
  }
  Future<void> stop() async { await _subscription?.cancel(); _subscription=null; }
}
class LatLngTween extends Tween<LatLng> {
  LatLngTween({super.begin, super.end});
  @override LatLng lerp(double t) {
    final a=begin??end??const LatLng(0,0), b=end??a;
    return LatLng(a.latitude+(b.latitude-a.latitude)*t,a.longitude+(b.longitude-a.longitude)*t);
  }
}
class LiveTrackingScreen extends StatefulWidget {
  final String collection,docId,title,mode; final String? broadcastPrefix; final bool readOnly;
  const LiveTrackingScreen({super.key,required this.collection,required this.docId,required this.title,required this.mode,this.broadcastPrefix,this.readOnly=false});
  @override State<LiveTrackingScreen> createState()=>_LiveTrackingScreenState();
}
class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  final LiveLocationBroadcaster _broadcaster=LiveLocationBroadcaster();
  @override void initState(){super.initState();if(!widget.readOnly&&widget.broadcastPrefix!=null){_broadcaster.start(collection:widget.collection,docId:widget.docId,prefix:widget.broadcastPrefix!);}}
  @override void dispose(){_broadcaster.stop();super.dispose();}
  double? _n(dynamic v)=>v is num?v.toDouble():double.tryParse(v?.toString()??'');
  LatLng? _point(Map<String,dynamic> d,String p){
    final lat=_n(d['${p}Lat']??d['${p}Latitude']);
    final lng=_n(d['${p}Lng']??d['${p}Longitude']);
    if(lat==null||lng==null||lat.isNaN||lng.isNaN)return null;
    return LatLng(lat,lng);
  }
  Widget _icon(IconData icon,Color color)=>Container(decoration:BoxDecoration(color:color,shape:BoxShape.circle,border:Border.all(color:Colors.white,width:3),boxShadow:const[BoxShadow(blurRadius:8,color:Colors.black26)]),child:Icon(icon,color:Colors.white,size:26));
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(widget.title)),
    body:StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(
      stream:FirebaseFirestore.instance.collection(widget.collection).doc(widget.docId).snapshots(),
      builder:(context,snapshot){
        if(snapshot.hasError)return Center(child:Text('Tracking unavailable: \${snapshot.error}'));
        if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
        final d=snapshot.data!.data()??<String,dynamic>{};
        final customer=_point(d,'customer');
        LatLng? partner;
        if(widget.mode=='order')partner=_point(d,'carrier');
        else if(widget.mode=='vehicle')partner=_point(d,'owner');
        else partner=_point(d,'partner');
        final pickup=_point(d,'pickup'),destination=_point(d,'destination');
        final points=<LatLng>[if(customer!=null)customer,if(partner!=null)partner,if(pickup!=null)pickup,if(destination!=null)destination];
        if(points.isEmpty)return const Center(child:Padding(padding:EdgeInsets.all(24),child:Text('Waiting for live location. Keep location enabled and allow ALLways to access it.',textAlign:TextAlign.center)));
        return FlutterMap(options:MapOptions(initialCenter:points.first,initialZoom:15),children:[
          TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'com.allways.app'),
          TweenAnimationBuilder<LatLng>(
            tween:LatLngTween(end:partner),
            duration:const Duration(milliseconds:850),
            curve:Curves.easeOut,
            builder:(context,animatedPartner,_){
              return MarkerLayer(markers:[
                if(customer!=null)Marker(point:customer,width:52,height:52,child:_icon(Icons.person_pin_circle,Colors.blue)),
                if(animatedPartner!=null)Marker(point:animatedPartner,width:52,height:52,child:_icon(widget.mode=='order'?Icons.delivery_dining:widget.mode=='vehicle'?Icons.directions_car:Icons.two_wheeler,Colors.purple)),
                if(pickup!=null)Marker(point:pickup,width:52,height:52,child:_icon(Icons.trip_origin,Colors.green)),
                if(destination!=null)Marker(point:destination,width:52,height:52,child:_icon(Icons.flag,Colors.red)),
              ]);
            },
          ),
          const RichAttributionWidget(attributions:[TextSourceAttribution('OpenStreetMap contributors')]),
        ]);
      },
    ),
  );
}
class Product {
  final String id,name,category,icon,description,brand,sellerId;
  final num price,stock;
  const Product({required this.id,required this.name,required this.category,required this.icon,required this.description,required this.brand,required this.sellerId,required this.price,required this.stock});
  factory Product.fromJson(Map<String,dynamic> j){
    num n(dynamic x)=>x is num?x:num.tryParse(x?.toString()??'')??0;
    return Product(id:(j['id']??'').toString(),name:(j['name']??j['title']??'Item').toString(),category:(j['category']??j['cat']??'Other').toString().trim(),icon:(j['icon']??'🛍️').toString(),description:(j['description']??'').toString(),brand:(j['brand']??'').toString(),sellerId:(j['sellerId']??j['sellerUid']??j['vendorId']??'').toString(),price:n(j['price']),stock:n(j['stock']));
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
    FirebaseMessaging.onMessageOpenedApp.listen((m){
      final title=m.notification?.title??'ALLways';
      final body=m.notification?.body??'Open ALLways to view this update.';
      saveIncomingNotification(title,body);
    });
    FirebaseMessaging.instance.getInitialMessage().then((m){
      if(m==null)return;
      final title=m.notification?.title??'ALLways';
      final body=m.notification?.body??'Open ALLways to view this update.';
      saveIncomingNotification(title,body);
    });
    messages=FirebaseMessaging.onMessage.listen((m)async{final title=m.notification?.title??m.data['title']??'ALLways';final body=m.notification?.body??m.data['body']??m.data['message']??'New update';await saveIncomingNotification(title,body);if(!mounted)return;ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(title+': '+body)));});
    if(user!=null){setupNotifications();loadAddresses();loadWishlist();}
  }
  @override void dispose(){timer?.cancel();auth?.cancel();messages?.cancel();super.dispose();}

  Future<void> setupNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('allways_notifications_enabled') == false) return;

      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      try {
        await const MethodChannel('com.allways.app/apk_installer')
            .invokeMethod('createNotificationChannel');
      } catch (_) {}

      // Global ALLways broadcast topic.
      await FirebaseMessaging.instance.subscribeToTopic('all_users');

      final t = await FirebaseMessaging.instance.getToken();

      Future<void> save(String token) async {
        final p = await SharedPreferences.getInstance();
        await p.setString('allways_fcm_token', token);
        if (user != null) {
          try {
            await FirebaseFirestore.instance
                .collection('fcmTokens')
                .doc(user!.uid)
                .set({
              'uid': user!.uid,
              'email': user!.email ?? '',
              'token': token,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          } catch (_) {}
        }
      }

      if (t != null && t.isNotEmpty) await save(t);

      FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
        if (t.isNotEmpty) await save(t);
      });
    } catch (_) {}
  }

  Future<void> saveIncomingNotification(String title,String body) async {
    try{
      final prefs=await SharedPreferences.getInstance();
      final raw=prefs.getStringList('allways_notifications')??<String>[];
      raw.insert(0,jsonEncode({'title':title,'body':body,'timestamp':DateTime.now().millisecondsSinceEpoch,'read':false}));
      unreadNotificationNotifier.value = true;
      if(raw.length>50)raw.removeRange(50,raw.length);
      await prefs.setStringList('allways_notifications',raw);
    }catch(_){}
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs=await SharedPreferences.getInstance();
    if(enabled){
      final settings=await FirebaseMessaging.instance.requestPermission(alert:true,badge:true,sound:true,provisional:false);
      if(settings.authorizationStatus==AuthorizationStatus.denied){await prefs.setBool('allways_notifications_enabled',false);return;}
      await FirebaseMessaging.instance.subscribeToTopic('all_users');
      await prefs.setBool('allways_notifications_enabled',true);
      await setupNotifications();
    }else{
      await FirebaseMessaging.instance.unsubscribeFromTopic('all_users');
      await prefs.setBool('allways_notifications_enabled',false);
      if(user!=null){try{await FirebaseFirestore.instance.collection('fcmTokens').doc(user!.uid).set({'uid':user!.uid,'notificationsEnabled':false,'updatedAt':FieldValue.serverTimestamp()},SetOptions(merge:true));}catch(_){}}
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

  Future<void> placeOrder(String name,String phone,String address,String note,double? latitude,double? longitude) async {
    if(user==null){login();return;} if(cart.isEmpty)return;
    await setupNotifications();
    final ph=phone.replaceAll(RegExp(r'\D'),'');
    if(name.trim().isEmpty||!RegExp(r'^\d{10}$').hasMatch(ph)||address.trim().isEmpty){msg('Enter name, valid 10-digit phone and address.');return;}
    for(final x in cart.values){final p=products.where((z)=>z.id==x.product.id).firstOrNull;if(p==null||p.stock<x.qty){msg(x.product.name+' is no longer available.');await loadInventory();return;}}
    final sub=total;final delivery=sub>=499?0:30;final grand=sub+delivery;final id='AW'+DateTime.now().millisecondsSinceEpoch.toString().substring(4);
    final sellerIds=cart.values.map((x)=>x.product.sellerId).where((x)=>x.isNotEmpty).toSet();
    final sellerId=sellerIds.length==1?sellerIds.first:'';
    final order={'id':id,'customerId':user!.uid,'sellerId':sellerId,'email':user!.email??'','name':name.trim(),'phone':ph,'address':address.trim(),'note':note.trim(),'customerLatitude':latitude,'customerLongitude':longitude,'locationSource':latitude!=null&&longitude!=null?'gps':'address',
      'items':cart.values.map((x)=>{'id':x.product.id,'name':x.product.name,'qty':x.qty,'price':x.product.price}).toList(),
      'subtotal':sub,'delivery':delivery,'total':grand,'paymentMethod':'COD','status':'New Order','estimatedDelivery':'','eta':'',
      'statusNote':'Order received','customerMessage':'Order received','cancellationReason':'','rating':null,'fcmToken':(await SharedPreferences.getInstance()).getString('allways_fcm_token')??'','customer_fcm_token':(await SharedPreferences.getInstance()).getString('allways_fcm_token')??'','createdAt':DateTime.now().millisecondsSinceEpoch,'updatedAt':DateTime.now().millisecondsSinceEpoch,'time':DateTime.now().toLocal().toString()};
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


  Future<void> reorderItems(List<Map<String, dynamic>> rawItems) async {
    if (user == null) { login(); return; }
    if (products.isEmpty) await loadInventory();
    int added=0, skipped=0;
    for(final raw in rawItems){
      final id=(raw['id']??'').toString();
      Product? product;
      for(final p in products){if(p.id==id){product=p;break;}}
      if(product==null||product.stock<=0){skipped++;continue;}
      final requested=raw['qty'] is num ? (raw['qty'] as num).toInt() : int.tryParse((raw['qty']??1).toString())??1;
      final wanted=requested<1?1:requested;
      final existing=cart[product.id]?.qty??0;
      final available=product.stock.toInt();
      final next=(existing+wanted)>available?available:(existing+wanted);
      if(next<=existing){skipped++;continue;}
      cart[product.id]=CartItem(product,next);added++;
    }
    if(mounted)setState((){});
    if(added==0){msg('None of the delivered items are currently available.');return;}
    msg(skipped>0?'$added item(s) added. $skipped unavailable item(s) were skipped.':'Your delivered items were added to the cart.');
    if(!mounted)return;
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>CartScreen(cart:cart,addresses:addresses,onQty:qty,onPlace:placeOrder)));
    if(mounted)setState((){});
  }

  Widget build(BuildContext c){
    final pages=[
      ShopPage(products:products,loading:loading,error:error,onRefresh:loadInventory,onAdd:add,cart:cart,onQty:qty,user:user,wishlistIds:wishlistIds,onWishlist:toggleWishlist,onOpenCart:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>CartScreen(cart:cart,addresses:addresses,onQty:qty,onPlace:placeOrder))),addresses:addresses),
      const TravelPage(),
      const LocalSellersPage(),
      ProfilePage(user:user,addresses:addresses,onLogin:login,onReload:loadAddresses,onDelete:deleteAddress,onCancel:cancelOrder,onReorder:reorderItems),
    ];
    return ValueListenableBuilder<String>(valueListenable:languageNotifier,builder:(context,lang,_)=>Scaffold(
      body:SafeArea(child:Column(children:[
        if(updateVersion!=null)
          MaterialBanner(
            content:Text('New ALLways update '+updateVersion!+(updateNotes!.isEmpty?'':' — '+updateNotes!)),
            leading:const Icon(Icons.system_update),
            actions:[TextButton(onPressed:openUpdate,child:const Text('UPDATE NOW'))],
          ),
        Expanded(child:pages[tab]),
      ])),
      bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:[
        NavigationDestination(icon:const Icon(Icons.shopping_bag_outlined),label:tr('Shop')),
        NavigationDestination(icon:const Icon(Icons.directions_car_outlined),label:tr('Travel')),
        NavigationDestination(icon:const Icon(Icons.storefront_outlined),label:tr('Local sellers')),
        NavigationDestination(icon:const Icon(Icons.person_outline),label:tr('Profile'))]),
      floatingActionButton:count==0?null:FloatingActionButton.extended(
        onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>CartScreen(cart:cart,addresses:addresses,onQty:qty,onPlace:placeOrder))),
        icon:const Icon(Icons.shopping_cart),label:Text(count.toString()+' • ₹'+total.toStringAsFixed(0))),
    ));
  }
}

class ShopPage extends StatefulWidget{
  final List<Product> products;final bool loading;final String? error;final Future<void> Function({bool silent}) onRefresh;final void Function(Product) onAdd;final Map<String,CartItem> cart;final void Function(String,int) onQty;final User? user;final Set<String> wishlistIds;final Future<void> Function(Product) onWishlist;final VoidCallback onOpenCart;final List<Map<String,dynamic>> addresses;
  const ShopPage({super.key,required this.products,required this.loading,required this.error,required this.onRefresh,required this.onAdd,required this.cart,required this.onQty,required this.user,required this.wishlistIds,required this.onWishlist,required this.onOpenCart,required this.addresses});
  @override State<ShopPage> createState()=>_ShopPageState();
}
class _ShopPageState extends State<ShopPage>{
  final searchController=TextEditingController();final stt.SpeechToText speech=stt.SpeechToText();
  String search='',location='Select delivery location';bool locating=false,listening=false;int bannerIndex=0;Timer? bannerTimer;
  static const preferred=['Popular Near You','Daily Needs','Fresh Fruits & Vegetables','Dairy','Grocery','Bakery','Snacks','Beverages','Breakfast Essentials','Rice & Grains','Atta & Flour','Pulses & Dal','Cooking Oil','Spices & Masala','Salt & Sugar','Dry Fruits & Nuts','Tea & Coffee','Biscuits & Cookies','Chocolates & Sweets','Instant Food','Noodles & Pasta','Sauces & Spreads','Pickles & Chutneys','Canned & Packaged Food','Frozen Food','Ice Cream','Meat & Seafood','Eggs','Personal Care','Bath & Body','Hair Care','Oral Care','Skin Care','Baby Care','Health & Wellness','Home Care','Cleaning Essentials','Laundry Care','Dishwashing','Kitchen Essentials','Paper & Tissue','Pet Care','Stationery','Electronics','Mobile Accessories','Household Essentials','Pooja Essentials','Organic & Natural','Local Specials','Seasonal Products'];
  static const icons={'All':'▦','Dairy':'🥛','Grocery':'🛒','Fruits & Vegetables':'🥬','Bakery':'🥖','Snacks':'🍟','Beverages':'🥤','Breakfast Essentials':'🍳','Rice & Grains':'🍚','Atta & Flour':'🌾','Pulses & Dal':'🫘','Cooking Oil':'🫗','Spices & Masala':'🌶️','Salt & Sugar':'🧂','Dry Fruits & Nuts':'🥜','Tea & Coffee':'☕','Biscuits & Cookies':'🍪','Chocolates & Sweets':'🍫','Instant Food':'🍜','Noodles & Pasta':'🍝','Sauces & Spreads':'🥫','Pickles & Chutneys':'🫙','Canned & Packaged Food':'📦','Frozen Food':'🧊','Ice Cream':'🍦','Meat & Seafood':'🥩','Eggs':'🥚','Personal Care':'🧴','Bath & Body':'🛁','Hair Care':'💇','Oral Care':'🪥','Skin Care':'🧖','Baby Care':'🍼','Health & Wellness':'💊','Home Care':'🏠','Cleaning Essentials':'🧹','Laundry Care':'🧺','Dishwashing':'🧽','Kitchen Essentials':'🍳','Paper & Tissue':'🧻','Pet Care':'🐾','Stationery':'📚','Electronics':'🔌','Mobile Accessories':'📱','Household Essentials':'🧰','Pooja Essentials':'🪔','Organic & Natural':'🌿','Local Specials':'⭐','Seasonal Products':'🎉'};
  @override void initState(){super.initState();syncLocation();bannerTimer=Timer.periodic(const Duration(seconds:4),(_){if(mounted)setState(()=>bannerIndex++);});}
  @override void dispose(){bannerTimer?.cancel();searchController.dispose();speech.stop();super.dispose();}
  @override void didUpdateWidget(covariant ShopPage old){super.didUpdateWidget(old);if(widget.addresses!=old.addresses)syncLocation();}
  void syncLocation(){if(widget.addresses.isNotEmpty){final x=widget.addresses.firstWhere((x)=>x['isCurrent']==true,orElse:()=>widget.addresses.first);final v=(x['address']??'').toString().trim();if(v.isNotEmpty)location=v;}}
  Future<void> voice()async{try{final ok=await speech.initialize(onStatus:(s){if(mounted&&s!='listening')setState(()=>listening=false);},onError:(_){if(mounted)setState(()=>listening=false);});if(!ok)return;setState(()=>listening=true);await speech.listen(onResult:(r){if(!mounted)return;searchController.text=r.recognizedWords;searchController.selection=TextSelection.fromPosition(TextPosition(offset:searchController.text.length));setState(()=>search=searchController.text);},listenOptions:stt.SpeechListenOptions(partialResults:true));}catch(_){if(mounted)setState(()=>listening=false);}}
  Future<void> changeLocation()async{if(widget.user==null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Sign in to select your delivery location.')));return;}await showModalBottomSheet(context:context,showDragHandle:true,builder:(sheet)=>SafeArea(child:ListView(children:[const ListTile(title:Text('Choose delivery location',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900))),...widget.addresses.take(8).map((x)=>ListTile(leading:const Icon(Icons.location_on_outlined),title:Text((x['name']??'Saved address').toString()),subtitle:Text((x['address']??'').toString()),onTap:(){final v=(x['address']??'').toString();if(v.isNotEmpty)setState(()=>location=v);Navigator.pop(sheet);})),ListTile(leading:const Icon(Icons.my_location),title:const Text('Use current location'),onTap:()async{Navigator.pop(sheet);await currentLocation();})])));}
  Future<void> currentLocation()async{if(locating)return;setState(()=>locating=true);try{if(!await Geolocator.isLocationServiceEnabled())throw Exception('Turn on GPS first.');var p=await Geolocator.checkPermission();if(p==LocationPermission.denied)p=await Geolocator.requestPermission();if(p==LocationPermission.denied||p==LocationPermission.deniedForever)throw Exception('Location permission was not granted.');final pos=await Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.high)).timeout(const Duration(seconds:10));var a='Latitude: '+pos.latitude.toString()+', Longitude: '+pos.longitude.toString();try{final m=await placemarkFromCoordinates(pos.latitude,pos.longitude);if(m.isNotEmpty){final x=m.first;final parts=[x.street,x.subLocality,x.locality,x.subAdministrativeArea,x.administrativeArea,x.postalCode].whereType<String>().where((v)=>v.trim().isNotEmpty).map((v)=>v.trim()).toList();if(parts.isNotEmpty)a=parts.toSet().join(', ');}}catch(_){}await FirebaseFirestore.instance.collection('customers').doc(widget.user!.uid).collection('addresses').doc('current_location').set({'name':'Current location','address':a,'latitude':pos.latitude,'longitude':pos.longitude,'isCurrent':true,'createdAt':FieldValue.serverTimestamp()},SetOptions(merge:true));if(mounted)setState(()=>location=a);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}finally{if(mounted)setState(()=>locating=false);}}
  List<String> get cats{final found=<String>{for(final p in widget.products)if(p.category.trim().isNotEmpty)p.category.trim()};final out=<String>[];for(final x in preferred)if(found.contains(x))out.add(x);out.addAll(found.where((x)=>!out.contains(x)).toList()..sort());return ['All',...out];}
  List<Product> byCat(String n)=>n=='All'?List<Product>.from(widget.products):widget.products.where((p)=>p.category.trim().toLowerCase()==n.trim().toLowerCase()).toList();
  void openCat(BuildContext c,String n)=>Navigator.push(c,MaterialPageRoute(builder:(_)=>CategoryProductsPage(category:n,products:byCat(n),onAdd:widget.onAdd,cart:widget.cart,onQty:widget.onQty,wishlistIds:widget.wishlistIds,onWishlist:widget.onWishlist)));
  Widget chip(BuildContext c,String n)=>InkWell(onTap:()=>openCat(c,n),child:SizedBox(width:72,child:Column(children:[Container(height:60,width:60,decoration:BoxDecoration(color:n=='All'?Theme.of(c).colorScheme.primaryContainer:Theme.of(c).colorScheme.surfaceContainerHighest,borderRadius:BorderRadius.circular(18)),alignment:Alignment.center,child:Text(icons[n]??'🛍️',style:const TextStyle(fontSize:28))),const SizedBox(height:4),Text(n,maxLines:1,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center,style:const TextStyle(fontSize:10,fontWeight:FontWeight.w700))])));
  Widget card(BuildContext c,Product p){
    final item=widget.cart[p.id];
    final liked=widget.wishlistIds.contains(p.id);
    return Card(
      margin:EdgeInsets.zero,
      clipBehavior:Clip.antiAlias,
      child:InkWell(
        onTap:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>ProductScreen(product:p,onAdd:()=>widget.onAdd(p),liked:liked,onWishlist:()=>widget.onWishlist(p)))),
        child:Padding(
          padding:const EdgeInsets.all(5),
          child:Column(
            crossAxisAlignment:CrossAxisAlignment.start,
            children:[
              Stack(children:[
                Container(height:72,width:double.infinity,alignment:Alignment.center,decoration:BoxDecoration(color:Theme.of(c).colorScheme.surfaceContainerHighest,borderRadius:BorderRadius.circular(11)),child:Text(p.icon,style:const TextStyle(fontSize:34))),
                Positioned(right:0,top:0,child:IconButton(visualDensity:VisualDensity.compact,padding:EdgeInsets.zero,constraints:const BoxConstraints(minWidth:28,minHeight:28),onPressed:()=>widget.onWishlist(p),icon:Icon(liked?Icons.favorite:Icons.favorite_border,color:Colors.red,size:18))),
              ]),
              const SizedBox(height:3),
              Text(p.name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w900)),
              Text(p.category,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.grey,fontSize:9)),
              Text('₹'+p.price.toString(),style:const TextStyle(fontSize:12,fontWeight:FontWeight.w900)),
              const Spacer(),
              if(item==null)
                SizedBox(height:27,width:double.infinity,child:FilledButton(style:FilledButton.styleFrom(padding:EdgeInsets.zero),onPressed:p.stock>0?()=>widget.onAdd(p):null,child:const Text('Add',style:TextStyle(fontSize:10))))
              else
                Container(
                  height:27,
                  decoration:BoxDecoration(border:Border.all(color:Theme.of(c).colorScheme.primary),borderRadius:BorderRadius.circular(14)),
                  child:Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[
                    InkWell(onTap:()=>widget.onQty(p.id,-1),child:const Icon(Icons.remove,size:14)),
                    Text(item.qty.toString(),style:const TextStyle(fontSize:10,fontWeight:FontWeight.w900)),
                    InkWell(onTap:()=>widget.onQty(p.id,1),child:const Icon(Icons.add,size:14)),
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget section(BuildContext c,String title,List<Product> items,bool all){
    if(items.isEmpty)return const SizedBox.shrink();
    final show=items.take(4).toList();
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[
        Expanded(child:Text(title,style:const TextStyle(fontSize:21,fontWeight:FontWeight.w900))),
        TextButton(onPressed:()=>openCat(c,all?'All':title),child:const Text('See all ›')),
      ]),
      GridView.builder(
        shrinkWrap:true,
        physics:const NeverScrollableScrollPhysics(),
        itemCount:show.length,
        gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:4,crossAxisSpacing:6,mainAxisSpacing:7,childAspectRatio:.52),
        itemBuilder:(context,i)=>card(context,show[i]),
      ),
      const SizedBox(height:14),
    ]);
  }

  @override
  Widget build(BuildContext c){
    final q=search.trim().toLowerCase();
    final searched=q.isEmpty?widget.products:widget.products.where((p)=>(p.name+' '+p.category+' '+p.brand+' '+p.description).toLowerCase().contains(q)).toList();
    final cs=cats;
    final sections=<String>[];
    for(final x in preferred){if(byCat(x).isNotEmpty)sections.add(x);}
    for(final x in cs.skip(1)){if(!sections.contains(x)&&byCat(x).isNotEmpty)sections.add(x);}
    return RefreshIndicator(
      onRefresh:()=>widget.onRefresh(),
      child:ListView(
        padding:const EdgeInsets.fromLTRB(12,0,12,110),
        children:[
          StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(
            stream:FirebaseFirestore.instance.collection('settings').doc('banners').snapshots(),
            builder:(context,s){
              final raw=s.data?.data()?['imageUrls'];
              final urls=raw is List?raw.map((e)=>e.toString()).where((e)=>e.isNotEmpty).take(3).toList():<String>[];
              final bg=urls.isEmpty?null:urls[bannerIndex%urls.length];
              return Container(
                padding:const EdgeInsets.fromLTRB(8,15,8,12),
                decoration:BoxDecoration(color:Theme.of(c).colorScheme.surface,image:bg==null?null:DecorationImage(image:NetworkImage(bg),fit:BoxFit.cover,colorFilter:ColorFilter.mode(Colors.black.withOpacity(.62),BlendMode.darken)),borderRadius:const BorderRadius.vertical(bottom:Radius.circular(24))),
                child:Column(children:[
                  Row(children:[
                    Expanded(child:RichText(text:const TextSpan(style:TextStyle(fontSize:31,fontWeight:FontWeight.w900),children:[TextSpan(text:'ALL',style:TextStyle(color:Color(0xFF9B7CFF))),TextSpan(text:'ways',style:TextStyle(color:Colors.white))]))),
                    ValueListenableBuilder<bool>(valueListenable:unreadNotificationNotifier,builder:(_,u,__)=>IconButton(onPressed:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const NotificationsPage())),icon:Badge(isLabelVisible:u,child:const Icon(Icons.notifications_none,color:Colors.white,size:28)))),
                    IconButton(onPressed:widget.onOpenCart,icon:Badge(isLabelVisible:widget.cart.isNotEmpty,label:Text(widget.cart.length.toString()),child:const Icon(Icons.shopping_cart_outlined,color:Colors.white,size:28))),
                  ]),
                  Align(alignment:Alignment.centerLeft,child:Text('Closer to You, Always',style:TextStyle(color:Colors.white.withOpacity(.82),fontSize:14))),
                  const SizedBox(height:8),
                  Card(color:Colors.black.withOpacity(.40),child:ListTile(leading:const Icon(Icons.location_on,color:Color(0xFFBFA6FF)),title:const Text('Deliver to',style:TextStyle(fontSize:11,color:Colors.white70)),subtitle:Text(location,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w800)),trailing:TextButton(onPressed:locating?null:changeLocation,child:const Text('Change')))),
                  const SizedBox(height:6),
                  TextField(controller:searchController,style:const TextStyle(color:Colors.white),decoration:InputDecoration(hintText:'Search for milk, bread, eggs…',hintStyle:const TextStyle(color:Colors.white70),prefixIcon:const Icon(Icons.search,color:Colors.white70),suffixIcon:IconButton(onPressed:listening?speech.stop:voice,icon:Icon(listening?Icons.mic:Icons.mic_none,color:listening?Colors.red:Colors.white)),filled:true,fillColor:Colors.black.withOpacity(.40),border:OutlineInputBorder(borderRadius:BorderRadius.circular(18),borderSide:BorderSide.none)),onChanged:(v)=>setState(()=>search=v)),
                ]),
              );
            },
          ),
          const SizedBox(height:4),
          SizedBox(height:88,child:ListView.separated(scrollDirection:Axis.horizontal,itemCount:cs.length,separatorBuilder:(_,__)=>const SizedBox(width:7),itemBuilder:(_,i)=>chip(c,cs[i]))),
          if(widget.loading)const Padding(padding:EdgeInsets.all(40),child:Center(child:CircularProgressIndicator()))
          else if(widget.error!=null)const InfoCard(title:'Could not load inventory',detail:'Check your connection and pull down to retry.')
          else if(searched.isEmpty)const InfoCard(title:'No items found',detail:'Try another search or category.')
          else ...[section(c,'Top Offers for You',searched.take(4).toList(),true),...sections.map((x)=>section(c,x,byCat(x),false))],
        ],
      ),
    );
  }
}

class CategoryProductsPage extends StatelessWidget{
  final String category;
  final List<Product> products;
  final void Function(Product) onAdd;
  final Map<String,CartItem> cart;
  final void Function(String,int) onQty;
  final Set<String> wishlistIds;
  final Future<void> Function(Product) onWishlist;
  const CategoryProductsPage({super.key,required this.category,required this.products,required this.onAdd,required this.cart,required this.onQty,required this.wishlistIds,required this.onWishlist});

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar:AppBar(title:Text(category)),
      body:products.isEmpty?const Center(child:Text('No products in this category yet.')):GridView.builder(
        padding:const EdgeInsets.all(12),
        itemCount:products.length,
        gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2,crossAxisSpacing:10,mainAxisSpacing:10,childAspectRatio:.62),
        itemBuilder:(context,i){
          final p=products[i],item=cart[p.id],liked=wishlistIds.contains(p.id);
          return Card(clipBehavior:Clip.antiAlias,child:Padding(padding:const EdgeInsets.all(9),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Stack(children:[
              Container(height:150,width:double.infinity,alignment:Alignment.center,decoration:BoxDecoration(color:Theme.of(context).colorScheme.surfaceContainerHighest,borderRadius:BorderRadius.circular(14)),child:Text(p.icon,style:const TextStyle(fontSize:60))),
              Positioned(right:0,top:0,child:IconButton(onPressed:()=>onWishlist(p),icon:Icon(liked?Icons.favorite:Icons.favorite_border,color:Colors.red))),
            ]),
            const SizedBox(height:7),
            Text(p.name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w900)),
            Text(p.category,style:const TextStyle(color:Colors.grey,fontSize:12)),
            Text('₹'+p.price.toString(),style:const TextStyle(fontSize:17,fontWeight:FontWeight.w900)),
            const Spacer(),
            if(item==null)
              SizedBox(width:double.infinity,height:38,child:FilledButton(onPressed:p.stock>0?()=>onAdd(p):null,child:const Text('Add')))
            else
              Container(height:38,decoration:BoxDecoration(border:Border.all(color:Theme.of(context).colorScheme.primary),borderRadius:BorderRadius.circular(20)),child:Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[
                IconButton(padding:EdgeInsets.zero,onPressed:()=>onQty(p.id,item.qty-1),icon:const Icon(Icons.remove,size:18)),
                Text(item.qty.toString(),style:const TextStyle(fontWeight:FontWeight.w900)),
                IconButton(padding:EdgeInsets.zero,onPressed:()=>onQty(p.id,item.qty+1),icon:const Icon(Icons.add,size:18)),
              ])),
          ])));
        },
      ),
    );
  }
}

class _AutoBannerCarousel extends StatefulWidget {
  final List<String> urls;
  final double height;
  const _AutoBannerCarousel({required this.urls, this.height = 165});
  @override State<_AutoBannerCarousel> createState() => _AutoBannerCarouselState();
}

class _AutoBannerCarouselState extends State<_AutoBannerCarousel> {
  late final PageController controller;
  Timer? timer;
  int index = 0;

  @override
  void initState() {
    super.initState();
    controller = PageController();
    _restartTimer();
  }

  void _restartTimer() {
    timer?.cancel();
    if (widget.urls.length > 1) {
      timer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted || !controller.hasClients) return;
        final next = (index + 1) % widget.urls.length;
        controller.animateToPage(next, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
      });
    }
  }

  @override
  void didUpdateWidget(covariant _AutoBannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.urls.length != oldWidget.urls.length) _restartTimer();
  }

  @override
  void dispose() {
    timer?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: widget.height,
        child: PageView.builder(
          controller: controller,
          itemCount: widget.urls.length,
          onPageChanged: (v) => setState(() => index = v),
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: LayoutBuilder(
                builder: (context, constraints) => Image.network(
                  cloudinaryImageUrl(widget.urls[i], width: constraints.maxWidth, height: widget.height),
                  fit: BoxFit.cover, width: double.infinity,
                  errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
          ),
        ),
      ),
      if (widget.urls.length > 1)
        Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.urls.length, (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: i == index ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
              ),
            )),
          ),
        ),
    ]);
  }
}

class ProductScreen extends StatelessWidget{
  final Product product; final VoidCallback onAdd; final bool liked; final VoidCallback onWishlist;
  const ProductScreen({super.key,required this.product,required this.onAdd,required this.liked,required this.onWishlist});
  @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:Text(product.name),actions:[IconButton(onPressed:onWishlist,icon:Icon(liked?Icons.favorite:Icons.favorite_border,color:Colors.red))]),body:ListView(padding:const EdgeInsets.all(20),children:[
    CircleAvatar(radius:54,child:Text(product.icon,style:const TextStyle(fontSize:44))),const SizedBox(height:20),
    Text(product.name,style:const TextStyle(fontSize:28,fontWeight:FontWeight.w900)),const SizedBox(height:8),Text(product.category,style:const TextStyle(color:Colors.grey)),
    if(product.brand.isNotEmpty)Text(product.brand,style:const TextStyle(color:Colors.grey)),const SizedBox(height:14),
    Text('₹'+product.price.toString(),style:const TextStyle(fontSize:24,fontWeight:FontWeight.w800)),const SizedBox(height:14),
    Text(product.description.isEmpty?'No description available.':product.description),const SizedBox(height:22),
    FilledButton.icon(onPressed:product.stock>0?onAdd:null,icon:const Icon(Icons.shopping_cart),label:Text(product.stock>0?'Add to cart':'Unavailable')),
  ]));
}

class CartScreen extends StatefulWidget{
  final Map<String,CartItem> cart;final List<Map<String,dynamic>> addresses;final void Function(String,int) onQty;final Future<void> Function(String,String,String,String,double?,double?) onPlace;
  const CartScreen({super.key,required this.cart,required this.addresses,required this.onQty,required this.onPlace});
  State<CartScreen> createState()=>_CartScreenState();
}
class _CartScreenState extends State<CartScreen>{
  final n=TextEditingController(),p=TextEditingController(),a=TextEditingController(),note=TextEditingController();bool placing=false,locating=false;double? selectedLatitude,selectedLongitude;
  @override void dispose(){n.dispose();p.dispose();a.dispose();note.dispose();super.dispose();}
  void use(Map<String,dynamic> x){n.text=(x['name']??'').toString();p.text=(x['phone']??'').toString();a.text=(x['address']??'').toString();selectedLatitude=(x['latitude'] as num?)?.toDouble();selectedLongitude=(x['longitude'] as num?)?.toDouble();setState((){});}
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
      selectedLatitude=pos.latitude;
      selectedLongitude=pos.longitude;
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
      const SizedBox(height:12),FilledButton(onPressed:placing?null:()async{setState(()=>placing=true);await widget.onPlace(n.text,p.text,a.text,note.text,selectedLatitude,selectedLongitude);if(mounted)setState(()=>placing=false);},child:Text(placing?'Placing order…':'Place COD Order'))
    ]));
  }
}

class OrdersPage extends StatelessWidget {
  final User? user;
  final Future<void> Function(String) onCancel; final Future<void> Function(List<Map<String,dynamic>>) onReorder;
  const OrdersPage({super.key, required this.user, required this.onCancel, required this.onReorder});

  DateTime _createdAt(Map<String, dynamic> o) {
    final value = o['createdAt'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    return DateTime.tryParse((o['time'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _dateTime(Map<String, dynamic> o) {
    final d = _createdAt(o);
    if (d.millisecondsSinceEpoch == 0) return 'Date unavailable';
    final hour = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    final minute = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return d.day.toString().padLeft(2, '0') + '/' + d.month.toString().padLeft(2, '0') + '/' + d.year.toString() + ' • ' + hour.toString() + ':' + minute + ' ' + ampm;
  }

  Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('delivered')) return Colors.green;
    if (s.contains('out for delivery') || s.contains('ready for pickup')) return Colors.orange;
    if (s.contains('cancel')) return Colors.red;
    if (s.contains('confirm') || s.contains('prepar')) return Colors.blue;
    return Colors.grey;
  }

  Widget _statusChip(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(status, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    if (user == null) return const InfoCard(title: 'Your orders', detail: 'Sign in to place and track your ALLways orders.');
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Your Orders', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('orders').where('customerId', isEqualTo: user!.uid).snapshots(),
        builder: (c, s) {
          if (s.hasError) return const InfoCard(title: 'Orders unavailable', detail: 'Please check your connection.');
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final docs = [...s.data!.docs]..sort((a, b) => _createdAt(b.data()).compareTo(_createdAt(a.data())));
          if (docs.isEmpty) return const Center(child: InfoCard(title: 'No orders yet', detail: 'Your placed orders will appear here.'));
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final d = docs[index];
              final o = d.data();
              final status = (o['status'] ?? 'New Order').toString();
              final canCancel = status == 'New Order' || status == 'Confirmed';
              final total = o['total'] is num ? (o['total'] as num).toDouble() : double.tryParse((o['total'] ?? 0).toString()) ?? 0;
              final rawItems = o['items'];
              final items = rawItems is List ? rawItems.map((x) => x is Map ? (x['name'].toString() + ' × ' + x['qty'].toString()) : x.toString()).join(', ') : '';
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  title: Row(
                    children: [
                      Expanded(child: Text('#' + (o['id'] ?? d.id).toString(), style: const TextStyle(fontWeight: FontWeight.w900))),
                      _statusChip(status),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_dateTime(o) + '\n₹' + total.toStringAsFixed(0), style: const TextStyle(color: Colors.grey)),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  children: [
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          StatusView(status: status),
                          if ((o['eta'] ?? o['estimatedDelivery'] ?? '').toString().isNotEmpty)
                            Card(margin: const EdgeInsets.only(top: 10, bottom: 8), child: ListTile(leading: const Icon(Icons.schedule), title: const Text('Estimated delivery', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: Text((o['eta'] ?? o['estimatedDelivery']).toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)))),
                          if ((o['customerMessage'] ?? o['statusNote'] ?? '').toString().isNotEmpty)
                            Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(leading: const Icon(Icons.message_outlined), title: const Text('Message from ALLways', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: Text((o['customerMessage'] ?? o['statusNote']).toString(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
                          Text(items),
                          const SizedBox(height: 6),
                          Text('Address: ' + (o['address'] ?? '').toString()),
                          if ((o['carrierUid'] ?? '').toString().isNotEmpty &&
                              (status.toLowerCase() == 'assigned' || status.toLowerCase() == 'picked up' || status.toLowerCase() == 'out for delivery'))
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: FilledButton.icon(
                                onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => LiveTrackingScreen(
                                  collection: 'orders',
                                  docId: d.id,
                                  title: 'Live order tracking',
                                  mode: 'order',
                                  broadcastPrefix: 'customer',
                                ))),
                                icon: const Icon(Icons.location_searching),
                                label: const Text('Track live'),
                              ),
                            ),
                          if (status.toLowerCase() == 'delivered' && rawItems is List)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: OutlinedButton.icon(
                                onPressed: () => onReorder(rawItems.whereType<Map>().map((x) => Map<String,dynamic>.from(x)).toList()),
                                icon: const Icon(Icons.replay),
                                label: const Text('Reorder'),
                              ),
                            ),
                          if ((o['cancellationReason'] ?? '').toString().isNotEmpty)
                            Padding(padding: const EdgeInsets.only(top: 8), child: Text('Cancellation reason: ' + o['cancellationReason'].toString())),
                          if (canCancel)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: OutlinedButton.icon(
                                onPressed: () => _confirmCancel(c, o['id']?.toString() ?? d.id, onCancel),
                                icon: const Icon(Icons.cancel_outlined),
                                label: const Text('Cancel order'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext c, String id, Future<void> Function(String) cancel) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: c,
      builder: (_) => AlertDialog(
        title: const Text('Cancel order?'),
        content: TextField(controller: reason, maxLines: 3, decoration: const InputDecoration(labelText: 'Reason for cancellation')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep order')),
          FilledButton(onPressed: () => Navigator.pop(c, reason.text.trim().isNotEmpty), child: const Text('Cancel order')),
        ],
      ),
    ) ?? false;
    final clean = reason.text.trim();
    reason.dispose();
    if (ok) await cancel(id + '||' + clean);
  }
}

class StatusView extends StatelessWidget{final String status;const StatusView({super.key,required this.status});Widget build(BuildContext c){
  const s=['New Order','Confirmed','Preparing','Out for delivery','Delivered'];final i=s.indexOf(status)<0?0:s.indexOf(status);
  return Column(children:[for(int x=0;x<s.length;x++)ListTile(dense:true,contentPadding:EdgeInsets.zero,leading:Icon(x<=i?Icons.check_circle:Icons.radio_button_unchecked,color:x<=i?Colors.green:Colors.grey),title:Text(s[x]))]);
}}


class TravelPage extends StatelessWidget {
  const TravelPage({super.key});
  Widget _actionCard(BuildContext context,{required IconData icon,required String title,required String subtitle,required VoidCallback onTap})=>Card(margin:const EdgeInsets.only(bottom:12),clipBehavior:Clip.antiAlias,child:InkWell(onTap:onTap,child:Padding(padding:const EdgeInsets.all(18),child:Row(children:[Container(width:54,height:54,decoration:BoxDecoration(color:Theme.of(context).colorScheme.primaryContainer,borderRadius:BorderRadius.circular(16)),child:Icon(icon,color:Theme.of(context).colorScheme.onPrimaryContainer)),const SizedBox(width:14),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900)),const SizedBox(height:5),Text(subtitle,style:TextStyle(color:Theme.of(context).colorScheme.onSurfaceVariant,height:1.35))])),const Icon(Icons.chevron_right)]))));
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.fromLTRB(16,18,16,110),children:[
    Text(tr('Travel'),style:const TextStyle(fontSize:30,fontWeight:FontWeight.w900)),
    const SizedBox(height:4),
    const Text('Book vehicles and connect with a two-wheeler ride partner.',style:TextStyle(color:Colors.grey)),
    const SizedBox(height:18),
    Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF311B92),Color(0xFFE91E63)],begin:Alignment.topLeft,end:Alignment.bottomRight),borderRadius:BorderRadius.circular(22)),child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(Icons.travel_explore,color:Colors.white,size:38),SizedBox(height:12),Text('ALLways Mobility',style:TextStyle(color:Colors.white,fontSize:24,fontWeight:FontWeight.w900)),SizedBox(height:6),Text('Local vehicle booking and two-wheeler ride sharing. No commission during the trial.',style:TextStyle(color:Colors.white70,height:1.4))])),
    const SizedBox(height:18),
    _actionCard(context,icon:Icons.directions_car_outlined,title:tr('Book vehicle'),subtitle:'Choose from 25 vehicle categories. Owners set their own price, with Book or Book & negotiate.',onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const VehicleBookingPage()))),
    _actionCard(context,icon:Icons.two_wheeler_outlined,title:'Book a Ride',subtitle:'Book a two-wheeler ride partner for your journey. Pickup is from the main road.',onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const RidePartnerPage()))),
    Card(child:Padding(padding:const EdgeInsets.all(16),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[const Icon(Icons.info_outline),const SizedBox(width:10),Expanded(child:Text('Trial service: verify the partner and vehicle before travelling. ALLways is not currently responsible for conduct, safety, vehicle condition, payment, loss, injury or disputes between ride participants.',style:TextStyle(color:Colors.grey,height:1.35)))]))),
  ]);
}

class ProfilePage extends StatefulWidget{
  final User? user; final List<Map<String,dynamic>> addresses; final VoidCallback onLogin;
  final Future<void> Function() onReload; final Future<void> Function(String) onDelete; final Future<void> Function(String) onCancel; final Future<void> Function(List<Map<String,dynamic>>) onReorder;
  const ProfilePage({super.key,required this.user,required this.addresses,required this.onLogin,required this.onReload,required this.onDelete,required this.onCancel,required this.onReorder});
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

  Widget _menuCard(BuildContext c,{required IconData icon,required String title,required String subtitle,required VoidCallback onTap,bool danger=false,bool showDot=false}){
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
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Icon(icon,color:danger?scheme.onErrorContainer:scheme.onPrimaryContainer),
                if(showDot) Positioned(right:-3,top:-3,child:Container(width:10,height:10,decoration:BoxDecoration(color:Colors.green,shape:BoxShape.circle,border:Border.all(color:scheme.surface,width:2)))),
              ]),
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
  // Language preference is reactive through languageNotifier so visible labels update immediately.
  Future<void> _chooseLanguage(BuildContext c) async {
    final prefs=await SharedPreferences.getInstance();
    final current=prefs.getString('allways_language')??'English';
    const languages=['English','Hindi','Hinglish','Bhojpuri','Awadhi'];
    await showDialog<void>(
      context:c,
      builder:(dialogContext)=>AlertDialog(
        title:const Text('Language'),
        content:Column(mainAxisSize:MainAxisSize.min,children:[
          for(final language in languages)
            RadioListTile<String>(
              value:language,
              groupValue:current,
              title:Text(language),
              onChanged:(value) async {
                if(value==null)return;
                await prefs.setString('allways_language',value);
                languageNotifier.value=value;
                if(dialogContext.mounted)Navigator.pop(dialogContext);
                if(c.mounted)ScaffoldMessenger.of(c).showSnackBar(SnackBar(content:Text('Language preference saved: '+value)));
              },
            ),
        ]),
      ),
    );
  }

  Future<void> _openNotifications(BuildContext c) async {
    await markNotificationsRead();
    if(!c.mounted)return;
    await showModalBottomSheet<void>(context:c,isScrollControlled:true,showDragHandle:true,builder:(_)=>const NotificationsPage());
  }

  @override Widget build(BuildContext c){
    final u=widget.user;
    if(u==null)return Center(child:FilledButton(onPressed:widget.onLogin,child:const Text('Sign in / Sign up')));
    return ListView(
      padding:const EdgeInsets.only(top:12,bottom:24),
      children:[
        Padding(padding:const EdgeInsets.fromLTRB(16,0,16,6),child:Text(tr('Profile'),style:const TextStyle(fontSize:28,fontWeight:FontWeight.w900))),
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
        _menuCard(c,icon:Icons.receipt_long_outlined,title:'Orders',subtitle:'View and track your ALLways orders',onTap:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>OrdersPage(user:u,onCancel:widget.onCancel,onReorder:widget.onReorder)))),
        _menuCard(c,icon:Icons.location_on_outlined,title:'Saved Addresses',subtitle:'Add, edit or manage your delivery addresses',onTap:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>SavedAddressesPage(userId:u.uid,addresses:widget.addresses,onReload:widget.onReload,onDelete:widget.onDelete)))),
        _menuCard(c,icon:Icons.favorite_border,title:'Wishlist',subtitle:'Your saved products and favourites',onTap:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const WishlistPage()))),
        _menuCard(c,icon:Icons.local_shipping_outlined,title:'ALLways Carrier',subtitle:'Become a Seller or Delivery Partner',onTap:()=>_openCarrier(c,u)),
        ValueListenableBuilder<bool>(valueListenable:unreadNotificationNotifier,builder:(_,unread,__)=>_menuCard(c,icon:Icons.notifications_outlined,title:tr('Notifications'),subtitle:'Alerts, order updates and push settings',showDot:unread,onTap:()=>_openNotifications(c))),
        _menuCard(c,icon:Icons.brightness_6_outlined,title:tr('Appearance'),subtitle:'Light, Dark or System theme',onTap:()=>_chooseAppearance(c)),
        _menuCard(c,icon:Icons.language_outlined,title:tr('Language'),subtitle:'Choose your preferred app language',onTap:()=>_chooseLanguage(c)),
        _menuCard(c,icon:Icons.share_outlined,title:tr('Share ALLways'),subtitle:'Share ALLways with friends and family',onTap:()=>SharePlus.instance.share(ShareParams(text:'Try ALLways — Closer to You, Always. Download ALLways 1.4.7: '+shareApkUrl))),
        _menuCard(c,icon:Icons.system_update_outlined,title:tr('Check for Updates'),subtitle:'Check for the latest ALLways version',onTap:()=>_checkForUpdate(c)),
        _menuCard(c,icon:Icons.privacy_tip_outlined,title:'Privacy Policy',subtitle:'How ALLways handles your information',onTap:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const PrivacyPolicyPage()))),
        _menuCard(c,icon:Icons.logout_outlined,title:tr('Log Out'),subtitle:'Sign out of your ALLways account',danger:true,onTap:()=>FirebaseAuth.instance.signOut()),
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

Future<void> markNotificationsRead() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('allways_notifications') ?? <String>[];
    final updated = raw.map((entry) {
      try {
        final decoded = jsonDecode(entry);
        if (decoded is Map) {
          final item = Map<String,dynamic>.from(decoded);
          item['read'] = true;
          return jsonEncode(item);
        }
      } catch (_) {}
      return entry;
    }).toList();
    await prefs.setStringList('allways_notifications', updated);
  } catch (_) {}
  unreadNotificationNotifier.value = false;
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
      if(value){
        final status=await FirebaseMessaging.instance.requestPermission(alert:true,badge:true,sound:true,provisional:false);
        if(status.authorizationStatus==AuthorizationStatus.denied){if(mounted)setState(()=>enabled=false);await prefs.setBool('allways_notifications_enabled',false);return;}
        await FirebaseMessaging.instance.subscribeToTopic('all_users');
        await prefs.setBool('allways_notifications_enabled',true);
        final token=await FirebaseMessaging.instance.getToken();
        final u=FirebaseAuth.instance.currentUser;
        if(token!=null&&u!=null){
          await FirebaseFirestore.instance.collection('fcmTokens').doc(u.uid).set({'uid':u.uid,'email':u.email??'','token':token,'notificationsEnabled':true,'updatedAt':FieldValue.serverTimestamp()},SetOptions(merge:true));
          await prefs.setString('allways_fcm_token',token);
        }
      }else{
        await FirebaseMessaging.instance.unsubscribeFromTopic('all_users');
        await prefs.setBool('allways_notifications_enabled',false);
        final u=FirebaseAuth.instance.currentUser;
        if(u!=null){try{await FirebaseFirestore.instance.collection('fcmTokens').doc(u.uid).set({'uid':u.uid,'notificationsEnabled':false,'updatedAt':FieldValue.serverTimestamp()},SetOptions(merge:true));}catch(_){}}
      }
    }catch(_){if(mounted)setState(()=>enabled=!value);}
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
  @override State<CarrierApplicationDialog> createState() => _CarrierApplicationDialogState();
}

class _CarrierApplicationDialogState extends State<CarrierApplicationDialog> {
  final fullName = TextEditingController();
  final shopName = TextEditingController();
  final dob = TextEditingController();
  final mobileNumber = TextEditingController();
  final locationAddress = TextEditingController();
  XFile? photo;
  XFile? bikePhoto;
  bool busy = false;
  bool locating = false;
  String? category;
  double? latitude;
  double? longitude;
  bool get seller => widget.type == 'seller';

  @override void dispose() {
    fullName.dispose(); shopName.dispose(); dob.dispose(); mobileNumber.dispose(); locationAddress.dispose(); super.dispose();
  }

  Future<void> pickPhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 600);
    if (x != null && mounted) setState(() => photo = x);
  }

  Future<void> pickBikePhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 600);
    if (x != null && mounted) setState(() => bikePhoto = x);
  }

  Future<void> useCurrentLocation() async {
    setState(() => locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) throw Exception('Location permission was not granted.');
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      latitude = position.latitude;
      longitude = position.longitude;
      try {
        final marks = await placemarkFromCoordinates(position.latitude, position.longitude);
        if (marks.isNotEmpty) {
          final p = marks.first;
          locationAddress.text = [p.name, p.subLocality, p.locality, p.subAdministrativeArea, p.administrativeArea, p.postalCode]
              .where((x) => x != null && x.trim().isNotEmpty).join(', ');
        }
      } catch (_) {}
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not get current location: ' + e.toString())));
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> submit() async {
    final mobile = mobileNumber.text.trim().replaceAll(RegExp(r'\D'), '');
    if (fullName.text.trim().isEmpty || mobile.length != 10 || photo == null ||
        (seller && (shopName.text.trim().isEmpty || category == null || locationAddress.text.trim().isEmpty || latitude == null || longitude == null)) ||
        (!seller && (dob.text.trim().isEmpty || bikePhoto == null))) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(seller
        ? 'Full name, mobile, shop name, category, current location and shop photo are required.'
        : 'Full name, mobile number, DOB, bike/number plate photo and a photo with your bike are required.')));
      return;
    }
    setState(() => busy = true);
    try {
      final url = await uploadImageToCloudinary(photo!, folder: 'onboarding/' + widget.user.uid);
      final data = <String, dynamic>{
        'uid': widget.user.uid, 'email': widget.user.email ?? '', 'type': widget.type,
        'fullName': fullName.text.trim(), 'mobileNumber': mobile, 'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      };
      if (seller) {
        data['shopName'] = shopName.text.trim();
        data['category'] = category!;
        data['photoUrl'] = url;
        data['locationAddress'] = locationAddress.text.trim();
        data['latitude'] = latitude;
        data['longitude'] = longitude;
      } else {
        final bikeUrl = await uploadImageToCloudinary(bikePhoto!, folder: 'onboarding/' + widget.user.uid);
        data['dob'] = dob.text.trim();
        data['photoUrl'] = url;
        data['bikePhotoUrl'] = bikeUrl;
      }
      await FirebaseFirestore.instance.collection('onboarding_requests').add(data);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(seller ? 'Seller request submitted.' : 'Delivery partner request submitted.')));
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: fullName, decoration: const InputDecoration(labelText: 'Full name')),
          const SizedBox(height: 10),
          TextFormField(controller: mobileNumber, keyboardType: TextInputType.phone, maxLength: 10, decoration: const InputDecoration(labelText: 'Mobile Number', counterText: '')),
          if (seller) ...[
            const SizedBox(height: 10),
            TextField(controller: shopName, decoration: const InputDecoration(labelText: 'Shop name')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Shop category'),
              items: sellerCategories.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
              onChanged: busy ? null : (v) => setState(() => category = v),
            ),
            const SizedBox(height: 10),
            TextField(controller: locationAddress, maxLines: 2, decoration: const InputDecoration(labelText: 'Shop location')),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: busy || locating ? null : useCurrentLocation,
              icon: locating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location),
              label: Text(locating ? 'Getting exact location…' : 'Use current location'),
            )),
            if (latitude != null && longitude != null)
              Align(alignment: Alignment.centerLeft, child: Text('Exact GPS saved: ' + latitude!.toStringAsFixed(6) + ', ' + longitude!.toStringAsFixed(6), style: const TextStyle(fontSize: 12, color: Colors.grey))),
          ],
          if (!seller) ...[
            const SizedBox(height: 10),
            TextField(controller: dob, decoration: const InputDecoration(labelText: 'Date of birth (DD/MM/YYYY)')),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: busy ? null : pickPhoto, icon: const Icon(Icons.photo_camera), label: Text(photo == null ? (seller ? 'Upload shop photo' : 'Upload bike/number plate photo') : 'Photo selected')),
          if (!seller) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: busy ? null : pickBikePhoto, icon: const Icon(Icons.two_wheeler_outlined), label: Text(bikePhoto == null ? 'Upload a photo with your bike' : 'Bike photo selected')),
          ],
        ]),
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
  @override State<SellerDashboard> createState() => _SellerDashboardState();
}

class _SellerDashboardState extends State<SellerDashboard> {
  final description = TextEditingController();
  final about = TextEditingController();
  String ownerName = '';
  final offers = TextEditingController();
  final openingHours = TextEditingController();
  List<Map<String, dynamic>> items = [];
  bool saving = false;
  String photoUrl = '';
  String businessName = '';
  String mobileNumber = '';
  String alternateMobileNumber = '';
  String locationAddress = '';
  bool? isOpen;
bool autoAssign = false;
bool loadingAssignmentMode = true;

  @override void initState() { super.initState(); loadSeller(); }

  @override void dispose() {
    description.dispose(); about.dispose(); offers.dispose(); openingHours.dispose(); super.dispose();
  }

  Future<void> loadSeller() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('sellers').doc(widget.user.uid).get();
      final data = snap.data() ?? {};
      ownerName = (data['name'] ?? widget.user.displayName ?? '').toString();
      description.text = (data['description'] ?? '').toString();
      about.text = (data['about'] ?? '').toString();
      offers.text = (data['dailyOffers'] ?? '').toString();
      openingHours.text = (data['openingHours'] ?? '').toString();
      photoUrl = (data['photoUrl'] ?? '').toString();
      businessName = (data['businessName'] ?? data['name'] ?? widget.user.displayName ?? 'My Shop').toString();
      mobileNumber = (data['mobileNumber'] ?? '').toString();
      alternateMobileNumber = (data['alternateMobileNumber'] ?? '').toString();
      locationAddress = (data['locationAddress'] ?? '').toString();
      isOpen = data['isOpen'] is bool ? data['isOpen'] as bool : null;
autoAssign = (data['assignment_mode'] ?? 'manual').toString().toLowerCase() == 'auto';
loadingAssignmentMode = false;
      final raw = data['items'];
      if (raw is List) items = raw.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).take(50).toList();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<String> uploadItemImage(XFile image) async => uploadImageToCloudinary(image, folder: 'sellers/' + widget.user.uid);

  Future<void> editSellerProfile() async {
    final owner = TextEditingController(text: ownerName);
    final shop = TextEditingController(text: businessName);
    final mobile = TextEditingController(text: mobileNumber);
    final alternateMobile = TextEditingController(text: alternateMobileNumber);
    XFile? selectedImage;
    bool uploading = false;
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Edit seller profile'),
            content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              OutlinedButton.icon(
                onPressed: uploading ? null : () async {
                  final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 600);
                  if (image != null) setDialogState(() => selectedImage = image);
                },
                icon: const Icon(Icons.camera_alt),
                label: Text(selectedImage == null ? 'Update Shop Photo' : 'New shop photo selected'),
              ),
              const SizedBox(height: 12),
              TextField(controller: owner, decoration: const InputDecoration(labelText: 'Your name')),
              const SizedBox(height: 10),
              TextFormField(controller: mobile, keyboardType: TextInputType.phone, maxLength: 10, decoration: const InputDecoration(labelText: 'Mobile Number', counterText: '')),
              const SizedBox(height: 10),
              TextFormField(controller: alternateMobile, keyboardType: TextInputType.phone, maxLength: 10, decoration: const InputDecoration(labelText: 'Alternate Mobile Number (optional)', counterText: '')),
              const SizedBox(height: 10),
              TextField(controller: shop, decoration: const InputDecoration(labelText: 'Shop name')),
              const SizedBox(height: 12),
              const Align(alignment: Alignment.centerLeft, child: Text('Update your name, shop name and the shop image customers see.', style: TextStyle(color: Colors.grey, fontSize: 12))),
            ])),
            actions: [
              TextButton(onPressed: uploading ? null : () => Navigator.pop(dialog, false), child: const Text('Cancel')),
              FilledButton(onPressed: uploading ? null : () async {
                if (owner.text.trim().isEmpty || shop.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter your name and shop name.')));
                  return;
                }
                setDialogState(() => uploading = true);
                try {
                  final cleanMobile = mobile.text.replaceAll(RegExp(r'\D'),'');
                  final cleanAlternate = alternateMobile.text.replaceAll(RegExp(r'\D'),'');
                  if (cleanMobile.length != 10 || (cleanAlternate.isNotEmpty && cleanAlternate.length != 10)) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid 10-digit mobile number.')));
                    setDialogState(() => uploading = false);
                    return;
                  }
                  var newPhoto = photoUrl;
                  if (selectedImage != null) {
                    final rawPhoto = await uploadImageToCloudinary(selectedImage!, folder: 'sellers/' + widget.user.uid);
                    newPhoto = cloudinarySmartCropUrl(rawPhoto);
                  }
                  await widget.user.updateDisplayName(owner.text.trim());
                  await FirebaseFirestore.instance.collection('sellers').doc(widget.user.uid).set({
                    'uid':widget.user.uid,'name':owner.text.trim(),'businessName':shop.text.trim(),
                    'photoUrl':newPhoto,'mobileNumber':cleanMobile,'alternateMobileNumber':cleanAlternate,
                    'updatedAt':FieldValue.serverTimestamp()
                  },SetOptions(merge:true));
                  ownerName = owner.text.trim(); businessName = shop.text.trim(); photoUrl = newPhoto; mobileNumber = cleanMobile;
                  if (mounted) setState(() {});
                  if (dialog.mounted) Navigator.pop(dialog, true);
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update seller profile: ' + e.toString())));
                  if (dialog.mounted) setDialogState(() => uploading = false);
                }
              }, child: Text(uploading ? 'Saving…' : 'Save changes')),
            ],
          ),
        ),
      );
      if (saved == true && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seller profile updated.')));
    } finally { owner.dispose(); shop.dispose(); mobile.dispose(); alternateMobile.dispose(); }
  }

  Future<void> _setAssignmentMode(bool value) async {
    setState(()=>autoAssign=value);
    try{
      await FirebaseFirestore.instance.collection('sellers').doc(widget.user.uid).set({
        'assignment_mode':value?'auto':'manual',
        'assignmentModeUpdatedAt':FieldValue.serverTimestamp(),
      },SetOptions(merge:true));
    }catch(e){
      if(mounted){
        setState(()=>autoAssign=!value);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not save assignment mode: '+e.toString())));
      }
    }
  }

  Future<void> pickServiceHours() async {
    final start = TimeOfDay(hour: 9, minute: 0);
    final end = TimeOfDay(hour: 21, minute: 0);
    final chosenStart = await showTimePicker(context: context, initialTime: start, helpText: 'Opening time');
    if (!mounted || chosenStart == null) return;
    final chosenEnd = await showTimePicker(context: context, initialTime: end, helpText: 'Closing time');
    if (!mounted || chosenEnd == null) return;
    final startText = chosenStart.format(context);
    final endText = chosenEnd.format(context);
    setState(() => openingHours.text = '$startText - $endText');
  }

  Future<void> saveSellerRealtime() async {
    try {
      await FirebaseFirestore.instance.collection('sellers').doc(widget.user.uid).set({
        'uid': widget.user.uid, 'name': ownerName, 'businessName': businessName, 'description': description.text.trim(),
        'about': about.text.trim(), 'dailyOffers': offers.text.trim(), 'openingHours': openingHours.text.trim(),
        'isOpen': isOpen, 'mobileNumber': mobileNumber, 'alternateMobileNumber': alternateMobileNumber, 'assignment_mode': autoAssign ? 'auto' : 'manual', 'items': items.take(50).toList(), 'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> addItem() async {
    if (items.length >= 50) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You can list up to 50 items.')));
      return;
    }
    final name = TextEditingController();
    final price = TextEditingController();
    final itemDescription = TextEditingController();
    final itemAbout = TextEditingController();
    String? category;
    XFile? image;

    final added = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add catalogue item'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Item name')),
              const SizedBox(height: 10),
              TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Price (optional)')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: sellerCategories.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
                onChanged: (v) => setDialogState(() => category = v),
              ),
              const SizedBox(height: 10),
              TextField(controller: itemDescription, maxLines: 3, decoration: const InputDecoration(labelText: 'Product description')),
              const SizedBox(height: 10),
              TextField(controller: itemAbout, maxLines: 3, decoration: const InputDecoration(labelText: 'About this product')),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 600);
                  if (x != null) setDialogState(() => image = x);
                },
                icon: const Icon(Icons.image_outlined),
                label: Text(image == null ? 'Choose product image' : 'Image selected'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final parsed = price.text.trim().isEmpty ? null : num.tryParse(price.text.trim());
                if (name.text.trim().isEmpty || image == null || (price.text.trim().isNotEmpty && (parsed == null || parsed < 0))) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item name and image are required.')));
                  return;
                }
                try {
                  final url = await uploadItemImage(image!);
                  if (!mounted) return;
                  setState(() => items.add({'name': name.text.trim(), 'price': parsed, 'category': category ?? 'Other', 'description': itemDescription.text.trim(), 'about': itemAbout.text.trim(), 'imageUrl': url}));
                  Navigator.pop(dialog, true);
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Image upload failed: ' + e.toString())));
                }
              },
              child: const Text('Add item'),
            ),
          ],
        ),
      ),
    );
    name.dispose(); price.dispose(); itemDescription.dispose(); itemAbout.dispose();
    if (added == true && mounted) { setState(() {}); await saveSellerRealtime(); }
  }

  Future<void> saveSeller() async {
    setState(() => saving = true);
    try {
      await FirebaseFirestore.instance.collection('sellers').doc(widget.user.uid).set({
        'uid': widget.user.uid, 'name': widget.user.displayName ?? '', 'businessName': businessName,
        'photoUrl': photoUrl, 'mobileNumber': mobileNumber, 'alternateMobileNumber': alternateMobileNumber, 'locationAddress': locationAddress,
        'description': description.text.trim(), 'about': about.text.trim(), 'dailyOffers': offers.text.trim(),
        'openingHours': openingHours.text.trim(), 'isOpen': isOpen, 'assignment_mode': autoAssign ? 'auto' : 'manual', 'items': items.take(50).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seller profile saved.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save seller profile: ' + e.toString())));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ExpansionTile(
        leading: CircleAvatar(backgroundImage: photoUrl.isEmpty ? null : NetworkImage(cloudinaryImageUrl(photoUrl, width: 56, height: 56)), child: photoUrl.isEmpty ? const Icon(Icons.storefront) : null),
        title: Text(businessName.isEmpty ? 'Seller Dashboard' : businessName, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('✓ Verified seller • ' + items.length.toString() + '/50 catalogue items'),
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (photoUrl.isNotEmpty) ClipRRect(borderRadius: BorderRadius.circular(16), child: LayoutBuilder(builder: (context, constraints) => Image.network(cloudinaryImageUrl(photoUrl, width: constraints.maxWidth, height: 170), height: 170, width: double.infinity, fit: BoxFit.cover))),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: saving ? null : editSellerProfile, icon: const Icon(Icons.edit_outlined), label: const Text('Edit seller profile, name & shop image')),
              const SizedBox(height: 8),
              TextField(controller: description, maxLines: 3, decoration: const InputDecoration(labelText: 'Shop description')),
              const SizedBox(height: 10),
              TextField(controller: about, maxLines: 3, decoration: const InputDecoration(labelText: 'About your shop')),
              const SizedBox(height: 10),
              TextField(controller: offers, maxLines: 2, decoration: const InputDecoration(labelText: 'Daily offers')),
              const SizedBox(height: 10),
              Row(children:[Expanded(child:TextField(controller: openingHours, readOnly:true, decoration:const InputDecoration(labelText:'Service hours'))),const SizedBox(width:8),IconButton(tooltip:'Choose service hours',onPressed:pickServiceHours,icon:const Icon(Icons.schedule))]),
              const SizedBox(height: 6),
              SegmentedButton<bool?>(
                segments: const [ButtonSegment<bool?>(value: true, label: Text('Open')), ButtonSegment<bool?>(value: false, label: Text('Closed'))],
                selected: isOpen == null ? <bool?>{} : <bool?>{isOpen},
                onSelectionChanged: (v) => setState(() => isOpen = v.isEmpty ? null : v.first),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: SwitchListTile(
                  title: const Text('Automatic Delivery Assignment', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(autoAssign ? 'Auto — available delivery partners are assigned automatically.' : 'Manual — admin assigns delivery partners.'),
                  value: autoAssign,
                  onChanged: loadingAssignmentMode ? null : _setAssignmentMode,
                ),
              ),
              if (locationAddress.isNotEmpty) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.location_on_outlined), title: const Text('Shop location'), subtitle: Text(locationAddress)),
              const SizedBox(height: 12),
              Text('Catalogue (' + items.length.toString() + '/50)', style: const TextStyle(fontWeight: FontWeight.w800)),
              ...items.asMap().entries.map((entry) {
                final item = entry.value;
                return Card(child: ListTile(
                  leading: (item['imageUrl'] ?? '').toString().isEmpty ? const Icon(Icons.inventory_2_outlined) : Image.network(cloudinaryImageUrl(item['imageUrl'].toString(), width: 48, height: 48), width: 48, height: 48, fit: BoxFit.cover),
                  title: Text((item['name'] ?? '').toString()),
                  subtitle: Text([
                    if ((item['category'] ?? '').toString().isNotEmpty) item['category'].toString(),
                    if (item['price'] != null) '₹' + item['price'].toString(),
                    if ((item['description'] ?? '').toString().isNotEmpty) item['description'].toString(),
                  ].join(' • ')),
                  trailing: IconButton(onPressed: () async { setState(() => items.removeAt(entry.key)); await saveSellerRealtime(); }, icon: const Icon(Icons.delete_outline)),
                ));
              }),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: items.length >= 50 ? null : addItem, icon: const Icon(Icons.add), label: const Text('Add catalogue item')),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: saving ? null : saveSeller, child: Text(saving ? 'Saving…' : 'Save seller profile'))),
            ]),
          ),
        ],
      ),
    );
  }
}


class CarrierDashboard extends StatefulWidget {
  final User user;
  const CarrierDashboard({super.key, required this.user});

  @override
  State<CarrierDashboard> createState() => _CarrierDashboardState();
}

class _CarrierDashboardState extends State<CarrierDashboard> {
  bool online = false;
  bool loadingDuty = true;
  StreamSubscription<QuerySnapshot<Map<String,dynamic>>>? _carrierOrderSubscription;
  LiveLocationBroadcaster? _carrierLocationBroadcaster;
  String? _broadcastingOrderId;

  @override
  void initState() {
    super.initState();
    _loadDutyStatus();
    _carrierOrderSubscription=FirebaseFirestore.instance.collection('orders').where('carrierUid',isEqualTo:widget.user.uid).snapshots().listen((snapshot) async {
      QueryDocumentSnapshot<Map<String,dynamic>>? active;
      for(final d in snapshot.docs){
        final status=(d.data()['status']??'').toString().toLowerCase();
        if(status=='assigned'||status=='picked up'||status=='out for delivery'){active=d;break;}
      }
      if(active==null){
        await _carrierLocationBroadcaster?.stop();
        _carrierLocationBroadcaster=null;
        _broadcastingOrderId=null;
        return;
      }
      if(_broadcastingOrderId==active.id)return;
      await _carrierLocationBroadcaster?.stop();
      final broadcaster=LiveLocationBroadcaster();
      final started=await broadcaster.start(collection:'orders',docId:active.id,prefix:'carrier');
      if(started){_carrierLocationBroadcaster=broadcaster;_broadcastingOrderId=active.id;}
    });
  }

  @override
  void dispose() {
    _carrierOrderSubscription?.cancel();
    _carrierLocationBroadcaster?.stop();
    super.dispose();
  }

  Future<void> _loadDutyStatus() async {
    try {
      final customer = await FirebaseFirestore.instance.collection('customers').doc(widget.user.uid).get();
      final customerData = customer.data();
      if (customerData != null && customerData['dutyStatus'] != null) {
        if (mounted) setState(() {
          online = (customerData['dutyStatus'] ?? 'offline').toString().toLowerCase() == 'online';
          loadingDuty = false;
        });
        return;
      }
      final doc = await FirebaseFirestore.instance.collection('onboarding_requests').where('uid', isEqualTo: widget.user.uid).where('type', isEqualTo: 'carrier').limit(1).get();
      if (doc.docs.isNotEmpty && mounted) {
        final value=(doc.docs.first.data()['dutyStatus'] ?? 'offline').toString().toLowerCase();
        setState(() {
          online = value == 'online';
          loadingDuty = false;
        });
        await FirebaseFirestore.instance.collection('customers').doc(widget.user.uid).set({
          'dutyStatus':value,
          'deliveryAvailable':value=='online',
          'updatedAt':FieldValue.serverTimestamp(),
        },SetOptions(merge:true));
      } else if (mounted) {
        setState(() => loadingDuty = false);
      }
    } catch (_) {
      if (mounted) setState(() => loadingDuty = false);
    }
  }

  Future<void> _setDutyStatus(bool value) async {
    final next=value?'online':'offline';
    setState(() => online=value);
    try {
      await FirebaseFirestore.instance.collection('customers').doc(widget.user.uid).set({
        'dutyStatus':next,
        'deliveryAvailable':value,
        'statusUpdatedAt':FieldValue.serverTimestamp(),
        'updatedAt':FieldValue.serverTimestamp(),
      },SetOptions(merge:true));
      final doc = await FirebaseFirestore.instance.collection('onboarding_requests').where('uid', isEqualTo: widget.user.uid).where('type', isEqualTo: 'carrier').limit(1).get();
      if (doc.docs.isNotEmpty) {
        await doc.docs.first.reference.update({
          'dutyStatus': next,
          'dutyStatusUpdatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => online = !value);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update duty status.')));
      }
    }
  }

  Future<void> openMaps(BuildContext context, String address) async {
    if (address.trim().isEmpty) return;
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=' + Uri.encodeComponent(address));
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open Google Maps.')));
    }
  }

  num _number(dynamic value) => value is num ? value : num.tryParse(value.toString()) ?? 0;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: Stack(
          alignment: Alignment.bottomRight,
          children: [
            const Icon(Icons.delivery_dining),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: online ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).cardColor, width: 2),
              ),
            ),
          ],
        ),
        title: Row(
          children: [
            const Expanded(child: Text('Carrier Dashboard', style: TextStyle(fontWeight: FontWeight.w800))),
            Container(width: 8, height: 8, decoration: BoxDecoration(color: online ? Colors.green : Colors.grey, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(online ? 'Online' : 'Offline', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: online ? Colors.green : Colors.grey)),
          ],
        ),
        subtitle: Text(online ? 'Duty Status: Online' : 'Duty Status: Offline'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  child: SwitchListTile(
                    title: const Text('Duty Status', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(online ? 'Online — ready for pickup requests' : 'Offline — you will not receive new pickup requests'),
                    value: online,
                    onChanged: loadingDuty ? null : _setDutyStatus,
                  ),
                ),
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerLeft, child: Text('Service Partner', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                const SizedBox(height: 8),
                Row(children:[
                  Expanded(child:OutlinedButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const VehicleBookingPage())),icon:const Icon(Icons.directions_car_outlined),label:const Text('Book vehicle'))),
                  const SizedBox(width:10),
                  Expanded(child:OutlinedButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const RidePartnerPage())),icon:const Icon(Icons.two_wheeler_outlined),label:const Text('Book a Ride'))),
                ]),
                const SizedBox(height: 6),
                const Text('Service Partner includes vehicle booking and two-wheeler ride sharing. Contact details unlock only after a confirmed booking.',style:TextStyle(color:Colors.grey,fontSize:12)),
                const SizedBox(height:14),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('orders').where('carrierUid', isEqualTo: widget.user.uid).snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox(height: 88, child: Center(child: CircularProgressIndicator()));
                    num earnings = 0;
                    int completed = 0;
                    final now = DateTime.now();
                    for (final d in snapshot.data!.docs) {
                      final o = d.data();
                      final created = o['createdAt'];
                      DateTime? orderDate;
                      if (created is Timestamp) {
                        orderDate = created.toDate();
                      } else if (created is num) {
                        orderDate = DateTime.fromMillisecondsSinceEpoch(created.toInt());
                      } else {
                        orderDate = DateTime.tryParse((o['time'] ?? '').toString());
                      }
                      final isToday = orderDate != null && orderDate.year == now.year && orderDate.month == now.month && orderDate.day == now.day;
                      if (isToday && (o['status'] ?? '').toString().toLowerCase() == 'delivered') {
                        completed++;
                        earnings += _number(o['carrierEarnings'] ?? o['deliveryFee'] ?? 0);
                      }
                    }
                    return Row(
                      children: [
                        Expanded(child: _carrierStat(context, 'Today\'s Earnings', '₹' + earnings.toStringAsFixed(0), Icons.currency_rupee)),
                        const SizedBox(width: 10),
                        Expanded(child: _carrierStat(context, 'Completed Deliveries', completed.toString(), Icons.check_circle_outline)),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),

                StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
                  stream:FirebaseFirestore.instance.collection('orders').where('carrierUid',isEqualTo:widget.user.uid).snapshots(),
                  builder:(context,snapshot){
                    final pending=(snapshot.data?.docs??const <QueryDocumentSnapshot<Map<String,dynamic>>>[]).where((d)=>(d.data()['status']??'').toString().toLowerCase()=='pending_acceptance').toList();
                    if(pending.isEmpty)return const SizedBox.shrink();
                    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                      Align(alignment:Alignment.centerLeft,child:Text('Delivery Offers',style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w900))),
                      const SizedBox(height:8),
                      ...pending.take(5).map((doc){
                        final o=doc.data();
                        Future<void> respond(bool accept) async {
                          try{
                            await FirebaseFirestore.instance.runTransaction((tx) async {
                              final latest=await tx.get(doc.reference);
                              final d=latest.data()??{};
                              if((d['status']??'').toString().toLowerCase()!='pending_acceptance')throw Exception('This delivery offer is no longer available.');
                              if((d['carrierUid']??'').toString()!=widget.user.uid)throw Exception('This offer is not assigned to this account.');
                              final partnerRef=FirebaseFirestore.instance.collection('customers').doc(widget.user.uid);
                              if(accept){
                                tx.update(doc.reference,{'status':'Assigned','carrierAccepted':true,'assignmentRejected':false,'statusNote':'Delivery partner accepted the assignment','customerMessage':'Delivery partner accepted the assignment','updatedAt':FieldValue.serverTimestamp()});
                                tx.set(partnerRef,{'pendingOrderId':null,'activeOrderId':doc.id,'deliveryAvailable':false,'updatedAt':FieldValue.serverTimestamp()},SetOptions(merge:true));
                              }else{
                                tx.update(doc.reference,{'carrierUid':null,'assignedPartnerId':null,'carrierAccepted':false,'assignmentRejected':true,'status':'unassigned','statusNote':'Delivery partner rejected the assignment','customerMessage':'The offered delivery partner rejected the assignment. We are finding another partner.','updatedAt':FieldValue.serverTimestamp()});
                                tx.set(partnerRef,{'pendingOrderId':null,'activeOrderId':null,'deliveryAvailable':online,'updatedAt':FieldValue.serverTimestamp()},SetOptions(merge:true));
                              }
                            });
                            if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(accept?'Delivery accepted.':'Delivery offer rejected.')));
                          }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not respond: $e')));}
                        }
                        return Card(margin:const EdgeInsets.only(bottom:8),child:ListTile(
                          leading:const Icon(Icons.local_shipping_outlined),
                          title:Text('#'+(o['id']??doc.id).toString(),style:const TextStyle(fontWeight:FontWeight.w800)),
                          subtitle:Text((o['address']??'Customer location unavailable').toString()),
                          trailing:Wrap(spacing:4,children:[
                            TextButton(onPressed:()=>respond(false),child:const Text('Reject')),
                            FilledButton(onPressed:()=>respond(true),child:const Text('Accept')),
                          ]),
                        ));
                      }),
                      const SizedBox(height:12),
                    ]);
                  },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('New Pickup Requests', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                ),
                const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('orders').where('status', isEqualTo: 'Ready for pickup').snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return const Padding(padding: EdgeInsets.all(12), child: Text('Pickup requests are temporarily unavailable.'));
                    if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator());
                    final docs = snapshot.data!.docs;
                    if (docs.isEmpty) return const Padding(padding: EdgeInsets.all(14), child: Text('No new pickup requests right now.'));
                    return Column(
                      children: docs.take(10).map((d) {
                        final o = d.data();
                        final rawItems = o['items'];
                        final itemText = rawItems is List ? rawItems.map((x) => x is Map ? (x['name'].toString() + ' × ' + x['qty'].toString()) : x.toString()).join(', ') : '';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
                            title: Text('#' + (o['id'] ?? d.id).toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text((itemText.isEmpty ? 'Order ready for pickup' : itemText) + '\nCOD: ₹' + _number(o['total']).toStringAsFixed(0)),
                            isThreeLine: true,
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                IconButton(
                                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LiveTrackingScreen(
                                    collection: 'orders',
                                    docId: d.id,
                                    title: 'Live delivery tracking',
                                    mode: 'order',
                                    readOnly: true,
                                  ))),
                                  icon: const Icon(Icons.location_searching),
                                  tooltip: 'Track customer',
                                ),
                                IconButton(
                                  onPressed: () => openMaps(context, (o['address'] ?? '').toString()),
                                  icon: const Icon(Icons.navigation_outlined),
                                  tooltip: 'Navigate',
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('orders').where('carrierUid', isEqualTo: widget.user.uid).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              final docs = snapshot.data!.docs.where((d) {
                final status = (d.data()['status'] ?? '').toString();
                return status != 'Delivered' && status != 'Cancelled';
              }).toList();
              if (docs.isEmpty) return const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 16), child: Text('No active assigned orders.'));
              return Column(
                children: docs.map((d) {
                  final order = d.data();
                  final rawItems = order['items'];
                  final itemText = rawItems is List ? rawItems.map((x) => x is Map ? (x['name'].toString() + ' × ' + x['qty'].toString()) : x.toString()).join(', ') : '';
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

  Widget _carrierStat(BuildContext context, String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),    );
  }
}

const vehicleCategories = <String>[
  'Motorcycle','Scooter','E-bike','Auto Rickshaw','E-Rickshaw','Hatchback','Sedan','SUV','MUV',
  'Luxury Car','Taxi / Cab','Tempo Traveller','Van','Mini Bus','Bus','Pickup Truck','Mini Truck (Tata Ace)',
  'Bolero Pickup','Goods Auto','Cargo Van','Tractor','Tractor Trolley','Trailer','Ambulance','Other / Enter manually',
];

class VehicleBookingPage extends StatefulWidget {
  const VehicleBookingPage({super.key});
  @override State<VehicleBookingPage> createState()=>_VehicleBookingPageState();
}

class _VehicleBookingPageState extends State<VehicleBookingPage> {
  Future<void> _publishVehicle() async {
    final user=FirebaseAuth.instance.currentUser;
    if(user==null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Please sign in first.')));return;}
    final name=TextEditingController(),phone=TextEditingController(),price=TextEditingController(),capacity=TextEditingController(),custom=TextEditingController(),village=TextEditingController(),landmark=TextEditingController(),pincode=TextEditingController();
    double? vehicleLatitude;
    double? vehicleLongitude;
    String category=vehicleCategories.first; bool negotiate=true; XFile? vehiclePhoto; bool uploading=false;
    try{
      final ok=await showDialog<bool>(context:context,builder:(dialogContext)=>StatefulBuilder(builder:(context,setDialogState)=>AlertDialog(
        title:const Text('List your vehicle'),
        content:SizedBox(width:420,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          DropdownButtonFormField<String>(initialValue:category,decoration:const InputDecoration(labelText:'Vehicle category'),items:vehicleCategories.map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v){if(v!=null)setDialogState(()=>category=v);}),
          if(category=='Other / Enter manually')TextField(controller:custom,decoration:const InputDecoration(labelText:'Enter vehicle type')),
          TextField(controller:name,decoration:const InputDecoration(labelText:'Owner name')),
          TextField(controller:phone,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'Mobile number')),
          const SizedBox(height:10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: uploading ? null : () async {
                final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 600);
                if (image != null) setDialogState(() => vehiclePhoto = image);
              },
              icon: const Icon(Icons.camera_alt),
              label: Text(vehiclePhoto == null ? 'Upload vehicle photo' : 'Vehicle photo selected'),
            ),
          ),
          const Align(alignment:Alignment.centerLeft,child:Text('Vehicle photo is required.',style:TextStyle(color:Colors.grey,fontSize:12))),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: uploading ? null : () async {
                try {
                  if (!await Geolocator.isLocationServiceEnabled()) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Turn on GPS first.')));
                    return;
                  }
                  var permission=await Geolocator.checkPermission();
                  if(permission==LocationPermission.denied) permission=await Geolocator.requestPermission();
                  if(permission==LocationPermission.denied||permission==LocationPermission.deniedForever){
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permission was not granted.')));
                    return;
                  }
                  final pos=await Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.high)).timeout(const Duration(seconds:10));
                  setDialogState((){vehicleLatitude=pos.latitude;vehicleLongitude=pos.longitude;});
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Current GPS location captured.')));
                } catch(e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not capture GPS location: $e')));
                }
              },
              icon: const Icon(Icons.my_location),
              label: Text(vehicleLatitude==null?'Use current location':'Current location captured'),
            ),
          ),
          TextField(controller:village,decoration:const InputDecoration(labelText:'Village / Town / City Name')),
          TextField(controller:landmark,decoration:const InputDecoration(labelText:'Landmark / Main Road')),
          TextField(controller:pincode,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Pincode')),
          TextField(controller:capacity,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Seats / capacity')),
          TextField(controller:price,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Your price (₹)')),
          SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Allow negotiation'),value:negotiate,onChanged:(v)=>setDialogState(()=>negotiate=v)),
          const Align(alignment:Alignment.centerLeft,child:Text('You choose the price. ALLways does not set a fixed vehicle-booking price.',style:TextStyle(color:Colors.grey,fontSize:12))),
        ]))),
        actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('Publish'))],
      )))??false;
      if(!ok)return;
      final cleanPhone=phone.text.replaceAll(RegExp(r'\D'),''); final cleanPrice=num.tryParse(price.text.trim())??0;
      if(name.text.trim().isEmpty||cleanPhone.length!=10||cleanPrice<=0||vehiclePhoto==null||village.text.trim().isEmpty||landmark.text.trim().isEmpty||pincode.text.trim().isEmpty){
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter owner name, valid 10-digit mobile number, price and upload a vehicle photo.')));return;
      }
      final type=category=='Other / Enter manually'?custom.text.trim():category;
      if(type.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter the vehicle type.')));return;}
      try {
        uploading = true;
        final vehiclePhotoUrl = await uploadImageToCloudinary(vehiclePhoto!, folder: 'vehicles/' + user.uid);
        await FirebaseFirestore.instance.collection('vehicles').add({
          'ownerUid':user.uid,'ownerName':name.text.trim(),'ownerPhone':cleanPhone,'category':type,
          'capacity':int.tryParse(capacity.text.trim())??0,'price':cleanPrice,'allowNegotiation':negotiate,
          'vehiclePhotoUrl':vehiclePhotoUrl,'status':'available','latitude':vehicleLatitude,'longitude':vehicleLongitude,'manual_location':{'villageTownCity':village.text.trim(),'landmarkMainRoad':landmark.text.trim(),'pincode':pincode.text.trim()},'createdAt':FieldValue.serverTimestamp()
        });
      } catch(e) {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Vehicle photo upload failed: '+e.toString())));
        return;
      }
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Vehicle published successfully.')));
    }finally{name.dispose();phone.dispose();price.dispose();capacity.dispose();custom.dispose();village.dispose();landmark.dispose();pincode.dispose();}
  }

  Future<void> _book(DocumentSnapshot<Map<String,dynamic>> doc,{required bool negotiate}) async {
    final user=FirebaseAuth.instance.currentUser;
    if(user==null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Please sign in first.')));return;}
    final d=doc.data()??{};
    await FirebaseFirestore.instance.collection('vehicleBookings').add({'vehicleId':doc.id,'ownerUid':d['ownerUid'],'ownerName':d['ownerName'],'ownerPhone':d['ownerPhone'],'customerUid':user.uid,'customerName':user.displayName??'ALLways customer','customerEmail':user.email??'','category':d['category'],'listedPrice':d['price'],'mode':negotiate?'negotiation':'book','status':'Booked','createdAt':FieldValue.serverTimestamp()});
    if(!mounted)return;
    await showDialog<void>(context:context,builder:(c)=>AlertDialog(
      title:Text(negotiate?'Booking request sent':'Vehicle booked'),
      content:Text(negotiate?'The vehicle owner can now contact you to negotiate and confirm the final price.':'Booking confirmed. You can now contact the vehicle owner.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Done')),FilledButton.icon(onPressed:()=>_call(d['ownerPhone']?.toString()??''),icon:const Icon(Icons.call),label:const Text('Contact owner'))],
    ));
  }

  Future<void> _call(String phone) async { if(phone.trim().isEmpty)return; await launchUrl(Uri.parse('tel:'+phone.trim())); }

  @override Widget build(BuildContext context){
    final user=FirebaseAuth.instance.currentUser;
    return Scaffold(appBar:AppBar(title:const Text('Book vehicle')),body:StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
      stream:FirebaseFirestore.instance.collection('vehicles').where('status',isEqualTo:'available').snapshots(),
      builder:(context,snapshot){
        final docs=snapshot.data?.docs??const <QueryDocumentSnapshot<Map<String,dynamic>>>[];
        return ListView(padding:const EdgeInsets.fromLTRB(16,8,16,28),children:[
          Card(child:ListTile(leading:const Icon(Icons.add_business_outlined),title:const Text('Offer your vehicle',style:TextStyle(fontWeight:FontWeight.w900)),subtitle:const Text('Vehicle owners choose their own price and can allow negotiation.'),trailing:const Icon(Icons.chevron_right),onTap:user==null?null:_publishVehicle)),
          const SizedBox(height:10),const Text('Available vehicles',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900)),const SizedBox(height:8),
          if(snapshot.hasError)const InfoCard(title:'Could not load vehicles',detail:'Please try again later.'),
          if(!snapshot.hasData)const Padding(padding:EdgeInsets.all(20),child:Center(child:CircularProgressIndicator())),
          if(snapshot.hasData&&docs.isEmpty)const InfoCard(title:'No vehicles listed yet',detail:'Vehicle owners can publish a vehicle from “Offer your vehicle”.'),
          ...docs.map((doc){final d=doc.data();final allow=d['allowNegotiation']==true;return Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[const Icon(Icons.directions_car_outlined),const SizedBox(width:10),Expanded(child:Text((d['category']??'Vehicle').toString(),style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900))),Text('₹'+(d['price']??0).toString(),style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900))]),
            const SizedBox(height:6),Text('Owner: '+(d['ownerName']??'').toString()+(d['capacity']!=null&&d['capacity'].toString()!='0'?' • Capacity: '+d['capacity'].toString():'')),
            const SizedBox(height:4),Text(allow?'Owner allows negotiation':'Fixed owner price',style:const TextStyle(color:Colors.grey)),const SizedBox(height:10),
            Row(children:[Expanded(child:FilledButton(onPressed:()=>_book(doc,negotiate:false),child:const Text('Book'))),if(allow)...[const SizedBox(width:8),Expanded(child:OutlinedButton(onPressed:()=>_book(doc,negotiate:true),child:const Text('Book & negotiate')))]])
          ])));}),
          const SizedBox(height:14),TravelBookingsSection(type:'vehicle'),const SizedBox(height:14),const Text('25 popular vehicle categories',style:TextStyle(fontSize:18,fontWeight:FontWeight.w900)),const SizedBox(height:8),
          Wrap(spacing:8,runSpacing:8,children:vehicleCategories.map((x)=>Chip(label:Text(x))).toList()),
        ]);
      },
    ));
  }
}

class RidePartnerPage extends StatefulWidget {
  const RidePartnerPage({super.key});
  @override State<RidePartnerPage> createState()=>_RidePartnerPageState();
}

class _RidePartnerPageState extends State<RidePartnerPage> {
  Future<void> _bookRide() async {
    final user=FirebaseAuth.instance.currentUser;
    if(user==null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Please sign in first.')));return;}
    final destination=TextEditingController(),km=TextEditingController(); int seats=1;
    try{
      final ok=await showDialog<bool>(context:context,builder:(dialogContext)=>StatefulBuilder(builder:(context,setDialogState)=>AlertDialog(
        title:const Text('Look for a Ride'),
        content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          DropdownButtonFormField<int>(initialValue:seats,decoration:const InputDecoration(labelText:'Available seats'),items:List.generate(3,(i)=>DropdownMenuItem(value:i+1,child:Text((i+1).toString()+' seat'+(i==0?'':'s')))),onChanged:(v){if(v!=null)setDialogState(()=>seats=v);}),
          TextField(controller:destination,decoration:const InputDecoration(labelText:'Destination')),
          TextField(controller:km,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Ride distance (km)')),
          const SizedBox(height:8),const Text('Pickup is from a main road only. Doorstep pickup is not available.',style:TextStyle(color:Colors.grey,fontSize:12)),
        ])),
        actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('Find ride'))],
      )))??false;
      if(!ok)return;
      final distance=num.tryParse(km.text.trim())??0;
      if(destination.text.trim().isEmpty||distance<=0){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter destination and a valid distance.')));return;}
      num perKmAbove20=5;
      if(distance>20){
        final rate=TextEditingController(text:'5');
        final calculated=await showDialog<num>(context:context,builder:(c)=>AlertDialog(
          title:const Text('Ride price calculator'),
          content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('First 20 km: ₹20\\nExtra distance: '+(distance-20).toStringAsFixed(1)+' km'),
            const SizedBox(height:12),
            TextField(controller:rate,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Rate per extra km (₹)')),
            const SizedBox(height:8),
            const Text('Trial calculator. Default extra-km rate is ₹5.',style:TextStyle(color:Colors.grey,fontSize:12)),
          ]),
          actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cancel')),FilledButton(onPressed:(){final r=num.tryParse(rate.text.trim())??0;if(r>0)Navigator.pop(c,r);},child:const Text('Calculate'))],
        ));
        rate.dispose();
        if(calculated==null)return;
        perKmAbove20=calculated;
      }
      final price=distance<5?10:(distance<=20?20:20+((distance-20)*perKmAbove20));
      double? pickupLatitude;
      double? pickupLongitude;
      double? destinationLatitude;
      double? destinationLongitude;
      try {
        if(await Geolocator.isLocationServiceEnabled()){
          var permission=await Geolocator.checkPermission();
          if(permission==LocationPermission.denied)permission=await Geolocator.requestPermission();
          if(permission!=LocationPermission.denied&&permission!=LocationPermission.deniedForever){
            final pos=await Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.high)).timeout(const Duration(seconds:8));
            pickupLatitude=pos.latitude;
            pickupLongitude=pos.longitude;
          }
        }
      }catch(_){}
      try{
        final locations=await locationFromAddress(destination.text.trim());
        if(locations.isNotEmpty){
          destinationLatitude=locations.first.latitude;
          destinationLongitude=locations.first.longitude;
        }
      }catch(_){}
      final snap=await FirebaseFirestore.instance.collection('ridePartners').where('vehicleType',isEqualTo:'two_wheeler').where('status',isEqualTo:'online').get();
      if(snap.docs.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('No two-wheeler ride partner is available right now.')));return;}
      final partner=snap.docs.first.data();
      await FirebaseFirestore.instance.collection('rideBookings').add({'customerUid':user.uid,'customerName':user.displayName??'ALLways customer','partnerUid':partner['uid'],'partnerName':partner['name'],'partnerPhone':partner['mobileNumber'],'destination':destination.text.trim(),'distanceKm':distance,'seats':seats,'price':price,'status':'pending_acceptance','pickupRule':'Main road pickup only','pickupLatitude':pickupLatitude,'pickupLongitude':pickupLongitude,'destinationLatitude':destinationLatitude,'destinationLongitude':destinationLongitude,'createdAt':FieldValue.serverTimestamp()});
      if(mounted)await showDialog<void>(context:context,builder:(c)=>AlertDialog(title:const Text('Ride request sent'),content:Text('₹'+price.toString()+' • '+distance.toString()+' km • Waiting for the ride partner to accept. Tracking and contact will unlock after acceptance.'),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Done'))]));
    }finally{destination.dispose();km.dispose();}
  }


  Future<void> _acceptRide(QueryDocumentSnapshot<Map<String,dynamic>> doc) async {
    final user=FirebaseAuth.instance.currentUser;
    if(user==null)return;
    try{
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final latest=await tx.get(doc.reference);
        final d=latest.data()??{};
        if((d['status']??'').toString().toLowerCase()!='pending_acceptance')throw Exception('Ride already accepted or no longer available.');
        if((d['partnerUid']??'').toString()!=user.uid)throw Exception('This ride is not assigned to you.');
        tx.update(doc.reference,{'status':'Accepted','partnerAccepted':true,'acceptedAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp()});
      });
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ride accepted. Live tracking is now available.')));
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not accept ride: $e')));}
  }

  Future<void> _rejectRide(QueryDocumentSnapshot<Map<String,dynamic>> doc) async {
    final user=FirebaseAuth.instance.currentUser;
    if(user==null)return;
    try{
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final latest=await tx.get(doc.reference);
        final d=latest.data()??{};
        if((d['status']??'').toString().toLowerCase()!='pending_acceptance')return;
        if((d['partnerUid']??'').toString()!=user.uid)return;
        tx.update(doc.reference,{'status':'Rejected','partnerAccepted':false,'rejectedAt':FieldValue.serverTimestamp(),'updatedAt':FieldValue.serverTimestamp()});
      });
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ride request rejected.')));
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not reject ride: $e')));}
  }

  Future<void> _setRideOnline(bool value) async {
    final user=FirebaseAuth.instance.currentUser;
    if(user==null)return;
    await FirebaseFirestore.instance.collection('ridePartners').doc(user.uid).set({'uid':user.uid,'status':value?'online':'offline','statusUpdatedAt':FieldValue.serverTimestamp()},SetOptions(merge:true));
  }

  @override Widget build(BuildContext context){
    final user=FirebaseAuth.instance.currentUser;
    return Scaffold(appBar:AppBar(title:const Text('Book a ride partner')),body:ListView(padding:const EdgeInsets.fromLTRB(16,8,16,28),children:[

      if(user!=null)
        StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
          stream:FirebaseFirestore.instance.collection('rideBookings').where('partnerUid',isEqualTo:user.uid).snapshots(),
          builder:(context,snapshot){
            final requests=(snapshot.data?.docs??const <QueryDocumentSnapshot<Map<String,dynamic>>>[]).where((d){
              final status=(d.data()['status']??'').toString().toLowerCase();
              return status=='pending_acceptance'||status=='accepted';
            }).toList();
            if(requests.isEmpty)return const SizedBox.shrink();
            return Column(children:requests.take(3).map((doc){
              final d=doc.data();
              final accepted=(d['status']??'').toString().toLowerCase()=='accepted';
              return Card(
                child:ListTile(
                  leading:Icon(accepted?Icons.navigation_outlined:Icons.notifications_active_outlined),
                  title:Text(accepted?'Accepted ride':'New ride request',style:const TextStyle(fontWeight:FontWeight.w900)),
                  subtitle:Text((d['destination']??'Destination').toString()+' • '+(d['distanceKm']??0).toString()+' km • ₹'+(d['price']??0).toString()),
                  trailing:accepted
                    ?OutlinedButton(
                        onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>LiveTrackingScreen(
                          collection:'rideBookings',
                          docId:doc.id,
                          title:'Live ride tracking',
                          mode:'ride',
                          broadcastPrefix:'partner',
                        ))),
                        child:const Text('Track'),
                      )
                    :Wrap(spacing:4,children:[
                        TextButton(onPressed:()=>_rejectRide(doc),child:const Text('Reject')),
                        FilledButton(onPressed:()=>_acceptRide(doc),child:const Text('Accept')),
                      ]),
                ),
              );
            }).toList());
          },
        ),

      Card(child:ListTile(leading:const Icon(Icons.two_wheeler_outlined),title:const Text('Book a Ride',style:TextStyle(fontWeight:FontWeight.w900)),subtitle:const Text('Two-wheeler only • main-road pickup • no doorstep pickup'),trailing:const Icon(Icons.chevron_right),onTap:_bookRide)),
      StreamBuilder<DocumentSnapshot<Map<String,dynamic>>>(
        stream:user==null?const Stream<DocumentSnapshot<Map<String,dynamic>>>.empty():FirebaseFirestore.instance.collection('ridePartners').doc(user.uid).snapshots(),
        builder:(context,snapshot){
          final profile=snapshot.data?.data();
          if(profile==null)return Card(child:ListTile(leading:const Icon(Icons.person_add_alt_1_outlined),title:const Text('Drive & Earn',style:TextStyle(fontWeight:FontWeight.w900)),subtitle:const Text('Become a two-wheeler ride partner'),trailing:const Icon(Icons.chevron_right),onTap:()=>_applyRidePartner(context)));
          final online=(profile['status']??'offline')=='online';
          return Card(child:Column(children:[
            SwitchListTile(title:Text(online?'Online — accepting ride requests':'Offline — not accepting ride requests',style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text((profile['name']??'Ride partner').toString()),value:online,onChanged:_setRideOnline),
            ListTile(leading:const Icon(Icons.edit_outlined),title:const Text('Update saved details'),onTap:()=>_applyRidePartner(context)),
          ]));
        }),
      const SizedBox(height:12),TravelBookingsSection(type:'ride'),const SizedBox(height:12),const Text('Ride pricing',style:TextStyle(fontSize:18,fontWeight:FontWeight.w900)),const SizedBox(height:6),const Text('Below 5 km: ₹10\n5 km: ₹15\nAbove 5 km: ₹20'),
      const SizedBox(height:12),const Text('Important',style:TextStyle(fontSize:18,fontWeight:FontWeight.w900)),const Text('ALLways is providing this as a trial platform without commission. ALLways is not currently responsible for conduct, safety, vehicle condition, payment, loss, injury or disputes between ride participants. Please verify the partner and vehicle before travelling. You can report a partner or ride through ALLways.'),
    ]));
  }

  Future<void> _applyRidePartner(BuildContext context) async {
    final user=FirebaseAuth.instance.currentUser;if(user==null)return;
    final existingSnap=await FirebaseFirestore.instance.collection('ridePartners').doc(user.uid).get();
    final existing=existingSnap.data();
    final name=TextEditingController(text:(existing?['name']??'').toString()),mobile=TextEditingController(text:(existing?['mobileNumber']??'').toString());String gender=(existing?['gender']??'Prefer not to say').toString();XFile? selectedPhoto;bool uploading=false;
    try{
      await showDialog<void>(context:context,builder:(dialogContext)=>StatefulBuilder(builder:(context,setState)=>AlertDialog(
        title:const Text('Drive & Earn'),
        content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
          TextField(controller:name,decoration:const InputDecoration(labelText:'Name')),
          DropdownButtonFormField<String>(initialValue:gender,decoration:const InputDecoration(labelText:'Gender'),items:['Male','Female','Other','Prefer not to say'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v){if(v!=null)setState(()=>gender=v);}),
          TextField(controller:mobile,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'Mobile number')),
          const SizedBox(height:10),
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Upload profile photo',
                  onPressed: uploading ? null : () async {
                    final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 600);
                    if (image != null) setState(() => selectedPhoto = image);
                  },
                  icon: Icon(selectedPhoto == null ? Icons.camera_alt : Icons.check_circle),
                ),
                Expanded(child: Text(selectedPhoto == null ? 'Upload profile photo' : 'Profile photo selected')),
              ],
            ),
          ),
          const Align(alignment:Alignment.centerLeft,child:Text('Required: name, gender, mobile number and profile photo.',style:TextStyle(color:Colors.grey,fontSize:12))),
        ])),
        actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('Cancel')),FilledButton(onPressed:()async{
          final ph=mobile.text.replaceAll(RegExp(r'\D'),'');
          if(name.text.trim().isEmpty||ph.length!=10||(((existing?['photoUrl']??'').toString().isEmpty)&&selectedPhoto==null)){
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter name, valid 10-digit mobile number and upload a profile photo.')));
            return;
          }
          setState(() => uploading = true);
          try {
            var photoUrl=(existing?['photoUrl']??'').toString();
            if(selectedPhoto!=null) photoUrl=await uploadImageToCloudinary(selectedPhoto!, folder: 'ride-partners/' + user.uid);
            await FirebaseFirestore.instance.collection('ridePartners').doc(user.uid).set({
              'uid':user.uid,'name':name.text.trim(),'gender':gender,'mobileNumber':ph,'photoUrl':photoUrl,
              'vehicleType':'two_wheeler','status':(existing?['status']??'offline').toString(),'updatedAt':FieldValue.serverTimestamp()
            },SetOptions(merge:true));
            if(dialogContext.mounted)Navigator.pop(dialogContext);
            if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ride partner profile submitted.')));
          } catch(e) {
            if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Profile photo upload failed: '+e.toString())));
            setState(() => uploading = false);
          }
        },child:const Text('Submit'))],
      )));
    }finally{name.dispose();mobile.dispose();}
  }
}

class TravelBookingsSection extends StatelessWidget {
  final String type;
  const TravelBookingsSection({super.key,required this.type});

  Future<void> _reviewReport(BuildContext context,String bookingId) async {
    final review=TextEditingController(); final report=TextEditingController(); int rating=5;
    final action=await showDialog<String>(context:context,builder:(c)=>StatefulBuilder(builder:(c,setState)=>AlertDialog(
      title:Text(type=='ride'?'Ride review / report':'Vehicle review / report'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Align(alignment:Alignment.centerLeft,child:Text('Review',style:TextStyle(fontWeight:FontWeight.w800))),
        DropdownButtonFormField<int>(initialValue:rating,items:[1,2,3,4,5].map((x)=>DropdownMenuItem(value:x,child:Text(x.toString()+' / 5'))).toList(),onChanged:(v){if(v!=null)setState(()=>rating=v);}),
        TextField(controller:review,maxLines:3,decoration:const InputDecoration(labelText:'Your review (optional)')),
        const SizedBox(height:12),
        const Align(alignment:Alignment.centerLeft,child:Text('Report an issue',style:TextStyle(fontWeight:FontWeight.w800))),
        TextField(controller:report,maxLines:3,decoration:const InputDecoration(labelText:'Report details (optional)')),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,'save'),child:const Text('Submit'))],
    )));
    if(action!='save') { review.dispose(); report.dispose(); return; }
    final user=FirebaseAuth.instance.currentUser;
    if(user==null) { review.dispose(); report.dispose(); return; }
    if(review.text.trim().isNotEmpty) await FirebaseFirestore.instance.collection('travelReviews').add({'bookingId':bookingId,'bookingType':type,'userUid':user.uid,'rating':rating,'review':review.text.trim(),'createdAt':FieldValue.serverTimestamp()});
    if(report.text.trim().isNotEmpty) await FirebaseFirestore.instance.collection('travelReports').add({'bookingId':bookingId,'bookingType':type,'userUid':user.uid,'report':report.text.trim(),'createdAt':FieldValue.serverTimestamp(),'status':'open'});
    review.dispose(); report.dispose();
    if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Review/report submitted.')));
  }

  @override Widget build(BuildContext context){
    final user=FirebaseAuth.instance.currentUser;
    if(user==null)return const SizedBox.shrink();
    final collection=type=='ride'?'rideBookings':'vehicleBookings';
    return Card(child:ExpansionTile(
      leading:Icon(type=='ride'?Icons.two_wheeler_outlined:Icons.directions_car_outlined),
      title:Text(type=='ride'?'My ride bookings':'My vehicle bookings',style:const TextStyle(fontWeight:FontWeight.w900)),
      children:[
        StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
          stream:FirebaseFirestore.instance.collection(collection).where('customerUid',isEqualTo:user.uid).snapshots(),
          builder:(context,snapshot){
            if(snapshot.hasError)return const Padding(padding:EdgeInsets.all(16),child:Text('Bookings unavailable.'));
            if(!snapshot.hasData)return const Padding(padding:EdgeInsets.all(16),child:CircularProgressIndicator());
            if(snapshot.data!.docs.isEmpty)return const Padding(padding:EdgeInsets.all(16),child:Text('No bookings yet.'));
            return Column(children:snapshot.data!.docs.take(20).map((doc){
              final d=doc.data();
              final name=(d['partnerName']??d['ownerName']??'Booking').toString();
              final status=(d['status']??'').toString();
              return ListTile(
                title:Text(name,style:const TextStyle(fontWeight:FontWeight.w800)),
                subtitle:Text(status+(d['price']!=null?' • ₹'+d['price'].toString():'')+(d['destination']!=null?' • '+d['destination'].toString():'')),
                trailing:Wrap(spacing:4,children:[
                  if(status.toLowerCase()!='rejected'&&status.toLowerCase()!='cancelled'&&status.toLowerCase()!='delivered')
                    OutlinedButton(
                      onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>LiveTrackingScreen(
                        collection:collection,
                        docId:doc.id,
                        title:type=='ride'?'Live ride tracking':'Live vehicle tracking',
                        mode:type=='ride'?'ride':'vehicle',
                        broadcastPrefix:'customer',
                      ))),
                      child:const Text('Track'),
                    ),
                  OutlinedButton(onPressed:()=>_reviewReport(context,doc.id),child:const Text('Review / Report')),
                ]),
              );
            }).toList());
          },
        ),
      ],
    ));
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
          Text('ALLways uses account information to authenticate customers, process orders, provide delivery updates and support seller or delivery-partner onboarding. Delivery addresses and order details are used to fulfill orders. Wishlist and saved-address data are stored under your customer account. Photos submitted for onboarding or seller listings are stored in Cloudinary, with their secure URLs saved in Firestore.'),
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

class LocalSellersPage extends StatefulWidget {
  const LocalSellersPage({super.key});
  @override State<LocalSellersPage> createState() => _LocalSellersPageState();
}

class _LocalSellersPageState extends State<LocalSellersPage> {
  String category = 'All';
  String search = '';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('sellers').where('status', isEqualTo: 'approved').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const InfoCard(title: 'Local sellers unavailable', detail: 'Please check your connection and try again.');
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final q = search.trim().toLowerCase();
        final sellers = snapshot.data!.docs.where((d) {
          final x = d.data();
          final text = [x['businessName'], x['name'], x['category'], x['description'], x['locationAddress']]
              .map((v) => (v ?? '').toString()).join(' ').toLowerCase();
          return (category == 'All' || (x['category'] ?? 'Other').toString() == category) && (q.isEmpty || text.contains(q));
        }).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            const Text('Local sellers', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('Discover approved local businesses and contact them directly.', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 14),
            TextField(decoration: const InputDecoration(hintText: 'Search shops or products', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => search = v)),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: ['All', ...sellerCategories].map((x) => Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: ChoiceChip(label: Text(x), selected: category == x, onSelected: (_) => setState(() => category = x)),
                )).toList(),
              ),
            ),
            const SizedBox(height: 14),
            if (sellers.isEmpty)
              const InfoCard(title: 'No local sellers found', detail: 'Try another category or search.')
            else
              ...sellers.map((d) {
                final x = d.data();
                final image = (x['photoUrl'] ?? '').toString();
                final shop = (x['businessName'] ?? x['name'] ?? 'Local seller').toString();
                final cat = (x['category'] ?? 'Other').toString();
                final rating = x['rating'];
                final ratingText = rating == null ? 'New' : '⭐ ' + rating.toString();
                final open = x['isOpen'];
                final statusText = open == true ? 'Open now' : open == false ? 'Closed' : 'Hours not set';
                final statusColor = open == true ? Colors.green : open == false ? Colors.grey : Colors.orange;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(10),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: image.isEmpty
                          ? const SizedBox(width: 64, height: 64, child: Icon(Icons.storefront_outlined, size: 32))
                          : Image.network(cloudinaryImageUrl(image, width: 64, height: 64), width: 64, height: 64, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox(width: 64, height: 64, child: Icon(Icons.broken_image_outlined))),
                    ),
                    title: Row(children: [
                      Expanded(child: Text(shop, style: const TextStyle(fontWeight: FontWeight.w800))),
                      const Icon(Icons.verified, size: 18, color: Colors.blue),
                    ]),
                    subtitle: Row(children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Expanded(child: Text('$cat • $ratingText • $statusText', overflow: TextOverflow.ellipsis)),
                    ]),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SellerProfilePage(sellerId: d.id))),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

class SellerProfilePage extends StatefulWidget {
  final String sellerId;
  const SellerProfilePage({super.key, required this.sellerId});
  @override State<SellerProfilePage> createState() => _SellerProfilePageState();
}

class _SellerProfilePageState extends State<SellerProfilePage> {
  bool favourite = false;

  @override
  void initState() {
    super.initState();
    _loadFavourite();
  }

  Future<void> _loadFavourite() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('customers').doc(u.uid).collection('favoriteSellers').doc(widget.sellerId).get();
      if (mounted) setState(() => favourite = snap.exists);
    } catch (_) {}
  }

  Future<void> _toggleFavourite() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in to save favourite sellers.')));
      return;
    }
    final ref = FirebaseFirestore.instance.collection('customers').doc(u.uid).collection('favoriteSellers').doc(widget.sellerId);
    setState(() => favourite = !favourite);
    try {
      if (favourite) {
        await ref.set({'sellerId': widget.sellerId, 'addedAt': FieldValue.serverTimestamp()});
      } else {
        await ref.delete();
      }
    } catch (_) {
      if (mounted) setState(() => favourite = !favourite);
    }
  }

  Future<void> callSeller(String phone) async {
    if (phone.isEmpty) return;
    await launchUrl(Uri.parse('tel:$phone'));
  }

  Future<void> openLocation(Map<String, dynamic> data) async {
    final lat = (data['latitude'] as num?)?.toDouble();
    final lng = (data['longitude'] as num?)?.toDouble();
    final address = (data['locationAddress'] ?? data['address'] ?? '').toString();
    final query = lat != null && lng != null ? '$lat,$lng' : address;
    if (query.isEmpty) return;
    await launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=' + Uri.encodeComponent(query)), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('sellers').doc(widget.sellerId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Scaffold(appBar: AppBar(title: const Text('Seller')), body: const InfoCard(title: 'Seller unavailable', detail: 'Please try again.'));
        if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final data = snapshot.data!.data() ?? {};
        final image = (data['photoUrl'] ?? '').toString();
        final shop = (data['businessName'] ?? data['name'] ?? 'Local seller').toString();
        final category = (data['category'] ?? 'Other').toString();
        final description = (data['description'] ?? '').toString();
        final about = (data['about'] ?? '').toString();
        final phone = (data['mobileNumber'] ?? '').toString();
        final location = (data['locationAddress'] ?? '').toString();
        final open = data['isOpen'];
        final hours = (data['openingHours'] ?? '').toString();
        final rawItems = data['items'];
        final items = rawItems is List ? rawItems.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

        return Scaffold(
          appBar: AppBar(
            title: const Text('Local Seller'),
            actions: [IconButton(onPressed: _toggleFavourite, icon: Icon(favourite ? Icons.favorite : Icons.favorite_border, color: Colors.red))],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: image.isEmpty
                    ? Container(height: 210, alignment: Alignment.center, child: const Icon(Icons.storefront_outlined, size: 72))
                    : LayoutBuilder(builder: (context, constraints) => Image.network(cloudinaryImageUrl(image, width: constraints.maxWidth, height: 210), height: 210, width: double.infinity, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(height: 210, alignment: Alignment.center, child: const Icon(Icons.broken_image_outlined, size: 48)))),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: Text(shop, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900))),
                const Icon(Icons.verified, size: 22, color: Colors.blue),
              ]),
              const SizedBox(height: 6),
              Text(category, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Chip(label: Text(data['rating'] == null ? 'New seller' : '⭐ ' + data['rating'].toString())),
                Chip(avatar: Container(width: 9, height: 9, decoration: BoxDecoration(color: open == true ? Colors.green : open == false ? Colors.grey : Colors.orange, shape: BoxShape.circle)), label: Text(open == true ? 'Open now' : open == false ? 'Closed' : 'Hours not set')),
                if (hours.isNotEmpty) Chip(label: Text(hours)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: FilledButton.icon(onPressed: phone.isEmpty ? null : () => callSeller(phone), icon: const Icon(Icons.call), label: const Text('Call'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(onPressed: () => openLocation(data), icon: const Icon(Icons.location_on_outlined), label: const Text('Directions'))),
              ]),
              if (location.isNotEmpty) ...[
                const SizedBox(height: 10),
                Card(child: ListTile(leading: const Icon(Icons.location_on_outlined), title: const Text('Location'), subtitle: Text(location))),
              ],
              if (description.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('About the shop', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(description),
              ],
              if (about.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('About', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(about),
              ],
              const SizedBox(height: 18),
              const Text('Products & services', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              if (items.isEmpty)
                const InfoCard(title: 'Catalogue coming soon', detail: 'Contact the seller directly for current products, prices and availability.')
              else
                ...items.map((item) => Card(
                  child: ListTile(
                    leading: (item['imageUrl'] ?? '').toString().isEmpty ? const Icon(Icons.inventory_2_outlined) : Image.network(cloudinaryImageUrl(item['imageUrl'].toString(), width: 54, height: 54), width: 54, height: 54, fit: BoxFit.cover),
                    title: Text((item['name'] ?? 'Item').toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text([
                      if ((item['category'] ?? '').toString().isNotEmpty) item['category'].toString(),
                      if ((item['description'] ?? '').toString().isNotEmpty) item['description'].toString(),
                      if ((item['about'] ?? '').toString().isNotEmpty) item['about'].toString(),
                      if (item['price'] != null) '₹' + item['price'].toString(),
                    ].join(' • ')),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LocalSellerProductPage(item: item, sellerName: shop))),
                  ),
                )),
              const SizedBox(height: 8),
              const Text('Local Seller model: Discover → View → Contact. ALLways does not provide cart or checkout for local sellers.', style: TextStyle(color: Colors.grey)),
            ],
          ),
        );
      },
    );
  }
}

class LocalSellerProductPage extends StatelessWidget {
  final Map<String,dynamic> item;
  final String sellerName;
  const LocalSellerProductPage({super.key,required this.item,required this.sellerName});

  @override Widget build(BuildContext context){
    final image=(item['imageUrl']??'').toString();
    final name=(item['name']??'Item').toString();
    final price=item['price'];
    final desc=(item['description']??'').toString();
    final about=(item['about']??'').toString();
    return Scaffold(appBar:AppBar(title:const Text('Product details')),body:ListView(padding:const EdgeInsets.fromLTRB(16,8,16,28),children:[
      ClipRRect(borderRadius:BorderRadius.circular(18),child:image.isEmpty?Container(height:240,alignment:Alignment.center,child:const Icon(Icons.inventory_2_outlined,size:80)):LayoutBuilder(builder: (context, constraints) => Image.network(cloudinaryImageUrl(image, width: constraints.maxWidth, height: 240),height:240,width:double.infinity,fit:BoxFit.cover))),
      const SizedBox(height:16),
      Text(name,style:const TextStyle(fontSize:26,fontWeight:FontWeight.w900)),
      if(price!=null) Padding(padding:const EdgeInsets.only(top:8),child:Text('₹$price',style:const TextStyle(fontSize:22,fontWeight:FontWeight.w800))),
      const SizedBox(height:12),
      Text('Sold by $sellerName',style:const TextStyle(color:Colors.grey)),
      if(desc.isNotEmpty)...[const SizedBox(height:18),const Text('Description',style:TextStyle(fontSize:19,fontWeight:FontWeight.w800)),const SizedBox(height:6),Text(desc)],
      if(about.isNotEmpty)...[const SizedBox(height:18),const Text('About this product',style:TextStyle(fontSize:19,fontWeight:FontWeight.w800)),const SizedBox(height:6),Text(about)],
    ]));
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
          'mobileNumber': data['mobileNumber'] ?? '',
          'category': data['category'] ?? 'Other',
          'locationAddress': data['locationAddress'] ?? '',
          'latitude': data['latitude'],
          'longitude': data['longitude'],
          'status': 'approved',
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

  Future<void> reviewRoleDetails(BuildContext context,String uid,String role,{DocumentSnapshot<Map<String,dynamic>>? request}) async {
    try {
      Map<String,dynamic> data={};
      if(role=='seller') {
        final snap=await FirebaseFirestore.instance.collection('sellers').doc(uid).get(); data=snap.data()??{};
      } else {
        QueryDocumentSnapshot<Map<String,dynamic>>? found;
        if(request is QueryDocumentSnapshot<Map<String,dynamic>>) found=request;
        if(found==null){ final q=await FirebaseFirestore.instance.collection('onboarding_requests').where('uid',isEqualTo:uid).where('type',isEqualTo:'carrier').limit(1).get(); if(q.docs.isNotEmpty) found=q.docs.first; }
        data=found?.data()??{};
      }
      if(!context.mounted)return;
      final photo=(data['photoUrl']??'').toString(), bike=(data['bikePhotoUrl']??'').toString();
      final title=role=='seller'?(data['businessName']??data['name']??'Seller').toString():(data['fullName']??data['name']??'Delivery partner').toString();
      await showDialog<void>(context:context,builder:(dialog)=>AlertDialog(title:Text(role=='seller'?'Seller details':'Delivery partner details'),content:SizedBox(width:420,child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        if(photo.isNotEmpty)ClipRRect(borderRadius:BorderRadius.circular(12),child:LayoutBuilder(builder: (context, constraints) => Image.network(cloudinaryImageUrl(photo, width: constraints.maxWidth, height: 160),height:160,width:double.infinity,fit:BoxFit.cover))),
        if(bike.isNotEmpty)...[const SizedBox(height:10),ClipRRect(borderRadius:BorderRadius.circular(12),child:LayoutBuilder(builder: (context, constraints) => Image.network(cloudinaryImageUrl(bike, width: constraints.maxWidth, height: 150),height:150,width:double.infinity,fit:BoxFit.cover)))],
        const SizedBox(height:12),Text(title,style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900)),const SizedBox(height:8),
        Text([
          if((data['email']??'').toString().isNotEmpty)'Email: '+data['email'].toString(),
          if((data['mobileNumber']??'').toString().isNotEmpty)'Mobile: '+data['mobileNumber'].toString(),
          if((data['shopName']??'').toString().isNotEmpty)'Shop: '+data['shopName'].toString(),
          if((data['businessName']??'').toString().isNotEmpty&&role=='seller')'Shop name: '+data['businessName'].toString(),
          if((data['category']??'').toString().isNotEmpty)'Category: '+data['category'].toString(),
          if((data['locationAddress']??'').toString().isNotEmpty)'Location: '+data['locationAddress'].toString(),
          if((data['dob']??'').toString().isNotEmpty)'DOB: '+data['dob'].toString(),
          if((data['gender']??'').toString().isNotEmpty)'Gender: '+data['gender'].toString(),
          if((data['openingHours']??'').toString().isNotEmpty)'Service hours: '+data['openingHours'].toString(),
          if((data['description']??'').toString().isNotEmpty)'Description: '+data['description'].toString(),
        ].join('\n')),
      ]))),actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Close'))]));
    }catch(e){if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not load details: '+e.toString())));}
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
                    leading: SizedBox(
                      width: role == 'carrier' && (x['bikePhotoUrl'] ?? '').toString().isNotEmpty ? 112 : 64,
                      height: 64,
                      child: Row(
                        children: [
                          if ((x['photoUrl'] ?? '').toString().isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(cloudinaryImageUrl((x['photoUrl'] ?? '').toString(), width: 64, height: 64), width: 64, height: 64, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
                            )
                          else
                            const SizedBox(width: 64, height: 64, child: Icon(Icons.person_outline)),
                          if (role == 'carrier' && (x['bikePhotoUrl'] ?? '').toString().isNotEmpty) ...[
                            const SizedBox(width: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(cloudinaryImageUrl((x['bikePhotoUrl'] ?? '').toString(), width: 40, height: 64), width: 40, height: 64, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    title: Text((x['fullName'] ?? 'Applicant').toString()),
                    subtitle: Text([
                      if ((x['mobileNumber'] ?? '').toString().isNotEmpty) 'Mobile: ' + (x['mobileNumber'] ?? '').toString(),
                      if ((x['shopName'] ?? '').toString().isNotEmpty) 'Shop: ' + (x['shopName'] ?? '').toString(),
                      if ((x['category'] ?? '').toString().isNotEmpty) 'Category: ' + (x['category'] ?? '').toString(),
                      if ((x['locationAddress'] ?? '').toString().isNotEmpty) 'Location: ' + (x['locationAddress'] ?? '').toString(),
                      if ((x['bikePhotoUrl'] ?? '').toString().isNotEmpty) 'Bike photo uploaded',
                      if ((x['dob'] ?? '').toString().isNotEmpty) 'DOB: ' + (x['dob'] ?? '').toString(),
                      if ((x['email'] ?? '').toString().isNotEmpty) (x['email'] ?? '').toString(),
                    ].join('\n')),
                    trailing: Wrap(
                      children: [
                        TextButton(onPressed: () => reviewRoleDetails(context, (x['uid'] ?? '').toString(), role, request: d), child: const Text('Review')),
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
                        trailing: Wrap(spacing:4,children:[TextButton(onPressed:()=>reviewRoleDetails(context,d.id,role),child:const Text('Review')),TextButton(onPressed:()=>remove(context,d.id),child:const Text('Remove'))]),
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

class AdminDeliveryAssignmentPanel extends StatefulWidget {
  const AdminDeliveryAssignmentPanel({super.key});
  @override State<AdminDeliveryAssignmentPanel> createState()=>_AdminDeliveryAssignmentPanelState();
}

class _AdminDeliveryAssignmentPanelState extends State<AdminDeliveryAssignmentPanel> {
  Future<void> _assign(BuildContext context,QueryDocumentSnapshot<Map<String,dynamic>> order) async {
    final partners=await FirebaseFirestore.instance.collection('customers').where('role',isEqualTo:'carrier').get();
    final online=partners.docs.where((d){
      final x=d.data();
      final duty=(x['dutyStatus']??'offline').toString().toLowerCase();
      return duty=='online' && x['deliveryAvailable']!=false && (x['activeOrderId']??'').toString().isEmpty && (x['pendingOrderId']??'').toString().isEmpty;
    }).toList();
    if(online.isEmpty){
      if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('No available delivery partner is online right now.')));
      return;
    }
    final selected=await showDialog<QueryDocumentSnapshot<Map<String,dynamic>>>(context:context,builder:(c)=>AlertDialog(
      title:const Text('Assign delivery partner'),
      content:SizedBox(width:420,child:ListView(shrinkWrap:true,children:online.map((d){
        final x=d.data();
        return ListTile(
          leading:const Icon(Icons.delivery_dining),
          title:Text((x['displayName']??x['email']??d.id).toString()),
          subtitle:Text((x['email']??'').toString()+' • Online & available'),
          onTap:()=>Navigator.pop(c,d),
        );
      }).toList())),
      actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cancel'))],
    ));
    if(selected==null)return;
    try{
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final latestOrder=await tx.get(order.reference);
        final latestPartner=await tx.get(selected.reference);
        final od=latestOrder.data()??{};
        final pd=latestPartner.data()??{};
        if((od['carrierUid']??'').toString().isNotEmpty) throw Exception('Order is already assigned.');
        if((pd['dutyStatus']??'offline').toString().toLowerCase()!='online'||pd['deliveryAvailable']==false||(pd['activeOrderId']??'').toString().isNotEmpty||(pd['pendingOrderId']??'').toString().isNotEmpty) throw Exception('This partner is no longer available.');
        tx.update(order.reference,{
          'carrierUid':selected.id,
          'assignedPartnerId':selected.id,
          'carrierName':(pd['displayName']??pd['email']??selected.id).toString(),
          'carrierEmail':(pd['email']??'').toString(),
          'carrierAccepted':false,
          'assignmentRejected':false,
          'status':'pending_acceptance',
          'statusNote':'Pending delivery partner acceptance',
          'customerMessage':'A delivery partner has been offered this order. Waiting for acceptance.',
          'assignedAt':FieldValue.serverTimestamp(),
          'assignmentMode':'manual',
          'updatedAt':FieldValue.serverTimestamp(),
        });
        tx.set(selected.reference,{
          'pendingOrderId':order.id,
          'updatedAt':FieldValue.serverTimestamp(),
        },SetOptions(merge:true));
      });
      if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Delivery partner assigned successfully.')));
    }catch(e){
      if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Assignment failed: '+e.toString())));
    }
  }

  @override Widget build(BuildContext context){
    return Card(child:ExpansionTile(leading:const Icon(Icons.assignment_ind_outlined),title:const Text('Delivery Assignment',style:TextStyle(fontWeight:FontWeight.w900)),subtitle:const Text('Assign available online delivery partners to orders'),children:[
      StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:FirebaseFirestore.instance.collection('orders').snapshots(),builder:(context,snapshot){
        if(!snapshot.hasData)return const Padding(padding:EdgeInsets.all(16),child:CircularProgressIndicator());
        final docs=snapshot.data!.docs.where((d){final x=d.data();final status=(x['status']??'').toString().toLowerCase();final assigned=(x['carrierUid']??'').toString().isNotEmpty;return (!assigned||status=='pending_acceptance')&&status!='delivered'&&status!='cancelled';}).take(30).toList();
        if(docs.isEmpty)return const Padding(padding:EdgeInsets.all(16),child:Text('No unassigned active orders.'));
        return Column(children:docs.map((d){
          final x=d.data();
          final hasCoords=x['customerLatitude'] is num && x['customerLongitude'] is num;
          return ListTile(
            title:Text('#'+(x['id']??d.id).toString(),style:const TextStyle(fontWeight:FontWeight.w800)),
            subtitle:Text((x['name']??'Customer').toString()+' • '+(x['status']??'').toString()+(hasCoords?' • Location saved':'')),
            trailing:((x['status']??'').toString().toLowerCase()=='pending_acceptance')?const Chip(label:Text('Pending Acceptance')):FilledButton(onPressed:()=>_assign(context,d),child:const Text('Assign')),
          );
        }).toList());
      }),
    ]));
  }
}

class AdminBroadcastPanel extends StatefulWidget {
  const AdminBroadcastPanel({super.key});
  @override State<AdminBroadcastPanel> createState()=>_AdminBroadcastPanelState();
}

class _AdminBroadcastPanelState extends State<AdminBroadcastPanel> {
  final title=TextEditingController();
  final body=TextEditingController();
  bool sending=false;

  @override void dispose(){title.dispose();body.dispose();super.dispose();}

  Future<void> _send() async {
    if(title.text.trim().isEmpty||body.text.trim().isEmpty){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter notification title and message.')));
      return;
    }
    setState(()=>sending=true);
    try{
      await FirebaseFirestore.instance.collection('notificationBroadcasts').add({
        'title':title.text.trim(),
        'body':body.text.trim(),
        'data':{'type':'global'},
        'createdAt':FieldValue.serverTimestamp(),
        'createdBy':FirebaseAuth.instance.currentUser?.uid??'',
        'status':'pending',
      });
      title.clear();body.clear();
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Broadcast queued for all users.')));
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not queue broadcast: '+e.toString())));
    }finally{if(mounted)setState(()=>sending=false);}
  }

  @override Widget build(BuildContext context)=>Card(
    child:ExpansionTile(
      leading:const Icon(Icons.campaign_outlined),
      title:const Text('Send notification to all users',style:TextStyle(fontWeight:FontWeight.w800)),
      children:[
        Padding(
          padding:const EdgeInsets.fromLTRB(16,0,16,16),
          child:Column(children:[
            TextField(controller:title,decoration:const InputDecoration(labelText:'Notification title')),
            const SizedBox(height:8),
            TextField(controller:body,maxLines:3,decoration:const InputDecoration(labelText:'Message')),
            const SizedBox(height:10),
            SizedBox(width:double.infinity,child:FilledButton.icon(
              onPressed:sending?null:_send,
              icon:const Icon(Icons.send_outlined),
              label:Text(sending?'Sending…':'Send to all users'),
            )),
          ]),
        ),
      ],
    ),
  );
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
            children: [              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
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
        title: const Text('Manage 3 Home Banners', style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: const Text('Replace any banner anytime — customers see all three rotating automatically.'),
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('settings').doc('banners').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Padding(padding: EdgeInsets.all(16), child: Text('Could not load banners.'));
              final urls = List<String>.from(snapshot.data?.data()?['imageUrls'] ?? const []);
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: List.generate(3, (index) {
                    final url = index < urls.length ? urls[index] : '';
                    return Card(
                      child: ListTile(
                        leading: SizedBox(
                          width: 72,height: 48,
                          child: url.isEmpty
                            ? const Icon(Icons.image_not_supported_outlined)
                            : Image.network(cloudinaryImageUrl(url,width:72,height:48),fit:BoxFit.cover,errorBuilder:(_,__,___)=>const Icon(Icons.broken_image)),
                        ),
                        title: Text('Banner ${index+1}'),
                        subtitle: Text(url.isEmpty?'No banner set':'Banner is active on the home page'),
                        trailing: TextButton.icon(
                          onPressed:()=>replaceBanner(index),
                          icon:const Icon(Icons.edit_outlined),
                          label:Text(url.isEmpty?'Add':'Replace'),
                        ),
                      ),
                    );
                  }),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> replaceBanner(int index) async {
    try {
      final image=await ImagePicker().pickImage(source:ImageSource.gallery,imageQuality:70,maxWidth:800);
      if(image==null)return;
      final url=await uploadImageToCloudinary(image,folder:'banners');
      final doc=FirebaseFirestore.instance.collection('settings').doc('banners');
      final snap=await doc.get();
      final urls=List<String>.from(snap.data()?['imageUrls']??const []);
      while(urls.length<3) urls.add('');
      urls[index]=url;
      await doc.set({
        'imageUrls':urls.take(3).toList(),
        'updatedAt':FieldValue.serverTimestamp(),
      },SetOptions(merge:true));
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('Banner ${index+1} updated successfully.')),
      );
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('Banner update failed: '+e.toString())),
      );
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
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.location_on_outlined),
                  title: const Text('Customer location', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text((order['address'] ?? 'Location address unavailable').toString()),
                  trailing: (order['customerLatitude'] is num && order['customerLongitude'] is num)
                    ? IconButton(
                        tooltip: 'Open customer location',
                        icon: const Icon(Icons.map_outlined),
                        onPressed: () {
                          final lat=(order['customerLatitude'] as num).toDouble();
                          final lng=(order['customerLongitude'] as num).toDouble();
                          launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),mode:LaunchMode.externalApplication);
                        },
                      )
                    : null,
                ),
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
                            : value == 'Ready for pickup'
                                ? 'Your order is ready for pickup'
                                : value == 'Assigned'
                                    ? 'Delivery partner assigned'
                                    : value == 'Picked up'
                                        ? 'Your order has been picked up'
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
                if ((order['carrierUid'] ?? '').toString().isNotEmpty &&
                    (status.toLowerCase() == 'assigned' || status.toLowerCase() == 'picked up' || status.toLowerCase() == 'out for delivery'))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LiveTrackingScreen(
                        collection: 'orders',
                        docId: doc.id,
                        title: 'Live delivery tracking',
                        mode: 'order',
                        readOnly: true,
                      ))),
                      icon: const Icon(Icons.location_searching),
                      label: const Text('Track delivery partner'),
                    ),
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
          const AdminBroadcastPanel(),
          const AdminDeliveryAssignmentPanel(),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Order Management', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('orders').snapshots(),
            builder: (context, countSnapshot) {
              final counts = <String,int>{for (final f in orderStatusFilters) f['value']!: 0};
              for (final doc in countSnapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String,dynamic>>>[]) {
                final key = normalizeOrderStatus((doc.data()['status'] ?? '').toString());
                if (counts.containsKey(key)) counts[key] = counts[key]! + 1;
              }
              return SizedBox(
                height: 54,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
                  itemCount: orderStatusFilters.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final filter = orderStatusFilters[index];
                    final value = filter['value']!;
                    final count = counts[value] ?? 0;
                    return ChoiceChip(
                      label: Text(filter['label']! + ' (' + count.toString() + ')'),
                      selected: selectedOrderStatusFilter == value,
                      onSelected: (selected) {
                        if (selected) setState(() => selectedOrderStatusFilter = value);
                      },
                    );
                  },
                ),
              );
            },
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
                final label = orderStatusFilters.firstWhere((x) => x['value'] == selectedOrderStatusFilter)['label']!;
                if (filteredDocs.isEmpty) return Center(child: Text('No ' + label.toLowerCase() + ' orders.'));
                return Column(children: [
                  Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 4), child: Align(alignment: Alignment.centerLeft, child: Text(label + ' Orders: ' + filteredDocs.length.toString(), style: const TextStyle(fontWeight: FontWeight.w800)))),
                  Expanded(child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) => orderCard(filteredDocs[index]),
                  )),
                ]);
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