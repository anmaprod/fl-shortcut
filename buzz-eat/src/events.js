// Connexions Server-Sent Events, rangées par canal :
// « restaurant:<id> » pour les écrans du bar, « order:<id> » pour le téléphone du client.
export class EventHub {
  constructor() {
    this.channels = new Map();
  }

  open(channel, req, res, { onClose } = {}) {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no'
    });
    res.write('retry: 3000\n\n');
    let set = this.channels.get(channel);
    if (!set) this.channels.set(channel, (set = new Set()));
    set.add(res);
    const close = () => {
      if (!set.delete(res)) return;
      if (!set.size && this.channels.get(channel) === set) this.channels.delete(channel);
      onClose?.();
    };
    req.on('close', close);
    res.on('error', close);
    return close;
  }

  send(res, event, data) {
    res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  }

  publish(channel, event, data) {
    for (const res of this.channels.get(channel) || []) this.send(res, event, data);
  }

  count(channel) {
    return this.channels.get(channel)?.size || 0;
  }

  // Ferme les connexions d'un canal (commande récupérée : plus rien à écouter).
  // L'ensemble est vidé d'abord : les fermetures voulues ici ne déclenchent pas onClose.
  end(channel) {
    const set = this.channels.get(channel);
    if (!set) return;
    this.channels.delete(channel);
    const all = [...set];
    set.clear();
    for (const res of all) res.end();
  }

  // Un commentaire toutes les 25 s garde les connexions ouvertes derrière les proxys.
  heartbeat() {
    for (const set of this.channels.values()) for (const res of set) res.write(': ping\n\n');
  }

  closeAll() {
    for (const channel of [...this.channels.keys()]) this.end(channel);
  }
}
