export class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export function sendJson(res, status, data, headers = {}) {
  const body = JSON.stringify(data);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'Content-Length': Buffer.byteLength(body),
    ...headers
  });
  res.end(body);
}

export function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > limit) {
        reject(new HttpError(413, 'Données trop volumineuses.'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

export function parseCookies(header) {
  const out = {};
  for (const part of String(header || '').split(';')) {
    const i = part.indexOf('=');
    if (i > 0) out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
  }
  return out;
}

// Texte saisi : caractères de contrôle retirés (sauf les retours à la ligne si permis), espaces en bord coupés.
export function cleanText(value, max, label, { multiline = false, required = false } = {}) {
  const pattern = multiline ? /[\u0000-\u0009\u000B-\u001F\u007F]/g : /[\u0000-\u001F\u007F]/g;
  const text = String(value ?? '')
    .replace(/\r\n?/g, '\n')
    .replace(pattern, '')
    .trim();
  if (required && !text) throw new HttpError(400, `${label} : champ obligatoire.`);
  if ([...text].length > max) throw new HttpError(400, `${label} : ${max} caractères au plus.`);
  return text;
}
