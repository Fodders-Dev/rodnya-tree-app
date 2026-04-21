param(
  [string]$PackageName = "com.ahjkuio.rodnya_family_app",
  [Parameter(Mandatory = $true)]
  [string]$VersionId,
  [string[]]$Screenshots,
  [string]$ScreenshotDir = ".tmp/rustore_screenshots_1.0.2/final",
  [ValidateSet("PORTRAIT", "LANDSCAPE")]
  [string]$Orientation = "PORTRAIT",
  [int]$StartOrdinal = 0
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Net.Http

function Get-RequiredEnv([string]$name) {
  $value = [Environment]::GetEnvironmentVariable($name)
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "Missing environment variable: $name"
  }
  return $value
}

function New-RuStoreSignaturePayload(
  [string]$KeyId,
  [string]$PrivateKeyBase64
) {
  $timestamp = [DateTimeOffset]::Now.ToString("yyyy-MM-ddTHH:mm:ss.fffffffzzz")
  $message = "$KeyId$timestamp"
  $privateKeyBytes = [Convert]::FromBase64String($PrivateKeyBase64)
  $signatureBytes = $null
  $rsa = [System.Security.Cryptography.RSA]::Create()
  try {
    $importMethod = $rsa.GetType().GetMethod(
      "ImportPkcs8PrivateKey",
      [type[]]@(
        [byte[]],
        [int].MakeByRefType()
      )
    )

    if ($null -ne $importMethod) {
      $bytesRead = 0
      $rsa.ImportPkcs8PrivateKey($privateKeyBytes, [ref]$bytesRead)
      $signatureBytes = $rsa.SignData(
        [System.Text.Encoding]::UTF8.GetBytes($message),
        [System.Security.Cryptography.HashAlgorithmName]::SHA512,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
      )
    }
  } finally {
    $rsa.Dispose()
  }

  if ($null -eq $signatureBytes) {
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("rustore-sign-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    try {
      $keyPath = Join-Path $tempDir "private-key.der"
      $messagePath = Join-Path $tempDir "message.txt"
      $signaturePath = Join-Path $tempDir "signature.bin"

      [System.IO.File]::WriteAllBytes($keyPath, $privateKeyBytes)
      [System.IO.File]::WriteAllBytes($messagePath, [System.Text.Encoding]::UTF8.GetBytes($message))

      $openssl = Get-Command "openssl" -ErrorAction SilentlyContinue
      if ($null -eq $openssl) {
        throw "OpenSSL not found in PATH and current PowerShell runtime does not support ImportPkcs8PrivateKey."
      }

      $opensslOutput = & $openssl.Source dgst -sha512 -sign $keyPath -keyform DER -out $signaturePath $messagePath 2>&1
      if ($LASTEXITCODE -ne 0) {
        throw "OpenSSL signing failed: $opensslOutput"
      }

      $signatureBytes = [System.IO.File]::ReadAllBytes($signaturePath)
    } finally {
      if (Test-Path $tempDir) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force
      }
    }
  }

  return @{
    keyId = $KeyId
    timestamp = $timestamp
    signature = [Convert]::ToBase64String($signatureBytes)
  }
}

function Invoke-RuStoreJsonRequest(
  [string]$Method,
  [string]$Uri,
  [hashtable]$Headers,
  $Body = $null
) {
  $params = @{
    Method = $Method
    Uri = $Uri
    Headers = $Headers
    ContentType = "application/json"
  }
  if ($null -ne $Body) {
    $params.Body = ($Body | ConvertTo-Json -Depth 10)
  }
  return Invoke-RestMethod @params
}

function Invoke-RuStoreFileUpload(
  [string]$Uri,
  [string]$Token,
  [string]$FilePath
) {
  $contentType = switch ([System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()) {
    ".png" { "image/png" }
    ".jpg" { "image/jpeg" }
    ".jpeg" { "image/jpeg" }
    default { throw "Unsupported screenshot format: $FilePath" }
  }

  $httpClient = [System.Net.Http.HttpClient]::new()
  $httpClient.Timeout = [TimeSpan]::FromMinutes(10)
  try {
    $httpClient.DefaultRequestHeaders.Add("Public-Token", $Token)
    $multipart = [System.Net.Http.MultipartFormDataContent]::new()
    $stream = [System.IO.File]::OpenRead($FilePath)
    try {
      $fileContent = [System.Net.Http.StreamContent]::new($stream)
      $fileContent.Headers.ContentType =
        [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse($contentType)
      $multipart.Add(
        $fileContent,
        "file",
        [System.IO.Path]::GetFileName($FilePath)
      )
      $response = $httpClient.PostAsync($Uri, $multipart).GetAwaiter().GetResult()
      $responseBody = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
      if (-not $response.IsSuccessStatusCode) {
        throw "RuStore screenshot upload failed: HTTP $($response.StatusCode)`n$responseBody"
      }
      return $responseBody | ConvertFrom-Json
    } finally {
      $stream.Dispose()
      $multipart.Dispose()
    }
  } finally {
    $httpClient.Dispose()
  }
}

if ($StartOrdinal -lt 0 -or $StartOrdinal -gt 9) {
  throw "StartOrdinal must be between 0 and 9."
}

if (-not $Screenshots -or $Screenshots.Count -eq 0) {
  if (-not (Test-Path $ScreenshotDir)) {
    throw "Screenshot directory not found: $ScreenshotDir"
  }
  $Screenshots = Get-ChildItem $ScreenshotDir -File |
    Where-Object { $_.Extension -in @(".png", ".jpg", ".jpeg") } |
    Sort-Object Name |
    ForEach-Object { $_.FullName }
}

if (-not $Screenshots -or $Screenshots.Count -eq 0) {
  throw "No screenshots found."
}

if (($StartOrdinal + $Screenshots.Count - 1) -gt 9) {
  throw "RuStore allows up to 10 screenshots per orientation with ordinals 0..9. Reduce the input set or change StartOrdinal."
}

$resolvedScreenshots = @()
foreach ($screenshot in $Screenshots) {
  if (-not (Test-Path $screenshot)) {
    throw "Screenshot not found: $screenshot"
  }
  $resolvedScreenshots += (Resolve-Path $screenshot).Path
}

$keyId = Get-RequiredEnv "RUSTORE_KEY_ID"
$privateKeyBase64 = Get-RequiredEnv "RUSTORE_PRIVATE_KEY_BASE64"
$signaturePayload = New-RuStoreSignaturePayload `
  -KeyId $keyId `
  -PrivateKeyBase64 $privateKeyBase64

$authResponse = Invoke-RuStoreJsonRequest `
  -Method "POST" `
  -Uri "https://public-api.rustore.ru/public/auth" `
  -Headers @{} `
  -Body $signaturePayload

if ($authResponse.code -ne "OK" -or
    [string]::IsNullOrWhiteSpace($authResponse.body.jwe)) {
  throw "Failed to obtain RuStore API token: $($authResponse | ConvertTo-Json -Depth 10)"
}

$token = $authResponse.body.jwe
$results = @()

for ($index = 0; $index -lt $resolvedScreenshots.Count; $index++) {
  $screenshotPath = $resolvedScreenshots[$index]
  $ordinal = $StartOrdinal + $index
  $uri = "https://public-api.rustore.ru/public/v1/application/$PackageName/version/$VersionId/image/screenshot/$Orientation/$ordinal"
  $uploadResponse = Invoke-RuStoreFileUpload `
    -Uri $uri `
    -Token $token `
    -FilePath $screenshotPath

  if ($uploadResponse.code -ne "OK") {
    throw "Failed to upload screenshot ${screenshotPath}: $($uploadResponse | ConvertTo-Json -Depth 10)"
  }

  $results += [PSCustomObject]@{
    Ordinal = $ordinal
    Orientation = $Orientation
    File = [System.IO.Path]::GetFileName($screenshotPath)
    Response = ($uploadResponse.body | ConvertTo-Json -Compress)
  }
}

Write-Host "RuStore screenshots uploaded successfully."
$results | Format-Table -AutoSize
