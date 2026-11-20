# 05 · Guía de ejecución

## Requisitos

| Herramienta | Versión | Verificar |
|---|---|---|
| Flutter SDK | **3.38 o superior** (Dart 3.10+) | `flutter --version` |
| Android SDK + emulador (o celular con depuración USB) | API 24+ | `flutter doctor` |
| Node.js | **22.13 o superior** (probado con 24.20) | `node --version` |
| Git | cualquiera | `git --version` |

> **Nota para este equipo de laboratorio:** la carpeta `C:\src\flutter` está incompleta (no tiene `bin\`). Hay que reinstalar Flutter, por ejemplo con
> `git clone -b stable https://github.com/flutter/flutter.git C:\src\flutter`
> (respaldar o borrar antes la carpeta actual) y luego ejecutar `flutter doctor`.

## 1. Backend cloud

```powershell
cd backend
copy .env.example .env      # editar JWT_SECRET y ADMIN_PASSWORD
npm start                   # sin npm install: cero dependencias
npm test                    # 11 pruebas de API
```

Salida esperada:

```
[server] API Offline-First escuchando en http://0.0.0.0:3000
[server] Emulador Android: http://10.0.2.2:3000
[server] Consola nube:     http://localhost:3000/console
```

Abre `http://localhost:3000/console` en el navegador (usuario y contraseña de `.env`). Se refresca cada 3 s y resalta las filas nuevas.

## 2. App Flutter

El repositorio versiona el código propio (`lib/`, `test/`, `pubspec.yaml`, `AndroidManifest.xml`, `network_security_config.xml`). Las carpetas generadas por Flutter (Gradle, `MainActivity`, íconos) se crean con un solo comando, que **no sobrescribe** los archivos existentes:

```powershell
cd app
powershell -ExecutionPolicy Bypass -File tool\setup.ps1
# equivale a:
#   flutter create --org mx.edu.utxj --project-name offline_first_tasks --platforms=android .
#   flutter pub get
#   flutter analyze
#   flutter test
```

### Ejecutar

**Emulador Android** (`10.0.2.2` es el host visto desde el emulador):

```powershell
flutter run --dart-define=API_URL=http://10.0.2.2:3000
```

**Celular físico por Wi-Fi (recomendado):** el celular y la PC deben estar en la misma red. Usa la IP de la PC (`ipconfig` → Wi-Fi → IPv4):

```powershell
flutter run --dart-define=API_URL=http://10.10.62.19:3000
```

La dirección también se puede cambiar **dentro de la app**: campo «Servidor» en el login, o menú ⋮ → «Servidor». Se guarda en el almacenamiento seguro. Las compilaciones *debug* permiten HTTP hacia cualquier IP (`src/debug/res/xml/network_security_config.xml`); la *release* exige HTTPS.

**Celular físico por USB** (redirige el puerto del celular a la PC; se pierde si se desconecta el cable):

```powershell
adb reverse tcp:3000 tcp:3000
flutter run --dart-define=API_URL=http://localhost:3000
```

**APK para entregar:**

```powershell
flutter build apk --release --dart-define=API_URL=http://10.0.2.2:3000
# build\app\outputs\flutter-apk\app-release.apk
```

### Ver la base SQLite del dispositivo (evidencia)

```powershell
adb shell "run-as mx.edu.utxj.offline_first_tasks cat databases/offline_first.db" > local.db
sqlite3 local.db "SELECT title, is_synced, updated_at, is_deleted, version FROM tasks;"
```

También sirve el **App Inspection → Database Inspector** de Android Studio.

### Forzar la ejecución de WorkManager (depuración)

```powershell
# 1) ver los trabajos agendados y su JOB_ID:
adb shell dumpsys jobscheduler | findstr offline_first
# 2) forzar uno:
adb shell cmd jobscheduler run -f mx.edu.utxj.offline_first_tasks <JOB_ID>
```

## Solución de problemas

| Síntoma | Causa / solución |
|---|---|
| «Sin conexión con el servidor» al iniciar sesión | El backend no está corriendo, o la `API_URL` no corresponde (emulador = `10.0.2.2`, USB = `localhost` + `adb reverse`). |
| `Cleartext HTTP traffic not permitted` | Usar una IP distinta a las permitidas: agrega el dominio en `network_security_config.xml`, o usa `adb reverse`. |
| `pub get` falla por versión de SDK | Actualiza Flutter a 3.38+ (`flutter upgrade`). |
| La lista no refleja una sync en segundo plano | Se actualiza al volver a primer plano (`onResumed`); el isolate de WorkManager no comparte memoria con la UI. |
