importScripts("https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyBMANI62EJMXe4kpXIgiCt7NLkjQFbpwR4",
  authDomain: "rising-roots-7a42d.firebaseapp.com",
  projectId: "rising-roots-7a42d",
  storageBucket: "rising-roots-7a42d.firebasestorage.app",
  messagingSenderId: "256908084750",
  appId: "1:256908084750:web:274bbe7cd3854fe293de5f",
  measurementId: "G-TKBGJ4TL29"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  self.registration.showNotification(
    payload.notification?.title ?? "Rising Roots",
    {
      body: payload.notification?.body ?? "You have a new alert.",
      icon: "/icons/Icon-192.png",
    },
  );
});

