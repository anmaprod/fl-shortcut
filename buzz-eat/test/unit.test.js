import assert from 'node:assert/strict';
import { test } from 'node:test';
import { normalizeCode } from '../src/config.js';
import { isAllowedPushEndpoint, parsePushSubscription } from '../src/push.js';
import { RateLimiter, hashPassword, verifyPassword } from '../src/security.js';
import { formatSiret, isValidSiret } from '../src/siret.js';
import { encodeForm, signWebhookPayload, verifyWebhook } from '../src/stripe.js';
import { THEMES, getTheme } from '../public/js/themes.js';

test('SIRET : clé de Luhn, espaces tolérés, exception de La Poste', () => {
  assert.equal(isValidSiret('44306184100047'), true);
  assert.equal(isValidSiret('443 061 841 00047'), true);
  assert.equal(isValidSiret('44306184100048'), false);
  assert.equal(isValidSiret('4430618410004'), false);
  assert.equal(isValidSiret('abcdefghijklmn'), false);
  assert.equal(isValidSiret('35600000000048'), true); // siège de La Poste (Luhn juste)
  assert.equal(isValidSiret('35600000049837'), true); // bureau de poste : somme des chiffres = 45
  assert.equal(formatSiret('44306184100047'), '443 061 841 00047');
});

function luminance(hex) {
  const c = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255);
  const [r, g, b] = c.map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
function contrast(a, b) {
  const [l1, l2] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (l1 + 0.05) / (l2 + 0.05);
}

test('palettes : texte lisible (contraste 4,5 au moins) en clair et en sombre, identifiants uniques', () => {
  assert.equal(new Set(THEMES.map((t) => t.id)).size, THEMES.length);
  for (const t of THEMES) {
    assert.ok(contrast(t.tint, '#ffffff') >= 4.5, `${t.name} : texte blanc sur la couleur, couleur sur fond blanc`);
    assert.ok(contrast(t.tintDark, '#1c1c1e') >= 4.5, `${t.name} : couleur sur fond sombre`);
    assert.ok(contrast(t.tintDark, '#000000') >= 4.5, `${t.name} : couleur sur fond noir`);
  }
  assert.equal(getTheme('inconnue').id, 'bleu');
});

test('mots de passe : scrypt salé, vérification', async () => {
  const h = await hashPassword('secret123');
  assert.notEqual(h, await hashPassword('secret123'));
  assert.equal(await verifyPassword('secret123', h), true);
  assert.equal(await verifyPassword('Secret123', h), false);
  assert.equal(await verifyPassword('x', 'n’importe quoi'), false);
});

test('limiteur : bloque au-delà du maximum, repart après la fenêtre', () => {
  let now = 0;
  const l = new RateLimiter(() => now);
  assert.equal(l.allow('k', 2, 1000), true);
  assert.equal(l.allow('k', 2, 1000), true);
  assert.equal(l.allow('k', 2, 1000), false);
  now = 1000;
  assert.equal(l.allow('k', 2, 1000), true);
});

test('codes promo : casse et espaces ignorés', () => {
  assert.equal(normalizeCode(' notre boite '), 'NOTREBOITE');
});

test('Stripe : encodage des paramètres imbriqués', () => {
  const form = encodeForm({
    mode: 'subscription',
    line_items: [{ quantity: 1, price_data: { unit_amount: 200, recurring: { interval: 'month' } } }],
    customer: undefined
  });
  assert.deepEqual([...form.entries()], [
    ['mode', 'subscription'],
    ['line_items[0][quantity]', '1'],
    ['line_items[0][price_data][unit_amount]', '200'],
    ['line_items[0][price_data][recurring][interval]', 'month']
  ]);
});

test('Stripe : signature du webhook vérifiée, ancienne ou fausse refusée', () => {
  const body = JSON.stringify({ id: 'evt_1', type: 'x' });
  const now = 1_800_000_000_000;
  const header = signWebhookPayload(body, 'whsec_a', now / 1000);
  assert.equal(verifyWebhook(Buffer.from(body), header, 'whsec_a', { now }).id, 'evt_1');
  assert.throws(() => verifyWebhook(Buffer.from(body), header, 'whsec_b', { now }), /invalide/);
  assert.throws(() => verifyWebhook(Buffer.from(body + ' '), header, 'whsec_a', { now }), /invalide/);
  assert.throws(() => verifyWebhook(Buffer.from(body), header, 'whsec_a', { now: now + 600_000 }), /ancienne/);
  assert.throws(() => verifyWebhook(Buffer.from(body), '', 'whsec_a', { now }), /absente/);
});

test('notifications : seuls les services des navigateurs sont acceptés', () => {
  assert.equal(isAllowedPushEndpoint('https://fcm.googleapis.com/fcm/send/abc'), true);
  assert.equal(isAllowedPushEndpoint('https://web.push.apple.com/QGx'), true);
  assert.equal(isAllowedPushEndpoint('https://updates.push.services.mozilla.com/wpush/v2/x'), true);
  assert.equal(isAllowedPushEndpoint('https://wns2-par02p.notify.windows.com/w/?token=x'), true);
  assert.equal(isAllowedPushEndpoint('http://fcm.googleapis.com/x'), false);
  assert.equal(isAllowedPushEndpoint('https://fcm.googleapis.com.evil.fr/x'), false);
  assert.equal(isAllowedPushEndpoint('https://169.254.169.254/latest'), false);
  assert.equal(isAllowedPushEndpoint('https://fcm.googleapis.com:8443/x'), false);
  assert.equal(parsePushSubscription({ endpoint: 'https://fcm.googleapis.com/x', keys: { p256dh: 'ab-_', auth: 'cd' } }).auth, 'cd');
  assert.equal(parsePushSubscription({ endpoint: 'https://fcm.googleapis.com/x', keys: { p256dh: '<>', auth: 'cd' } }), null);
});
