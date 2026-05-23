importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyDOF4uPYBBIOij1i3kcxj_VDVxKjHr7TNY",
  authDomain: "alphatrack-59a90.firebaseapp.com",
  projectId: "alphatrack-59a90",
  storageBucket: "alphatrack-59a90.firebasestorage.app",
  messagingSenderId: "49462039490",
  appId: "REPLACE_WITH_WEB_APP_ID"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function(payload) {
  console.log("[SW] Background message:", payload);

  const title = payload.notification?.title || "AgroTehComert";
  const body  = payload.notification?.body  || "";

  self.registration.showNotification(title, {
    body: body,
    icon: "/icons/Icon-192.png",
    badge: "/icons/Icon-192.png",
    vibrate: [200, 100, 200],
    tag: payload.data?.tag || "agroteh-notification",
  });
});
