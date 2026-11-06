// Tests du Worker sans réseau : SumUp et les fichiers du site sont simulés.
// Lancer : npm test (dans web/)
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import worker from '../src/worker.js';

const SITE = 'https://flshortcuts.example';
const ID = '4e425463-3e1b-431d-83fa-1e51c2925e99';
const env = (reglages = {}) => ({
  SUMUP_API_KEY: 'sup_sk_test',
  SUMUP_MERCHANT_CODE: 'MTEST123',
  ASSETS: { fetch: async () => new Response('page', { status: 200 }) },
  ...reglages,
});

let appels;
beforeEach(() => {
  appels = [];
  globalThis.fetch = async (adresse, options = {}) => {
    appels.push({ adresse, options });
    if (options.method === 'POST') return Response.json({ id: ID, status: 'PENDING' }, { status: 201 });
    return Response.json({ id: ID, status: 'PAID', amount: 5 });
  };
});

const payer = (corps, entetes = {}) =>
  new Request(`${SITE}/api/paiement`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Origin: SITE, ...entetes },
    body: typeof corps === 'string' ? corps : JSON.stringify(corps),
  });

test('crée un paiement SumUp du montant choisi, en euros, avec retour sur le site', async () => {
  const r = await worker.fetch(payer({ montant: 5, systeme: 'windows' }), env());
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { id: ID, montant: 5, googlePay: null });
  assert.equal(appels.length, 1);
  assert.equal(appels[0].adresse, 'https://api.sumup.com/v0.1/checkouts');
  assert.equal(appels[0].options.headers.Authorization, 'Bearer sup_sk_test');
  const envoye = JSON.parse(appels[0].options.body);
  assert.equal(envoye.amount, 5);
  assert.equal(envoye.currency, 'EUR');
  assert.equal(envoye.merchant_code, 'MTEST123');
  assert.equal(envoye.description, 'FL Shortcuts pour Windows, prix libre');
  assert.equal(envoye.redirect_url, `${SITE}/?paiement=retour`);
  assert.match(envoye.checkout_reference, /^[0-9a-f-]{36}$/);
});

test('deux paiements ont deux références différentes', async () => {
  await worker.fetch(payer({ montant: 3 }), env());
  await worker.fetch(payer({ montant: 3 }), env());
  const [a, b] = appels.map((c) => JSON.parse(c.options.body).checkout_reference);
  assert.notEqual(a, b);
});

test('donne Google Pay seulement quand son identifiant est réglé', async () => {
  const r = await worker.fetch(payer({ montant: 10 }), env({ GOOGLE_PAY_MERCHANT_ID: 'BCR2DN4T' }));
  assert.deepEqual((await r.json()).googlePay, { merchantId: 'BCR2DN4T', merchantName: 'FL Shortcuts' });
});

test('refuse les montants hors de 1 à 999 € ou non entiers, sans appeler SumUp', async () => {
  for (const montant of [0, -5, 1000, 2.5, '5', null, 'abc']) {
    const r = await worker.fetch(payer({ montant }), env());
    assert.equal(r.status, 400, `montant ${JSON.stringify(montant)}`);
  }
  const illisible = await worker.fetch(payer('pas du json'), env());
  assert.equal(illisible.status, 400);
  assert.equal(appels.length, 0);
});

test('répond 503 tant que SumUp n’est pas configuré, pour que le site propose le gratuit', async () => {
  for (const manque of [{ SUMUP_API_KEY: '' }, { SUMUP_MERCHANT_CODE: undefined }]) {
    const r = await worker.fetch(payer({ montant: 5 }), env(manque));
    assert.equal(r.status, 503);
  }
  assert.equal(appels.length, 0);
});

test('refuse un paiement lancé depuis un autre site', async () => {
  const r = await worker.fetch(payer({ montant: 5 }, { Origin: 'https://autre.example' }), env());
  assert.equal(r.status, 403);
  assert.equal(appels.length, 0);
});

test('SumUp refuse ou ne répond pas : erreur claire, sans détail de SumUp', async () => {
  globalThis.fetch = async () => new Response('{"error_code":"INVALID"}', { status: 400 });
  const refus = await worker.fetch(payer({ montant: 5 }), env());
  assert.equal(refus.status, 502);
  assert.doesNotMatch(JSON.stringify(await refus.json()), /INVALID/);

  globalThis.fetch = async () => { throw new Error('réseau'); };
  const panne = await worker.fetch(payer({ montant: 5 }), env());
  assert.equal(panne.status, 502);
});

test('lit l’état d’un paiement chez SumUp et ne renvoie que l’état et le montant', async () => {
  const r = await worker.fetch(new Request(`${SITE}/api/paiement/${ID}`), env());
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { statut: 'PAID', montant: 5 });
  assert.equal(appels[0].adresse, `https://api.sumup.com/v0.1/checkouts/${ID}`);
  assert.equal(r.headers.get('Cache-Control'), 'no-store');
});

test('refuse un identifiant de paiement mal formé sans appeler SumUp', async () => {
  for (const id of ['abc', '../../me', `${ID}/x`]) {
    const r = await worker.fetch(new Request(`${SITE}/api/paiement/${encodeURIComponent(id)}`), env());
    assert.equal(r.status, 404, id);
  }
  assert.equal(appels.length, 0);
});

test('mauvaise méthode et adresse inconnue', async () => {
  assert.equal((await worker.fetch(new Request(`${SITE}/api/paiement`), env())).status, 405);
  const supprimer = new Request(`${SITE}/api/paiement/${ID}`, { method: 'DELETE' });
  assert.equal((await worker.fetch(supprimer, env())).status, 405);
  assert.equal((await worker.fetch(new Request(`${SITE}/api/autre`), env())).status, 404);
});

test('les autres adresses servent les pages du site', async () => {
  const r = await worker.fetch(new Request(`${SITE}/`), env());
  assert.equal(await r.text(), 'page');
});
