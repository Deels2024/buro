self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('push', event => {
  let payload = {};
  try { payload = event.data ? event.data.json() : {}; } catch (_) { /* Show a safe generic notification. */ }
  event.waitUntil(self.registration.showNotification('Бюро находок', {
    body: payload.body || 'Есть новое событие. Откройте кабинет.',
    icon: '/icons/icon-192.png', badge: '/icons/icon-192.png',
    tag: payload.tag || 'bureau-update',
    data: {url: '/app/?action=notifications'}
  }));
});
self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({type: 'window', includeUncontrolled: true});
    const app = windows.find(client => new URL(client.url).origin === self.location.origin &&
      new URL(client.url).pathname.startsWith('/app/'));
    if (app) {
      await app.navigate('/app/?action=notifications');
      return app.focus();
    }
    return self.clients.openWindow('/app/?action=notifications');
  })());
});
