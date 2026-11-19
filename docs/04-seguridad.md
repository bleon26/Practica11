# 04 · Codificación segura: blindaje de datos locales y remotos

## Controles de la práctica

| Control (diapositiva) | Implementación | Archivo |
|---|---|---|
| **Cifrado en reposo:** proteger tokens con `flutter_secure_storage` | El JWT se guarda solo en `FlutterSecureStorage`: AES-GCM con clave del **Android Keystore** / **Keychain** de iOS. Nunca va a SQLite ni a SharedPreferences. | [`token_storage.dart`](../app/lib/data/secure/token_storage.dart) |
| **Idempotencia en API:** evitar duplicados con UUID generado en el cliente | `Task.create()` genera un UUID v4 offline. El servidor hace *upsert* por ese id y responde `duplicate` si recibe el mismo `updated_at`. | [`task.dart`](../app/lib/data/models/task.dart), [`syncService.js`](../backend/src/syncService.js) |
| **Reglas de seguridad:** validar el UID autenticado en el backend | Cada ruta `/tasks*` exige un JWT válido; el `user_id` sale **del token**, nunca del cuerpo. Todas las consultas filtran `WHERE user_id = ?`. | [`app.js`](../backend/src/app.js) `requireUser()` |
| **Limpieza de sesión:** purgar la base SQLite al cerrar sesión | `logout()` borra `tasks` y `sync_meta`, borra el almacenamiento seguro y cancela WorkManager. Si quedan cambios sin sincronizar, la app lo advierte antes. | [`auth_repository.dart`](../app/lib/data/repositories/auth_repository.dart), [`app_services.dart`](../app/lib/core/app_services.dart) |

## Reglas del backend

1. **Autenticación obligatoria**: sin `Authorization: Bearer <JWT>` válido → `401`.
2. **JWT HS256 estricto**: se valida la firma con comparación en tiempo constante (`timingSafeEqual`), se rechaza `alg: none` o cualquier otro algoritmo y se verifica `exp`. El secreto viene de la variable de entorno `JWT_SECRET`, nunca del código.
3. **Propiedad por UID**:
   - Leer una tarea ajena → `404` (no revela que existe).
   - Escribir sobre un UUID ajeno → `forbidden` / `403`.
   - El PULL solo devuelve registros del UID del token.
4. **El cliente no controla campos del servidor**: `user_id`, `version`, `rev` y `server_updated_at` los asigna el servidor; se ignoran si vienen en el cuerpo.
5. **Validación de entrada**: `id` con formato UUID, `title` de 1 a 200 caracteres, `description` ≤ 2000, `updated_at` en ISO-8601 **con zona UTC (Z)** y no más de 5 min en el futuro (anti-manipulación del LWW). Lotes ≤ 500 y cuerpo ≤ 1 MB.
6. **Contraseñas**: scrypt (N = 16384, r = 8, p = 1) con sal aleatoria de 16 bytes por usuario.
7. **Anti fuerza bruta**: límite de 20 intentos por minuto por IP en `/auth/*`, y mensaje genérico «Usuario o contraseña incorrectos».
8. **Cabeceras**: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Cache-Control: no-store`, `Referrer-Policy: no-referrer`, y CSP en la consola.
9. **Errores**: los `500` no exponen trazas al cliente.
10. **Consola nube**: login por formulario (`ADMIN_USER` / `ADMIN_PASSWORD`) que emite una cookie de sesión **firmada con HMAC**, `HttpOnly`, `SameSite=Strict`, con `Path=/console` y 8 h de vida. También acepta Basic Auth para `curl`. Queda **deshabilitada** si no se define contraseña. Renderiza con `textContent` para evitar XSS con títulos escritos por usuarios.

Todas estas reglas están cubiertas por pruebas automáticas en [`backend/test/api.test.js`](../backend/test/api.test.js): aislamiento entre usuarios, `alg=none`, validación y consola protegida.

### Equivalente en Firebase (Firestore Rules)

Si el backend se migra a Firebase, la misma regla de UID se expresa así:

```js
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {
    match /users/{uid}/tasks/{taskId} {
      allow read: if request.auth != null && request.auth.uid == uid;
      allow create, update: if request.auth != null
        && request.auth.uid == uid
        && request.resource.data.title is string
        && request.resource.data.title.size() > 0
        && request.resource.data.title.size() <= 200
        && request.resource.data.updated_at is string
        && taskId.matches('^[0-9a-f-]{36}$');
      allow delete: if false; // solo borrado lógico (is_deleted)
    }
  }
}
```

## Protecciones adicionales en el dispositivo

| Medida | Motivo |
|---|---|
| `android:allowBackup="false"` | Evita extraer la base SQLite y el almacenamiento seguro con `adb backup` o con los respaldos del sistema. |
| `network_security_config.xml` | **HTTPS obligatorio**; HTTP solo hacia `10.0.2.2` / `localhost` (backend de laboratorio). |
| Cambio de usuario | Si inicia sesión un UID distinto al último del dispositivo, se purga SQLite **antes** de guardar la nueva sesión, para que nunca se mezclen datos de dos usuarios. |
| Token expirado | Se borra el token pero se conservan los pendientes del mismo usuario, así un `401` no causa pérdida de datos. |
| Sin secretos en el repo | `.env`, keystores y bases de datos están en `.gitignore`; solo se versiona `.env.example`. |

## Limitaciones conocidas y mejoras

| Limitación | Mejora propuesta |
|---|---|
| El archivo SQLite **no está cifrado** (está protegido por el sandbox de la app y por `allowBackup=false`). | Usar `sqflite_sqlcipher` con la clave guardada en `flutter_secure_storage`. |
| El backend de laboratorio usa HTTP. | En producción: TLS (reverse proxy con HTTPS) y quitar el `domain-config` de cleartext. |
| JWT sin *refresh token* (expira en 24 h). | Agregar refresh tokens rotativos y revocación. |
| El rate limit vive en memoria (una sola instancia). | Redis o el API gateway. |
| LWW depende de los relojes (mitigado con la marca monótona y el límite de 5 min). | Relojes híbridos lógicos (HLC) o CRDT para campos concurrentes. |
