// Tests du Worker sans réseau : SumUp et les fichiers du site sont simulés.
// Lancer : npm test (dans web/)
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import worker from '../src/worker.js';

const SITE = 'https://flshortcuts.example';
const ID = '4e425463-3e1b-431d-83fa-1e51c2925e99';
const PAGE = `https://checkout.sumup.com/pay/${ID}`;
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
    if (options.method === 'POST') return Response.json({ id: ID, status: 'PENDING', hosted_checkout_url: PAGE }, { status: 201 });
    return Response.json({ id: ID, status: 'PAID', amount: 5 });
  };
});

const payer = (corps, entetes = {}) =>
  new Request(`${SITE}/api/paiement`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Origin: SITE, ...entetes },
    body: typeof corps === 'string' ? corps : JSON.stringify(corps),
  });

test('crée un paiement sur la page SumUp, du montant choisi, en euros, avec retour sur le site', async () => {
  const r = await worker.fetch(payer({ montant: 5, systeme: 'windows' }), env());
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { id: ID, montant: 5, url: PAGE });
  assert.equal(appels.length, 1);
  assert.equal(appels[0].adresse, 'https://api.sumup.com/v0.1/checkouts');
  assert.equal(appels[0].options.headers.Authorization, 'Bearer sup_sk_test');
  const envoye = JSON.parse(appels[0].options.body);
  assert.equal(envoye.amount, 5);
  assert.equal(envoye.currency, 'EUR');
  assert.equal(envoye.merchant_code, 'MTEST123');
  assert.equal(envoye.description, 'FL Shortcuts pour Windows, prix libre');
  assert.equal(envoye.redirect_url, `${SITE}/?paiement=retour`);
  assert.deepEqual(envoye.hosted_checkout, { enabled: true });
  assert.match(envoye.checkout_reference, /^[0-9a-f-]{36}$/);
});

test('n’envoie le navigateur que vers une page https de SumUp', async () => {
  for (const adresse of [undefined, 'http://checkout.sumup.com/pay/x', 'https://sumup.com.pirate.example/pay', 'javascript:alert(1)', 'pas une adresse']) {
    globalThis.fetch = async () => Response.json({ id: ID, status: 'PENDING', hosted_checkout_url: adresse }, { status: 201 });
    const r = await worker.fetch(payer({ montant: 5 }), env());
    assert.equal(r.status, 502, String(adresse));
  }
});

test('deux paiements ont deux références différentes', async () => {
  await worker.fetch(payer({ montant: 3 }), env());
  await worker.fetch(payer({ montant: 3 }), env());
  const [a, b] = appels.map((c) => JSON.parse(c.options.body).checkout_reference);
  assert.notEqual(a, b);
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

// ---------- Lien par mail ----------
const BREVO = { BREVO_API_KEY: 'xkeysib-test', MAIL_EXPEDITEUR: 'bonjour@flshortcuts.example' };
const demanderLien = (corps, entetes = {}) =>
  new Request(`${SITE}/api/lien`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Origin: SITE, 'CF-Connecting-IP': '203.0.113.7', ...entetes },
    body: typeof corps === 'string' ? corps : JSON.stringify(corps),
  });
const envoiBrevo = () => appels.find((c) => c.adresse === 'https://api.brevo.com/v3/smtp/email');

test('lien : envoie le lien Mac par Brevo, à la bonne adresse, depuis l’adresse réglée', async () => {
  globalThis.fetch = async (adresse, options = {}) => {
    appels.push({ adresse, options });
    return Response.json({ messageId: '<1@relay>' }, { status: 201 });
  };
  const r = await worker.fetch(demanderLien({ mail: ' toi@exemple.fr ', systeme: 'mac' }), env(BREVO));
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { envoye: true });
  const envoi = envoiBrevo();
  assert.equal(envoi.options.headers['api-key'], 'xkeysib-test');
  const corps = JSON.parse(envoi.options.body);
  assert.deepEqual(corps.to, [{ email: 'toi@exemple.fr' }]);
  assert.deepEqual(corps.sender, { name: 'FL Shortcuts', email: 'bonjour@flshortcuts.example' });
  assert.equal(corps.subject, 'Ton lien FL Shortcuts pour Mac');
  assert.match(corps.htmlContent, /releases\/latest\/download\/FLShortcut\.dmg/);
  assert.match(corps.textContent, /releases\/latest\/download\/FLShortcut\.dmg/);
  assert.match(corps.textContent, /Merci de soutenir FL Shortcuts/);
});

test('lien : Windows donne l’installeur Windows', async () => {
  globalThis.fetch = async (adresse, options = {}) => { appels.push({ adresse, options }); return Response.json({}, { status: 201 }); };
  await worker.fetch(demanderLien({ mail: 'toi@exemple.fr', systeme: 'windows' }), env(BREVO));
  const corps = JSON.parse(envoiBrevo().options.body);
  assert.equal(corps.subject, 'Ton lien FL Shortcuts pour Windows');
  assert.match(corps.textContent, /FLShortcut-Windows-Setup\.exe/);
});

test('lien : remercie pour le montant seulement si SumUp dit PAID', async () => {
  for (const [statut, attendu] of [['PAID', /Merci pour ton soutien de 5 €/], ['PENDING', /Merci de soutenir/]]) {
    appels = [];
    globalThis.fetch = async (adresse, options = {}) => {
      appels.push({ adresse, options });
      if (adresse.startsWith('https://api.sumup.com')) return Response.json({ id: ID, status: statut, amount: 5 });
      return Response.json({}, { status: 201 });
    };
    await worker.fetch(demanderLien({ mail: 'toi@exemple.fr', paiement: ID }), env(BREVO));
    assert.match(JSON.parse(envoiBrevo().options.body).textContent, attendu, statut);
  }
});

test('lien : sans Brevo réglé, répond envoye: false sans rien envoyer', async () => {
  const r = await worker.fetch(demanderLien({ mail: 'toi@exemple.fr' }), env());
  assert.equal(r.status, 200);
  assert.deepEqual(await r.json(), { envoye: false });
  assert.equal(appels.length, 0);
});

test('lien : refuse une adresse invalide, une demande illisible ou venue d’un autre site', async () => {
  for (const mail of ['', 'pas-un-mail', 'a@b', 'a b@c.fr', '<x>@y.fr', 42, 'x'.repeat(250) + '@y.fr']) {
    const r = await worker.fetch(demanderLien({ mail }), env(BREVO));
    assert.equal(r.status, 400, JSON.stringify(mail));
  }
  assert.equal((await worker.fetch(demanderLien('pas du json'), env(BREVO))).status, 400);
  const ailleurs = await worker.fetch(demanderLien({ mail: 'toi@exemple.fr' }, { Origin: 'https://autre.example' }), env(BREVO));
  assert.equal(ailleurs.status, 403);
  assert.equal(appels.length, 0);
});

test('lien : au-delà de la limite, 429 et rien n’est envoyé ; la limite compte l’IP et l’adresse', async () => {
  const cles = [];
  const limite = (ok) => ({ limit: async ({ key }) => { cles.push(key); return { success: ok(key) }; } });
  const r = await worker.fetch(demanderLien({ mail: 'Toi@Exemple.fr' }), env({ ...BREVO, LIMITE_MAIL: limite((k) => !k.startsWith('mail:')) }));
  assert.equal(r.status, 429);
  assert.deepEqual(cles, ['ip:203.0.113.7', 'mail:toi@exemple.fr']);
  assert.equal(appels.length, 0);
});

test('lien : Brevo refuse, réponse 502 envoye: false', async () => {
  globalThis.fetch = async () => new Response('{"code":"unauthorized"}', { status: 401 });
  const r = await worker.fetch(demanderLien({ mail: 'toi@exemple.fr' }), env(BREVO));
  assert.equal(r.status, 502);
  assert.deepEqual(await r.json(), { envoye: false });
});
