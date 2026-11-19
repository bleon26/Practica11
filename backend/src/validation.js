'use strict';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ISO_UTC_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$/;
const USERNAME_RE = /^[a-zA-Z0-9_.-]{3,32}$/;

class ValidationError extends Error {
  constructor(message) {
    super(message);
    this.status = 400;
  }
}

function validateCredentials(body) {
  if (!body || typeof body !== 'object') throw new ValidationError('Cuerpo JSON requerido');
  const { username, password } = body;
  if (typeof username !== 'string' || !USERNAME_RE.test(username)) {
    throw new ValidationError('username: 3-32 caracteres [a-zA-Z0-9_.-]');
  }
  if (typeof password !== 'string' || password.length < 8 || password.length > 128) {
    throw new ValidationError('password: entre 8 y 128 caracteres');
  }
  return { username, password };
}

/**
 * Valida y normaliza un cambio de tarea enviado por el cliente.
 * Nunca se confía en user_id/version/rev enviados: los asigna el servidor.
 */
function validateTaskChange(raw, { maxClockSkewMs }) {
  if (!raw || typeof raw !== 'object') throw new ValidationError('Tarea inválida');
  const { id, title, description = '', is_done = 0, is_deleted = 0, updated_at, base_version = null } = raw;

  if (typeof id !== 'string' || !UUID_RE.test(id)) throw new ValidationError('id debe ser UUID');
  if (typeof title !== 'string' || title.trim().length === 0 || title.length > 200) {
    throw new ValidationError(`title inválido (1-200) en ${id}`);
  }
  if (typeof description !== 'string' || description.length > 2000) {
    throw new ValidationError(`description inválida (<=2000) en ${id}`);
  }
  if (typeof updated_at !== 'string' || !ISO_UTC_RE.test(updated_at) || Number.isNaN(Date.parse(updated_at))) {
    throw new ValidationError(`updated_at debe ser ISO-8601 UTC (…Z) en ${id}`);
  }
  if (Date.parse(updated_at) - Date.now() > maxClockSkewMs) {
    throw new ValidationError(`updated_at está en el futuro (reloj del dispositivo desfasado) en ${id}`);
  }
  const toFlag = (v) => (v === true || v === 1 ? 1 : 0);
  if (base_version !== null && (!Number.isInteger(base_version) || base_version < 0)) {
    throw new ValidationError(`base_version inválida en ${id}`);
  }

  return {
    id: id.toLowerCase(),
    title: title.trim(),
    description,
    is_done: toFlag(is_done),
    is_deleted: toFlag(is_deleted),
    updated_at,
    base_version,
  };
}

module.exports = { ValidationError, validateCredentials, validateTaskChange, UUID_RE };
