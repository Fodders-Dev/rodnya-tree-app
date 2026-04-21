param(
    [string]$ServerHost = "212.69.84.167",
    [string]$User = "root",
    [string]$TargetDir = "/opt/rodnya/backend",
    [string]$ServiceName = "rodnya-backend.service",
    [string]$RemoteScriptPath = "/usr/local/bin/rodnya-activate-backend-release",
    [string]$RemoteUploadDir = "/tmp",
    [string]$IdentityFile,
    [switch]$SkipTests
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

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\\..")
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$archivePath = Join-Path $env:TEMP "rodnya-backend-$timestamp.tgz"

Push-Location $repoRoot
try {
    if (-not $SkipTests) {
        Invoke-Checked "node" @("--test", "backend/test/api.test.js")
    }

    if (Test-Path $archivePath) {
        Remove-Item $archivePath -Force
    }

    Push-Location (Join-Path $repoRoot "backend")
    try {
        Invoke-Checked "tar.exe" @(
            "--exclude=node_modules",
            "--exclude=data",
            "--exclude=test",
            "--exclude=.gitignore",
            "-czf",
            $archivePath,
            "."
        )
    } finally {
        Pop-Location
    }

    $gitSha = (& git rev-parse --short HEAD).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to resolve git revision"
    }

    $dirtyTree = if ((& git status --porcelain).Trim()) { "dirty-tree-backend-build" } else { "clean-tree-backend-build" }
    $buildLabel = "deploy $(Get-Date -Format 'yyyy-MM-dd HH:mm zzz') / git $gitSha / $dirtyTree"
    $remoteArchive = "$RemoteUploadDir/rodnya-backend-$timestamp.tgz"

    $sshArgs = @()
    if ($IdentityFile) {
        $sshArgs += @("-i", $IdentityFile)
    }

    Invoke-Checked "scp" ($sshArgs + @($archivePath, "${User}@${ServerHost}:$remoteArchive"))

    $escapedLabel = $buildLabel.Replace("'", "'`"'`"'")
    $remoteCommand = "if [ `$(id -u) -eq 0 ]; then '$RemoteScriptPath' '$remoteArchive' '$TargetDir' '$ServiceName' '$escapedLabel'; else sudo -n '$RemoteScriptPath' '$remoteArchive' '$TargetDir' '$ServiceName' '$escapedLabel'; fi && rm -f '$remoteArchive'"
    Invoke-Checked "ssh" ($sshArgs + @("${User}@${ServerHost}", $remoteCommand))

    $verifyCommand = "test -f '$TargetDir/.last_release_id' && systemctl is-active '$ServiceName' && curl -fsS http://127.0.0.1:8080/ready"
    Invoke-Checked "ssh" ($sshArgs + @("${User}@${ServerHost}", $verifyCommand))
} finally {
    Pop-Location
}
