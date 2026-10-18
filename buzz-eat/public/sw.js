// Service worker : notifications « commande prête » quand la page du client n'est pas devant.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch {}
  event.waitUntil(
    self.registration.showNotification(data.title || 'Votre commande est prête !', {
      body: data.body || 'Venez la retirer au bar.',
      tag: data.tag || 'commande',
      renotify: true,
      requireInteraction: true,
      vibrate: [600, 200, 600, 200, 900],
      icon: data.icon || '/icons/icon-192.png',
      badge: '/icons/icon-192.png',
      data: { url: data.url || '/' }
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = new URL(event.notification.data?.url || '/', self.location.origin).href;
  event.waitUntil(
    (async () => {
      const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      const open = windows.find((w) => w.url === url);
      if (open) return open.focus();
      return self.clients.openWindow(url);
    })()
  );
});
