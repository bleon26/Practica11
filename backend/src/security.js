'use strict';

const crypto = require('node:crypto');

// ---------------------------------------------------------------------------
// Contraseñas: scrypt con sal aleatoria por usuario (nunca texto plano).
// Formato almacenado: scrypt$N$r$p$salHex$hashHex
// ---------------------------------------------------------------------------
const SCRYPT = { N: 16384, r: 8, p: 1, keyLen: 64 };

function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const hash = crypto.scryptSync(password, salt, SCRYPT.keyLen, {
    N: SCRYPT.N, r: SCRYPT.r, p: SCRYPT.p,
  });
  return ['scrypt', SCRYPT.N, SCRYPT.r, SCRYPT.p, salt.toString('hex'), hash.toString('hex')].join('$');
}

function verifyPassword(password, stored) {
  const parts = String(stored).split('$');
  if (parts.length !== 6 || parts[0] !== 'scrypt') return false;
  const [, N, r, p, saltHex, hashHex] = parts;
  const expected = Buffer.from(hashHex, 'hex');
  const actual = crypto.scryptSync(password, Buffer.from(saltHex, 'hex'), expected.length, {
    N: Number(N), r: Number(r), p: Number(p),
  });
  return crypto.timingSafeEqual(expected, actual);
}

// ---------------------------------------------------------------------------
// JWT HS256 (implementación mínima con node:crypto, comparación en tiempo
// constante y validación estricta de algoritmo y expiración).
// ---------------------------------------------------------------------------
const b64url = (buf) => Buffer.from(buf).toString('base64url');

function signJwt(payload, secret, ttlSeconds) {
  const header = { alg: 'HS256', typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const body = { ...payload, iat: now, exp: now + ttlSeconds };
  const data = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(body))}`;
  const sig = crypto.createHmac('sha256', secret).update(data).digest('base64url');
  return `${data}.${sig}`;
}

function verifyJwt(token, secret) {
  if (typeof token !== 'string') return null;
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  const [h, p, s] = parts;
  let header;
  let payload;
  try {
    header = JSON.parse(Buffer.from(h, 'base64url').toString('utf8'));
    payload = JSON.parse(Buffer.from(p, 'base64url').toString('utf8'));
  } catch {
    return null;
  }
  if (header.alg !== 'HS256' || header.typ !== 'JWT') return null; // bloquea alg=none
  const expected = crypto.createHmac('sha256', secret).update(`${h}.${p}`).digest();
  const given = Buffer.from(s, 'base64url');
  if (given.length !== expected.length || !crypto.timingSafeEqual(given, expected)) return null;
  if (typeof payload.exp !== 'number' || payload.exp < Math.floor(Date.now() / 1000)) return null;
  if (typeof payload.sub !== 'string') return null;
  return payload;
}

// ---------------------------------------------------------------------------
// Limitador de intentos (anti fuerza bruta en /auth/*), en memoria.
// ---------------------------------------------------------------------------
function createRateLimiter({ windowMs = 60_000, max = 10 } = {}) {
  const hits = new Map();
  return function isLimited(key) {
    const now = Date.now();
    const entry = hits.get(key);
    if (!entry || now - entry.start > windowMs) {
      hits.set(key, { start: now, count: 1 });
      return false;
    }
    entry.count += 1;
    return entry.count > max;
  };
}

/** Compara strings en tiempo constante (credenciales de la consola admin). */
function safeEqual(a, b) {
  const ha = crypto.createHash('sha256').update(String(a)).digest();
  const hb = crypto.createHash('sha256').update(String(b)).digest();
  return crypto.timingSafeEqual(ha, hb);
}

module.exports = {
  hashPassword,
  verifyPassword,
  signJwt,
  verifyJwt,
  createRateLimiter,
  safeEqual,
};
