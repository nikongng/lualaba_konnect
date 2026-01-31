importScripts("https://www.gstatic.com/firebasejs/9.10.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/9.10.0/firebase-messaging-compat.js");

// Configuration Firebase Web pour le projet (générée depuis lib/firebase_options.dart)
firebase.initializeApp({
  apiKey: "AIzaSyDX-hHwrPsIfY4WGrZ2wgXeAZf5KWe18Ls",
  authDomain: "lualaba-konnect.firebaseapp.com",
  projectId: "lualaba-konnect",
  storageBucket: "lualaba-konnect.firebasestorage.app",
  messagingSenderId: "1079633969142",
  appId: "1:1079633969142:web:a051ce8850c8645365d1d7",
  measurementId: "G-Y6HJTVSWHH",
});

const messaging = firebase.messaging();

// Gestion des messages quand l'app est en arrière-plan
messaging.onBackgroundMessage((payload) => {
  console.log('Notification reçue en arrière-plan :', payload);
  const notificationTitle = (payload && payload.notification && payload.notification.title) || 'Alerte';
  const notificationOptions = {
    body: (payload && payload.notification && payload.notification.body) || '',
    icon: '/icons/Icon-192.png',
    data: payload && payload.data ? payload.data : {},
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});

// Clic sur la notification — ouvrir ou focus la fenêtre correspondante
self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  const data = event.notification.data || {};
  const url = data.url || '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function(clientList) {
      for (const client of clientList) {
        if (client.url === url && 'focus' in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow(url);
    })
  );
});