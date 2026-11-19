# Genera las carpetas de plataforma de Flutter (Gradle, MainActivity, iconos)
# SIN sobrescribir el código del repositorio (lib/, test/, AndroidManifest.xml,
# network_security_config.xml): `flutter create` omite los archivos existentes.
#
# Uso (desde la carpeta app/):
#   powershell -ExecutionPolicy Bypass -File tool\setup.ps1

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error 'Flutter no está en el PATH. Instala Flutter 3.38+ (https://docs.flutter.dev/get-started/install).'
}

flutter create --org mx.edu.utxj --project-name offline_first_tasks --platforms=android .
flutter pub get
flutter analyze
flutter test

Write-Host ''
Write-Host 'Listo. Inicia el backend (cd ..\backend; npm start) y luego:' -ForegroundColor Green
Write-Host '  flutter run --dart-define=API_URL=http://10.0.2.2:3000' -ForegroundColor Green
