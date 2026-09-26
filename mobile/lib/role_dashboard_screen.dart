import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'role_workspace_screen.dart';

class RoleDashboardScreen extends StatefulWidget {
  final String role;
  final User user;
  final Widget child;
  final VoidCallback onSignOut;
  const RoleDashboardScreen({super.key, required this.role, required this.user, required this.child, required this.onSignOut});

  @override State<RoleDashboardScreen> createState() => _RoleDashboardScreenState();
}

class _RoleDashboardScreenState extends State<RoleDashboardScreen> {
  int tab = 0;
  Map<String,dynamic> profile = {};
  bool loadingProfile = true;

  Color get accent => switch(widget.role) {
    'admin' => const Color(0xFFC2185B),
    'seller' => const Color(0xFF119447),
    'delivery_partner' => const Color(0xFF1565C0),
    'carrier' => const Color(0xFF5B1ACF),
    _ => Colors.black,
  };
  Color get soft => Color.alphaBlend(accent.withOpacity(.07), const Color(0xFFFFF8FA));
  bool get admin => widget.role == 'admin';
  bool get seller => widget.role == 'seller';
  bool get delivery => widget.role == 'delivery_partner';
  bool get carrier => widget.role == 'carrier';

  String get title => switch(widget.role) {
    'admin' => 'ALLways Admin',
    'seller' => 'ALLways Seller',
    'delivery_partner' => 'ALLways Delivery Partner',
    'carrier' => 'ALLways Carrier',
    _ => 'ALLways',
  };
  IconData get icon => switch(widget.role) {
    'admin' => Icons.workspace_premium,
    'seller' => Icons.storefront,
    'delivery_partner' => Icons.delivery_dining,
    'carrier' => Icons.two_wheeler,
    _ => Icons.dashboard,
  };

  @override void initState(){super.initState(); _loadProfile();}

  Future<void> _loadProfile() async {
    try {
      final col = seller ? 'sellers' : carrier ? 'ridePartners' : 'customers';
      final snap = await FirebaseFirestore.instance.collection(col).doc(widget.user.uid).get();
      if(mounted) setState((){profile=snap.data()??{}; loadingProfile=false;});
    } catch (_) { if(mounted) setState(()=>loadingProfile=false); }
  }

  String get name {
    final n=(profile['businessName']??profile['shopName']??profile['name']??profile['fullName']??'').toString().trim();
    return n.isNotEmpty ? n : ((widget.user.displayName??'').trim().isNotEmpty ? widget.user.displayName!.trim() : 'ALLways Account');
  }
  String get status {
    if(admin)return 'Super Admin';
    if(seller)return '✓ Verified Seller';
    final s=(profile['status']??profile['dutyStatus']??'offline').toString().toLowerCase();
    return s=='online'?'Online':'Offline';
  }

  List<_Stat> get stats => switch(widget.role) {
    'admin' => const [_Stat('23','Pending Orders',Icons.receipt_long),_Stat('12','Active Deliveries',Icons.delivery_dining),_Stat('8','Active Carriers',Icons.two_wheeler),_Stat('52','Total Sellers',Icons.storefront)],
    'seller' => const [_Stat('12','Total Orders',Icons.receipt_long),_Stat('4','Pending',Icons.schedule),_Stat('3','Preparing',Icons.inventory_2),_Stat('5','Completed',Icons.check_circle)],
    'delivery_partner' => const [_Stat('5',"Today's Deliveries",Icons.local_shipping),_Stat('₹620',"Today's Earnings",Icons.currency_rupee),_Stat('4.8','Rating',Icons.star),_Stat('98%','Completion',Icons.task_alt)],
    'carrier' => const [_Stat('5',"Today's Rides",Icons.two_wheeler),_Stat('₹420',"Today's Earnings",Icons.currency_rupee),_Stat('4.8','Rating',Icons.star),_Stat('100%','Acceptance',Icons.verified)],
    _ => const [],
  };

  List<_Action> get actions => switch(widget.role) {
    'admin' => const [
      _Action('Manage Sellers',Icons.storefront),_Action('Manage Carriers',Icons.two_wheeler),_Action('Manage Delivery Partners',Icons.delivery_dining),
      _Action('Manage Orders',Icons.receipt_long),_Action('Manage Banners',Icons.view_carousel),_Action('Send Notifications',Icons.campaign),
      _Action('Users & Roles',Icons.manage_accounts),_Action('Reports & Analytics',Icons.analytics),_Action('App Settings',Icons.settings),
    ],
    'seller' => const [
      _Action('Products',Icons.inventory_2),_Action('Orders',Icons.receipt_long),_Action('Shop Profile',Icons.storefront),_Action('Offers',Icons.local_offer),
      _Action('Inventory',Icons.fact_check),_Action('Sales Analytics',Icons.bar_chart),_Action('Payouts',Icons.account_balance_wallet),_Action('Support',Icons.support_agent),
    ],
    'delivery_partner' => const [
      _Action('Delivery Requests',Icons.local_shipping),_Action('My Deliveries',Icons.assignment_turned_in),_Action('Earnings',Icons.currency_rupee),_Action('Incentives',Icons.card_giftcard),
      _Action('Performance',Icons.bar_chart),_Action('Documents',Icons.description),_Action('Safety & SOS',Icons.shield),_Action('Help & Support',Icons.support_agent),
    ],
    'carrier' => const [
      _Action('Ride Requests',Icons.two_wheeler),_Action('My Rides',Icons.route),_Action('Earnings',Icons.currency_rupee),_Action('Ratings',Icons.star),
      _Action('Ride History',Icons.history),_Action('Vehicle & Documents',Icons.description),_Action('Safety & SOS',Icons.shield),_Action('Help & Support',Icons.support_agent),
    ],
    _ => const [],
  };

  Future<void> openWorkspace(String section) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoleFeatureScreen(
          role: widget.role,
          feature: section,
          user: widget.user,
          accent: accent,
        ),
      ),
    );
    if (mounted) _loadProfile();
  }

  void account() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (s) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: accent.withOpacity(.12),
                  child: Icon(icon, color: accent),
                ),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(widget.user.email ?? ''),
              ),
              const ListTile(
                leading: Icon(Icons.person_outline),
                title: Text('Profile & documents'),
              ),
              const ListTile(
                leading: Icon(Icons.help_outline),
                title: Text('Help & support'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: () {
                  Navigator.pop(s);
                  widget.onSignOut();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFFFFF8FA),
    body:SafeArea(child:IndexedStack(index:tab,children:[
      home(),
      section(admin?'Live Operations':seller?'Orders':delivery?'Deliveries':'Rides'),
      section(admin?'Reports & Analytics':seller?'Sales Analytics':'Earnings'),
      section(admin?'Users & Roles':'Profile & Settings'),
    ])),
    bottomNavigationBar:navigation(),
  );

  Widget home()=>RefreshIndicator(
    onRefresh:_loadProfile,
    child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:const EdgeInsets.fromLTRB(18,10,18,24),children:[
      Row(children:[Icon(icon,color:accent,size:28),const SizedBox(width:10),Expanded(child:Text(title,style:const TextStyle(fontSize:22,fontWeight:FontWeight.w900)))]),
      const SizedBox(height:18),
      profileCard(),
      const SizedBox(height:16),
      statsRow(),
      const SizedBox(height:18),
      const Text('Quick Actions',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900)),
      const SizedBox(height:10),
      actionGrid(),
      if(delivery||carrier) ...[const SizedBox(height:18),liveMap()],
      const SizedBox(height:18),
      recent(),
      const SizedBox(height:18),
      performance(),
    ]),
  );

  Widget profileCard(){
    final photo=(profile['photoUrl']??profile['profilePhoto']??'').toString().trim();
    final online=status=='Online';
    return Card(elevation:0,color:soft,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(24)),child:Padding(
      padding:const EdgeInsets.fromLTRB(16,16,12,16),
      child:Row(children:[
        CircleAvatar(radius:30,backgroundColor:accent.withOpacity(.12),backgroundImage:photo.isEmpty?null:NetworkImage(photo),
          child:photo.isEmpty?Text(name.substring(0,1).toUpperCase(),style:TextStyle(fontSize:22,fontWeight:FontWeight.w900,color:accent)):null),
        const SizedBox(width:14),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900)),
          const SizedBox(height:3),Text(status,style:TextStyle(fontSize:12,color:accent,fontWeight:FontWeight.w700)),
          const SizedBox(height:2),Text(profileLine(),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12)),
        ])),
        if(delivery||carrier) Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:7),decoration:BoxDecoration(color:online?const Color(0xFFE2F7E9):Colors.black12,borderRadius:BorderRadius.circular(20)),child:Row(children:[Container(width:8,height:8,decoration:BoxDecoration(color:online?Colors.green:Colors.grey,shape:BoxShape.circle)),const SizedBox(width:5),Text(status,style:TextStyle(fontSize:11,fontWeight:FontWeight.w800,color:online?Colors.green.shade800:Colors.black54))]))
        else IconButton(onPressed:account,icon:const Icon(Icons.chevron_right)),
      ]),
    ));
  }

  String profileLine(){
    if(seller)return (profile['catalogueCount']??profile['catalogueItems']??0).toString()+'/50 catalogue items';
    if(delivery)return (profile['vehicleNumber']??profile['vehicle']??'Vehicle details').toString();
    if(carrier)return (profile['vehicleNumber']??'Vehicle').toString()+' • '+(profile['vehicleType']??'Bike').toString();
    return 'ALLways platform management';
  }

  Widget statsRow()=>SizedBox(height:92,child:ListView.separated(scrollDirection:Axis.horizontal,itemCount:stats.length,separatorBuilder:(_,__)=>const SizedBox(width:8),itemBuilder:(_,i)=>Container(
    width:118,padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:[const Color(0xFFFFE5EA),const Color(0xFFE8F3FF),const Color(0xFFF0E8FF),const Color(0xFFE7F8EC)][i%4],borderRadius:BorderRadius.circular(16)),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(stats[i].icon,size:18,color:accent),const Spacer(),Text(stats[i].value,style:const TextStyle(fontSize:19,fontWeight:FontWeight.w900)),Text(stats[i].label,maxLines:2,style:const TextStyle(fontSize:10.5))]),
  )));

  Widget actionGrid()=>GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),itemCount:actions.length,gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:3,mainAxisSpacing:9,crossAxisSpacing:9,childAspectRatio:.96),itemBuilder:(_,i){
    final a=actions[i]; return InkWell(borderRadius:BorderRadius.circular(15),onTap:()=>openWorkspace(a.title),child:Container(
      padding:const EdgeInsets.all(8),decoration:BoxDecoration(color:soft,borderRadius:BorderRadius.circular(15),border:Border.all(color:accent.withOpacity(.06))),
      child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(a.icon,color:accent,size:26),const SizedBox(height:7),Text(a.title,textAlign:TextAlign.center,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11.5,fontWeight:FontWeight.w700))]),
    ));
  });

  Widget recent(){
    final heading=admin?'Recent Orders':seller?"Today's Orders":delivery?'Recent Deliveries':'Recent Rides';
    final states=carrier?['Ride request','Completed ride','Completed ride']:delivery?['New delivery','Preparing','Completed']:['New Order','Preparing','Confirmed'];
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Text(heading,style:const TextStyle(fontSize:19,fontWeight:FontWeight.w900)),const Spacer(),TextButton(onPressed:()=>openWorkspace(heading),child:Text('View All',style:TextStyle(color:accent)))]),
      ...List.generate(3,(i)=>Card(elevation:0,margin:const EdgeInsets.only(bottom:8),color:soft,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(16)),child:ListTile(
        leading:CircleAvatar(backgroundColor:accent.withOpacity(.10),child:Icon(carrier?Icons.two_wheeler:delivery?Icons.local_shipping:Icons.receipt_long,color:accent)),
        title:Text(['#AW425454459','#AW425371404','#AW425336958'][i],style:const TextStyle(fontWeight:FontWeight.w800,fontSize:13)),
        subtitle:Text(['Aastha • ₹324','Pooja Singh • ₹405','Rohan • ₹324'][i]),
        trailing:Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:5),decoration:BoxDecoration(color:accent.withOpacity(.10),borderRadius:BorderRadius.circular(14)),child:Text(states[i],style:TextStyle(color:accent,fontSize:10,fontWeight:FontWeight.w800))),
      ))),
    ]);
  }

  Widget performance(){
    final values=admin?[('52','Active Sellers'),('18','Online Partners'),('12','Online Carriers')]:seller?[('₹4,320','Total Sales'),('86','Product Views'),('12','New Customers')]:delivery?[('₹3,420','This Week'),('28','Deliveries'),('4.8','Rating')]:[('₹2,940','This Week'),('21','Rides'),('4.8','Rating')];
    return Card(elevation:0,color:soft,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(20)),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(admin?'Platform Overview':seller?'Shop Performance':delivery?'Delivery Performance':'Ride Performance',style:const TextStyle(fontSize:17,fontWeight:FontWeight.w900)),
      const SizedBox(height:12),Row(children:values.map((x)=>Expanded(child:Column(children:[Text(x.$1,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w900)),const SizedBox(height:3),Text(x.$2,textAlign:TextAlign.center,style:const TextStyle(fontSize:10))]))).toList()),
    ])));
  }

  Widget liveMap()=>_RoleLiveMap(accent:accent,carrier:carrier,onOpen:()=>openWorkspace(carrier?'Ride Requests':'Delivery Requests'));

  Widget section(String label) {
    final List<_Action> sectionActions;
    if (admin) {
      sectionActions = label == 'Live Operations'
          ? const [
              _Action('Manage Orders', Icons.receipt_long),
              _Action('Manage Delivery Partners', Icons.delivery_dining),
              _Action('Manage Carriers', Icons.two_wheeler),
              _Action('Manage Sellers', Icons.storefront),
            ]
          : label == 'Reports & Analytics'
              ? const [
                  _Action('Reports & Analytics', Icons.analytics),
                  _Action('Users & Roles', Icons.manage_accounts),
                ]
              : const [
                  _Action('Users & Roles', Icons.manage_accounts),
                  _Action('App Settings', Icons.settings),
                ];
    } else if (seller) {
      sectionActions = label == 'Orders'
          ? const [_Action('Orders', Icons.receipt_long), _Action('Inventory', Icons.fact_check)]
          : label == 'Sales Analytics'
              ? const [_Action('Sales Analytics', Icons.bar_chart), _Action('Payouts', Icons.account_balance_wallet)]
              : const [
                  _Action('Shop Profile', Icons.storefront),
                  _Action('Products', Icons.inventory_2),
                  _Action('Offers', Icons.local_offer),
                  _Action('Help & Support', Icons.support_agent),
                ];
    } else if (delivery) {
      sectionActions = label == 'Deliveries'
          ? const [_Action('Delivery Requests', Icons.local_shipping), _Action('My Deliveries', Icons.assignment_turned_in)]
          : label == 'Earnings'
              ? const [_Action('Earnings', Icons.currency_rupee), _Action('Performance', Icons.bar_chart), _Action('Incentives', Icons.card_giftcard)]
              : const [
                  _Action('Documents', Icons.description),
                  _Action('Safety & SOS', Icons.shield),
                  _Action('Help & Support', Icons.support_agent),
                  _Action('Profile & Settings', Icons.person),
                ];
    } else {
      sectionActions = label == 'Rides'
          ? const [_Action('Ride Requests', Icons.two_wheeler), _Action('My Rides', Icons.route), _Action('Ride History', Icons.history)]
          : label == 'Earnings'
              ? const [_Action('Earnings', Icons.currency_rupee), _Action('Ratings', Icons.star)]
              : const [
                  _Action('Vehicle & Documents', Icons.description),
                  _Action('Safety & SOS', Icons.shield),
                  _Action('Help & Support', Icons.support_agent),
                  _Action('Profile & Settings', Icons.person),
                ];
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 28),
      children: [
        Icon(icon, size: 54, color: accent),
        const SizedBox(height: 12),
        Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(
          'Choose exactly what you want to manage.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 20),
        ...sectionActions.map(
          (a) => Card(
            elevation: 0,
            color: soft,
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              leading: CircleAvatar(
                backgroundColor: accent.withOpacity(.10),
                child: Icon(a.icon, color: accent),
              ),
              title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('Open this section separately'),
              trailing: Icon(Icons.chevron_right, color: accent),
              onTap: () => openWorkspace(a.title),
            ),
          ),
        ),
      ],
    );
  }

  Widget navigation(){
    final labels=admin?const['Home','Operations','Analytics','Users']:seller?const['Home','Orders','Analytics','Profile']:delivery?const['Home','Deliveries','Earnings','Profile']:const['Home','Rides','Earnings','Profile'];
    final icons=admin?const[Icons.home,Icons.tune,Icons.analytics,Icons.manage_accounts]:seller?const[Icons.home,Icons.receipt_long,Icons.bar_chart,Icons.person]:delivery?const[Icons.home,Icons.local_shipping,Icons.account_balance_wallet,Icons.person]:const[Icons.home,Icons.two_wheeler,Icons.account_balance_wallet,Icons.person];
    return NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (v) => setState(() => tab = v),
      destinations: List.generate(
        4,
        (i) => NavigationDestination(
          icon: Icon(icons[i]),
          selectedIcon: Icon(icons[i], color: accent),
          label: labels[i],
        ),
      ),
    );
  }
}

class _RoleLiveMap extends StatefulWidget {
  final Color accent; final bool carrier; final VoidCallback onOpen;
  const _RoleLiveMap({required this.accent,required this.carrier,required this.onOpen});
  @override State<_RoleLiveMap> createState()=>_RoleLiveMapState();
}
class _RoleLiveMapState extends State<_RoleLiveMap> {
  Position? position; Timer? timer;
  @override void initState(){super.initState();load();timer=Timer.periodic(const Duration(seconds:15),(_)=>load());}
  @override void dispose(){timer?.cancel();super.dispose();}
  Future<void> load() async {
    try{
      if(!await Geolocator.isLocationServiceEnabled())return;
      var p=await Geolocator.checkPermission(); if(p==LocationPermission.denied)p=await Geolocator.requestPermission();
      if(p==LocationPermission.denied||p==LocationPermission.deniedForever)return;
      final x=await Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.high,distanceFilter:10));
      if(mounted)setState(()=>position=x);
    }catch(_){}
  }
  @override Widget build(BuildContext context){
    final center=LatLng(position?.latitude??25.16,position?.longitude??82.04);
    return Card(elevation:0,clipBehavior:Clip.antiAlias,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(20)),child:SizedBox(height:250,child:Stack(children:[
      FlutterMap(options:MapOptions(initialCenter:center,initialZoom:13.2),children:[
        TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',userAgentPackageName:'in.allways.app'),
        MarkerLayer(markers:[Marker(point:center,width:58,height:58,child:Container(decoration:BoxDecoration(color:widget.accent,shape:BoxShape.circle,border:Border.all(color:Colors.white,width:4)),child:Icon(widget.carrier?Icons.two_wheeler:Icons.delivery_dining,color:Colors.white,size:28)))])
      ]),
      Positioned(top:12,left:12,right:12,child:Container(padding:const EdgeInsets.symmetric(horizontal:14,vertical:11),decoration:BoxDecoration(color:Colors.white.withOpacity(.94),borderRadius:BorderRadius.circular(15)),child:Row(children:[Icon(Icons.location_on,color:widget.accent),const SizedBox(width:8),Expanded(child:Text(position==null?'Getting your live location…':'Live location • GPS updating',style:const TextStyle(fontWeight:FontWeight.w800)))]))),
      Positioned(bottom:12,left:12,right:12,child:FilledButton.icon(onPressed:widget.onOpen,icon:const Icon(Icons.near_me),label:Text(widget.carrier?'View ride requests':'View delivery requests'))),
    ])));
  }
}

class _Stat { final String value,label; final IconData icon; const _Stat(this.value,this.label,this.icon); }
class _Action { final String title; final IconData icon; const _Action(this.title,this.icon); }
