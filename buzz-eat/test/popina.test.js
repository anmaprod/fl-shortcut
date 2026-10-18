import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { after, before, test } from 'node:test';
import { popinaLabel, popinaOrderText, roomMatches, verifyPopinaSignature, wasSentToPreparation } from '../src/popina.js';
import { openEvents, startTestApp } from './helpers.js';

const SECRET = 'a'.repeat(32) + 'B'.repeat(32);

// Commande au format des webhooks Popina (exemple de leur documentation, raccourci).
function popinaOrder(overrides = {}) {
  return {
    id: '65825B5F-F7DC-4BCF-9EDB-25C9751377AB',
    locationId: '7268c3d1-5e8d-46b9-90ba-318c495df867',
    establishmentName: 'Jean de la Côte',
    roomName: 'Salle',
    tableName: '8',
    isPaid: false,
    isCanceled: false,
    beeperNumber: -1,
    comment: null,
    productRowList: [
      { id: 'p1', name: 'Schweppes', isCanceled: false, quantity: 1, transmittedAt: '2024-10-10T14:58:43.000Z', modifierRowList: [] },
      { id: 'p2', name: 'Café', isCanceled: true, quantity: 1, transmittedAt: '2024-10-10T14:58:43.000Z', modifierRowList: [] }
    ],
    menuRowList: [
      {
        name: 'Menu complet',
        productRowList: [
          { id: 'm1', name: 'Entree du jour', isCanceled: false, quantity: 1, transmittedAt: '2024-10-10T14:58:43.000Z', modifierRowList: [] },
          { id: 'm2', name: 'Plat du jour', isCanceled: false, quantity: 1, transmittedAt: null, modifierRowList: [{ name: 'Bleu', amount: 0 }] }
        ]
      }
    ],
    paymentRowList: [],
    ...overrides
  };
}

test('Popina : texte de la commande, repère, envoi en préparation, salles', () => {
  const data = popinaOrder({ comment: 'Sans glaçons' });
  assert.equal(popinaOrderText(data), '1 × Schweppes\n1 × Menu complet : Entree du jour, Plat du jour (Bleu)\nNote : Sans glaçons');
  assert.equal(popinaLabel(data), 'Table 8');
  assert.equal(popinaLabel({ ...data, beeperNumber: 12 }), 'Bipeur 12');
  assert.equal(popinaLabel({ ...data, tableName: null }), '');
  assert.equal(wasSentToPreparation(data), true);
  const notSent = popinaOrder({
    productRowList: [{ name: 'Bière', quantity: 2, transmittedAt: null }],
    menuRowList: []
  });
  assert.equal(wasSentToPreparation(notSent), false);
  assert.equal(popinaOrderText(notSent), '2 × Bière');
  assert.equal(popinaOrderText({ productRowList: 'pas une liste', menuRowList: [null] }), '');
  assert.equal(roomMatches('', 'Terrasse'), true);
  assert.equal(roomMatches('Comptoir, terrasse', 'Terrasse'), true);
  assert.equal(roomMatches('Comptoir', 'Salle'), false);
});

test('Popina : signature HMAC-SHA256 hexadécimale du corps reçu', () => {
  const body = Buffer.from('{"meta":{},"data":{}}');
  const good = crypto.createHmac('sha256', SECRET).update(body).digest('hex');
  assert.equal(verifyPopinaSignature(body, good, SECRET), true);
  assert.equal(verifyPopinaSignature(body, good.toUpperCase(), SECRET), true);
  assert.equal(verifyPopinaSignature(body, good, 'autre'), false);
  assert.equal(verifyPopinaSignature(Buffer.from('{"meta":{},"data":{} }'), good, SECRET), false);
  assert.equal(verifyPopinaSignature(body, 'zz', SECRET), false);
  assert.equal(verifyPopinaSignature(body, good, null), false);
});

let t;
before(async () => {
  t = await startTestApp();
});
after(() => t.close());

async function connectedAccount(email, settings = {}) {
  const { cookie } = await t.signup(email);
  await t.request('POST', '/api/billing/promo', { code: 'NOTRE-BOITE' }, { cookie });
  const link = await t.request('PUT', '/api/popina', { enabled: true, secret: SECRET, ...settings }, { cookie });
  return { cookie, path: new URL(link.json.webhookUrl).pathname };
}

function send(path, event, data, { secret = SECRET } = {}) {
  const body = JSON.stringify({ meta: { id: crypto.randomUUID(), event, emittedAt: new Date().toISOString() }, data });
  const signature = crypto.createHmac('sha256', secret).update(body).digest('hex');
  return t.request('POST', path, body, {
    headers: { 'Content-Type': 'application/json', 'x-popina-webhook-event': event, 'x-popina-hmac-signature': signature }
  });
}

const orders = async (cookie) => (await t.request('GET', '/api/orders', undefined, { cookie })).json.orders;
const info = async (cookie) => (await t.request('GET', '/api/popina', undefined, { cookie })).json.lastInfo;

test('Popina : réglages, adresse propre à l’établissement, clé secrète jamais renvoyée', async () => {
  const { cookie } = await t.signup('popina-a@example.fr');
  const empty = await t.request('GET', '/api/popina', undefined, { cookie });
  assert.deepEqual(empty.json, { enabled: false, webhookUrl: null, hasSecret: false, createOn: 'sent', rooms: '', lastAt: null, lastInfo: null });
  assert.equal((await t.request('PUT', '/api/popina', { secret: 'court' }, { cookie })).status, 400);
  assert.equal((await t.request('PUT', '/api/popina', { createOn: 'jamais' }, { cookie })).status, 400);
  const set = await t.request('PUT', '/api/popina', { enabled: true, secret: SECRET, rooms: 'Comptoir' }, { cookie });
  assert.equal(set.json.enabled, true);
  assert.equal(set.json.hasSecret, true);
  assert.equal(set.json.secret, undefined);
  assert.match(set.json.webhookUrl, /^http:\/\/127\.0\.0\.1:\d+\/api\/popina\/[A-Za-z0-9_-]{32}$/);
  const renewed = await t.request('POST', '/api/popina/address', {}, { cookie });
  assert.notEqual(renewed.json.webhookUrl, set.json.webhookUrl);
  assert.equal(renewed.json.hasSecret, true);
  const old = new URL(set.json.webhookUrl).pathname;
  assert.equal((await send(old, 'order.call', popinaOrder())).status, 404);
});

test('Popina : envoi en préparation = commande Buzz Eat et QR code ; mise à jour ; annulation', async () => {
  const { cookie, path } = await connectedAccount('popina-b@example.fr');
  const staff = await openEvents(`${t.base}/api/events`, cookie);
  await staff.next('snapshot');

  const bad = await send(path, 'order.call', popinaOrder(), { secret: 'x'.repeat(64) });
  assert.equal(bad.status, 401);
  assert.match(await info(cookie), /signature invalide/);

  const waiting = popinaOrder({ productRowList: [{ name: 'Bière', quantity: 2, transmittedAt: null }], menuRowList: [] });
  assert.equal((await send(path, 'order.call', waiting)).status, 200);
  assert.deepEqual(await orders(cookie), []);
  assert.match(await info(cookie), /En attente/);

  assert.equal((await send(path, 'order.call', popinaOrder())).status, 200);
  const created = (await staff.next('order')).order;
  assert.equal(created.source, 'popina');
  assert.equal(created.customer, 'Table 8');
  assert.equal(created.details, '1 × Schweppes\n1 × Menu complet : Entree du jour, Plat du jour (Bleu)');
  assert.match(await info(cookie), /Commande n° 1 créée/);
  const qr = await t.request('GET', `/api/orders/${created.id}/qr.svg`, undefined, { cookie });
  assert.equal(qr.status, 200);

  // même commande renvoyée avec un article en plus : mise à jour, pas de doublon
  const token = created.clientPath.split('/').pop();
  const client = await openEvents(`${t.base}/api/c/${token}/events`);
  await client.next('state');
  const more = popinaOrder();
  more.productRowList.push({ name: 'Perrier', quantity: 1, transmittedAt: '2024-10-10T15:00:00.000Z' });
  await send(path, 'order.call', more);
  assert.match((await client.next('state')).order.details, /1 × Perrier/);
  assert.equal((await orders(cookie)).length, 1);

  await send(path, 'order.canceled', { ...more, isCanceled: true });
  assert.equal((await client.next('done')).reason, 'canceled');
  assert.deepEqual(await orders(cookie), []);
  staff.close();
});

test('Popina : une commande récupérée ne revient pas quand Popina la renvoie (paiement)', async () => {
  const { cookie, path } = await connectedAccount('popina-c@example.fr');
  await send(path, 'order.call', popinaOrder());
  const [order] = await orders(cookie);
  await t.request('POST', `/api/orders/${order.id}/pickup`, {}, { cookie });
  await send(path, 'order.paid', popinaOrder({ isPaid: true }));
  assert.deepEqual(await orders(cookie), []);
  assert.match(await info(cookie), /déjà terminée/);
});

test('Popina : création au paiement, filtre des salles, abonnement, connexion coupée', async () => {
  const paid = await connectedAccount('popina-d@example.fr', { createOn: 'paid' });
  await send(paid.path, 'order.call', popinaOrder());
  assert.deepEqual(await orders(paid.cookie), []);
  await send(paid.path, 'order.paid', popinaOrder({ isPaid: true, beeperNumber: 7 }));
  assert.deepEqual((await orders(paid.cookie)).map((o) => o.customer), ['Bipeur 7']);

  const counter = await connectedAccount('popina-e@example.fr', { rooms: 'Comptoir' });
  await send(counter.path, 'order.call', popinaOrder({ roomName: 'Terrasse' }));
  assert.deepEqual(await orders(counter.cookie), []);
  assert.match(await info(counter.cookie), /salle « Terrasse »/);
  await send(counter.path, 'order.call', popinaOrder({ id: 'autre', roomName: 'comptoir' }));
  assert.equal((await orders(counter.cookie)).length, 1);

  const { cookie } = await t.signup('popina-f@example.fr');
  const link = await t.request('PUT', '/api/popina', { enabled: true, secret: SECRET }, { cookie });
  const path = new URL(link.json.webhookUrl).pathname;
  await send(path, 'order.call', popinaOrder());
  assert.deepEqual(await orders(cookie), []);
  assert.match(await info(cookie), /abonnement inactif/);

  await t.request('PUT', '/api/popina', { enabled: false }, { cookie: counter.cookie });
  await send(counter.path, 'order.call', popinaOrder({ id: 'encore', roomName: 'Comptoir' }));
  assert.equal((await orders(counter.cookie)).length, 1);
});

test('Popina : sans clé secrète, rien n’est accepté', async () => {
  const { cookie } = await t.signup('popina-g@example.fr');
  const link = await t.request('PUT', '/api/popina', { enabled: true }, { cookie });
  const path = new URL(link.json.webhookUrl).pathname;
  assert.equal((await send(path, 'order.call', popinaOrder())).status, 401);
  assert.match(await info(cookie), /clé secrète/);
  assert.equal((await send('/api/popina/inconnuinconnuinconnu', 'order.call', popinaOrder())).status, 404);
});
