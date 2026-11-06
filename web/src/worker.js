// Site FL Shortcuts sur Cloudflare : les fichiers de public/ et deux adresses pour le paiement SumUp.
//
//   POST /api/paiement        { montant, systeme }  crée un paiement SumUp et renvoie l'adresse de sa page
//                                                   de paiement (checkout.sumup.com), où le navigateur part payer
//   GET  /api/paiement/<id>                          renvoie l'état du paiement chez SumUp (PAID, PENDING…)
//
// Réglages du Worker (Cloudflare › Workers › fl-shortcuts › Settings › Variables and Secrets) :
//   SUMUP_API_KEY        secret : clé API SumUp (sup_sk_…), jamais dans le code ni dans le dépôt
//   SUMUP_MERCHANT_CODE  code marchand SumUp (commence par M)
// Tant que l'un des deux manque, /api/paiement répond 503 et le site propose le téléchargement gratuit.

const SUMUP = 'https://api.sumup.com/v0.1/checkouts';
export const MIN = 1;
export const MAX = 999;
const ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/api/paiement') {
      if (request.method !== 'POST') return json({ erreur: 'Méthode non autorisée.' }, 405, { Allow: 'POST' });
      return creer(request, env, url);
    }
    if (url.pathname.startsWith('/api/paiement/')) {
      if (request.method !== 'GET') return json({ erreur: 'Méthode non autorisée.' }, 405, { Allow: 'GET' });
      return etat(decodeURIComponent(url.pathname.slice('/api/paiement/'.length)), env);
    }
    if (url.pathname.startsWith('/api/')) return json({ erreur: 'Adresse inconnue.' }, 404);
    return env.ASSETS.fetch(request);
  },
};

async function creer(request, env, url) {
  // Seul le site lui-même peut lancer un paiement.
  const origine = request.headers.get('Origin');
  if (origine && origine !== url.origin) return json({ erreur: 'Origine refusée.' }, 403);
  if (!env.SUMUP_API_KEY || !env.SUMUP_MERCHANT_CODE) return json({ erreur: "Le paiement n'est pas encore ouvert." }, 503);

  let demande;
  try { demande = await request.json(); } catch { return json({ erreur: 'Demande illisible.' }, 400); }
  const montant = demande?.montant;
  if (!Number.isInteger(montant) || montant < MIN || montant > MAX) {
    return json({ erreur: `Le montant doit être un nombre entier entre ${MIN} et ${MAX} €.` }, 400);
  }
  const systeme = demande?.systeme === 'windows' ? 'Windows' : 'Mac';

  const reponse = await fetch(SUMUP, {
    method: 'POST',
    headers: { Authorization: `Bearer ${env.SUMUP_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      checkout_reference: crypto.randomUUID(),
      amount: montant,
      currency: 'EUR',
      merchant_code: env.SUMUP_MERCHANT_CODE,
      description: `FL Shortcuts pour ${systeme}, prix libre`,
      // Page de paiement de SumUp (carte, Apple Pay, Google Pay), ouverte 30 minutes.
      hosted_checkout: { enabled: true },
      // Après le paiement, le bouton de retour de SumUp ramène ici ; la page vérifie alors le paiement.
      redirect_url: `${url.origin}/?paiement=retour`,
    }),
  }).catch(() => null);

  const echec = () => json({ erreur: "Le paiement n'a pas pu démarrer. Réessaie dans un instant." }, 502);
  if (!reponse || !reponse.ok) {
    console.error('SumUp, création refusée', reponse?.status, reponse ? await reponse.text() : 'réseau');
    return echec();
  }
  const paiement = await reponse.json();
  const page = pageSumup(paiement.hosted_checkout_url);
  if (!paiement.id || !page) {
    console.error('SumUp, réponse sans page de paiement');
    return echec();
  }
  return json({ id: paiement.id, montant, url: page });
}

// Le navigateur ne part que vers une adresse https de SumUp, jamais ailleurs.
function pageSumup(adresse) {
  try {
    const u = new URL(adresse);
    const chezSumup = u.hostname === 'sumup.com' || u.hostname.endsWith('.sumup.com');
    return u.protocol === 'https:' && chezSumup ? u.href : null;
  } catch {
    return null;
  }
}

async function etat(id, env) {
  if (!ID.test(id)) return json({ erreur: 'Paiement inconnu.' }, 404);
  if (!env.SUMUP_API_KEY) return json({ erreur: "Le paiement n'est pas encore ouvert." }, 503);
  const reponse = await fetch(`${SUMUP}/${id}`, {
    headers: { Authorization: `Bearer ${env.SUMUP_API_KEY}` },
  }).catch(() => null);
  if (reponse?.status === 404) return json({ erreur: 'Paiement inconnu.' }, 404);
  if (!reponse || !reponse.ok) {
    console.error('SumUp, lecture refusée', reponse?.status);
    return json({ erreur: 'SumUp ne répond pas pour le moment.' }, 502);
  }
  const paiement = await reponse.json();
  // Seulement l'état et le montant : rien d'autre ne sort de chez SumUp.
  return json({ statut: paiement.status, montant: paiement.amount });
}

function json(donnees, statut = 200, entetes = {}) {
  return new Response(JSON.stringify(donnees), {
    status: statut,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...entetes },
  });
}
