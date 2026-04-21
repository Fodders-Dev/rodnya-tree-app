param(
  [ValidateSet("appbundle", "apk", "both")]
  [string]$ArtifactKind = "appbundle"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$flutterSafe = Join-Path $repoRoot "tool\flutter_safe.ps1"

if (-not (Test-Path $flutterSafe)) {
  throw "flutter_safe.ps1 not found: $flutterSafe"
}

if (
  -not $env:RODNYA_RELEASE_SIGNING_PROPERTIES -and
  -not $env:RODNYA_KEYSTORE_FILE -and
  -not (Test-Path (Join-Path $repoRoot "android\\release-signing.properties"))
) {
  Write-Warning "Release signing is not configured. Set RODNYA_RELEASE_SIGNING_PROPERTIES or RODNYA_KEYSTORE_* env vars before building."
}

$defines = @(
  "--dart-define=RODNYA_RUNTIME_PRESET=prod_custom_api",
  "--dart-define=RODNYA_ENABLE_LEGACY_DYNAMIC_LINKS=false",
  "--dart-define=RODNYA_GOOGLE_WEB_CLIENT_ID=676171184233-hl6gauj8c1trtn25a8me7pvm4m4clndv.apps.googleusercontent.com",
  "--dart-define=RODNYA_APP_STORE=rustore",
  "--dart-define=RODNYA_ENABLE_RUSTORE_BILLING=false",
  "--dart-define=RODNYA_ENABLE_RUSTORE_REVIEW=true",
  "--dart-define=RODNYA_ENABLE_RUSTORE_UPDATES=true"
)

function Invoke-RustoreBuild([string]$artifactType) {
  $buildArgs = @("build", $artifactType, "--flavor", "rustore", "--release") + $defines

  if ($env:RODNYA_BUILD_NAME) {
    $buildArgs += "--build-name=$($env:RODNYA_BUILD_NAME)"
  }

  if ($env:RODNYA_BUILD_NUMBER) {
    $buildArgs += "--build-number=$($env:RODNYA_BUILD_NUMBER)"
  }

  powershell -ExecutionPolicy Bypass -File $flutterSafe @buildArgs
}

switch ($ArtifactKind) {
  "appbundle" { Invoke-RustoreBuild "appbundle" }
  "apk" { Invoke-RustoreBuild "apk" }
  "both" {
    Invoke-RustoreBuild "appbundle"
    Invoke-RustoreBuild "apk"
  }
}
