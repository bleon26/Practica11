# 02 · Modelo de datos

## Base local (SQLite en el dispositivo)

Archivo: `offline_first.db` (ruta de `getDatabasesPath()`). Definido en [`app_database.dart`](../app/lib/data/local/app_database.dart).

```sql
CREATE TABLE tasks (
  id          TEXT PRIMARY KEY,           -- UUID v4 generado offline
  title       TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  is_done     INTEGER NOT NULL DEFAULT 0,
  is_synced   INTEGER DEFAULT 0,          -- 0 pendiente, 1 sincronizado
  updated_at  TEXT NOT NULL,              -- ISO-8601 UTC (LWW)
  is_deleted  INTEGER DEFAULT 0,          -- borrado lógico (soft delete)
  version     INTEGER NOT NULL DEFAULT 0  -- última versión de servidor conocida
);
CREATE INDEX idx_tasks_is_synced ON tasks(is_synced);

CREATE TABLE sync_meta (                  -- estado del motor de sync
  key   TEXT PRIMARY KEY,                 -- 'pull_cursor'
  value TEXT NOT NULL
);
```

| Campo | Propósito |
|---|---|
| `id` | UUID v4 creado **en el cliente** sin red. Es la clave de idempotencia: el servidor nunca genera otro id, así que reenviar el mismo registro no lo duplica. |
| `is_synced` | **Bandera sucia.** `saveLocal()` siempre escribe `0`; solo el ACK del servidor la pone en `1`. |
| `updated_at` | Marca ISO-8601 **UTC** con microsegundos (`2026-11-19T22:10:11.123456Z`). Es el criterio de Last-Write-Wins. `Task.edit()` garantiza que siempre avance, aunque el reloj del dispositivo esté atrasado. |
| `is_deleted` | Borrado lógico. El registro se oculta en la UI, se sube a la nube para propagarse a otros dispositivos y se purga localmente cuando la nube lo confirma. |
| `version` | Versión del servidor que vio este dispositivo (0 = nunca subido). Se envía como `base_version` para detectar ediciones concurrentes. |

Las tres columnas de la diapositiva del Paso 2 (`is_synced`, `updated_at`, `is_deleted`) se conservan con el mismo nombre y significado. Se agregaron `description`, `is_done` y `version`.

## Base del servidor (SQLite en el backend)

Definida en [`backend/src/db.js`](../backend/src/db.js).

| Tabla | Columnas clave | Notas |
|---|---|---|
| `users` | `id` (UUID), `username` (único), `password_hash` | Hash `scrypt$N$r$p$sal$hash`; nunca texto plano. |
| `tasks` | `id`, `user_id`, `title`, `description`, `is_done`, `is_deleted`, `updated_at`, `version`, `rev`, `server_updated_at` | `user_id` lo asigna el servidor a partir del JWT. `rev` es un contador global monótono, el cursor de PULL. |
| `conflicts` | `task_id`, `user_id`, `winner` (`client`/`server`), `client_updated_at`, `server_updated_at`, `client_base_version`, `server_version` | Bitácora de colisiones para auditoría y evidencia. |
| `meta` | `rev` | Último número de revisión emitido. |

**¿Por qué un `rev` del servidor y no `updated_at` para el PULL?** Los relojes de los dispositivos pueden estar desfasados. Si el PULL pidiera «cambios desde la fecha X del cliente», podría saltarse registros. `rev` lo asigna únicamente el servidor y siempre crece, así que el PULL incremental es exacto.

## Contrato de la API REST

Base: `http://<host>:3000`. Todas las rutas `/tasks*` requieren `Authorization: Bearer <JWT>`.

| Método | Ruta | Uso | Respuesta |
|---|---|---|---|
| `POST` | `/auth/register` | Alta `{username, password}` | `201 {token, expires_in, user}` |
| `POST` | `/auth/login` | Inicio de sesión | `200 {token, expires_in, user}` |
| `GET` | `/auth/me` | Usuario del token | `200 {user}` |
| `POST` | `/tasks/sync` | **PUSH** por lotes (≤ 500) `{tasks:[…]}` | `200 {results:[{id, status, conflict, task}]}` |
| `GET` | `/tasks/changes?since=<rev>` | **PULL** incremental (incluye borrados) | `200 {tasks, cursor, has_more}` |
| `GET` | `/tasks` | CRUD: listar activas | `200 {tasks}` |
| `POST` | `/tasks` | CRUD: crear (id UUID del cliente) | `201 {status, task}` |
| `GET` | `/tasks/:id` | CRUD: leer | `200 {task}` / `404` |
| `PUT` | `/tasks/:id` | CRUD: actualizar (aplica LWW) | `200` / `409` si la nube es más reciente |
| `DELETE` | `/tasks/:id` | CRUD: borrado lógico | `200 {status, task}` |
| `GET` | `/console` · `/console/data` | Consola nube (Basic Auth) | HTML / JSON |
| `GET` | `/health` | Salud del servicio | `200` |

### Cuerpo de un cambio (PUSH)

```json
{
  "id": "36e0c20e-e4ed-4278-bc8f-b326da21b8a6",
  "title": "Creada en modo avión",
  "description": "",
  "is_done": 0,
  "is_deleted": 0,
  "updated_at": "2026-11-19T10:00:00.123456Z",
  "base_version": null
}
```

### Estados por registro en la respuesta del PUSH

| `status` | Significado | Acción del cliente |
|---|---|---|
| `applied` | Insertado o actualizado (`version` + 1) | ACK → `is_synced = 1` |
| `duplicate` | Ya estaba aplicado (reintento idempotente) | ACK → `is_synced = 1` |
| `rejected` | La nube tiene un `updated_at` más reciente | MERGE: se adopta la copia de la nube |
| `forbidden` | El UUID pertenece a otro usuario | Se deja pendiente y se reporta |
