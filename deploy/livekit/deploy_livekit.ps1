param(
    [string]$ServerHost = "212.69.84.167",
    [string]$User = "root",
    [string]$TargetDir = "/opt/rodnya/livekit",
    [string]$ServiceName = "rodnya-livekit.service",
    [string]$BackendServiceName = "rodnya-backend.service",
    [string]$RemoteScriptPath = "/usr/local/bin/rodnya-activate-livekit-release",
    [string]$RemoteUploadDir = "/tmp",
    [string]$CaddyfilePath = "/etc/caddy/Caddyfile",
    [string]$BackendEnvPath = "/etc/rodnya-backend.env",
    [string]$LiveKitHost = "livekit.rodnya-tree.ru",
    [string]$TurnHost = "turn.rodnya-tree.ru",
    [string]$NodeIp = "212.69.84.167",
    [string]$NetworkInterface = "ens1",
    [string]$TurnTlsPort = "5349",
    [string]$IdentityFile,
    [string]$LiveKitApiKey,
    [string]$LiveKitApiSecret,
    [string]$LiveKitWebhookKey
)

$ErrorActionPreference = "Stop"

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $FilePath $($Arguments -join ' ')"
    }
}

function New-HexString {
    param([int]$ByteCount = 8)
    $bytes = New-Object byte[] $ByteCount
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    -join ($bytes | ForEach-Object { $_.ToString("x2") })
}

function New-SafeSecret {
    param([int]$ByteCount = 32)
    $bytes = New-Object byte[] $ByteCount
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    ([Convert]::ToBase64String($bytes) -replace '[+/=]', 'A')
}

if (-not $LiveKitApiKey) {
    $LiveKitApiKey = "rodnya$(New-HexString -ByteCount 8)"
}
if (-not $LiveKitApiSecret) {
    $LiveKitApiSecret = New-SafeSecret -ByteCount 32
}
if (-not $LiveKitWebhookKey) {
    $LiveKitWebhookKey = New-SafeSecret -ByteCount 32
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$archivePath = Join-Path $env:TEMP "rodnya-livekit-$timestamp.tgz"
$scriptPath = Join-Path $repoRoot "deploy\livekit\activate_livekit_release.sh"

if (-not (Test-Path $scriptPath)) {
    throw "Missing remote activator script: $scriptPath"
}

Push-Location $repoRoot
try {
    if (Test-Path $archivePath) {
        Remove-Item $archivePath -Force
    }

    Invoke-Checked "tar.exe" @(
        "-czf",
        $archivePath,
        "deploy/livekit"
    )

    $sshArgs = @()
    if ($IdentityFile) {
        $sshArgs += @("-i", $IdentityFile)
    }

    $remoteArchive = "$RemoteUploadDir/rodnya-livekit-$timestamp.tgz"
    $remoteScript = "$RemoteUploadDir/rodnya-activate-livekit-release-$timestamp.sh"

    Invoke-Checked "scp" ($sshArgs + @($archivePath, "${User}@${ServerHost}:$remoteArchive"))
    Invoke-Checked "scp" ($sshArgs + @($scriptPath, "${User}@${ServerHost}:$remoteScript"))

    $remoteCommand = @"
set -euo pipefail
install -m 0755 '$remoteScript' '$RemoteScriptPath'
'$RemoteScriptPath' '$remoteArchive' '$TargetDir' '$ServiceName' '$CaddyfilePath' '$BackendEnvPath' '$LiveKitHost' '$TurnHost' '$LiveKitApiKey' '$LiveKitApiSecret' '$LiveKitWebhookKey' '$NodeIp' '$NetworkInterface' '$TurnTlsPort' '$BackendServiceName'
rm -f '$remoteArchive' '$remoteScript'
"@

    Invoke-Checked "ssh" ($sshArgs + @("-n", "${User}@${ServerHost}", $remoteCommand))
} finally {
    Pop-Location
}
