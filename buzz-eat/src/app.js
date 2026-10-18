import fs from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';
import QRCode from 'qrcode';
import { createBilling, isSubscribed, subscriptionView } from './billing.js';
import { EventHub } from './events.js';
import { HttpError, cleanText, parseCookies, readBody, sendJson } from './http.js';
import { popinaLabel, popinaOrderText, roomMatches, verifyPopinaSignature, wasSentToPreparation } from './popina.js';
import { parsePushSubscription } from './push.js';
import { RateLimiter, hashPassword, randomToken, sha256, verifyPassword } from './security.js';
import { formatSiret, isValidSiret, normalizeSiret } from './siret.js';
import { verifyWebhook } from './stripe.js';
import { DEFAULT_THEME, THEMES } from '../public/js/themes.js';

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.webmanifest': 'application/manifest+json'
};

const PAGES = {
  '/': 'index.html',
  '/app': 'app.html',
  '/reglages': 'reglages.html',
  '/apercu': 'client.html'
};

const TOKEN = /^[A-Za-z0-9_-]{16,64}$/;
const CLIENT_PAGE = /^\/c\/([A-Za-z0-9_-]{16,64})$/;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const CSP = [
  "default-src 'self'",
  "script-src 'self'",
  "style-src 'self'",
  "img-src 'self' data: blob:",
  "media-src 'self' blob: data:",
  "connect-src 'self'",
  "manifest-src 'self'",
  "worker-src 'self'",
  "object-src 'none'",
  "base-uri 'none'",
  "frame-ancestors 'none'",
  "form-action 'self'"
].join('; ');

const LOGO_TYPES = {
  'image/png': (b) => b.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])),
  'image/jpeg': (b) => b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff,
  'image/webp': (b) => b.toString('latin1', 0, 4) === 'RIFF' && b.toString('latin1', 8, 12) === 'WEBP'
};
const LOGO_MAX_BYTES = 800 * 1024;

// Journée de service : elle change à 5 h (heure de Paris), pas à minuit, pour les bars ouverts tard.
function serviceDay(now) {
  return new Intl.DateTimeFormat('fr-CA', {
    timeZone: 'Europe/Paris',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  }).format(new Date(now - 5 * 60 * 60 * 1000));
}

export function createApp({ config, db, push, stripe = null, clock = () => Date.now(), log = console }) {
  const hub = new EventHub();
  const limiter = new RateLimiter(clock);
  const billing = createBilling({ config, db, stripe, limiter, log });
  const publicDir = path.join(config.root, 'public');
  const routes = [];
  let dummyHash = null;

  function route(method, pattern, handler, opts = {}) {
    const keys = [];
    const re = new RegExp(`^${pattern.replace(/:(\w+)/g, (_, k) => (keys.push(k), '([^/]+)'))}$`);
    routes.push({ method, re, keys, handler, opts });
  }

  // ---------- Contexte de la requête ----------

  function requestOrigin(req) {
    const proto = config.trustProxy
      ? String(req.headers['x-forwarded-proto'] || 'http').split(',')[0].trim()
      : req.socket.encrypted
        ? 'https'
        : 'http';
    const host = (config.trustProxy && req.headers['x-forwarded-host']) || req.headers.host || 'localhost';
    return `${proto}://${String(host).split(',')[0].trim()}`;
  }

  const baseUrl = (req) => config.publicUrl || requestOrigin(req);

  function clientIp(req) {
    if (config.trustProxy && req.headers['x-forwarded-for']) {
      return String(req.headers['x-forwarded-for']).split(',')[0].trim();
    }
    return req.socket.remoteAddress || '?';
  }

  function checkOrigin(req) {
    const origin = req.headers.origin;
    if (!origin) return;
    const allowed = new Set([requestOrigin(req)]);
    if (config.publicUrl) allowed.add(new URL(config.publicUrl).origin);
    if (!allowed.has(origin)) throw new HttpError(403, 'Requête refusée (origine inconnue).');
  }

  function sessionCookie(req, token, maxAgeSec) {
    const secure = baseUrl(req).startsWith('https://') ? '; Secure' : '';
    return `sid=${token}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAgeSec}${secure}`;
  }

  function currentRestaurant(req) {
    const token = parseCookies(req.headers.cookie).sid;
    if (!token) return null;
    const session = db.session(sha256(token), clock());
    return session ? db.restaurant(session.restaurant_id) : null;
  }

  function startSession(req, res, restaurantId) {
    const token = randomToken(32);
    db.createSession(sha256(token), restaurantId, clock() + config.sessionMaxAgeMs);
    res.setHeader('Set-Cookie', sessionCookie(req, token, Math.floor(config.sessionMaxAgeMs / 1000)));
  }

  // ---------- Vues ----------

  // Le numéro de version change à chaque envoi : l'adresse peut être gardée en cache pour toujours.
  function logoUrl(r) {
    return r.logo_type ? `/api/logo/${r.id}?v=${r.logo_version}` : null;
  }

  function publicRestaurant(r) {
    return { name: r.name, siret: formatSiret(r.siret), theme: r.theme, logoUrl: logoUrl(r) };
  }

  function meView(r) {
    return {
      restaurant: {
        id: r.id,
        email: r.email,
        name: r.name,
        siret: r.siret,
        siretFormatted: formatSiret(r.siret),
        theme: r.theme,
        logoUrl: logoUrl(r)
      },
      subscription: subscriptionView(r, { priceCents: config.priceCents, onlinePayment: Boolean(stripe) }),
      appName: config.appName
    };
  }

  function staffOrder(o) {
    return {
      id: o.id,
      number: o.number,
      customer: o.customer,
      details: o.details,
      status: o.status,
      createdAt: o.created_at,
      readyAt: o.ready_at,
      clientPath: `/c/${o.token}`,
      source: o.source,
      alertOn: Boolean(o.alert_on),
      listening: hub.count(`order:${o.id}`) > 0,
      push: db.countPushSubscriptions(o.id) > 0
    };
  }

  function publicOrder(o, r) {
    return {
      number: o.number,
      customer: o.customer,
      details: o.details,
      status: o.status,
      createdAt: o.created_at,
      readyAt: o.ready_at,
      restaurant: publicRestaurant(r)
    };
  }

  // ---------- Diffusion ----------

  function notifyStaff(orderId, restaurantId) {
    const o = db.order(orderId, restaurantId);
    if (o) hub.publish(`restaurant:${restaurantId}`, 'order', { order: staffOrder(o) });
  }

  function sendPush(o, r) {
    const subs = db.pushSubscriptions(o.id);
    if (!subs.length) return;
    push
      .send(subs, {
        title: `Commande n° ${o.number} prête !`,
        body: `Venez la retirer au bar · ${r.name}`,
        tag: `commande-${o.token}`,
        url: `/c/${o.token}`,
        icon: logoUrl(r) || '/icons/icon-192.png'
      })
      .catch((err) => log.warn(`Notifications : ${err.message}`));
  }

  function removeOrder(o, reason) {
    db.deleteOrder(o.id);
    hub.publish(`order:${o.id}`, 'done', { reason });
    hub.end(`order:${o.id}`);
    hub.publish(`restaurant:${o.restaurant_id}`, 'removed', { id: o.id, reason });
  }

  function createOrder(r, { customer, details, source = 'bar' }) {
    const now = clock();
    const o = {
      id: randomToken(9),
      restaurantId: r.id,
      token: randomToken(16),
      number: db.nextOrderNumber(r.id, serviceDay(now)),
      customer,
      details,
      source,
      createdAt: now
    };
    db.createOrder(o);
    const order = staffOrder(db.order(o.id, r.id));
    hub.publish(`restaurant:${r.id}`, 'order', { order });
    return order;
  }

  function findOrder(r, id) {
    const o = db.order(id, r.id);
    if (!o) throw new HttpError(404, 'Cette commande n’existe plus.');
    return o;
  }

  function findClientOrder(token) {
    const o = TOKEN.test(token) ? db.orderByToken(token) : null;
    if (!o) throw new HttpError(404, 'Cette commande n’existe plus.');
    return o;
  }

  // ---------- Comptes ----------

  route('POST', '/api/signup', async ({ req, res, body }) => {
    if (!limiter.allow(`signup:${clientIp(req)}`, config.signupsPerHour, 60 * 60 * 1000)) {
      throw new HttpError(429, 'Trop de comptes créés depuis cette connexion. Réessayez plus tard.');
    }
    const email = cleanText(body.email, 254, 'E-mail', { required: true }).toLowerCase();
    if (!EMAIL.test(email)) throw new HttpError(400, 'Adresse e-mail invalide.');
    const password = String(body.password || '');
    if (password.length < 8) throw new HttpError(400, 'Mot de passe : 8 caractères au moins.');
    if (password.length > 200) throw new HttpError(400, 'Mot de passe trop long.');
    const name = cleanText(body.name, 80, 'Nom de l’établissement', { required: true });
    const siret = normalizeSiret(body.siret);
    if (!isValidSiret(siret)) throw new HttpError(400, 'Numéro SIRET invalide (14 chiffres).');
    if (db.restaurantByEmail(email)) throw new HttpError(409, 'Un compte existe déjà avec cet e-mail.');
    const id = randomToken(12);
    db.createRestaurant({
      id,
      email,
      passwordHash: await hashPassword(password),
      name,
      siret,
      theme: DEFAULT_THEME,
      createdAt: clock()
    });
    startSession(req, res, id);
    return meView(db.restaurant(id));
  });

  route('POST', '/api/login', async ({ req, res, body }) => {
    const email = String(body.email || '')
      .trim()
      .toLowerCase();
    if (!limiter.allow(`login:${clientIp(req)}:${email}`, 10, 15 * 60 * 1000)) {
      throw new HttpError(429, 'Trop d’essais. Réessayez dans quelques minutes.');
    }
    const r = db.restaurantByEmail(email);
    // Même calcul avec ou sans compte : la durée de la réponse ne dit pas si l'e-mail est inscrit.
    dummyHash ||= await hashPassword(randomToken());
    const ok = await verifyPassword(String(body.password || ''), r ? r.password_hash : dummyHash);
    if (!r || !ok) throw new HttpError(401, 'E-mail ou mot de passe incorrect.');
    startSession(req, res, r.id);
    return meView(r);
  });

  route('POST', '/api/logout', ({ req, res }) => {
    const token = parseCookies(req.headers.cookie).sid;
    if (token) db.deleteSession(sha256(token));
    res.setHeader('Set-Cookie', sessionCookie(req, '', 0));
    return { ok: true };
  });

  route('GET', '/api/me', ({ r }) => meView(r), { auth: true });

  // ---------- Personnalisation ----------

  route(
    'PUT',
    '/api/restaurant',
    ({ r, body }) => {
      const fields = {};
      if (body.name !== undefined) fields.name = cleanText(body.name, 80, 'Nom de l’établissement', { required: true });
      if (body.siret !== undefined) {
        fields.siret = normalizeSiret(body.siret);
        if (!isValidSiret(fields.siret)) throw new HttpError(400, 'Numéro SIRET invalide (14 chiffres).');
      }
      if (body.theme !== undefined) {
        if (!THEMES.some((t) => t.id === body.theme)) throw new HttpError(400, 'Palette de couleurs inconnue.');
        fields.theme = body.theme;
      }
      db.updateRestaurant(r.id, fields);
      return meView(db.restaurant(r.id));
    },
    { auth: true }
  );

  route(
    'PUT',
    '/api/restaurant/logo',
    ({ r, body }) => {
      const m = /^data:(image\/(?:png|jpeg|webp));base64,([A-Za-z0-9+/]+={0,2})$/.exec(String(body.dataUrl || ''));
      if (!m) throw new HttpError(400, 'Logo : image PNG, JPEG ou WebP attendue.');
      const data = Buffer.from(m[2], 'base64');
      if (data.length > LOGO_MAX_BYTES) throw new HttpError(400, 'Logo trop lourd (800 Ko au plus).');
      if (!LOGO_TYPES[m[1]](data)) throw new HttpError(400, 'Ce fichier n’est pas une image valide.');
      db.setLogo(r.id, data, m[1]);
      return meView(db.restaurant(r.id));
    },
    { auth: true, limit: 1.2 * 1024 * 1024 }
  );

  route(
    'DELETE',
    '/api/restaurant/logo',
    ({ r }) => {
      db.setLogo(r.id, null, null);
      return meView(db.restaurant(r.id));
    },
    { auth: true }
  );

  route('GET', '/api/logo/:id', ({ res, params }) => {
    const logo = db.logo(params.id);
    if (!logo?.logo) throw new HttpError(404, 'Pas de logo.');
    res.writeHead(200, {
      'Content-Type': logo.logo_type,
      'Content-Length': logo.logo.length,
      'Cache-Control': 'public, max-age=31536000, immutable',
      'Content-Security-Policy': "default-src 'none'"
    });
    res.end(Buffer.from(logo.logo));
  });

  // ---------- Commandes (écran du bar) ----------

  route('GET', '/api/orders', ({ r }) => ({ orders: db.orders(r.id).map(staffOrder) }), { auth: true });

  route(
    'POST',
    '/api/orders',
    ({ r, body }) => {
      if (!isSubscribed(r)) throw new HttpError(402, 'Abonnement requis pour prendre des commandes.');
      const customer = cleanText(body.customer, 40, 'Nom du client');
      const details = cleanText(body.details, 500, 'Commande', { multiline: true });
      return { order: createOrder(r, { customer, details }) };
    },
    { auth: true }
  );

  route(
    'POST',
    '/api/orders/:id/ready',
    ({ r, params }) => {
      let o = findOrder(r, params.id);
      if (o.status !== 'ready') {
        db.markReady(o.id, clock());
        o = db.order(o.id, r.id);
        hub.publish(`order:${o.id}`, 'state', { order: publicOrder(o, r) });
        sendPush(o, r);
      }
      const order = staffOrder(o);
      hub.publish(`restaurant:${r.id}`, 'order', { order });
      return { order };
    },
    { auth: true }
  );

  route(
    'POST',
    '/api/orders/:id/ring',
    ({ r, params }) => {
      const o = findOrder(r, params.id);
      if (o.status !== 'ready') throw new HttpError(409, 'La commande n’est pas encore prête.');
      hub.publish(`order:${o.id}`, 'ring', { at: clock() });
      sendPush(o, r);
      return { ok: true };
    },
    { auth: true }
  );

  route(
    'POST',
    '/api/orders/:id/pickup',
    ({ r, params }) => {
      removeOrder(findOrder(r, params.id), 'picked_up');
      return { ok: true };
    },
    { auth: true }
  );

  route(
    'DELETE',
    '/api/orders/:id',
    ({ r, params }) => {
      removeOrder(findOrder(r, params.id), 'canceled');
      return { ok: true };
    },
    { auth: true }
  );

  route(
    'GET',
    '/api/orders/:id/qr.svg',
    async ({ req, res, r, params }) => {
      const o = findOrder(r, params.id);
      const svg = await QRCode.toString(`${baseUrl(req)}/c/${o.token}`, {
        type: 'svg',
        errorCorrectionLevel: 'M',
        margin: 2,
        color: { dark: '#000000', light: '#ffffff' }
      });
      res.writeHead(200, { 'Content-Type': 'image/svg+xml', 'Cache-Control': 'private, no-store' });
      res.end(svg);
    },
    { auth: true }
  );

  route(
    'GET',
    '/api/events',
    ({ req, res, r }) => {
      hub.open(`restaurant:${r.id}`, req, res);
      hub.send(res, 'snapshot', { orders: db.orders(r.id).map(staffOrder) });
    },
    { auth: true }
  );

  // Page d'exemple pour l'établissement : sa marque, une commande fictive, l'alarme à essayer.
  route(
    'GET',
    '/api/apercu',
    ({ r }) => ({
      order: {
        number: 42,
        customer: 'Exemple',
        details: '2 cafés\n1 croissant',
        status: 'preparing',
        createdAt: clock(),
        readyAt: null,
        restaurant: publicRestaurant(r)
      }
    }),
    { auth: true }
  );

  // ---------- Téléphone du client ----------

  route('GET', '/api/push/key', () => ({ publicKey: push.publicKey }));

  route('GET', '/api/c/:token', ({ params }) => {
    const o = findClientOrder(params.token);
    return { order: publicOrder(o, db.restaurant(o.restaurant_id)) };
  });

  route('GET', '/api/c/:token/events', ({ req, res, params }) => {
    const o = findClientOrder(params.token);
    hub.open(`order:${o.id}`, req, res, { onClose: () => notifyStaff(o.id, o.restaurant_id) });
    hub.send(res, 'state', { order: publicOrder(o, db.restaurant(o.restaurant_id)) });
    notifyStaff(o.id, o.restaurant_id);
  });

  route('POST', '/api/c/:token/alert', ({ params }) => {
    const o = findClientOrder(params.token);
    db.markAlertOn(o.id);
    notifyStaff(o.id, o.restaurant_id);
    return { ok: true };
  });

  route('POST', '/api/c/:token/push', ({ params, body }) => {
    const o = findClientOrder(params.token);
    const sub = parsePushSubscription(body.subscription);
    if (!sub) throw new HttpError(400, 'Abonnement aux notifications invalide.');
    if (db.countPushSubscriptions(o.id) >= 5) throw new HttpError(429, 'Trop d’appareils pour cette commande.');
    db.addPushSubscription(o.id, sub);
    db.markAlertOn(o.id);
    notifyStaff(o.id, o.restaurant_id);
    return { ok: true };
  });

  // ---------- Caisse Popina ----------

  function popinaView(req, link) {
    return {
      enabled: Boolean(link?.enabled),
      webhookUrl: link ? `${baseUrl(req)}/api/popina/${link.token}` : null,
      hasSecret: Boolean(link?.secret),
      createOn: link?.create_on || 'sent',
      rooms: link?.rooms || '',
      lastAt: link?.last_at || null,
      lastInfo: link?.last_info || null
    };
  }

  route('GET', '/api/popina', ({ req, r }) => popinaView(req, db.popina(r.id)), { auth: true });

  route(
    'PUT',
    '/api/popina',
    ({ req, r, body }) => {
      db.ensurePopina(r.id, randomToken(24));
      const fields = {};
      if (body.enabled !== undefined) fields.enabled = body.enabled ? 1 : 0;
      if (body.secret !== undefined) {
        const secret = String(body.secret).trim();
        if (secret && !/^[\x21-\x7e]{16,256}$/.test(secret)) {
          throw new HttpError(400, 'Clé secrète Popina invalide (64 caractères, sans espace).');
        }
        fields.secret = secret || null;
      }
      if (body.createOn !== undefined) {
        if (!['sent', 'paid'].includes(body.createOn)) throw new HttpError(400, 'Choix inconnu.');
        fields.create_on = body.createOn;
      }
      if (body.rooms !== undefined) fields.rooms = cleanText(body.rooms, 200, 'Salles');
      db.updatePopina(r.id, fields);
      return popinaView(req, db.popina(r.id));
    },
    { auth: true }
  );

  // Nouvelle adresse : l'ancienne ne marche plus (à faire si elle a été communiquée par erreur).
  route(
    'POST',
    '/api/popina/address',
    ({ req, r }) => {
      db.ensurePopina(r.id, randomToken(24));
      db.updatePopina(r.id, { token: randomToken(24) });
      return popinaView(req, db.popina(r.id));
    },
    { auth: true }
  );

  const shorten = (value, max) => {
    const chars = [...value];
    return chars.length > max ? `${chars.slice(0, max - 1).join('')}…` : value;
  };

  function handlePopina(r, link, event, data) {
    if (!link.enabled) return 'Reçue, connexion désactivée';
    const known = db.externalOrder(r.id, data.id);
    const existing = known?.order_id ? db.order(known.order_id, r.id) : null;
    if (event === 'order.canceled' || data.isCanceled) {
      if (!existing) return 'Annulation reçue';
      removeOrder(existing, 'canceled');
      return `Commande n° ${existing.number} annulée`;
    }
    const customer = shorten(cleanText(shorten(popinaLabel(data), 100), 100, 'Repère'), 40);
    const details = shorten(cleanText(shorten(popinaOrderText(data), 2000), 2000, 'Commande', { multiline: true }), 500);
    if (existing) {
      if (customer !== existing.customer || details !== existing.details) {
        db.updateOrderText(existing.id, customer, details);
        const o = db.order(existing.id, r.id);
        hub.publish(`restaurant:${r.id}`, 'order', { order: staffOrder(o) });
        hub.publish(`order:${o.id}`, 'state', { order: publicOrder(o, r) });
      }
      return `Commande n° ${existing.number} mise à jour`;
    }
    // Déjà créée puis récupérée : Popina peut encore l'envoyer (paiement, clôture), on ne la recrée pas.
    if (known) return 'Commande déjà terminée';
    const wanted =
      link.create_on === 'paid'
        ? event === 'order.paid'
        : (event === 'order.call' || event === 'order.paid') && wasSentToPreparation(data);
    if (!wanted) return link.create_on === 'paid' ? 'En attente du paiement' : 'En attente de l’envoi en préparation';
    if (!roomMatches(link.rooms, data.roomName)) return `Ignorée (salle « ${shorten(String(data.roomName || ''), 40)} »)`;
    if (!isSubscribed(r)) return 'Ignorée : abonnement inactif';
    const order = createOrder(r, { customer, details, source: 'popina' });
    db.rememberExternalOrder(r.id, data.id, order.id, clock());
    return `Commande n° ${order.number} créée`;
  }

  route(
    'POST',
    '/api/popina/:token',
    ({ req, params, rawBody }) => {
      const link = TOKEN.test(params.token) ? db.popinaByToken(params.token) : null;
      if (!link) throw new HttpError(404, 'Adresse inconnue.');
      const note = (info) => db.updatePopina(link.restaurant_id, { last_at: clock(), last_info: info });
      if (!link.secret) {
        note('Refusée : clé secrète Popina pas encore saisie');
        throw new HttpError(401, 'Clé secrète non configurée.');
      }
      if (!verifyPopinaSignature(rawBody, req.headers['x-popina-hmac-signature'], link.secret)) {
        note('Refusée : signature invalide (vérifiez la clé secrète)');
        throw new HttpError(401, 'Signature invalide.');
      }
      let payload;
      try {
        payload = JSON.parse(rawBody.toString('utf8'));
      } catch {
        throw new HttpError(400, 'JSON invalide.');
      }
      const data = payload?.data;
      if (!data || typeof data.id !== 'string' || !data.id || data.id.length > 100) {
        throw new HttpError(400, 'Commande Popina illisible.');
      }
      const event = String(payload.meta?.event || req.headers['x-popina-webhook-event'] || '');
      note(handlePopina(db.restaurant(link.restaurant_id), link, event, data));
      return { received: true };
    },
    { raw: true, limit: 1024 * 1024 }
  );

  // ---------- Abonnement ----------

  route(
    'POST',
    '/api/billing/promo',
    ({ r, body }) => {
      billing.applyPromo(r, body.code, r.id);
      return meView(db.restaurant(r.id));
    },
    { auth: true }
  );

  route('POST', '/api/billing/checkout', async ({ req, r }) => ({ url: await billing.checkout(r, baseUrl(req)) }), {
    auth: true
  });

  route(
    'POST',
    '/api/billing/confirm',
    async ({ r, body }) => {
      await billing.confirm(r, body.sessionId);
      return meView(db.restaurant(r.id));
    },
    { auth: true }
  );

  route('POST', '/api/billing/portal', async ({ req, r }) => ({ url: await billing.portal(r, baseUrl(req)) }), {
    auth: true
  });

  route(
    'POST',
    '/api/stripe/webhook',
    ({ req, rawBody }) => {
      if (!config.stripeWebhookSecret) throw new HttpError(503, 'Webhook Stripe non configuré.');
      let event;
      try {
        event = verifyWebhook(rawBody, req.headers['stripe-signature'], config.stripeWebhookSecret, { now: clock() });
      } catch (err) {
        throw new HttpError(400, err.message);
      }
      billing.handleEvent(event, clock());
      return { received: true };
    },
    { raw: true, limit: 512 * 1024 }
  );

  // ---------- Fichiers ----------

  async function serveStatic(req, res, pathname) {
    let file = PAGES[pathname] || (CLIENT_PAGE.test(pathname) ? 'client.html' : null);
    if (!file) {
      let decoded;
      try {
        decoded = decodeURIComponent(pathname);
      } catch {
        return false;
      }
      file = path.normalize(decoded).replace(/^([/\\])+/, '');
      if (file.startsWith('..') || file.includes('\0')) return false;
    }
    const full = path.join(publicDir, file);
    if (!full.startsWith(publicDir + path.sep)) return false;
    const type = MIME[path.extname(full)];
    if (!type) return false;
    let stat;
    try {
      stat = await fs.stat(full);
    } catch {
      return false;
    }
    if (!stat.isFile()) return false;
    const etag = `W/"${stat.size}-${Math.floor(stat.mtimeMs)}"`;
    const headers = { 'Content-Type': type, 'Cache-Control': 'no-cache', ETag: etag };
    if (file === 'sw.js') headers['Service-Worker-Allowed'] = '/';
    if (req.headers['if-none-match'] === etag) {
      res.writeHead(304, headers);
      res.end();
      return true;
    }
    const data = await fs.readFile(full);
    res.writeHead(200, { ...headers, 'Content-Length': data.length });
    res.end(req.method === 'HEAD' ? undefined : data);
    return true;
  }

  // ---------- Aiguillage ----------

  async function handle(req, res) {
    res.setHeader('Content-Security-Policy', CSP);
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=(), payment=()');
    if (baseUrl(req).startsWith('https://')) {
      res.setHeader('Strict-Transport-Security', 'max-age=31536000');
    }

    const url = new URL(req.url, 'http://local');
    try {
      for (const rt of routes) {
        if (rt.method !== req.method) continue;
        const m = rt.re.exec(url.pathname);
        if (!m) continue;
        let params;
        try {
          params = Object.fromEntries(rt.keys.map((k, i) => [k, decodeURIComponent(m[i + 1])]));
        } catch {
          throw new HttpError(400, 'Adresse invalide.');
        }
        const ctx = { req, res, url, params, body: {} };
        if (req.method !== 'GET') {
          if (!rt.opts.raw) {
            checkOrigin(req);
            if (!String(req.headers['content-type'] || '').startsWith('application/json')) {
              throw new HttpError(415, 'Données JSON attendues.');
            }
          }
          const raw = await readBody(req, rt.opts.limit || 32 * 1024);
          if (rt.opts.raw) ctx.rawBody = raw;
          else if (raw.length) {
            try {
              ctx.body = JSON.parse(raw.toString('utf8')) || {};
            } catch {
              throw new HttpError(400, 'JSON invalide.');
            }
          }
        }
        if (rt.opts.auth) {
          ctx.r = currentRestaurant(req);
          if (!ctx.r) throw new HttpError(401, 'Connectez-vous pour continuer.');
        }
        const result = await rt.handler(ctx);
        if (result !== undefined && !res.headersSent) sendJson(res, 200, result);
        return;
      }
      if (url.pathname.startsWith('/api/')) throw new HttpError(404, 'Introuvable.');
      if ((req.method === 'GET' || req.method === 'HEAD') && (await serveStatic(req, res, url.pathname))) return;
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Page introuvable');
    } catch (err) {
      if (res.headersSent) {
        res.end();
        return;
      }
      if (err instanceof HttpError) sendJson(res, err.status, { error: err.message });
      else if (url.pathname.startsWith('/api/billing/')) {
        log.warn(`Stripe : ${err.message}`);
        sendJson(res, 502, { error: 'Le service de paiement ne répond pas. Réessayez dans un instant.' });
      } else {
        log.error(err);
        sendJson(res, 500, { error: 'Erreur du serveur.' });
      }
    }
  }

  // ---------- Entretien ----------

  function sweep() {
    const now = clock();
    for (const o of db.staleOrders(now - config.orderMaxAgeMs)) removeOrder(o, 'expired');
    db.purgeSessions(now);
    db.purgeStripeEvents(now - 30 * 24 * 60 * 60 * 1000);
    db.purgeExternalOrders(now - 48 * 60 * 60 * 1000);
    limiter.sweep();
  }

  const timers = [setInterval(sweep, 10 * 60 * 1000), setInterval(() => hub.heartbeat(), 25 * 1000)];
  for (const t of timers) t.unref();

  const server = http.createServer((req, res) => {
    handle(req, res);
  });
  server.on('close', () => hub.closeAll());

  return {
    server,
    hub,
    sweep,
    close() {
      for (const t of timers) clearInterval(t);
      hub.closeAll();
      const closed = new Promise((resolve) => server.close(() => resolve()));
      server.closeAllConnections();
      return closed;
    }
  };
}
