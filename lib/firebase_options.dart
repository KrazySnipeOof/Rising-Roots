import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb;

/// Firebase options generated from provided configuration.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    throw UnsupportedError(
      'DefaultFirebaseOptions have not been configured for '
      '${defaultTargetPlatform.name}. Only web is currently supported.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBMANI62EJMXe4kpXIgiCt7NLkjQFbpwR4',
    authDomain: 'rising-roots-7a42d.firebaseapp.com',
    projectId: 'rising-roots-7a42d',
    storageBucket: 'rising-roots-7a42d.firebasestorage.app',
    messagingSenderId: '256908084750',
    appId: '1:256908084750:web:274bbe7cd3854fe293de5f',
    measurementId: 'G-TKBGJ4TL29',
  );
}

