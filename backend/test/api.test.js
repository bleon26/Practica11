'use strict';

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');

const { loadConfig } = require('../src/config');
const { createApp } = require('../src/app');
const { compareIso } = require('../src/syncService');

let server;
let base;

before(async () => {
  const config = loadConfig({
    dbPath: ':memory:', silent: true, adminPassword: 'admin-pass-123', jwtSecret: 'test-secret',
  });
  ({ server } = createApp({ config, authRateLimit: 1000 }));
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => new Promise((r) => server.close(r)));

async function api(method, path, { token, body, headers = {} } = {}) {
  const res = await fetch(base + path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch { /* html */ }
  return { status: res.status, json, text };
}

async function register(username) {
  const r = await api('POST', '/auth/register', { body: { username, password: 'secreta123' } });
  assert.equal(r.status, 201);
  return r.json.token;
}

const iso = (msOffset = 0) => new Date(Date.now() + msOffset).toISOString();
const task = (over = {}) => ({
  id: crypto.randomUUID(), title: 'Tarea', description: '', is_done: 0, is_deleted: 0,
  updated_at: iso(-60_000), base_version: null, ...over,
});

test('compareIso compara precisión de microsegundos (Dart) contra milisegundos (JS)', () => {
  assert.equal(compareIso('2026-01-01T10:00:00.000001Z', '2026-01-01T10:00:00.000Z'), 1);
  assert.equal(compareIso('2026-01-01T10:00:00Z', '2026-01-01T10:00:00.000000Z'), 0);
  assert.equal(compareIso('2026-01-01T09:59:59.999999Z', '2026-01-01T10:00:00.000Z'), -1);
});

test('rutas /tasks requieren JWT válido (regla de seguridad por UID)', async () => {
  assert.equal((await api('GET', '/tasks')).status, 401);
  assert.equal((await api('GET', '/tasks', { token: 'a.b.c' })).status, 401);
  // alg=none debe rechazarse
  const none = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({ sub: 'x', exp: 9e9 })).toString('base64url');
  assert.equal((await api('GET', '/tasks', { token: `${none}.${payload}.` })).status, 401);
});

test('login con credenciales incorrectas responde 401 genérico', async () => {
  await register('login_user');
  const bad = await api('POST', '/auth/login', { body: { username: 'login_user', password: 'incorrecta1' } });
  assert.equal(bad.status, 401);
  const ok = await api('POST', '/auth/login', { body: { username: 'login_user', password: 'secreta123' } });
  assert.equal(ok.status, 200);
  assert.ok(ok.json.token);
});

test('PUSH idempotente: reenviar el mismo UUID no duplica', async () => {
  const token = await register('idem_user');
  const t = task({ title: 'Comprar insumos' });
  const r1 = await api('POST', '/tasks/sync', { token, body: { tasks: [t] } });
  assert.equal(r1.json.results[0].status, 'applied');
  assert.equal(r1.json.results[0].task.version, 1);

  const r2 = await api('POST', '/tasks/sync', { token, body: { tasks: [t] } });
  assert.equal(r2.json.results[0].status, 'duplicate');
  assert.equal(r2.json.results[0].task.version, 1);

  const list = await api('GET', '/tasks', { token });
  assert.equal(list.json.tasks.length, 1);
});

test('LWW: gana el updated_at más reciente; el cambio viejo es rechazado', async () => {
  const token = await register('lww_user');
  const t = task({ updated_at: iso(-50_000) });
  await api('POST', '/tasks/sync', { token, body: { tasks: [t] } });

  const newer = { ...t, title: 'Versión nueva', updated_at: iso(-10_000), base_version: 1 };
  const r1 = await api('POST', '/tasks/sync', { token, body: { tasks: [newer] } });
  assert.equal(r1.json.results[0].status, 'applied');
  assert.equal(r1.json.results[0].task.version, 2);

  // Otro dispositivo que editó offline ANTES (updated_at más antiguo) y base_version 1
  const stale = { ...t, title: 'Versión vieja', updated_at: iso(-30_000), base_version: 1 };
  const r2 = await api('POST', '/tasks/sync', { token, body: { tasks: [stale] } });
  assert.equal(r2.json.results[0].status, 'rejected');
  assert.equal(r2.json.results[0].conflict, true);
  assert.equal(r2.json.results[0].task.title, 'Versión nueva');
});

test('Control de versiones: edición concurrente detectada aunque gane el cliente', async () => {
  const token = await register('ver_user');
  const t = task({ updated_at: iso(-50_000) });
  await api('POST', '/tasks/sync', { token, body: { tasks: [t] } });
  await api('POST', '/tasks/sync', { token, body: { tasks: [{ ...t, title: 'A', updated_at: iso(-40_000), base_version: 1 }] } });
  // Dispositivo B partía de la versión 1 (no vio la 2) pero su cambio es más reciente
  const r = await api('POST', '/tasks/sync', { token, body: { tasks: [{ ...t, title: 'B', updated_at: iso(-20_000), base_version: 1 }] } });
  assert.equal(r.json.results[0].status, 'applied');
  assert.equal(r.json.results[0].conflict, true);
  assert.equal(r.json.results[0].task.version, 3);
});

test('Aislamiento: un usuario no puede leer ni sobrescribir tareas de otro', async () => {
  const alice = await register('alice');
  const bob = await register('bob');
  const t = task({ title: 'Privada de Alice' });
  await api('POST', '/tasks/sync', { token: alice, body: { tasks: [t] } });

  assert.equal((await api('GET', `/tasks/${t.id}`, { token: bob })).status, 404);
  const hijack = await api('POST', '/tasks/sync', {
    token: bob, body: { tasks: [{ ...t, title: 'Hackeada', updated_at: iso(-1000) }] },
  });
  assert.equal(hijack.json.results[0].status, 'forbidden');
  const pull = await api('GET', '/tasks/changes?since=0', { token: bob });
  assert.equal(pull.json.tasks.length, 0);
  const own = await api('GET', `/tasks/${t.id}`, { token: alice });
  assert.equal(own.json.task.title, 'Privada de Alice');
});

test('PULL incremental por cursor y propagación de borrado lógico', async () => {
  const token = await register('pull_user');
  const a = task({ title: 'A' });
  const b = task({ title: 'B' });
  await api('POST', '/tasks/sync', { token, body: { tasks: [a, b] } });

  const p1 = await api('GET', '/tasks/changes?since=0', { token });
  assert.equal(p1.json.tasks.length, 2);
  const cursor = p1.json.cursor;

  const p2 = await api('GET', `/tasks/changes?since=${cursor}`, { token });
  assert.equal(p2.json.tasks.length, 0);

  const del = await api('DELETE', `/tasks/${a.id}`, { token });
  assert.equal(del.status, 200);
  const p3 = await api('GET', `/tasks/changes?since=${cursor}`, { token });
  assert.equal(p3.json.tasks.length, 1);
  assert.equal(p3.json.tasks[0].is_deleted, 1);
  assert.equal((await api('GET', '/tasks', { token })).json.tasks.length, 1);
});

test('Validación: rechaza id no UUID, fechas sin zona y fechas futuras', async () => {
  const token = await register('val_user');
  const bad = [
    task({ id: '123' }),
    task({ updated_at: '2026-01-01 10:00:00' }),
    task({ updated_at: iso(60 * 60 * 1000) }),
    task({ title: '' }),
  ];
  for (const t of bad) {
    const r = await api('POST', '/tasks/sync', { token, body: { tasks: [t] } });
    assert.equal(r.status, 400, JSON.stringify(t));
  }
});

test('Consola nube protegida con Basic Auth', async () => {
  assert.equal((await api('GET', '/console')).status, 401);
  const auth = 'Basic ' + Buffer.from('admin:admin-pass-123').toString('base64');
  const ok = await api('GET', '/console/data', { headers: { Authorization: auth } });
  assert.equal(ok.status, 200);
  assert.ok(Array.isArray(ok.json.tasks));
  const wrong = 'Basic ' + Buffer.from('admin:otra').toString('base64');
  assert.equal((await api('GET', '/console', { headers: { Authorization: wrong } })).status, 401);
});
