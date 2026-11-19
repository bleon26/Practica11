'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');

/**
 * Base de datos "nube" del servidor (SQLite embebido de Node).
 *
 * - tasks.rev: contador global monótono asignado por el servidor en cada
 *   escritura. El cliente lo usa como cursor de PULL (since=rev), así el
 *   pull incremental NO depende del reloj del dispositivo.
 * - tasks.version: contador incremental por registro (control de versiones).
 * - tasks.updated_at: marca ISO-8601 UTC del cliente (Last-Write-Wins).
 */
function openDatabase(dbPath) {
  if (dbPath !== ':memory:') {
    fs.mkdirSync(path.dirname(path.resolve(dbPath)), { recursive: true });
  }
  const db = new DatabaseSync(dbPath);
  db.exec(`
    PRAGMA journal_mode = WAL;
    PRAGMA foreign_keys = ON;

    CREATE TABLE IF NOT EXISTS users (
      id            TEXT PRIMARY KEY,
      username      TEXT NOT NULL UNIQUE COLLATE NOCASE,
      password_hash TEXT NOT NULL,
      created_at    TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS tasks (
      id                TEXT PRIMARY KEY,
      user_id           TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      title             TEXT NOT NULL,
      description       TEXT NOT NULL DEFAULT '',
      is_done           INTEGER NOT NULL DEFAULT 0,
      is_deleted        INTEGER NOT NULL DEFAULT 0,
      updated_at        TEXT NOT NULL,
      version           INTEGER NOT NULL DEFAULT 1,
      rev               INTEGER NOT NULL,
      server_updated_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_tasks_user_rev ON tasks(user_id, rev);

    CREATE TABLE IF NOT EXISTS conflicts (
      id                INTEGER PRIMARY KEY AUTOINCREMENT,
      task_id           TEXT NOT NULL,
      user_id           TEXT NOT NULL,
      strategy          TEXT NOT NULL,
      winner            TEXT NOT NULL,
      client_updated_at TEXT NOT NULL,
      server_updated_at TEXT NOT NULL,
      client_base_version INTEGER,
      server_version    INTEGER NOT NULL,
      detected_at       TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS meta (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );
    INSERT OR IGNORE INTO meta(key, value) VALUES ('rev', '0');
  `);
  return db;
}

/** Siguiente número de revisión global (llamar dentro de una transacción). */
function nextRev(db) {
  db.prepare(`UPDATE meta SET value = CAST(value AS INTEGER) + 1 WHERE key = 'rev'`).run();
  return Number(db.prepare(`SELECT value FROM meta WHERE key = 'rev'`).get().value);
}

/** Ejecuta fn dentro de BEGIN IMMEDIATE / COMMIT (rollback ante error). */
function transaction(db, fn) {
  db.exec('BEGIN IMMEDIATE');
  try {
    const result = fn();
    db.exec('COMMIT');
    return result;
  } catch (err) {
    db.exec('ROLLBACK');
    throw err;
  }
}

module.exports = { openDatabase, nextRev, transaction };
