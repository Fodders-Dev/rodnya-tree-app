param(
    [string]$ServerHost = "212.69.84.167",
    [string]$User = "rodnya-deploy",
    [string]$TargetDir = "/var/www/rodnya-site",
    [string]$RemoteScriptPath = "/usr/local/bin/rodnya-activate-web-release",
    [string]$RemoteUploadDir = "/tmp",
    [string]$GoogleWebClientId = "676171184233-hl6gauj8c1trtn25a8me7pvm4m4clndv.apps.googleusercontent.com",
    [string]$SmokeBaseUrl = "https://rodnya-tree.ru",
    [string]$SmokeApiUrl = "https://api.rodnya-tree.ru",
    [string]$SmokeEmail,
    [string]$SmokePassword,
    [string]$SmokeFixtureTreeId,
    [string]$SmokeClaimUrl,
    [string]$SmokeInviteUrl,
    [string]$IdentityFile,
    [switch]$SkipBuild,
    [switch]$SkipSmoke,
    [switch]$NoRollbackOnSmokeFailure
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
$archivePath = Join-Path $env:TEMP "rodnya-site-$timestamp.tgz"

Push-Location $repoRoot
try {
    if (-not $SkipBuild) {
        Invoke-Checked "flutter" @("pub", "get")
        $buildArgs = @(
            "build",
            "web",
            "--release",
            "--dart-define=RODNYA_RUNTIME_PRESET=prod_custom_api",
            "--dart-define=RODNYA_ENABLE_LEGACY_DYNAMIC_LINKS=false"
        )
        if ($GoogleWebClientId) {
            $buildArgs += "--dart-define=RODNYA_GOOGLE_WEB_CLIENT_ID=$GoogleWebClientId"
        }
        Invoke-Checked -FilePath "flutter" -Arguments $buildArgs
        Invoke-Checked "node" @("tool/sync_web_shell_assets.js")
    }

    if (Test-Path $archivePath) {
        Remove-Item $archivePath -Force
    }

    $localHiddenBuildMarker = Join-Path $repoRoot "build\\web\\.last_build_id"
    if (Test-Path $localHiddenBuildMarker) {
        Remove-Item $localHiddenBuildMarker -Force
    }

    $localPublicBuildMarker = Join-Path $repoRoot "build\\web\\last_build_id.txt"
    if (Test-Path $localPublicBuildMarker) {
        Remove-Item $localPublicBuildMarker -Force
    }

    Push-Location (Join-Path $repoRoot "build\\web")
    try {
        Invoke-Checked "tar.exe" @("-czf", $archivePath, ".")
    } finally {
        Pop-Location
    }

    $gitSha = (& git rev-parse --short HEAD).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to resolve git revision"
    }

    $dirtyTree = if ((& git status --porcelain).Trim()) { "dirty-tree-web-build" } else { "clean-tree-web-build" }
    $buildLabel = "deploy $(Get-Date -Format 'yyyy-MM-dd HH:mm zzz') / git $gitSha / $dirtyTree"
    $remoteArchive = "$RemoteUploadDir/rodnya-site-$timestamp.tgz"

    $sshArgs = @()
    if ($IdentityFile) {
        $sshArgs += @("-i", $IdentityFile)
    }

    Invoke-Checked "scp" ($sshArgs + @($archivePath, "${User}@${ServerHost}:$remoteArchive"))

    $escapedLabel = $buildLabel.Replace("'", "'`"'`"'")
    $remoteCommand = "DEPLOY_TIMESTAMP='$timestamp' BUILD_LABEL='$escapedLabel' ; export DEPLOY_TIMESTAMP BUILD_LABEL; if [ `$(id -u) -eq 0 ]; then '$RemoteScriptPath' '$remoteArchive' '$TargetDir' '$escapedLabel'; else sudo -n '$RemoteScriptPath' '$remoteArchive' '$TargetDir' '$escapedLabel'; fi && rm -f '$remoteArchive'"
    Invoke-Checked "ssh" ($sshArgs + @("${User}@${ServerHost}", $remoteCommand))

    $verifyCommand = "test -f '$TargetDir/.last_build_id' && test -f '$TargetDir/last_build_id.txt' && cat '$TargetDir/last_build_id.txt'"
    Invoke-Checked "ssh" ($sshArgs + @("${User}@${ServerHost}", $verifyCommand))

    Invoke-Checked "node" @(
        "tool/backend_ready_alert.mjs",
        "--url",
        "$SmokeApiUrl/ready"
    )

    if (-not $SkipSmoke) {
        Invoke-Checked "npm" @("ci")
        Invoke-Checked "npx" @("playwright", "install", "chromium")

        $smokeOutput = Join-Path $repoRoot "output\playwright\prod-route-smoke.after-deploy.json"
        $smokeArgs = @(
            "tool/prod_route_smoke.mjs",
            "--base-url", $SmokeBaseUrl,
            "--api-url", $SmokeApiUrl,
            "--output-json", $smokeOutput
        )
        if ($SmokeEmail) {
            $smokeArgs += @("--email", $SmokeEmail)
        }
        if ($SmokePassword) {
            $smokeArgs += @("--password", $SmokePassword)
        }
        if ($SmokeFixtureTreeId) {
            $smokeArgs += @("--fixture-tree-id", $SmokeFixtureTreeId)
        }
        if ($SmokeClaimUrl) {
            $smokeArgs += @("--claim-url", $SmokeClaimUrl)
        }
        if ($SmokeInviteUrl) {
            $smokeArgs += @("--invite-url", $SmokeInviteUrl)
        }

        try {
            Invoke-Checked "node" $smokeArgs
        } catch {
            if (-not $NoRollbackOnSmokeFailure) {
                $rollbackArchive = "/opt/rodnya/backups/$timestamp-web/rodnya-site.tgz"
                $rollbackLabel = "rollback $(Get-Date -Format 'yyyy-MM-dd HH:mm zzz') / failed-smoke / git $gitSha"
                $escapedRollbackLabel = $rollbackLabel.Replace("'", "'`"'`"'")
                $rollbackCommand = "test -f '$rollbackArchive' && if [ `$(id -u) -eq 0 ]; then BUILD_LABEL='$escapedRollbackLabel' '$RemoteScriptPath' '$rollbackArchive' '$TargetDir' '$escapedRollbackLabel'; else BUILD_LABEL='$escapedRollbackLabel' sudo -n '$RemoteScriptPath' '$rollbackArchive' '$TargetDir' '$escapedRollbackLabel'; fi"
                Write-Warning "Smoke failed. Rolling back web release from $rollbackArchive"
                Invoke-Checked "ssh" ($sshArgs + @("${User}@${ServerHost}", $rollbackCommand))
            }
            throw
        }
    }
} finally {
    Pop-Location
}
