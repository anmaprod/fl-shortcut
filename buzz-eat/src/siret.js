// SIRET : 14 chiffres dont la clé de Luhn est juste.
// Exception : les établissements de La Poste (SIREN 356 000 000) ont une somme de chiffres multiple de 5.

export function normalizeSiret(value) {
  return String(value || '').replace(/[\s.\-]/g, '');
}

function luhnOk(digits) {
  let sum = 0;
  for (let i = 0; i < digits.length; i++) {
    let d = Number(digits[digits.length - 1 - i]);
    if (i % 2 === 1) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
  }
  return sum % 10 === 0;
}

export function isValidSiret(value) {
  const s = normalizeSiret(value);
  if (!/^\d{14}$/.test(s)) return false;
  if (luhnOk(s)) return true;
  if (s.startsWith('356000000')) {
    const sum = [...s].reduce((a, c) => a + Number(c), 0);
    return sum % 5 === 0;
  }
  return false;
}

export function formatSiret(value) {
  const s = normalizeSiret(value);
  return /^\d{14}$/.test(s) ? `${s.slice(0, 3)} ${s.slice(3, 6)} ${s.slice(6, 9)} ${s.slice(9)}` : s;
}
