import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class RoleFeatureScreen extends StatelessWidget {
  final String role;
  final String feature;
  final User user;
  final Color accent;

  const RoleFeatureScreen({
    super.key,
    required this.role,
    required this.feature,
    required this.user,
    required this.accent,
  });

  IconData get featureIcon {
    const m = <String, IconData>{
      'Manage Sellers': Icons.storefront, 'Manage Carriers': Icons.two_wheeler,
      'Manage Delivery Partners': Icons.delivery_dining, 'Manage Orders': Icons.receipt_long,
      'Manage Banners': Icons.view_carousel, 'Send Notifications': Icons.campaign,
      'Users & Roles': Icons.manage_accounts, 'Reports & Analytics': Icons.analytics,
      'App Settings': Icons.settings, 'Products': Icons.inventory_2, 'Orders': Icons.receipt_long,
      'Shop Profile': Icons.storefront, 'Offers': Icons.local_offer, 'Inventory': Icons.fact_check,
      'Sales Analytics': Icons.bar_chart, 'Payouts': Icons.account_balance_wallet,
      'Delivery Requests': Icons.local_shipping, 'My Deliveries': Icons.assignment_turned_in,
      'Earnings': Icons.currency_rupee, 'Incentives': Icons.card_giftcard, 'Performance': Icons.bar_chart,
      'Documents': Icons.description, 'Safety & SOS': Icons.shield, 'Help & Support': Icons.support_agent,
      'Ride Requests': Icons.two_wheeler, 'My Rides': Icons.route, 'Ratings': Icons.star,
      'Ride History': Icons.history, 'Vehicle & Documents': Icons.description,
      'Profile & Settings': Icons.person,
    };
    return m[feature] ?? Icons.dashboard;
  }

  String get roleLabel {
    if (role == 'admin') return 'Platform control';
    if (role == 'seller') return 'Shop management';
    if (role == 'delivery_partner') return 'Delivery partner';
    if (role == 'carrier') return 'Rider operations';
    return 'ALLways';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFFF8FA),
    appBar: AppBar(
      backgroundColor: const Color(0xFFFFF8FA),
      elevation: 0,
      foregroundColor: Colors.black87,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(feature, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
        Text(roleLabel, style: TextStyle(fontSize: 11, color: accent, fontWeight: FontWeight.w700)),
      ]),
      actions: [
        IconButton(
          tooltip: 'Help',
          onPressed: () => _info(context, feature, 'This is a dedicated ALLways section for ' + feature + '.'),
          icon: const Icon(Icons.help_outline),
        ),
      ],
    ),
    body: SafeArea(child: _content(context)),
  );

  Widget _content(BuildContext context) {
    if (feature == 'Products' || feature == 'Inventory') return _sellerCatalog();
    if (feature == 'Orders' || feature == 'Manage Orders') return _orders();
    if (feature == 'Delivery Requests') return _requests(true);
    if (feature == 'My Deliveries') return _assigned(true);
    if (feature == 'Ride Requests') return _requests(false);
    if (feature == 'My Rides' || feature == 'Ride History') return _assigned(false);
    if (feature == 'Earnings' || feature == 'Payouts') return _earnings();
    if (feature == 'Manage Sellers') return _collection('sellers', 'Seller');
    if (feature == 'Manage Carriers') return _collection('ridePartners', 'Carrier');
    if (feature == 'Manage Delivery Partners') return _collection('customers', 'Delivery Partner', roleFilter: 'delivery_partner');
    if (feature == 'Users & Roles') return _collection('customers', 'User', showRole: true);
    if (feature == 'Sales Analytics' || feature == 'Reports & Analytics' || feature == 'Performance' || feature == 'Ratings') return _metrics();
    return _structuredMenu(context);
  }

  Widget _page(List<Widget> children) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
    children: children,
  );

  Widget _header(String title, String text) => Card(
    elevation: 0,
    color: accent.withOpacity(.07),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        CircleAvatar(
          radius: 27,
          backgroundColor: accent.withOpacity(.12),
          child: Icon(featureIcon, color: accent, size: 27),
        ),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(text, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
        ])),
      ]),
    ),
  );

  Widget _sellerCatalog() => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('sellers').doc(user.uid).snapshots(),
    builder: (context, snap) {
      if (snap.hasError) return _page([_header(feature, 'Could not read seller data.'), _error(snap.error.toString())]);
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final data = snap.data!.data() ?? <String, dynamic>{};
      final raw = data['items'];
      final items = raw is List ? raw.whereType<Map>().map((x) => Map<String, dynamic>.from(x)).toList() : <Map<String, dynamic>>[];
      final inStock = items.where((x) => _num(x['stock']) > 0).length;
      return _page([
        _header(feature, items.isEmpty ? 'No catalogue items loaded yet.' : 'Your catalogue and stock are shown separately from orders.'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _metric(items.length.toString(), 'Listed', Icons.inventory_2)),
          const SizedBox(width: 8),
          Expanded(child: _metric(inStock.toString(), 'In stock', Icons.check_circle_outline)),
          const SizedBox(width: 8),
          Expanded(child: _metric((items.length - inStock).toString(), 'Out', Icons.remove_shopping_cart_outlined)),
        ]),
        const SizedBox(height: 12),
        if (items.isEmpty) _empty('No catalogue items', 'Add products in your seller catalogue and they will appear here.')
        else ...items.map((x) {
          final stock = _num(x['stock']);
          return Card(
            elevation: 0,
            child: ListTile(
              leading: _avatar((x['imageUrl'] ?? x['image'] ?? '').toString()),
              title: Text((x['name'] ?? x['title'] ?? 'Product').toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('₹' + _num(x['price']).toStringAsFixed(0) + ' • ' + stock.toStringAsFixed(0) + ' in stock\n' + (x['category'] ?? 'Other').toString()),
              isThreeLine: true,
              trailing: Icon(stock > 0 ? Icons.check_circle : Icons.warning_amber_rounded, color: stock > 0 ? Colors.green : Colors.orange),
            ),
          );
        }),
      ]);
    },
  );

  Widget _orders() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('orders').snapshots(),
    builder: (context, snap) {
      if (snap.hasError) return _page([_header(feature, 'Order management'), _error(snap.error.toString())]);
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final docs = snap.data!.docs.where((d) {
        final o = d.data();
        if (role == 'seller') return (o['sellerId'] ?? o['sellerUid'] ?? '').toString() == user.uid;
        if (role == 'delivery_partner' || role == 'carrier') return (o['carrierUid'] ?? '').toString() == user.uid;
        return true;
      }).toList()..sort((a,b) => _time(b.data()['createdAt']).compareTo(_time(a.data()['createdAt'])));
      return _page([
        _header(feature, 'Every order is kept in this dedicated section.'),
        const SizedBox(height: 12),
        _metric(docs.length.toString(), 'Orders', Icons.receipt_long),
        const SizedBox(height: 12),
        if (docs.isEmpty) _empty('No orders here', 'Matching orders will appear automatically.')
        else ...docs.map((d) => _orderTile(context, d)),
      ]);
    },
  );

  Widget _requests(bool delivery) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('orders').snapshots(),
    builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final docs = snap.data!.docs.where((d) {
        final o = d.data();
        final s = (o['status'] ?? '').toString().toLowerCase();
        final assigned = (o['carrierUid'] ?? '').toString();
        if (assigned == user.uid && s == 'pending_acceptance') return true;
        if (assigned.isNotEmpty) return false;
        return s != 'delivered' && s != 'cancelled' && (delivery || s.contains('ride'));
      }).toList();
      return _page([
        _header(feature, delivery ? 'Review delivery offers before accepting.' : 'Keep ride requests separate from completed rides.'),
        const SizedBox(height: 12),
        if (docs.isEmpty) _empty('No requests', 'New requests will appear here when available.')
        else ...docs.map((d) => _requestTile(context, d, delivery)),
      ]);
    },
  );

  Widget _assigned(bool delivery) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('orders').where('carrierUid', isEqualTo: user.uid).snapshots(),
    builder: (context, snap) {
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final docs = snap.data!.docs.where((d) {
        final s = (d.data()['status'] ?? '').toString().toLowerCase();
        return delivery ? s != 'delivered' && s != 'cancelled' : s == 'delivered';
      }).toList();
      return _page([
        _header(feature, delivery ? 'Your active delivery queue.' : 'Your completed ride history.'),
        const SizedBox(height: 12),
        if (docs.isEmpty) _empty('Nothing here yet', 'Assigned or completed work will appear automatically.')
        else ...docs.map((d) => _orderTile(context, d)),
      ]);
    },
  );

  Widget _earnings() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('orders').where('carrierUid', isEqualTo: user.uid).snapshots(),
    builder: (context, snap) {
      num total = 0; int done = 0;
      for (final d in snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String,dynamic>>>[]) {
        final o = d.data();
        if ((o['status'] ?? '').toString().toLowerCase() == 'delivered') {
          done++;
          total += _num(o['deliveryFee'] ?? o['partnerEarning'] ?? o['total']);
        }
      }
      return _page([
        _header(feature, 'Completed work and earnings stay together here.'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _metric('₹' + total.toStringAsFixed(0), 'Completed earnings', Icons.currency_rupee)),
          const SizedBox(width: 8),
          Expanded(child: _metric(done.toString(), 'Completed', Icons.check_circle_outline)),
        ]),
        const SizedBox(height: 14),
        if (snap.hasError) _error(snap.error.toString())
        else if (snap.data == null) const Center(child: CircularProgressIndicator())
        else if (snap.data!.docs.isEmpty) _empty('No completed work', 'Your earnings history will appear after completed work.')
        else ...snap.data!.docs.where((d) => (d.data()['status'] ?? '').toString().toLowerCase() == 'delivered').map((d) {
          final o = d.data();
          return Card(elevation: 0, child: ListTile(
            leading: CircleAvatar(backgroundColor: accent.withOpacity(.10), child: Icon(Icons.currency_rupee, color: accent)),
            title: Text('#' + (o['id'] ?? d.id).toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text((o['name'] ?? o['customerName'] ?? 'Customer').toString()),
            trailing: Text('₹' + _num(o['deliveryFee'] ?? o['partnerEarning'] ?? o['total']).toStringAsFixed(0), style: const TextStyle(fontWeight: FontWeight.w900)),
          ));
        }),
      ]);
    },
  );

  Widget _collection(String name, String label, {String? roleFilter, bool showRole = false}) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection(name).snapshots(),
    builder: (context, snap) {
      if (snap.hasError) return _page([_header(feature, 'Live ' + label + ' records.'), _error(snap.error.toString())]);
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      var docs = snap.data!.docs.toList();
      if (roleFilter != null) docs = docs.where((d) => (d.data()['role'] ?? '').toString().toLowerCase() == roleFilter).toList();
      return _page([
        _header(feature, 'Dedicated ' + label.toLowerCase() + ' management.'),
        const SizedBox(height: 12),
        _metric(docs.length.toString(), label == 'User' ? 'Accounts' : label, Icons.people_outline),
        const SizedBox(height: 12),
        if (docs.isEmpty) _empty('No records found', 'No matching records are currently available.')
        else ...docs.map((d) {
          final x = d.data();
          final n = (x['businessName'] ?? x['shopName'] ?? x['displayName'] ?? x['name'] ?? x['email'] ?? d.id).toString();
          final s = (x['status'] ?? x['dutyStatus'] ?? 'active').toString();
          return Card(elevation: 0, child: ListTile(
            leading: CircleAvatar(backgroundColor: accent.withOpacity(.10), child: Icon(featureIcon, color: accent)),
            title: Text(n, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(showRole ? (x['role'] ?? 'customer').toString() + ' • ' + s : s),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _info(context, n, (x['email'] ?? '').toString() + '\n' + (x['mobileNumber'] ?? x['phone'] ?? '').toString() + '\n' + s),
          ));
        }),
      ]);
    },
  );

  Widget _metrics() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('orders').snapshots(),
    builder: (context, snap) {
      final all = snap.data?.docs ?? const <QueryDocumentSnapshot<Map<String,dynamic>>>[];
      final docs = all.where((d) {
        final o=d.data();
        if (role == 'seller') return (o['sellerId'] ?? o['sellerUid'] ?? '').toString() == user.uid;
        if (role == 'delivery_partner' || role == 'carrier') return (o['carrierUid'] ?? '').toString() == user.uid;
        return true;
      }).toList();
      final completed = docs.where((d) => (d.data()['status'] ?? '').toString().toLowerCase() == 'delivered').length;
      num value=0; for(final d in docs) value += _num(d.data()['total']);
      return _page([
        _header(feature, 'Focused metrics from live ALLways data.'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _metric(docs.length.toString(), 'Records', Icons.receipt_long)),
          const SizedBox(width: 8),
          Expanded(child: _metric(completed.toString(), 'Completed', Icons.check_circle_outline)),
          const SizedBox(width: 8),
          Expanded(child: _metric('₹' + value.toStringAsFixed(0), 'Value', Icons.currency_rupee)),
        ]),
        const SizedBox(height: 16),
        Card(elevation: 0, child: ListTile(
          leading: Icon(featureIcon, color: accent),
          title: Text(feature, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: const Text('This section is isolated from day-to-day operations so it stays easy to use.'),
        )),
      ]);
    },
  );

  Widget _structuredMenu(BuildContext context) {
    List<(String,IconData)> options;
    if (feature == 'Shop Profile') {
      options=[('Business details',Icons.storefront),('Opening hours',Icons.schedule),('Delivery settings',Icons.local_shipping),('Seller photo',Icons.image)];
    } else if (feature == 'Offers') {
      options=[('Active offers',Icons.local_offer),('Create offer',Icons.add_circle_outline),('Offer history',Icons.history)];
    } else if (feature == 'Incentives') {
      options=[('Current incentives',Icons.card_giftcard),('Daily target',Icons.flag),('Bonus history',Icons.history)];
    } else if (feature == 'Documents' || feature == 'Vehicle & Documents') {
      options=[('Verification status',Icons.verified_user),('Vehicle documents',Icons.description),('Update document',Icons.upload_file)];
    } else if (feature == 'Safety & SOS') {
      options=[('Emergency contact',Icons.contact_phone),('SOS',Icons.sos),('Trip safety',Icons.shield)];
    } else if (feature == 'Help & Support') {
      options=[('Order issue',Icons.receipt_long),('Account help',Icons.support_agent),('Contact support',Icons.support_agent)];
    } else {
      options=[('Notifications',Icons.notifications_outlined),('Location',Icons.location_on_outlined),('Language',Icons.language),('Account',Icons.person)];
    }
    return _page([
      _header(feature, 'Each option is kept inside its own role section.'),
      const SizedBox(height: 12),
      ...options.map((x) => Card(elevation: 0, child: ListTile(
        leading: CircleAvatar(backgroundColor: accent.withOpacity(.10), child: Icon(x.$2, color: accent)),
        title: Text(x.$1, style: const TextStyle(fontWeight: FontWeight.w800)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _info(context, x.$1, x.$1 + ' is isolated from the other ' + feature + ' controls.'),
      ))),
    ]);
  }

  Widget _orderTile(BuildContext context, QueryDocumentSnapshot<Map<String,dynamic>> d) {
    final o=d.data(); final status=(o['status']??'New Order').toString();
    return Card(elevation:0, child:ListTile(
      leading:CircleAvatar(backgroundColor:accent.withOpacity(.10),child:Icon(role=='carrier'?Icons.two_wheeler:Icons.receipt_long,color:accent)),
      title:Text('#'+(o['id']??d.id).toString(),style:const TextStyle(fontWeight:FontWeight.w800)),
      subtitle:Text((o['name']??o['customerName']??'Customer').toString()+' • '+status),
      trailing:Text('₹'+_num(o['total']).toStringAsFixed(0),style:const TextStyle(fontWeight:FontWeight.w900)),
      onTap:()=>_info(context,'#'+(o['id']??d.id).toString(),'Status: '+status+'\nAddress: '+(o['address']??'Not available').toString()+'\nPhone: '+(o['phone']??'').toString()),
    ));
  }

  Widget _requestTile(BuildContext context, QueryDocumentSnapshot<Map<String,dynamic>> d, bool delivery) {
    final o=d.data();
    final mine=(o['carrierUid']??'').toString()==user.uid;
    return Card(elevation:0,child:Padding(
      padding:const EdgeInsets.all(12),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[
          CircleAvatar(backgroundColor:accent.withOpacity(.10),child:Icon(delivery?Icons.local_shipping:Icons.two_wheeler,color:accent)),
          const SizedBox(width:10),
          Expanded(child:Text('#'+(o['id']??d.id).toString(),style:const TextStyle(fontWeight:FontWeight.w900))),
          Text('₹'+_num(o['total']).toStringAsFixed(0),style:const TextStyle(fontWeight:FontWeight.w900)),
        ]),
        const SizedBox(height:8),
        Text((o['address']??'Pickup location unavailable').toString()),
        const SizedBox(height:8),
        Row(children:[
          Expanded(child:OutlinedButton(onPressed:()=>_info(context,'Request details','Customer: '+(o['name']??o['customerName']??'').toString()+'\nPhone: '+(o['phone']??'').toString()),child:const Text('Details'))),
          if(mine) ...[
            const SizedBox(width:8),
            Expanded(child:FilledButton(onPressed:()=>_accept(context,d),child:const Text('Accept'))),
          ],
        ]),
      ]),
    ));
  }

  Future<void> _accept(BuildContext context, QueryDocumentSnapshot<Map<String,dynamic>> doc) async {
    try {
      await doc.reference.update({
        'status':'Assigned',
        'carrierAccepted':true,
        'assignmentRejected':false,
        'statusNote':role=='carrier'?'Rider accepted the request':'Delivery partner accepted the assignment',
        'updatedAt':FieldValue.serverTimestamp(),
      });
      if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Request accepted.')));
    } catch(e) {
      if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not accept request: '+e.toString())));
    }
  }

  Widget _metric(String value,String label,IconData icon)=>Card(
    elevation:0,
    color:accent.withOpacity(.07),
    child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Icon(icon,color:accent,size:20),const SizedBox(height:8),
      Text(value,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900)),
      Text(label,maxLines:2,style:const TextStyle(fontSize:10.5)),
    ])),
  );

  Widget _empty(String title,String message)=>Card(
    elevation:0,
    child:Padding(padding:const EdgeInsets.all(20),child:Column(children:[
      Icon(featureIcon,color:accent,size:36),const SizedBox(height:10),
      Text(title,style:const TextStyle(fontWeight:FontWeight.w900)),
      const SizedBox(height:5),Text(message,textAlign:TextAlign.center,style:const TextStyle(color:Colors.black54)),
    ])),
  );

  Widget _error(String message)=>Card(elevation:0,child:Padding(padding:const EdgeInsets.all(14),child:Text(message,style:const TextStyle(color:Colors.red))));

  Widget _avatar(String url) {
    if(url.isEmpty)return CircleAvatar(backgroundColor:accent.withOpacity(.10),child:Icon(Icons.inventory_2,color:accent));
    return CircleAvatar(backgroundImage:NetworkImage(url),backgroundColor:accent.withOpacity(.10));
  }

  num _num(dynamic v)=>v is num?v:num.tryParse((v??'').toString().replaceAll(',',''))??0;
  int _time(dynamic v) {
    if(v is Timestamp)return v.millisecondsSinceEpoch;
    if(v is num)return v.toInt();
    return DateTime.tryParse((v??'').toString())?.millisecondsSinceEpoch??0;
  }

  void _info(BuildContext context,String title,String message)=>showModalBottomSheet<void>(
    context:context,showDragHandle:true,
    builder:(_)=>SafeArea(child:Padding(
      padding:const EdgeInsets.fromLTRB(20,8,20,24),
      child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(title,style:const TextStyle(fontSize:19,fontWeight:FontWeight.w900)),
        const SizedBox(height:10),Text(message),
      ]),
    )),
  );
}
