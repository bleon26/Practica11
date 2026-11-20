# 06 · Pruebas de reconexión y evaluación

## A. Escenarios obligatorios (emulador o dispositivo)

Preparación: backend corriendo (`npm start`), consola abierta en `http://localhost:3000/console`, app instalada y con sesión iniciada **con red** (el primer login requiere servidor).

### Escenario 1 · Modo avión: crear y editar 3 registros offline

| # | Paso | Resultado esperado | ✔ |
|---|---|---|---|
| 1.1 | Activar **modo avión** (o en el emulador: *Extended controls → Cellular → Data: off* y Wi-Fi off) | Aparece el banner «Sin conexión…» y el ícono `cloud_off` en la barra | ☐ |
| 1.2 | Crear las tareas **A**, **B** y **C** | Aparecen **al instante** (sin spinner); cada una con ícono naranja `cloud_upload` (`is_synced = 0`) | ☐ |
| 1.3 | Editar A (título), marcar B como hecha, agregar descripción a C | Cambios inmediatos; el banner indica «3 cambios pendientes» | ☐ |
| 1.4 | Revisar la consola nube | **No** aparecen A, B ni C | ☐ |

📸 Evidencia: `docs/evidencias/01-modo-avion.png` (lista con íconos naranjas y banner).

### Escenario 2 · Cierre forzado: verificar persistencia en SQLite

| # | Paso | Resultado esperado | ✔ |
|---|---|---|---|
| 2.1 | Sin desactivar el modo avión, cerrar la app desde recientes o con *Ajustes → Apps → Forzar detención* | — | ☐ |
| 2.2 | Abrir la app de nuevo | A, B y C siguen ahí con sus ediciones y aún pendientes | ☐ |
| 2.3 | (Opcional) Ver la BD: `sqlite3 local.db "SELECT title,is_synced FROM tasks"` | 3 filas con `is_synced = 0` | ☐ |

📸 Evidencia: `docs/evidencias/02-cierre-forzado.png`.

### Escenario 3 · Reconexión: validar la subida automática en la consola nube

| # | Paso | Resultado esperado | ✔ |
|---|---|---|---|
| 3.1 | Desactivar el modo avión **sin tocar nada en la app** | El banner desaparece; `connectivity_plus` dispara el sync | ☐ |
| 3.2 | Observar la app | Los íconos pasan a verde `cloud_done` (`is_synced = 1`, `v1`/`v2`) | ☐ |
| 3.3 | Observar la consola nube | A, B y C aparecen resaltadas, con `version` y la hora de recepción | ☐ |
| 3.4 | **Variante en segundo plano:** repetir 1.1–1.2, **cerrar la app**, quitar el modo avión y esperar | WorkManager (`NetworkType.connected`) sube los cambios con la app cerrada; aparecen en la consola | ☐ |

📸 Evidencia: `docs/evidencias/03-reconexion-app.png` y `docs/evidencias/03-reconexion-consola.png`.

### Escenario extra · Colisión entre dos dispositivos

| # | Paso | Resultado esperado | ✔ |
|---|---|---|---|
| 4.1 | Iniciar sesión con el **mismo usuario** en dos emuladores (o emulador + `curl`) | Ambos muestran la misma tarea | ☐ |
| 4.2 | Dispositivo 1 en modo avión edita la tarea → «Versión offline» | Pendiente en el dispositivo 1 | ☐ |
| 4.3 | Dispositivo 2 (online) edita la misma tarea → «Versión online» | Sube de inmediato (versión + 1) | ☐ |
| 4.4 | Dispositivo 1 reconecta | El servidor responde `rejected`; el dispositivo 1 adopta «Versión online» (LWW) | ☐ |
| 4.5 | Consola nube → «Colisiones detectadas» | Fila con **gana servidor** y `base_version 1 → 2` | ☐ |

📸 Evidencia: `docs/evidencias/04-colision-consola.png`.

## B. Pruebas automáticas

### Backend (`cd backend && npm test`) — **11/11 ✔** (ejecutado el 20/11/2026)

```
✔ compareIso compara precisión de microsegundos (Dart) contra milisegundos (JS)
✔ rutas /tasks requieren JWT válido (regla de seguridad por UID)
✔ login con credenciales incorrectas responde 401 genérico
✔ PUSH idempotente: reenviar el mismo UUID no duplica
✔ LWW: gana el updated_at más reciente; el cambio viejo es rechazado
✔ Control de versiones: edición concurrente detectada aunque gane el cliente
✔ Aislamiento: un usuario no puede leer ni sobrescribir tareas de otro
✔ PULL incremental por cursor y propagación de borrado lógico
✔ Validación: rechaza id no UUID, fechas sin zona y fechas futuras
✔ Consola nube: login por formulario con cookie firmada HttpOnly
✔ Consola nube protegida con Basic Auth
ℹ tests 11 · pass 11 · fail 0
```

### App (`cd app && flutter test`)

Usan **SQLite real** (vía `sqflite_common_ffi`) y un backend en memoria con la misma semántica que el servidor, así que los escenarios corren sin emulador:

| Archivo | Cubre |
|---|---|
| `offline_sync_scenarios_test.dart` | Paso 3 (Stream inmediato), **Escenario 1** modo avión, **Escenario 2** cierre forzado (reabre el mismo `.db`), **Escenario 3** reconexión, ACK condicional, idempotencia, PULL de otro dispositivo, las dos ramas de LWW, soft delete y limpieza de sesión |
| `conflict_resolver_test.dart` | Tabla de decisión LWW completa, incluida la precisión de microsegundos |
| `task_model_test.dart` | UUID v4 offline, marca monótona, `toMap`/`fromMap`, JSON remoto |
| `widget_test.dart` | Indicador visual offline |

Resultado — **24/24 ✔** (19/11/2026 con Flutter 3.50.0; repetido el 20/11/2026 con Flutter 3.47.2):

```
00:01 +24: All tests passed!
```

`flutter analyze`: 0 errores y 0 advertencias. Solo quedan avisos *info* de que `package:flutter/material.dart` está deprecado desde Flutter 3.47 en favor de `material_ui`.

App compilada (`flutter build apk --debug`) e instalada en un **Motorola moto g54 5G** por USB con `adb reverse tcp:3000 tcp:3000` (19/11 y 20/11/2026).

## C. Registro de resultados

| Escenario | Fecha | Dispositivo / emulador | Resultado | Evidencia |
|---|---|---|---|---|
| Registro, alta de tarea y PUSH | 20/11/2026 | moto g54 5G | ✔ | Sección D |
| Servidor caído: datos conservados | 20/11/2026 | moto g54 5G | ✔ | `app-05-servidor-caido.jpg` |
| 1 · Modo avión | | | | |
| 2 · Cierre forzado | | | | |
| 3 · Reconexión (app abierta) | | | | |
| 3 · Reconexión (app cerrada / WorkManager) | | | | |
| Extra · Colisión | | | | |

## D. Evidencias en dispositivo físico (20/11/2026)

Motorola moto g54 5G · APK *debug* · backend local en `http://localhost:3000` vía `adb reverse` · usuario de prueba `Brandon2610`.

| Captura | Qué demuestra |
|---|---|
| ![Registro](evidencias/app-01-registro.jpg) | **Registro / login.** Pantalla de alta de cuenta contra el backend; el campo «Servidor» permite cambiar la URL sin recompilar. |
| ![Lista vacía](evidencias/app-02-lista-vacia.jpg) | **Sesión iniciada.** Primer PULL (`GET /tasks/changes?since=0`) sin tareas; el ícono de la barra indica que todo está sincronizado. |
| ![Nueva tarea](evidencias/app-03-nueva-tarea.jpg) | **Paso 3 · Escritura local.** El diálogo guarda en SQLite y la UI se actualiza por Stream, sin esperar al servidor. |
| ![Tarea sincronizada](evidencias/app-04-tarea-sincronizada.jpg) | **Paso 6 · PUSH → ACK.** La tarea «prueba» pasó de `v0` naranja (`is_synced = 0`) a `v1` verde (`is_synced = 1`). |
| ![Servidor caído](evidencias/app-05-servidor-caido.jpg) | **Tolerancia a fallos.** Con el backend apagado el sync falla (`Connection refused`), la app lo informa y **los datos siguen en el dispositivo**. |

**Lado servidor:** la consola nube muestra la misma tarea recibida (`version 1`, UUID generado en el cliente, hora de recepción) y la tabla de colisiones vacía.

![Consola nube](evidencias/nube-01-consola.png)

Bitácora del servidor durante la prueba:

```
[auth] registro Brandon2610
POST /auth/register -> 201
GET /tasks/changes?since=0 -> 200
[sync] push Brandon2610: {"applied":1}
POST /tasks/sync -> 200
```

### Defecto encontrado y corregido durante la prueba

| | |
|---|---|
| **Síntoma** | Tras crear una tarea con la app abierta aparecía `DatabaseException(database_closed)` y la tarea se quedaba en `v0` (pendiente). |
| **Causa** | En Android, `sqflite` comparte por defecto **una sola conexión nativa por archivo** en todo el proceso. La tarea de WorkManager corría en el mismo proceso, abría `offline_first.db` y al terminar llamaba a `db.close()`, cerrando también la conexión de la UI. |
| **Corrección** | El isolate de segundo plano abre una conexión propia: `AppDatabase(singleInstance: false)` ([`background_sync.dart`](../app/lib/sync/background_sync.dart), [`app_database.dart`](../app/lib/data/local/app_database.dart)). |
| **Verificación** | `flutter analyze` sin observaciones, 24/24 pruebas, reinstalación en el teléfono: la tarea subió (`applied: 1`) y quedó en `v1`. |

> Pendiente: capturas de los escenarios 1–3 con **modo avión** activo y del escenario de colisión (sección A).

