# 07 · Evidencia de nivel de logro (lista de cotejo, cierre de la Unidad II)

| Dimensión | Evidencia requerida | Criterio clave | Dónde está | Estado |
|---|---|---|---|---|
| **Hacer** | App Flutter Offline-First | CRUD nube, caché SQLite y sync bidireccional | [`app/`](../app) · [`backend/`](../backend) | ✅ Código completo · ✅ probado en moto g54 · ⏳ capturas en modo avión |
| **Saber** | Documentación técnica | Modelo de datos, cifrado y reglas del backend | [`docs/`](.) | ✅ |
| **Ser** | Ética y repositorio Git | Commits continuos y protección de datos | Historial `git log` · [04-seguridad.md](04-seguridad.md) | ✅ [github.com/bleon26/Practica11](https://github.com/bleon26/Practica11) |

## Hacer — App Flutter Offline-First

- [x] **Paso 1** · Dependencias en `pubspec.yaml`: sqflite, path, connectivity_plus, workmanager, uuid (+ http y flutter_secure_storage).
- [x] **Paso 2** · Tabla SQLite con `is_synced`, `updated_at`, `is_deleted` → [`app_database.dart`](../app/lib/data/local/app_database.dart)
- [x] **Paso 3** · Escritura local inmediata `saveLocal()` con `ConflictAlgorithm.replace` e `is_synced = 0` → [`task_local_datasource.dart`](../app/lib/data/local/task_local_datasource.dart)
- [x] **Paso 4** · Escucha reactiva con `Connectivity().onConnectivityChanged` + indicador visual → [`connectivity_service.dart`](../app/lib/sync/connectivity_service.dart), [`offline_banner.dart`](../app/lib/ui/widgets/offline_banner.dart)
- [x] **Paso 5** · `Workmanager().registerOneOffTask('sync-task-id', 'bidirectionalSync', constraints: Constraints(networkType: NetworkType.connected))` → [`background_sync.dart`](../app/lib/sync/background_sync.dart)
- [x] **Paso 6** · Ciclo PUSH → ACK → PULL → MERGE → [`sync_repository.dart`](../app/lib/sync/sync_repository.dart)
- [x] **CRUD nube**: crear, leer, actualizar y borrar (lógico) → API REST en [`app.js`](../backend/src/app.js)
- [x] **Single Source of Truth**: la UI solo escucha Streams de SQLite
- [x] Estrategias contra colisiones: **LWW** + **control de versiones**
- [x] App instalada en dispositivo físico: registro, alta de tarea, PUSH y consola nube → [06 · sección D](06-pruebas-de-reconexion.md#d-evidencias-en-dispositivo-físico-20112026)
- [ ] Escenario 1 · Modo avión (captura) → [06-pruebas-de-reconexion.md](06-pruebas-de-reconexion.md#escenario-1--modo-avión-crear-y-editar-3-registros-offline)
- [ ] Escenario 2 · Cierre forzado (captura)
- [ ] Escenario 3 · Reconexión en la consola nube (captura)

## Saber — Documentación técnica

- [x] Arquitectura y respuesta a la pregunta detonante → [01-arquitectura.md](01-arquitectura.md)
- [x] **Modelo de datos** local, servidor y contrato API → [02-modelo-de-datos.md](02-modelo-de-datos.md)
- [x] Sincronización y colisiones → [03-sincronizacion-y-colisiones.md](03-sincronizacion-y-colisiones.md)
- [x] **Cifrado** y **reglas del backend** → [04-seguridad.md](04-seguridad.md)
- [x] Guía de ejecución → [05-guia-de-ejecucion.md](05-guia-de-ejecucion.md)
- [x] Plan de pruebas → [06-pruebas-de-reconexion.md](06-pruebas-de-reconexion.md)

## Ser — Ética y repositorio Git

- [x] Repositorio Git con **commits continuos** por capa (backend → datos → sync → UI → pruebas → docs)
- [x] Mensajes de commit descriptivos (Conventional Commits)
- [x] **Protección de datos**: sin secretos versionados (`.env`, keystores y `.db` en `.gitignore`), contraseñas con scrypt, token cifrado, purga de datos al cerrar sesión, `allowBackup=false`
- [x] Aislamiento por usuario verificado con pruebas automáticas
- [x] Repositorio publicado: https://github.com/bleon26/Practica11

## Blindaje de datos (diapositiva de codificación segura)

- [x] Cifrado en reposo: tokens con `flutter_secure_storage`
- [x] Idempotencia en la API: UUID generado en el cliente
- [x] Reglas de seguridad: validar el UID autenticado en el backend
- [x] Limpieza de sesión: purgar SQLite al cerrar sesión
