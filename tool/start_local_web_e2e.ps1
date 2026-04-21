param(
  [int]$Port = 3000,
  [string]$Bind = '127.0.0.1',
  [string]$ApiBaseUrl = 'http://127.0.0.1:8080',
  [string]$WsBaseUrl = 'ws://127.0.0.1:8080',
  [switch]$RepairShellAssets,
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$flutterSafe = Join-Path $PSScriptRoot 'flutter_safe.ps1'
$syncAssetsScript = Join-Path $PSScriptRoot 'sync_web_shell_assets.js'
$serverScript = Join-Path $PSScriptRoot 'serve_web_build.py'
$buildWebDir = Join-Path $repoRoot 'build/web'
$publicAppUrl = "http://$Bind`:$Port"

if (-not $SkipBuild) {
  & $flutterSafe build web `
    --dart-define=RODNYA_PUBLIC_APP_URL=$publicAppUrl `
    --dart-define=RODNYA_API_BASE_URL=$ApiBaseUrl `
    --dart-define=RODNYA_WS_BASE_URL=$WsBaseUrl `
    --dart-define=RODNYA_ENABLE_LEGACY_DYNAMIC_LINKS=false `
    --dart-define=RODNYA_E2E=true
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

if ((Test-Path $buildWebDir) -or $RepairShellAssets) {
  node $syncAssetsScript
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

python $serverScript --directory $buildWebDir --bind $Bind --port $Port
