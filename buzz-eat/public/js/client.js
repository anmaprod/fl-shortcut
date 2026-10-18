import { createAlarm } from './alarm.js';
import { $, api, applyTheme, h, registerServiceWorker, renderBrand } from './common.js';

const preview = location.pathname === '/apercu';
const token = preview ? null : location.pathname.split('/').pop();
const alarm = createAlarm();

let order = null;
let alertOn = false;
let acknowledged = false;
let finished = false;
let events = null;

function render() {
  const r = order.restaurant;
  applyTheme(r.theme);
  renderBrand($('#brand'), r);
  document.title = `Commande n° ${order.number} · ${r.name}`;
  $('#loading').hidden = true;
  $('#ticket').hidden = false;
  $('#num').textContent = `n° ${order.number}`;
  $('#customer').hidden = !order.customer;
  $('#customer').textContent = order.customer;
  $('#details').hidden = !order.details;
  $('#details').textContent = order.details;
  const ready = order.status === 'ready';
  $('#status').classList.toggle('is-ready', ready);
  $('#status-text').textContent = ready ? 'Prête : venez la retirer au bar' : 'En préparation';
  $('#alert-card').hidden = ready;
  $('#ready-num').textContent = `n° ${order.number}`;
  $('#footer').replaceChildren(h('div', { text: `${r.name} · SIRET ${r.siret}` }), h('div', { text: 'Buzz Eat' }));
}

function showReady() {
  acknowledged = false;
  const screen = $('#ready');
  screen.hidden = false;
  screen.classList.add('ringing');
  $('#stop').focus();
  alarm.start();
  notifyIfHidden();
}

function acknowledge() {
  acknowledged = true;
  alarm.stop();
  $('#ready').classList.remove('ringing');
  $('#ready').hidden = true;
}

function onState(next, { initial = false } = {}) {
  const wasReady = order?.status === 'ready';
  order = next;
  render();
  if (order.status === 'ready' && !wasReady && !initial) showReady();
}

const DONE = {
  picked_up: ['✅', 'Commande récupérée', 'Bon appétit ! Vous pouvez fermer cette page.'],
  canceled: ['ℹ️', 'Commande annulée', 'L’établissement a annulé cette commande. Rapprochez-vous du bar si besoin.'],
  expired: ['ℹ️', 'Commande terminée', 'Cette commande n’est plus suivie.'],
  gone: ['ℹ️', 'Commande terminée', 'Cette commande a déjà été récupérée ou n’existe plus.']
};

function onDone(reason) {
  finished = true;
  events?.close();
  alarm.stop();
  const [icon, title, text] = DONE[reason] || DONE.gone;
  $('#ready').hidden = true;
  $('#loading').hidden = true;
  $('#ticket').hidden = true;
  $('#alert-card').hidden = true;
  $('#done').hidden = false;
  $('#done-icon').textContent = icon;
  $('#done-title').textContent = title;
  $('#done-text').textContent = text;
  document.title = title;
}

async function notifyIfHidden() {
  if (document.visibilityState === 'visible' || !('Notification' in window) || Notification.permission !== 'granted') return;
  const reg = await navigator.serviceWorker?.getRegistration();
  reg?.showNotification(`Commande n° ${order.number} prête !`, {
    body: `Venez la retirer au bar · ${order.restaurant.name}`,
    tag: `commande-${token}`,
    renotify: true,
    requireInteraction: true,
    vibrate: [600, 200, 600, 200, 900],
    icon: order.restaurant.logoUrl || '/icons/icon-192.png',
    data: { url: location.pathname }
  });
}

// ---------- Activation de l'alerte ----------

function keyBytes(base64url) {
  const b64 = base64url.replace(/-/g, '+').replace(/_/g, '/');
  const raw = atob(b64 + '='.repeat((4 - (b64.length % 4)) % 4));
  return Uint8Array.from(raw, (c) => c.charCodeAt(0));
}

function sameKey(buffer, base64url) {
  if (!buffer) return false;
  const a = new Uint8Array(buffer);
  const b = keyBytes(base64url);
  return a.length === b.length && a.every((x, i) => x === b[i]);
}

async function subscribePush() {
  if (!('PushManager' in window)) return false;
  try {
    const reg = (await registerServiceWorker()) && (await navigator.serviceWorker.ready);
    if (!reg) return false;
    const { publicKey } = await api('GET', '/api/push/key');
    let sub = await reg.pushManager.getSubscription();
    if (sub && !sameKey(sub.options.applicationServerKey, publicKey)) {
      await sub.unsubscribe();
      sub = null;
    }
    sub ||= await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyBytes(publicKey) });
    await api('POST', `/api/c/${token}/push`, { subscription: sub.toJSON() });
    return true;
  } catch {
    return false;
  }
}

async function enableAlert() {
  // Son et autorisation demandés tout de suite, dans le geste : les navigateurs l'exigent.
  const sound = alarm.unlock();
  const permission =
    'Notification' in window && Notification.permission === 'default'
      ? Notification.requestPermission().catch(() => 'denied')
      : null;
  $('#enable').disabled = true;
  const soundOk = await sound;
  await permission;
  const notifications = 'Notification' in window && Notification.permission === 'granted';
  const screenOn = await alarm.keepScreenOn();
  alertOn = true;
  let pushOk = false;
  if (!preview) {
    api('POST', `/api/c/${token}/alert`, {}).catch(() => {});
    if (notifications) pushOk = await subscribePush();
  }
  const tips = [
    soundOk ? 'Le son est activé : montez le volume.' : 'Le son n’a pas pu démarrer : touchez « Tester le son ».',
    alarm.canVibrate
      ? 'Le téléphone vibrera aussi.'
      : 'Ce téléphone ne vibre pas depuis une page web : laissez le son allumé.',
    screenOn ? 'L’écran reste allumé tant que cette page est ouverte.' : 'Gardez cette page ouverte et l’écran allumé.',
    pushOk ? 'Une notification vous préviendra même si vous quittez cette page.' : null
  ];
  $('#tips').replaceChildren(...tips.filter(Boolean).map((t) => h('li', { text: t })));
  $('#alert-off').hidden = true;
  $('#alert-on').hidden = false;
}

// ---------- Suivi en direct ----------

async function refresh() {
  try {
    const { order: next } = await api('GET', `/api/c/${token}`);
    onState(next);
    return true;
  } catch (err) {
    if (err.status === 404) onDone('gone');
    return false;
  }
}

function connect() {
  events = new EventSource(`/api/c/${token}/events`);
  events.addEventListener('state', (e) => onState(JSON.parse(e.data).order));
  events.addEventListener('ring', () => showReady());
  events.addEventListener('done', (e) => onDone(JSON.parse(e.data).reason));
  events.onerror = () => {
    if (events.readyState !== EventSource.CLOSED || finished) return;
    setTimeout(async () => {
      if (!finished && (await refresh()) && !finished) connect();
    }, 3000);
  };
}

document.addEventListener('visibilitychange', () => {
  if (document.visibilityState !== 'visible' || finished) return;
  if (alertOn && !alarm.screenKeptOn) alarm.keepScreenOn();
  if (!preview) refresh();
});

$('#enable').addEventListener('click', enableAlert);
$('#test-sound').addEventListener('click', () => alarm.unlock());
$('#stop').addEventListener('click', acknowledge);

async function init() {
  if (preview) {
    try {
      const { order: demo } = await api('GET', '/api/apercu');
      onState(demo, { initial: true });
    } catch {
      location.href = '/';
      return;
    }
    $('#preview-bar').hidden = false;
    $('#sim-ready').addEventListener('click', () => {
      if (finished) location.reload();
      else if (order.status === 'ready') showReady();
      else onState({ ...order, status: 'ready', readyAt: Date.now() });
    });
    $('#sim-done').addEventListener('click', () => onDone('picked_up'));
    return;
  }
  registerServiceWorker();
  try {
    const { order: first } = await api('GET', `/api/c/${token}`);
    onState(first, { initial: true });
    connect();
  } catch (err) {
    if (err.status === 404) onDone('gone');
    else $('#loading').textContent = 'Connexion impossible. Vérifiez votre réseau puis rechargez la page.';
  }
  setInterval(() => {
    if (!finished && events?.readyState !== EventSource.OPEN) refresh();
  }, 15000);
}

init();
