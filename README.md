# Práctica Guiada Semana 11 · Arquitectura Offline-First en Flutter

**Desarrollo Móvil Integral · Ingeniería en Desarrollo de Software 10° · UTXJ · Cierre de la Unidad II**

App de tareas que funciona **sin conexión** y sincroniza con la nube en ambos sentidos. Usa SQLite como **fuente única de verdad**, WorkManager para el trabajo en segundo plano, y resuelve colisiones con **Last-Write-Wins + control de versiones**.

> **Pregunta detonante:** *¿Cómo resolvemos colisiones de datos cuando la app se utiliza sin conexión y luego se reconecta?*
> → Cada registro lleva un UUID generado en el cliente, `updated_at` en UTC, `is_synced` y `version`. Al reconectar se ejecuta **PUSH → ACK → PULL → MERGE**: gana la escritura más reciente, las ediciones concurrentes se detectan por versión y quedan registradas, y todo reintento es idempotente. Detalle completo en [docs/01-arquitectura.md](docs/01-arquitectura.md).

```
UI Flutter  ⇄  SQLite local (fuente única de verdad)  ⇄  Backend cloud (segundo plano)
 Streams        is_synced · updated_at · is_deleted         JWT · UID · LWW · versiones
```

## Estructura del repositorio

```
.
├── app/        App Flutter (sqflite, connectivity_plus, workmanager, uuid, secure storage)
├── backend/    API cloud en Node.js sin dependencias (auth, CRUD, sync, consola nube)
└── docs/       Documentación técnica y plan de pruebas
```

## Inicio rápido

```powershell
# 1) Backend
cd backend
copy .env.example .env        # define JWT_SECRET y ADMIN_PASSWORD
npm start                     # http://localhost:3000  ·  consola: /console
npm test                      # 10 pruebas de API

# 2) App (requiere Flutter 3.38+)
cd ..\app
powershell -ExecutionPolicy Bypass -File tool\setup.ps1
flutter run --dart-define=API_URL=http://10.0.2.2:3000
```

Guía completa (dispositivo físico, APK, inspección de SQLite): [docs/05-guia-de-ejecucion.md](docs/05-guia-de-ejecucion.md).

## Implementación paso a paso

| Paso | Tema | Implementación |
|---|---|---|
| 1 | Dependencias | [`app/pubspec.yaml`](app/pubspec.yaml) |
| 2 | Tabla SQLite con metadatos de sync | [`app_database.dart`](app/lib/data/local/app_database.dart) |
| 3 | Escritura local inmediata | [`task_local_datasource.dart`](app/lib/data/local/task_local_datasource.dart) `saveLocal()` |
| 4 | Escucha reactiva de red | [`connectivity_service.dart`](app/lib/sync/connectivity_service.dart) |
| 5 | Tareas en segundo plano | [`background_sync.dart`](app/lib/sync/background_sync.dart) |
| 6 | Ciclo PUSH & PULL bidireccional | [`sync_repository.dart`](app/lib/sync/sync_repository.dart) · [`syncService.js`](backend/src/syncService.js) |
| — | Colisiones (LWW + versiones) | [`conflict_resolver.dart`](app/lib/sync/conflict_resolver.dart) |
| — | Codificación segura | [`token_storage.dart`](app/lib/data/secure/token_storage.dart) · [`app.js`](backend/src/app.js) |

## Documentación

1. [Arquitectura Offline-First y stack](docs/01-arquitectura.md)
2. [Modelo de datos y contrato de la API](docs/02-modelo-de-datos.md)
3. [Sincronización bidireccional y colisiones](docs/03-sincronizacion-y-colisiones.md)
4. [Codificación segura: cifrado y reglas del backend](docs/04-seguridad.md)
5. [Guía de ejecución](docs/05-guia-de-ejecucion.md)
6. [Pruebas de reconexión y evaluación](docs/06-pruebas-de-reconexion.md)
7. [Lista de cotejo: Hacer · Saber · Ser](docs/07-lista-de-cotejo.md)

## Estado de verificación

| Componente | Estado |
|---|---|
| Backend: 10 pruebas automáticas + prueba manual con HTTP real | ✅ Pasan (Node 24.20) |
| App Flutter: `flutter analyze` / `flutter test` | ✅ 0 errores · 24/24 pruebas (Flutter 3.50.0) |
| APK instalado en dispositivo físico (moto g54 5G) | ✅ |
| Escenarios en emulador o dispositivo (modo avión, cierre forzado, reconexión) | ⏳ Pendiente, con capturas en [`docs/evidencias/`](docs/evidencias) |

## Licencia

Uso académico.
