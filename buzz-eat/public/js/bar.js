import { $, api, applyTheme, clock, elapsed, formatPrice, h, registerServiceWorker, renderBrand, toast } from './common.js';

const orders = new Map();
const cards = new Map();
let me = null;
let events = null;
let qr = { id: null, scanned: false };

// ---------- Cartes des commandes ----------

function clientChip(o) {
  if (o.alertOn && (o.listening || o.push)) return h('span', { class: 'chip chip-ok', text: '📱 Alerte activée' });
  if (o.listening) return h('span', { class: 'chip chip-warn', text: '📱 Page ouverte, alerte pas activée' });
  if (o.alertOn) return h('span', { class: 'chip chip-warn', text: '⚠️ Téléphone du client déconnecté' });
  return h('span', { class: 'chip', text: 'QR code pas encore scanné' });
}

function timeText(o) {
  return o.status === 'ready'
    ? `Prête ${elapsed(o.readyAt)}`
    : `Prise à ${clock(o.createdAt)} · ${elapsed(o.createdAt)}`;
}

// Bouton d'action : grisé pendant l'envoi, rendu utilisable si l'envoi échoue.
function actionButton(cls, text, fn) {
  const button = h('button', { class: `btn ${cls}`, type: 'button', text });
  button.addEventListener('click', async () => {
    button.disabled = true;
    try {
      await fn();
    } catch (err) {
      toast(err.message, { error: true });
    }
    button.disabled = false;
  });
  return button;
}

function actions(o) {
  const qrButton = h('button', { class: 'btn btn-ghost', type: 'button', onclick: () => showQr(o.id), text: 'QR code' });
  const remove = () => {
    orders.delete(o.id);
    render();
  };
  if (o.status === 'ready') {
    return [
      actionButton('btn-ok btn-lg btn-main', '✓ Récupérée', async () => {
        await api('POST', `/api/orders/${o.id}/pickup`);
        remove();
      }),
      actionButton('btn-secondary', '🔔 Sonner à nouveau', async () => {
        await api('POST', `/api/orders/${o.id}/ring`);
        toast(`Le téléphone de la commande n° ${o.number} sonne à nouveau.`);
      }),
      qrButton
    ];
  }
  return [
    actionButton('btn-primary btn-lg btn-main', '🔔 Venir retirer la commande', async () => {
      const { order } = await api('POST', `/api/orders/${o.id}/ready`);
      orders.set(order.id, order);
      render();
    }),
    qrButton,
    actionButton('btn-danger-ghost', 'Annuler', async () => {
      if (!confirm(`Annuler la commande n° ${o.number} ?`)) return;
      await api('DELETE', `/api/orders/${o.id}`);
      remove();
    })
  ];
}

function buildCard(o) {
  const ready = o.status === 'ready';
  return h(
    'article',
    { class: `order ${ready ? 'is-ready' : 'is-preparing'}`, 'aria-label': `Commande n° ${o.number}` },
    h(
      'div',
      { class: 'order-head' },
      h('div', { class: 'order-num', text: o.number }),
      h(
        'div',
        { class: 'order-meta' },
        h('div', { class: 'order-customer', text: o.customer || `Commande n° ${o.number}` }),
        h('div', { class: 'order-time', text: timeText(o) })
      )
    ),
    o.details ? h('p', { class: 'order-details', text: o.details }) : null,
    h('div', { class: 'order-chips' }, clientChip(o)),
    h('div', { class: 'order-actions' }, actions(o))
  );
}

// Une carte n'est refaite que si sa commande a changé : le bouton touché garde sa place.
function cardFor(o) {
  const sig = JSON.stringify(o);
  const cached = cards.get(o.id);
  if (cached?.sig === sig) return cached.el;
  const el = buildCard(o);
  cards.set(o.id, { sig, el, order: o });
  return el;
}

// Seules les cartes nouvelles ou déplacées sont réinsérées : les autres ne rejouent pas leur animation.
function fill(list, items, emptyText) {
  if (!items.length) {
    if (!list.querySelector('.empty')) list.replaceChildren(h('p', { class: 'empty', text: emptyText }));
    return;
  }
  list.querySelector('.empty')?.remove();
  items.map(cardFor).forEach((el, i) => {
    if (list.children[i] !== el) list.insertBefore(el, list.children[i] || null);
  });
  while (list.children.length > items.length) list.lastElementChild.remove();
}

function render() {
  for (const id of cards.keys()) if (!orders.has(id)) cards.delete(id);
  const all = [...orders.values()];
  const preparing = all.filter((o) => o.status !== 'ready').sort((a, b) => a.createdAt - b.createdAt);
  const ready = all.filter((o) => o.status === 'ready').sort((a, b) => a.readyAt - b.readyAt);
  $('#prep-count').textContent = preparing.length;
  $('#ready-count').textContent = ready.length;
  fill($('#prep-list'), preparing, 'Aucune commande en préparation.');
  fill($('#ready-list'), ready, 'Aucune commande à retirer.');
}

function refreshTimes() {
  for (const { el, order } of cards.values()) {
    const t = el.querySelector('.order-time');
    if (t) t.textContent = timeText(order);
  }
}

// ---------- QR code ----------

function showQr(id) {
  const o = orders.get(id);
  if (!o) return;
  qr = { id, scanned: o.listening || o.alertOn };
  $('#qr-num').textContent = o.number;
  $('#qr-img').src = `/api/orders/${id}/qr.svg`;
  $('#qr-scanned').hidden = !qr.scanned;
  const dialog = $('#qr-dialog');
  if (!dialog.open) dialog.showModal();
}

function onOrderUpdate(o) {
  const dialog = $('#qr-dialog');
  if (!dialog.open || qr.id !== o.id || qr.scanned || !(o.listening || o.alertOn)) return;
  qr.scanned = true;
  $('#qr-scanned').hidden = false;
  setTimeout(() => {
    if (qr.id === o.id && dialog.open) dialog.close();
  }, 1800);
}

$('#qr-dialog').addEventListener('close', () => {
  qr = { id: null, scanned: false };
  $('#details').focus();
});

// ---------- Nouvelle commande ----------

$('#order-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const button = $('#validate');
  button.disabled = true;
  $('#order-error').textContent = '';
  try {
    const { order } = await api('POST', '/api/orders', {
      details: $('#details').value,
      customer: $('#customer').value
    });
    orders.set(order.id, order);
    render();
    e.target.reset();
    showQr(order.id);
  } catch (err) {
    $('#order-error').textContent = err.message;
    if (err.status === 402) $('#sub-banner').hidden = false;
  } finally {
    button.disabled = !me.subscription.active;
  }
});

$('#details').addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) $('#order-form').requestSubmit();
});

// ---------- Temps réel ----------

function setLive(on) {
  const live = $('#live');
  live.classList.toggle('off', !on);
  live.textContent = on ? 'En direct' : 'Reconnexion…';
}

function reconnectLater() {
  setTimeout(async () => {
    try {
      await api('GET', '/api/me');
      connect();
    } catch (err) {
      if (err.status === 401) location.href = '/';
      else reconnectLater();
    }
  }, 4000);
}

function connect() {
  events = new EventSource('/api/events');
  events.onopen = () => setLive(true);
  events.addEventListener('snapshot', (e) => {
    orders.clear();
    for (const o of JSON.parse(e.data).orders) orders.set(o.id, o);
    render();
  });
  events.addEventListener('order', (e) => {
    const { order } = JSON.parse(e.data);
    orders.set(order.id, order);
    render();
    onOrderUpdate(order);
  });
  events.addEventListener('removed', (e) => {
    const { id } = JSON.parse(e.data);
    orders.delete(id);
    render();
    if (qr.id === id) $('#qr-dialog').close();
  });
  events.onerror = () => {
    setLive(false);
    if (events.readyState === EventSource.CLOSED) reconnectLater();
  };
}

async function init() {
  try {
    me = await api('GET', '/api/me');
  } catch (err) {
    if (err.status === 401) location.href = '/';
    else toast(err.message, { error: true });
    return;
  }
  applyTheme(me.restaurant.theme);
  renderBrand($('#brand'), me.restaurant);
  document.title = `${me.restaurant.name} · Buzz Eat`;
  $('#sub-banner').hidden = me.subscription.active;
  $('#sub-price').textContent = formatPrice(me.subscription.listPriceCents);
  $('#validate').disabled = !me.subscription.active;
  render();
  connect();
  registerServiceWorker();
  setInterval(refreshTimes, 30000);
}

init();
