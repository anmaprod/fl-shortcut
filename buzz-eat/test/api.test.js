import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { signWebhookPayload } from '../src/stripe.js';
import { openEvents, startTestApp, VALID_SIRET } from './helpers.js';

const PNG_1PX = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
  'base64'
);
const SUB = { endpoint: 'https://fcm.googleapis.com/fcm/send/abc', keys: { p256dh: 'BPk1', auth: 'au7h' } };

let t;
before(async () => {
  t = await startTestApp({
    stripeResponses: {
      retrieve: (id) => ({
        id,
        mode: 'subscription',
        status: 'complete',
        payment_status: 'paid',
        client_reference_id: t.lastRestaurantId,
        customer: 'cus_retour',
        subscription: { id: 'sub_retour', status: 'active', customer: 'cus_retour', current_period_end: 1_900_000_000 }
      })
    }
  });
});
after(() => t.close());

async function subscribedAccount(email) {
  const { cookie } = await t.signup(email);
  const promo = await t.request('POST', '/api/billing/promo', { code: 'notre-boite' }, { cookie });
  assert.equal(promo.status, 200);
  return cookie;
}

test('inscription : SIRET et e-mail vérifiés, session ouverte, doublon refusé', async () => {
  const bad = await t.signup('a@example.fr', { siret: '12345678901234' });
  assert.equal(bad.status, 400);
  assert.match(bad.json.error, /SIRET/);

  const ok = await t.signup('a@example.fr');
  assert.equal(ok.status, 200);
  assert.match(ok.headers.get('set-cookie'), /HttpOnly; SameSite=Lax/);
  assert.equal(ok.json.restaurant.siret, VALID_SIRET);
  assert.equal(ok.json.subscription.active, false);

  const me = await t.request('GET', '/api/me', undefined, { cookie: ok.cookie });
  assert.equal(me.json.restaurant.name, 'Le Comptoir');
  assert.equal((await t.signup('A@example.fr')).status, 409);
  assert.equal((await t.request('GET', '/api/me')).status, 401);
});

test('inscription : 10 comptes par heure au plus depuis une même connexion', async () => {
  const limited = await startTestApp({ env: { SIGNUPS_PER_HOUR: '' } });
  try {
    const statuses = [];
    for (let i = 0; i < 11; i++) statuses.push((await limited.signup(`q${i}@example.fr`)).status);
    assert.equal(statuses.filter((s) => s === 200).length, 10);
    assert.equal(statuses.at(-1), 429);
  } finally {
    await limited.close();
  }
});

test('connexion et déconnexion', async () => {
  await t.signup('b@example.fr');
  const wrong = await t.request('POST', '/api/login', { email: 'b@example.fr', password: 'mauvais!!' });
  assert.equal(wrong.status, 401);
  const ok = await t.request('POST', '/api/login', { email: 'B@example.fr ', password: 'motdepasse' });
  assert.equal(ok.status, 200);
  await t.request('POST', '/api/logout', {}, { cookie: ok.cookie });
  assert.equal((await t.request('GET', '/api/me', undefined, { cookie: ok.cookie })).status, 401);
});

test('abonnement : sans abonnement pas de commande ; code promo interne = 0 €', async () => {
  const { cookie } = await t.signup('c@example.fr');
  const blocked = await t.request('POST', '/api/orders', { details: 'Un café' }, { cookie });
  assert.equal(blocked.status, 402);

  const unknown = await t.request('POST', '/api/billing/promo', { code: 'FAUX' }, { cookie });
  assert.equal(unknown.status, 400);

  const promo = await t.request('POST', '/api/billing/promo', { code: ' notre-boite ' }, { cookie });
  assert.equal(promo.status, 200);
  assert.deepEqual(
    { active: promo.json.subscription.active, plan: promo.json.subscription.plan, price: promo.json.subscription.priceCents },
    { active: true, plan: 'promo', price: 0 }
  );
  assert.equal((await t.request('POST', '/api/orders', { details: 'Un café' }, { cookie })).status, 200);
});

test('abonnement : essais de code promo limités', async () => {
  const { cookie } = await t.signup('d@example.fr');
  const statuses = [];
  for (let i = 0; i < 9; i++) statuses.push((await t.request('POST', '/api/billing/promo', { code: `X${i}` }, { cookie })).status);
  assert.equal(statuses.at(-1), 429);
  assert.equal((await t.request('POST', '/api/billing/promo', { code: 'NOTRE-BOITE' }, { cookie })).status, 429);
});

test('commande : numéro, QR code, page client, prête, récupérée = tout s’efface', async () => {
  const cookie = await subscribedAccount('e@example.fr');
  const staff = await openEvents(`${t.base}/api/events`, cookie);
  assert.deepEqual((await staff.next('snapshot')).orders, []);

  const created = await t.request('POST', '/api/orders', { customer: 'Julie', details: '2 bières\n1 planche' }, { cookie });
  const order = created.json.order;
  assert.equal(order.number, 1);
  assert.equal(order.status, 'preparing');
  assert.equal((await staff.next('order')).order.id, order.id);
  assert.equal((await t.request('POST', '/api/orders', {}, { cookie })).json.order.number, 2);
  await staff.next('order');

  const qr = await t.request('GET', `/api/orders/${order.id}/qr.svg`, undefined, { cookie });
  assert.equal(qr.status, 200);
  assert.match(qr.headers.get('content-type'), /image\/svg\+xml/);
  assert.match(qr.text, /<svg[\s\S]*<path/);

  const page = await t.request('GET', order.clientPath);
  assert.equal(page.status, 200);
  assert.match(page.headers.get('content-security-policy'), /script-src 'self'/);
  assert.equal(page.headers.get('referrer-policy'), 'no-referrer');

  const token = order.clientPath.split('/').pop();
  const view = await t.request('GET', `/api/c/${token}`);
  assert.equal(view.json.order.number, 1);
  assert.equal(view.json.order.details, '2 bières\n1 planche');
  assert.equal(view.json.order.restaurant.siret, '443 061 841 00047');
  assert.equal(view.json.order.id, undefined);

  const client = await openEvents(`${t.base}/api/c/${token}/events`);
  assert.equal((await client.next('state')).order.status, 'preparing');
  assert.equal((await staff.next('order')).order.listening, true);

  assert.equal((await t.request('POST', `/api/c/${token}/push`, { subscription: SUB })).status, 200);
  assert.equal((await staff.next('order')).order.push, true);

  const ready = await t.request('POST', `/api/orders/${order.id}/ready`, {}, { cookie });
  assert.equal(ready.json.order.status, 'ready');
  assert.equal((await client.next('state')).order.status, 'ready');
  assert.equal(t.pushes.length, 1);
  assert.match(t.pushes[0].payload.title, /Commande n° 1 prête/);
  assert.equal(t.pushes[0].subs[0].endpoint, SUB.endpoint);

  await t.request('POST', `/api/orders/${order.id}/ring`, {}, { cookie });
  await client.next('ring');
  assert.equal(t.pushes.length, 2);

  const pickup = await t.request('POST', `/api/orders/${order.id}/pickup`, {}, { cookie });
  assert.equal(pickup.status, 200);
  assert.equal((await client.next('done')).reason, 'picked_up');
  await client.waitEnd();
  assert.equal((await staff.next('removed')).id, order.id);

  assert.equal((await t.request('GET', `/api/c/${token}`)).status, 404);
  assert.equal(t.db.pushSubscriptions(order.id).length, 0);
  const left = (await t.request('GET', '/api/orders', undefined, { cookie })).json.orders;
  assert.deepEqual(left.map((o) => o.number), [2]);
  staff.close();
});

test('commande : annulation prévient le client', async () => {
  const cookie = await subscribedAccount('f@example.fr');
  const { order } = (await t.request('POST', '/api/orders', { details: 'Thé' }, { cookie })).json;
  const token = order.clientPath.split('/').pop();
  const client = await openEvents(`${t.base}/api/c/${token}/events`);
  await client.next('state');
  await t.request('DELETE', `/api/orders/${order.id}`, {}, { cookie });
  assert.equal((await client.next('done')).reason, 'canceled');
});

test('commande : un établissement ne voit pas les commandes d’un autre', async () => {
  const a = await subscribedAccount('g@example.fr');
  const b = await subscribedAccount('h@example.fr');
  const { order } = (await t.request('POST', '/api/orders', { details: 'Eau' }, { cookie: a })).json;
  assert.equal((await t.request('POST', `/api/orders/${order.id}/ready`, {}, { cookie: b })).status, 404);
  assert.equal((await t.request('GET', `/api/orders/${order.id}/qr.svg`, undefined, { cookie: b })).status, 404);
  assert.deepEqual((await t.request('GET', '/api/orders', undefined, { cookie: b })).json.orders, []);
});

test('commande : effacée d’elle-même au bout de 12 heures', async () => {
  const cookie = await subscribedAccount('i@example.fr');
  const { order } = (await t.request('POST', '/api/orders', { details: 'Oubliée' }, { cookie })).json;
  t.advance(12 * 60 * 60 * 1000 + 1);
  t.app.sweep();
  const token = order.clientPath.split('/').pop();
  assert.equal((await t.request('GET', `/api/c/${token}`)).status, 404);
  // la session (30 jours) reste ouverte
  assert.equal((await t.request('GET', '/api/me', undefined, { cookie })).status, 200);
});

test('commande : textes limités et nettoyés', async () => {
  const cookie = await subscribedAccount('j@example.fr');
  const long = await t.request('POST', '/api/orders', { details: 'x'.repeat(501) }, { cookie });
  assert.equal(long.status, 400);
  const { order } = (await t.request('POST', '/api/orders', { customer: ' Léo\u0007 ', details: 'a\r\nb\u0000' }, { cookie })).json;
  assert.equal(order.customer, 'Léo');
  assert.equal(order.details, 'a\nb');
});

test('notifications : adresse hors des services connus refusée', async () => {
  const cookie = await subscribedAccount('k@example.fr');
  const { order } = (await t.request('POST', '/api/orders', {}, { cookie })).json;
  const token = order.clientPath.split('/').pop();
  const evil = { endpoint: 'https://intranet.local/hook', keys: SUB.keys };
  assert.equal((await t.request('POST', `/api/c/${token}/push`, { subscription: evil })).status, 400);
});

test('personnalisation : nom, SIRET, palette, logo', async () => {
  const { cookie } = await t.signup('l@example.fr');
  const upd = await t.request('PUT', '/api/restaurant', { name: 'Chez Max', theme: 'rouge' }, { cookie });
  assert.equal(upd.json.restaurant.name, 'Chez Max');
  assert.equal(upd.json.restaurant.theme, 'rouge');
  assert.equal((await t.request('PUT', '/api/restaurant', { theme: 'fluo' }, { cookie })).status, 400);
  assert.equal((await t.request('PUT', '/api/restaurant', { siret: '123' }, { cookie })).status, 400);

  const svg = 'data:image/svg+xml;base64,' + Buffer.from('<svg/>').toString('base64');
  assert.equal((await t.request('PUT', '/api/restaurant/logo', { dataUrl: svg }, { cookie })).status, 400);
  const fake = 'data:image/png;base64,' + Buffer.from('pas une image').toString('base64');
  assert.equal((await t.request('PUT', '/api/restaurant/logo', { dataUrl: fake }, { cookie })).status, 400);

  const up = await t.request('PUT', '/api/restaurant/logo', { dataUrl: 'data:image/png;base64,' + PNG_1PX.toString('base64') }, { cookie });
  assert.equal(up.status, 200);
  const logoUrl = up.json.restaurant.logoUrl;
  const logo = await fetch(t.base + logoUrl);
  assert.equal(logo.headers.get('content-type'), 'image/png');
  assert.deepEqual(Buffer.from(await logo.arrayBuffer()), PNG_1PX);

  const removed = await t.request('DELETE', '/api/restaurant/logo', {}, { cookie });
  assert.equal(removed.json.restaurant.logoUrl, null);
  const again = await t.request('PUT', '/api/restaurant/logo', { dataUrl: 'data:image/png;base64,' + PNG_1PX.toString('base64') }, { cookie });
  assert.notEqual(again.json.restaurant.logoUrl, logoUrl, 'nouvelle adresse : l’ancienne image en cache ne revient pas');
});

test('sécurité : requêtes d’un autre site ou sans JSON refusées', async () => {
  const { cookie } = await t.signup('m@example.fr');
  const form = await t.request('PUT', '/api/restaurant', 'theme=vert', {
    cookie,
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' }
  });
  assert.equal(form.status, 415);
  const foreign = await t.request('PUT', '/api/restaurant', { theme: 'vert' }, { cookie, headers: { Origin: 'https://pirate.example' } });
  assert.equal(foreign.status, 403);
  const same = await t.request('PUT', '/api/restaurant', { theme: 'vert' }, { cookie, headers: { Origin: t.base } });
  assert.equal(same.status, 200);
  assert.equal((await t.request('GET', '/../src/config.js')).status, 404);
  assert.equal((await t.request('GET', '/%2e%2e/package.json')).status, 404);
  assert.equal((await t.request('GET', '/api/c/%E0%A4%A')).status, 400);
  assert.equal((await t.request('POST', '/api/login', { email: 'personne@example.fr', password: 'motdepasse' })).status, 401);
});

test('Stripe : paiement à 5 €/mois, retour de paiement, webhooks signés', async () => {
  const { cookie, json } = await t.signup('n@example.fr');
  t.lastRestaurantId = json.restaurant.id;

  const checkout = await t.request('POST', '/api/billing/checkout', {}, { cookie });
  assert.equal(checkout.json.url, 'https://checkout.stripe.test/s');
  const params = t.stripeCalls.at(-1)[1];
  assert.equal(params.mode, 'subscription');
  assert.equal(params.client_reference_id, json.restaurant.id);
  assert.deepEqual(params.line_items[0].price_data, {
    currency: 'eur',
    unit_amount: 500,
    recurring: { interval: 'month' },
    product_data: { name: 'Abonnement Buzz Eat' }
  });

  const confirmed = await t.request('POST', '/api/billing/confirm', { sessionId: 'cs_test_1234567890' }, { cookie });
  assert.equal(confirmed.json.subscription.active, true);
  assert.equal(confirmed.json.subscription.plan, 'stripe');
  assert.equal(confirmed.json.subscription.priceCents, 500);
  assert.equal(confirmed.json.subscription.canManage, true);

  const portal = await t.request('POST', '/api/billing/portal', {}, { cookie });
  assert.equal(portal.json.url, 'https://billing.stripe.test/p');

  // abonnement payant en cours : le code promo ne s'applique pas par-dessus
  assert.equal((await t.request('POST', '/api/billing/promo', { code: 'NOTRE-BOITE' }, { cookie })).status, 409);

  const send = (event, secret = 'whsec_test') => {
    const body = JSON.stringify(event);
    return t.request('POST', '/api/stripe/webhook', body, {
      headers: { 'Content-Type': 'application/json', 'Stripe-Signature': signWebhookPayload(body, secret, Math.floor(t.now() / 1000)) }
    });
  };
  const deleted = {
    id: 'evt_del',
    type: 'customer.subscription.deleted',
    data: { object: { id: 'sub_retour', status: 'canceled', customer: 'cus_retour', metadata: {} } }
  };
  assert.equal((await send(deleted, 'whsec_faux')).status, 400);
  assert.equal((await t.request('GET', '/api/me', undefined, { cookie })).json.subscription.active, true);
  assert.equal((await send(deleted)).status, 200);
  assert.equal((await t.request('GET', '/api/me', undefined, { cookie })).json.subscription.active, false);
  assert.equal((await t.request('POST', '/api/orders', {}, { cookie })).status, 402);

  const completed = {
    id: 'evt_new',
    type: 'checkout.session.completed',
    data: {
      object: {
        mode: 'subscription',
        client_reference_id: json.restaurant.id,
        customer: 'cus_retour',
        subscription: 'sub_2',
        payment_status: 'paid'
      }
    }
  };
  await send(completed);
  assert.equal((await t.request('GET', '/api/me', undefined, { cookie })).json.subscription.active, true);
  // un ancien abonnement qui se termine ne coupe pas le nouveau
  await send({ ...deleted, id: 'evt_old_again' });
  assert.equal((await t.request('GET', '/api/me', undefined, { cookie })).json.subscription.active, true);
  // même événement renvoyé par Stripe : traité une seule fois
  const pastDue = {
    id: 'evt_pd',
    type: 'customer.subscription.updated',
    data: { object: { id: 'sub_2', status: 'unpaid', customer: 'cus_retour', items: { data: [{ current_period_end: 1_900_000_000 }] } } }
  };
  await send(pastDue);
  assert.equal((await t.request('GET', '/api/me', undefined, { cookie })).json.subscription.status, 'unpaid');
  await t.request('POST', '/api/billing/confirm', { sessionId: 'cs_test_1234567890' }, { cookie });
});

test('Stripe : sans clé, le paiement est indiqué comme non configuré ; le code promo marche', async () => {
  const bare = await startTestApp({ withStripe: false });
  try {
    const { cookie, json } = await bare.signup('o@example.fr');
    assert.equal(json.subscription.onlinePayment, false);
    const checkout = await bare.request('POST', '/api/billing/checkout', {}, { cookie });
    assert.equal(checkout.status, 503);
    assert.match(checkout.json.error, /pas encore configuré/);
    assert.equal((await bare.request('POST', '/api/billing/promo', { code: 'NOTRE-BOITE' }, { cookie })).status, 200);
  } finally {
    await bare.close();
  }
});

test('codes promo : aucun code n’existe si l’environnement n’en définit pas', async () => {
  const bare = await startTestApp({ env: { PROMO_CODES_GRATUITS: '' } });
  try {
    const { cookie } = await bare.signup('p@example.fr');
    assert.equal((await bare.request('POST', '/api/billing/promo', { code: 'NOTRE-BOITE' }, { cookie })).status, 400);
    assert.equal((await bare.request('POST', '/api/billing/promo', { code: '' }, { cookie })).status, 400);
  } finally {
    await bare.close();
  }
});
