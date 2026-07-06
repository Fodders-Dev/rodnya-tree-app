# Builds the SIDELOAD / OTA release APK (раздача через Telegram, вне магазина).
# Same signed release build as the store one, but:
#   - RuStore update SDK OFF  -> the in-app OTA updater (/v1/app/latest) owns updates
#   - RuStore review prompt OFF (no store-review popup on a non-store build)
#   - RuStore PUSH channel KEPT (dual FCM + RuStore push; works on GMS-less RU devices)
# The APK self-updates on sideload because the OTA gate keys off the installer
# (installer != store), not the flavor.
#
# Usage:
#   pwsh tool/build_sideload_release.ps1                       # version from pubspec
#   $env:RODNYA_BUILD_NAME="1.0.25"; $env:RODNYA_BUILD_NUMBER="33"; pwsh tool/build_sideload_release.ps1
#
# After it prints the SHA-256, host the APK at an https URL and set these on the
# backend (systemd env), then restart — OTA then offers this build to older installs:
#   RODNYA_LATEST_ANDROID_VERSION_CODE = <build number, e.g. 33>
#   RODNYA_LATEST_ANDROID_APK_URL      = https://.../rodnya-<ver>.apk
#   RODNYA_LATEST_ANDROID_APK_SHA256   = <printed below>
#   RODNYA_LATEST_ANDROID_VERSION_NAME = <optional, e.g. 1.0.25>
#   RODNYA_LATEST_ANDROID_NOTES        = <optional release notes>
#   RODNYA_MIN_ANDROID_VERSION_CODE    = <optional force-update floor>

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$flutterSafe = Join-Path $repoRoot "tool\flutter_safe.ps1"
if (-not (Test-Path $flutterSafe)) { throw "flutter_safe.ps1 not found: $flutterSafe" }

# Signing is enforced by gradle itself (android/app/build.gradle throws a clear
# GradleException if release-signing.properties / RODNYA_KEYSTORE_* are missing),
# so no separate pre-flight is needed here.

$defines = @(
  "--dart-define=RODNYA_RUNTIME_PRESET=prod_custom_api",
  "--dart-define=RODNYA_ENABLE_LEGACY_DYNAMIC_LINKS=false",
  "--dart-define=RODNYA_GOOGLE_WEB_CLIENT_ID=676171184233-hl6gauj8c1trtn25a8me7pvm4m4clndv.apps.googleusercontent.com",
  "--dart-define=RODNYA_APP_STORE=rustore",
  "--dart-define=RODNYA_ENABLE_RUSTORE_BILLING=false",
  "--dart-define=RODNYA_ENABLE_RUSTORE_REVIEW=false",
  "--dart-define=RODNYA_ENABLE_RUSTORE_UPDATES=false"
)

$buildArgs = @("build", "apk", "--flavor", "rustore", "--release") + $defines
if ($env:RODNYA_BUILD_NAME)   { $buildArgs += "--build-name=$($env:RODNYA_BUILD_NAME)" }
if ($env:RODNYA_BUILD_NUMBER) { $buildArgs += "--build-number=$($env:RODNYA_BUILD_NUMBER)" }

Write-Host "Building SIDELOAD/OTA release APK (RuStore updates+review OFF, OTA owns updates)..." -ForegroundColor Cyan
powershell -ExecutionPolicy Bypass -File $flutterSafe @buildArgs
if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed (exit $LASTEXITCODE)." }

$apk = Join-Path $repoRoot "build\app\outputs\flutter-apk\app-rustore-release.apk"
if (-not (Test-Path $apk)) { throw "APK not found at $apk" }

$sha = (Get-FileHash -Algorithm SHA256 -LiteralPath $apk).Hash.ToLower()
$sizeMb = [math]::Round((Get-Item $apk).Length / 1MB, 1)

Write-Host ""
Write-Host "==================== SIDELOAD APK READY ====================" -ForegroundColor Green
Write-Host "  file    : $apk  ($sizeMb MB)"
Write-Host "  sha256  : $sha"
Write-Host ""
Write-Host "  Host the APK at an https URL, then set on the backend + restart:" -ForegroundColor Yellow
Write-Host "    RODNYA_LATEST_ANDROID_VERSION_CODE = $($env:RODNYA_BUILD_NUMBER)"
Write-Host "    RODNYA_LATEST_ANDROID_APK_URL      = https://.../rodnya.apk"
Write-Host "    RODNYA_LATEST_ANDROID_APK_SHA256   = $sha"
Write-Host "============================================================" -ForegroundColor Green
