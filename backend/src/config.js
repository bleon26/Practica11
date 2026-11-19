'use strict';

const path = require('node:path');
const crypto = require('node:crypto');

// Carga backend/.env si existe (Node >= 20.12). El archivo NO se versiona.
try {
  process.loadEnvFile(path.join(__dirname, '..', '.env'));
} catch {
  /* sin .env: se usan variables de entorno / valores por defecto */
}

function loadConfig(overrides = {}) {
  let jwtSecret = overrides.jwtSecret ?? process.env.JWT_SECRET;
  if (!jwtSecret) {
    // Nunca se usa un secreto fijo en el código: si no se configura,
    // se genera uno aleatorio por arranque (los tokens caducan al reiniciar).
    jwtSecret = crypto.randomBytes(48).toString('hex');
    if (!overrides.silent) {
      console.warn('[config] JWT_SECRET no definido: se generó uno temporal para esta ejecución.');
    }
  }

  return {
    port: Number(overrides.port ?? process.env.PORT ?? 3000),
    jwtSecret,
    jwtTtlSeconds: Number(overrides.jwtTtlSeconds ?? process.env.JWT_TTL_SECONDS ?? 86400),
    adminUser: overrides.adminUser ?? process.env.ADMIN_USER ?? 'admin',
    adminPassword: overrides.adminPassword ?? process.env.ADMIN_PASSWORD ?? null,
    dbPath: overrides.dbPath ?? process.env.DB_PATH ?? path.join(__dirname, '..', 'data', 'cloud.db'),
    // Tolerancia de reloj: un cliente no puede fechar un cambio en el futuro
    // más allá de este margen (evita "ganar" siempre el LWW con fechas falsas).
    maxClockSkewMs: Number(overrides.maxClockSkewMs ?? 5 * 60 * 1000),
    maxBatchSize: 500,
    silent: Boolean(overrides.silent),
  };
}

module.exports = { loadConfig };
