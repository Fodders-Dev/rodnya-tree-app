param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$FlutterArgs
)

$ErrorActionPreference = 'Stop'

function Resolve-FlutterBinary {
  $command = Get-Command flutter -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $defaultFlutter = 'C:\src\flutter\bin\flutter.bat'
  if (Test-Path $defaultFlutter) {
    return $defaultFlutter
  }

  throw "Flutter binary not found. Add 'flutter' to PATH or install it at $defaultFlutter."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sha256 = [System.Security.Cryptography.SHA256]::Create()
$repoHashBytes = $sha256.ComputeHash(
  [System.Text.Encoding]::UTF8.GetBytes($repoRoot.ToLowerInvariant())
)
$repoHash = -join ($repoHashBytes[0..5] | ForEach-Object { $_.ToString('x2') })
$safeRoot = Join-Path $env:TEMP "rodnya_safe_workspace_$repoHash"
$safeWorkspace = Join-Path $safeRoot 'repo'
$flutterBinary = Resolve-FlutterBinary

New-Item -ItemType Directory -Path $safeRoot -Force | Out-Null

if (Test-Path $safeWorkspace) {
  $existingItem = Get-Item -LiteralPath $safeWorkspace -Force
  $existingTarget = $existingItem.LinkTarget
  if (-not $existingTarget) {
    $existingTarget = @($existingItem.Target)[0]
  }
  if ($existingTarget -ne $repoRoot) {
    Remove-Item -LiteralPath $safeWorkspace -Force -Recurse
  }
}

if (-not (Test-Path $safeWorkspace)) {
  New-Item -ItemType Junction -Path $safeWorkspace -Target $repoRoot | Out-Null
}

Push-Location $safeWorkspace
try {
  & $flutterBinary @FlutterArgs
  exit $LASTEXITCODE
}
finally {
  Pop-Location
}
