// Alarme du client : son fabriqué ici (pas de fichier à charger), vibration et réveil de l'écran.

function alarmWav() {
  const rate = 22050;
  const segments = [];
  for (let i = 0; i < 4; i++) segments.push([988, 0.16], [0, 0.05], [1319, 0.16], [0, 0.05]);
  segments.push([0, 0.5]);
  const total = segments.reduce((n, [, d]) => n + Math.round(d * rate), 0);
  const buf = new ArrayBuffer(44 + total * 2);
  const v = new DataView(buf);
  const ascii = (o, s) => [...s].forEach((c, i) => v.setUint8(o + i, c.charCodeAt(0)));
  ascii(0, 'RIFF');
  v.setUint32(4, 36 + total * 2, true);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  v.setUint32(16, 16, true);
  v.setUint16(20, 1, true);
  v.setUint16(22, 1, true);
  v.setUint32(24, rate, true);
  v.setUint32(28, rate * 2, true);
  v.setUint16(32, 2, true);
  v.setUint16(34, 16, true);
  ascii(36, 'data');
  v.setUint32(40, total * 2, true);
  let o = 44;
  const fade = 0.006 * rate;
  for (const [f, d] of segments) {
    const n = Math.round(d * rate);
    for (let i = 0; i < n; i++) {
      let s = 0;
      if (f) {
        const w = (2 * Math.PI * f * i) / rate;
        const env = Math.min(1, i / fade, (n - i) / fade);
        s = ((Math.sin(w) + 0.35 * Math.sin(3 * w) + 0.15 * Math.sin(5 * w)) / 1.5) * env * 0.95;
      }
      v.setInt16(o, Math.max(-1, Math.min(1, s)) * 32767, true);
      o += 2;
    }
  }
  return new Blob([buf], { type: 'audio/wav' });
}

const VIBRATION = [700, 250, 700, 250, 700];

export function createAlarm() {
  const audio = new Audio();
  audio.src = URL.createObjectURL(alarmWav());
  audio.loop = true;
  audio.preload = 'auto';
  let ringing = false;
  let vibrateTimer = null;
  let wakeLock = null;

  const canVibrate = typeof navigator.vibrate === 'function';

  async function keepScreenOn() {
    if (!('wakeLock' in navigator) || document.visibilityState !== 'visible') return false;
    try {
      wakeLock = await navigator.wakeLock.request('screen');
      return true;
    } catch {
      return false;
    }
  }

  return {
    canVibrate,
    canKeepScreenOn: 'wakeLock' in navigator,

    // À appeler dans le geste de l'utilisateur (le clic) : les navigateurs n'autorisent le son qu'après.
    unlock() {
      try {
        if (navigator.audioSession) navigator.audioSession.type = 'playback';
      } catch {}
      audio.currentTime = 0;
      const played = audio.play().then(
        () => {
          setTimeout(() => {
            if (!ringing) {
              audio.pause();
              audio.currentTime = 0;
            }
          }, 450);
          return true;
        },
        () => false
      );
      if (canVibrate) navigator.vibrate(150);
      return played;
    },

    keepScreenOn,
    get screenKeptOn() {
      return Boolean(wakeLock && !wakeLock.released);
    },

    start() {
      ringing = true;
      audio.currentTime = 0;
      audio.play().catch(() => {});
      if (canVibrate) {
        navigator.vibrate(VIBRATION);
        clearInterval(vibrateTimer);
        vibrateTimer = setInterval(() => navigator.vibrate(VIBRATION), 3000);
      }
    },

    stop() {
      ringing = false;
      audio.pause();
      audio.currentTime = 0;
      clearInterval(vibrateTimer);
      if (canVibrate) navigator.vibrate(0);
    },

    get ringing() {
      return ringing;
    }
  };
}
