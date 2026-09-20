import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyALo6RBHA9Rt4NbES7yML006RtaAujMZr0',
    appId: '1:869987297351:android:51229aaff7b13c68976962',
    messagingSenderId: '869987297351',
    projectId: 'allways-web',
    storageBucket: 'allways-web.firebasestorage.app',
  );

  static FirebaseOptions get currentPlatform => android;
}
