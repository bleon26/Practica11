'use strict';

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const { openDatabase } = require('./db');
const { createSyncService } = require('./syncService');
const {
  hashPassword, verifyPassword, signJwt, verifyJwt, createRateLimiter, safeEqual,
} = require('./security');
const { ValidationError, validateCredentials, validateTaskChange, UUID_RE } = require('./validation');

const MAX_BODY_BYTES = 1024 * 1024;
const CONSOLE_HTML = fs.readFileSync(path.join(__dirname, 'console.html'), 'utf8');

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function send(res, status, body, extraHeaders = {}) {
  const isString = typeof body === 'string';
  res.writeHead(status, {
    'Content-Type': isString ? 'text/html; charset=utf-8' : 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'Referrer-Policy': 'no-referrer',
    ...extraHeaders,
  });
  res.end(isString ? body : JSON.stringify(body));
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        reject(new HttpError(413, 'Cuerpo demasiado grande'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      if (chunks.length === 0) return resolve({});
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch {
        reject(new HttpError(400, 'JSON inválido'));
      }
    });
    req.on('error', reject);
  });
}

function createApp(options = {}) {
  const config = options.config;
  const db = options.db ?? openDatabase(config.dbPath);
  const sync = createSyncService(db);
  const authLimiter = createRateLimiter({ windowMs: 60_000, max: options.authRateLimit ?? 20 });
  const log = config.silent ? () => {} : (...a) => console.log(...a);

  const stmts = {
    userByName: db.prepare('SELECT * FROM users WHERE username = ?'),
    userById: db.prepare('SELECT id, username, created_at FROM users WHERE id = ?'),
    insertUser: db.prepare('INSERT INTO users (id, username, password_hash, created_at) VALUES (?, ?, ?, ?)'),
    consoleTasks: db.prepare(`
      SELECT t.*, u.username FROM tasks t JOIN users u ON u.id = t.user_id
      ORDER BY t.rev DESC LIMIT 300`),
    consoleConflicts: db.prepare(`
      SELECT c.*, u.username FROM conflicts c JOIN users u ON u.id = c.user_id
      ORDER BY c.id DESC LIMIT 100`),
    consoleUsers: db.prepare(`
      SELECT u.id, u.username, u.created_at,
             (SELECT COUNT(*) FROM tasks t WHERE t.user_id = u.id AND t.is_deleted = 0) AS active_tasks
      FROM users u ORDER BY u.created_at DESC`),
  };

  // ------------------------------------------------------------------ auth
  /** Regla de seguridad #1: toda ruta /tasks exige un JWT válido; el UID sale del token. */
  function requireUser(req) {
    const header = req.headers.authorization ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : null;
    const payload = verifyJwt(token, config.jwtSecret);
    if (!payload) throw new HttpError(401, 'Token ausente, inválido o expirado');
    const user = stmts.userById.get(payload.sub);
    if (!user) throw new HttpError(401, 'Usuario inexistente');
    return user;
  }

  function requireAdmin(req) {
    if (!config.adminPassword) throw new HttpError(503, 'Consola deshabilitada: define ADMIN_PASSWORD');
    const header = req.headers.authorization ?? '';
    if (!header.startsWith('Basic ')) throw new HttpError(401, 'Credenciales requeridas');
    const decoded = Buffer.from(header.slice(6), 'base64').toString('utf8');
    const idx = decoded.indexOf(':');
    const user = decoded.slice(0, idx);
    const pass = decoded.slice(idx + 1);
    const ok = safeEqual(user, config.adminUser) & safeEqual(pass, config.adminPassword);
    if (!ok) throw new HttpError(401, 'Credenciales inválidas');
  }

  function issueToken(user) {
    return {
      token: signJwt({ sub: user.id, username: user.username }, config.jwtSecret, config.jwtTtlSeconds),
      expires_in: config.jwtTtlSeconds,
      user: { id: user.id, username: user.username },
    };
  }

  // --------------------------------------------------------------- handlers
  async function handle(req, res) {
    const url = new URL(req.url, 'http://localhost');
    const { pathname } = url;
    const method = req.method;
    const ip = req.socket.remoteAddress ?? 'unknown';

    if (method === 'GET' && pathname === '/health') {
      return send(res, 200, { status: 'ok', time: new Date().toISOString() });
    }

    // ---------- Autenticación
    if (method === 'POST' && (pathname === '/auth/register' || pathname === '/auth/login')) {
      if (authLimiter(ip)) throw new HttpError(429, 'Demasiados intentos, espera un minuto');
      const { username, password } = validateCredentials(await readJson(req));

      if (pathname === '/auth/register') {
        if (stmts.userByName.get(username)) throw new HttpError(409, 'El usuario ya existe');
        const id = crypto.randomUUID();
        stmts.insertUser.run(id, username, hashPassword(password), new Date().toISOString());
        log(`[auth] registro ${username}`);
        return send(res, 201, issueToken({ id, username }));
      }

      const user = stmts.userByName.get(username);
      // Mensaje genérico: no revela si el usuario existe.
      if (!user || !verifyPassword(password, user.password_hash)) {
        throw new HttpError(401, 'Usuario o contraseña incorrectos');
      }
      return send(res, 200, issueToken(user));
    }

    if (method === 'GET' && pathname === '/auth/me') {
      return send(res, 200, { user: requireUser(req) });
    }

    // ---------- Tareas (todas filtradas por el UID autenticado)
    if (pathname === '/tasks' || pathname.startsWith('/tasks/')) {
      const user = requireUser(req);

      // PULL incremental
      if (method === 'GET' && pathname === '/tasks/changes') {
        const since = Number.parseInt(url.searchParams.get('since') ?? '0', 10);
        if (!Number.isInteger(since) || since < 0) throw new HttpError(400, 'since inválido');
        const limit = Math.min(Number.parseInt(url.searchParams.get('limit') ?? '500', 10) || 500, 500);
        return send(res, 200, sync.changesSince(user.id, since, limit));
      }

      // PUSH por lotes (idempotente)
      if (method === 'POST' && pathname === '/tasks/sync') {
        const body = await readJson(req);
        if (!Array.isArray(body.tasks)) throw new HttpError(400, 'Se esperaba { tasks: [...] }');
        if (body.tasks.length > config.maxBatchSize) throw new HttpError(413, `Máximo ${config.maxBatchSize} por lote`);
        const changes = body.tasks.map((t) => validateTaskChange(t, config));
        const results = sync.applyBatch(user.id, changes);
        const summary = results.reduce((acc, r) => ({ ...acc, [r.status]: (acc[r.status] ?? 0) + 1 }), {});
        log(`[sync] push ${user.username}: ${JSON.stringify(summary)}`);
        return send(res, 200, { results });
      }

      // CRUD REST clásico
      if (method === 'GET' && pathname === '/tasks') {
        return send(res, 200, { tasks: sync.listActive(user.id) });
      }

      if (method === 'POST' && pathname === '/tasks') {
        const change = validateTaskChange(await readJson(req), config);
        const result = sync.applyChange(user.id, change);
        return sendResult(res, result, 201);
      }

      const match = /^\/tasks\/([^/]+)$/.exec(pathname);
      if (match) {
        const id = match[1].toLowerCase();
        if (!UUID_RE.test(id)) throw new HttpError(400, 'id debe ser UUID');

        if (method === 'GET') {
          const task = sync.getTask(user.id, id);
          if (!task) throw new HttpError(404, 'No encontrada');
          return send(res, 200, { task });
        }

        if (method === 'PUT') {
          const change = validateTaskChange({ ...(await readJson(req)), id }, config);
          return sendResult(res, sync.applyChange(user.id, change), 200);
        }

        if (method === 'DELETE') {
          const current = sync.getTask(user.id, id);
          if (!current) throw new HttpError(404, 'No encontrada');
          // Borrado lógico: se propaga a los demás dispositivos vía PULL.
          const change = validateTaskChange({
            ...current,
            is_deleted: 1,
            updated_at: new Date().toISOString(),
            base_version: current.version,
          }, config);
          return sendResult(res, sync.applyChange(user.id, change), 200);
        }
      }
      throw new HttpError(404, 'Ruta no encontrada');
    }

    // ---------- Consola nube (administración / evidencia)
    if (method === 'GET' && pathname === '/console') {
      requireAdmin(req);
      return send(res, 200, CONSOLE_HTML, {
        'Content-Security-Policy': "default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'",
      });
    }
    if (method === 'GET' && pathname === '/console/data') {
      requireAdmin(req);
      return send(res, 200, {
        users: stmts.consoleUsers.all(),
        tasks: stmts.consoleTasks.all(),
        conflicts: stmts.consoleConflicts.all(),
        generated_at: new Date().toISOString(),
      });
    }

    throw new HttpError(404, 'Ruta no encontrada');
  }

  function sendResult(res, result, okStatus) {
    if (result.status === 'forbidden') throw new HttpError(403, 'El registro pertenece a otro usuario');
    if (result.status === 'rejected') return send(res, 409, result);
    return send(res, result.status === 'applied' ? okStatus : 200, result);
  }

  const server = http.createServer((req, res) => {
    const started = Date.now();
    handle(req, res)
      .catch((err) => {
        if (err instanceof HttpError || err instanceof ValidationError) {
          const headers = err.status === 401 && req.url.startsWith('/console')
            ? { 'WWW-Authenticate': 'Basic realm="consola-nube", charset="UTF-8"' }
            : {};
          return send(res, err.status, { error: err.message }, headers);
        }
        console.error('[error]', err);
        return send(res, 500, { error: 'Error interno' }); // sin filtrar detalles
      })
      .finally(() => {
        if (!req.url.startsWith('/console/data')) {
          log(`${req.method} ${req.url} -> ${res.statusCode} (${Date.now() - started} ms)`);
        }
      });
  });

  return { server, db };
}

module.exports = { createApp };
