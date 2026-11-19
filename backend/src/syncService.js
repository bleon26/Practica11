'use strict';

const { nextRev, transaction } = require('./db');

/**
 * Normaliza un ISO-8601 UTC a precisión de microsegundos para poder
 * compararlo como string (Dart envía 6 decimales, JS 3).
 *   2026-01-01T10:00:00Z        -> 2026-01-01T10:00:00.000000Z
 *   2026-01-01T10:00:00.5Z      -> 2026-01-01T10:00:00.500000Z
 */
function normalizeIso(iso) {
  const m = /^(.*T\d{2}:\d{2}:\d{2})(?:\.(\d{1,6}))?Z$/.exec(iso);
  if (!m) return iso;
  return `${m[1]}.${(m[2] ?? '').padEnd(6, '0')}Z`;
}

/** <0 si a es anterior a b, 0 si iguales, >0 si a es posterior. */
function compareIso(a, b) {
  const na = normalizeIso(a);
  const nb = normalizeIso(b);
  return na < nb ? -1 : na > nb ? 1 : 0;
}

function toApi(row) {
  if (!row) return null;
  return {
    id: row.id,
    title: row.title,
    description: row.description,
    is_done: row.is_done,
    is_deleted: row.is_deleted,
    updated_at: row.updated_at,
    version: row.version,
    rev: row.rev,
    server_updated_at: row.server_updated_at,
  };
}

function createSyncService(db) {
  const stmts = {
    getById: db.prepare('SELECT * FROM tasks WHERE id = ?'),
    insert: db.prepare(`
      INSERT INTO tasks (id, user_id, title, description, is_done, is_deleted,
                         updated_at, version, rev, server_updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?)`),
    update: db.prepare(`
      UPDATE tasks
         SET title = ?, description = ?, is_done = ?, is_deleted = ?,
             updated_at = ?, version = version + 1, rev = ?, server_updated_at = ?
       WHERE id = ? AND user_id = ?`),
    changesSince: db.prepare(`
      SELECT * FROM tasks WHERE user_id = ? AND rev > ? ORDER BY rev ASC LIMIT ?`),
    listActive: db.prepare(`
      SELECT * FROM tasks WHERE user_id = ? AND is_deleted = 0 ORDER BY updated_at DESC`),
    logConflict: db.prepare(`
      INSERT INTO conflicts (task_id, user_id, strategy, winner, client_updated_at,
                             server_updated_at, client_base_version, server_version, detected_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`),
  };

  /**
   * Aplica UN cambio del cliente con:
   *  - Idempotencia: el id es un UUID generado en el cliente; reenviar el mismo
   *    cambio (mismo updated_at) no duplica ni re-versiona.
   *  - Last-Write-Wins por updated_at (UTC).
   *  - Control de versiones: si base_version < version del servidor, otro
   *    dispositivo editó el registro en paralelo -> se registra el conflicto.
   *
   * Devuelve { id, status, conflict, task } con status:
   *   applied    -> el servidor aceptó el cambio
   *   duplicate  -> ya estaba aplicado (reintento idempotente)
   *   rejected   -> el servidor tiene una versión más reciente (gana servidor)
   *   forbidden  -> el UUID pertenece a otro usuario
   */
  function applyChange(userId, change) {
    return transaction(db, () => {
      const now = new Date().toISOString();
      const existing = stmts.getById.get(change.id);

      if (!existing) {
        const rev = nextRev(db);
        stmts.insert.run(change.id, userId, change.title, change.description,
          change.is_done, change.is_deleted, change.updated_at, rev, now);
        return { id: change.id, status: 'applied', conflict: false, task: toApi(stmts.getById.get(change.id)) };
      }

      if (existing.user_id !== userId) {
        return { id: change.id, status: 'forbidden', conflict: false, task: null };
      }

      const cmp = compareIso(change.updated_at, existing.updated_at);
      const concurrent = change.base_version !== null && change.base_version < existing.version;

      if (cmp === 0) {
        return { id: change.id, status: 'duplicate', conflict: false, task: toApi(existing) };
      }

      if (cmp > 0) {
        const rev = nextRev(db);
        stmts.update.run(change.title, change.description, change.is_done, change.is_deleted,
          change.updated_at, rev, now, change.id, userId);
        if (concurrent) {
          stmts.logConflict.run(change.id, userId, 'LWW+version', 'client', change.updated_at,
            existing.updated_at, change.base_version, existing.version, now);
        }
        return { id: change.id, status: 'applied', conflict: concurrent, task: toApi(stmts.getById.get(change.id)) };
      }

      // El cambio del cliente es más antiguo que lo que ya tiene la nube.
      stmts.logConflict.run(change.id, userId, 'LWW+version', 'server', change.updated_at,
        existing.updated_at, change.base_version, existing.version, now);
      return { id: change.id, status: 'rejected', conflict: true, task: toApi(existing) };
    });
  }

  function applyBatch(userId, changes) {
    return changes.map((c) => applyChange(userId, c));
  }

  /** PULL incremental por cursor de revisión del servidor. */
  function changesSince(userId, sinceRev, limit = 500) {
    const rows = stmts.changesSince.all(userId, sinceRev, limit + 1);
    const hasMore = rows.length > limit;
    const page = rows.slice(0, limit);
    const cursor = page.length ? page[page.length - 1].rev : sinceRev;
    return { tasks: page.map(toApi), cursor, has_more: hasMore };
  }

  function getTask(userId, id) {
    const row = stmts.getById.get(id);
    if (!row || row.user_id !== userId) return null;
    return toApi(row);
  }

  function listActive(userId) {
    return stmts.listActive.all(userId).map(toApi);
  }

  return { applyChange, applyBatch, changesSince, getTask, listActive };
}

module.exports = { createSyncService, compareIso, normalizeIso };
