import crypto from 'node:crypto';

// Webhooks de la caisse Popina (https://www.pragma-project.dev/docs/guides/webhooks) :
// POST signé (en-tête x-popina-hmac-signature = HMAC-SHA256 hexadécimal du corps reçu, clé de 64 caractères
// donnée par Popina), événements order.call (commande modifiée, envoi en préparation…), order.paid,
// order.canceled et order.transferred. Montants en centimes, articles dans productRowList et menuRowList.

export function verifyPopinaSignature(rawBody, signature, secret) {
  if (!secret || typeof signature !== 'string' || !/^[0-9a-f]{64}$/i.test(signature)) return false;
  const expected = crypto.createHmac('sha256', secret).update(rawBody).digest();
  return crypto.timingSafeEqual(expected, Buffer.from(signature, 'hex'));
}

const list = (value) => (Array.isArray(value) ? value.filter((x) => x && typeof x === 'object') : []);
const text = (value) => (typeof value === 'string' ? value.trim() : '');

function withModifiers(row) {
  const modifiers = list(row.modifierRowList).map((m) => text(m.name)).filter(Boolean);
  const name = text(row.name) || 'Article';
  return modifiers.length ? `${name} (${modifiers.join(', ')})` : name;
}

function quantity(row) {
  const q = Number(row.quantity);
  return Number.isFinite(q) && q > 0 ? q : 1;
}

// Texte de la commande pour l'écran du bar et le téléphone du client : une ligne par article.
export function popinaOrderText(data) {
  const lines = [];
  for (const row of list(data.productRowList)) {
    if (!row.isCanceled) lines.push(`${quantity(row)} × ${withModifiers(row)}`);
  }
  for (const menu of list(data.menuRowList)) {
    const inside = list(menu.productRowList)
      .filter((p) => !p.isCanceled)
      .map(withModifiers);
    lines.push(`${quantity(menu)} × ${text(menu.name) || 'Menu'}${inside.length ? ` : ${inside.join(', ')}` : ''}`);
  }
  const comment = text(data.comment);
  if (comment) lines.push(`Note : ${comment}`);
  return lines.join('\n');
}

// Repère montré à la place du nom du client : le numéro de bipeur s'il y en a un, sinon la table.
export function popinaLabel(data) {
  const beeper = Number(data.beeperNumber);
  if (Number.isInteger(beeper) && beeper > 0) return `Bipeur ${beeper}`;
  const table = text(data.tableName);
  return table ? `Table ${table}` : '';
}

// Envoyée en préparation : au moins un article (hors annulés) porte une date de transmission.
export function wasSentToPreparation(data) {
  const rows = [...list(data.productRowList), ...list(data.menuRowList).flatMap((m) => list(m.productRowList))];
  return rows.some((p) => !p.isCanceled && p.transmittedAt);
}

// Salles retenues, séparées par des virgules ; liste vide : toutes les salles.
export function roomMatches(rooms, roomName) {
  const wanted = String(rooms || '')
    .split(',')
    .map((r) => r.trim().toLowerCase())
    .filter(Boolean);
  return !wanted.length || wanted.includes(text(roomName).toLowerCase());
}
