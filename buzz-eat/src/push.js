import webpush from 'web-push';

// Seuls les services de notification des navigateurs reçoivent nos envois :
// une adresse inventée ne doit pas faire appeler par le serveur une machine de son choix.
const PUSH_HOSTS = [
  'fcm.googleapis.com',
  'android.googleapis.com',
  'updates.push.services.mozilla.com',
  'push.services.mozilla.com',
  'web.push.apple.com',
  'notify.windows.com'
];

export function isAllowedPushEndpoint(endpoint) {
  let url;
  try {
    url = new URL(endpoint);
  } catch {
    return false;
  }
  if (url.protocol !== 'https:' || url.port) return false;
  return PUSH_HOSTS.some((h) => url.hostname === h || url.hostname.endsWith(`.${h}`));
}

export function parsePushSubscription(body) {
  const endpoint = body?.endpoint;
  const p256dh = body?.keys?.p256dh;
  const auth = body?.keys?.auth;
  const b64url = /^[A-Za-z0-9_-]+={0,2}$/;
  if (typeof endpoint !== 'string' || endpoint.length > 1024 || !isAllowedPushEndpoint(endpoint)) return null;
  if (typeof p256dh !== 'string' || p256dh.length > 200 || !b64url.test(p256dh)) return null;
  if (typeof auth !== 'string' || auth.length > 100 || !b64url.test(auth)) return null;
  return { endpoint, p256dh, auth };
}

// Clés VAPID : celles de l'environnement, sinon créées une fois et gardées dans la base.
export function createPushSender({ config, db, log = console }) {
  let keys =
    config.vapidPublicKey && config.vapidPrivateKey
      ? { publicKey: config.vapidPublicKey, privateKey: config.vapidPrivateKey }
      : JSON.parse(db.getSetting('vapid') || 'null');
  if (!keys) {
    keys = webpush.generateVAPIDKeys();
    db.setSetting('vapid', JSON.stringify(keys));
  }
  webpush.setVapidDetails(config.vapidSubject, keys.publicKey, keys.privateKey);

  return {
    publicKey: keys.publicKey,
    async send(subscriptions, payload) {
      await Promise.all(
        subscriptions.map(async (s) => {
          try {
            await webpush.sendNotification(
              { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
              JSON.stringify(payload),
              { TTL: 900, urgency: 'high' }
            );
          } catch (err) {
            if (err.statusCode === 404 || err.statusCode === 410) db.deletePushSubscription(s.endpoint);
            else log.warn(`Notification non envoyée (${err.statusCode || err.message})`);
          }
        })
      );
    }
  };
}
