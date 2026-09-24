          textTheme:GoogleFonts.interTextTheme(ThemeData.dark(useMaterial3:true).textTheme),
        ),
        themeMode:mode,
        home:const Shell(),
      ),
  );
}

class Product {
  final String id,name,category,icon,description,brand,sellerId; final num price,stock;
  const Product({required this.id,required this.name,required this.category,required this.icon,required this.description,required this.brand,required this.sellerId,required this.price,required this.stock});
  factory Product.fromJson(Map<String,dynamic> j){
    num n(dynamic x)=>x is num?x:num.tryParse(x?.toString()??'')??0;
    return Product(id:(j['id']??'').toString(),name:(j['name']??j['title']??'Item').toString(),
      category:(j['category']??j['cat']??'Other').toString(),icon:(j['icon']??'🛍️').toString(),
      description:(j['description']??'').toString(),brand:(j['brand']??'').toString(),sellerId:(j['sellerId']??j['sellerUid']??j['vendorId']??'').toString(),
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