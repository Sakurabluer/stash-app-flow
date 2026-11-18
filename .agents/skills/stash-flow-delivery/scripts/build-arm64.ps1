[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$')]
    [string]$VersionName,
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 2100000000)]
    [int]$BuildNumber,
    [string]$OutputPath,
    [string]$SdkPath,
    [string[]]$ForbiddenEnvironmentVariables = @()
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../..')).Path
if (-not $OutputPath) {
    $OutputPath = Join-Path $projectRoot "release/stash-flow-$VersionName-$BuildNumber-arm64.apk"
} elseif (-not [IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $projectRoot $OutputPath
}
if ((Test-Path -LiteralPath $OutputPath) -or (Test-Path -LiteralPath "$OutputPath.sha256")) {
    throw 'Output already exists. Choose a new output name to preserve the previous APK.'
}

$flutter = Join-Path $projectRoot '.tooling/flutter/bin/flutter.bat'
if (-not (Test-Path -LiteralPath $flutter)) {
    $flutter = (Get-Command flutter -ErrorAction Stop).Source
}
$python = (Get-Command python -ErrorAction Stop).Source
if ($SdkPath) {
    $env:ANDROID_HOME = $SdkPath
}
foreach ($signingName in @('STASH_FLOW_KEYSTORE', 'STASH_FLOW_KEY_ALIAS', 'STASH_FLOW_STORE_PASSWORD', 'STASH_FLOW_KEY_PASSWORD')) {
    $value = [Environment]::GetEnvironmentVariable($signingName, 'Process')
    if (-not $value) {
        $value = [Environment]::GetEnvironmentVariable($signingName, 'User')
        if ($value) { [Environment]::SetEnvironmentVariable($signingName, $value, 'Process') }
    }
    if (-not $value) { throw "Missing release signing configuration: $signingName" }
}
if (-not (Test-Path -LiteralPath $env:STASH_FLOW_KEYSTORE -PathType Leaf)) {
    throw 'Configured release keystore is unavailable.'
}
foreach ($scanVariable in $ForbiddenEnvironmentVariables) {
    if (-not [Environment]::GetEnvironmentVariable($scanVariable, 'Process')) {
        throw "Required APK scan environment variable is empty: $scanVariable"
    }
}

Push-Location $projectRoot
try {
    & $flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis failed.' }
    & $flutter test --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed.' }
    & $flutter build apk --release --target-platform=android-arm64 "--build-name=$VersionName" "--build-number=$BuildNumber" --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Flutter ARM64 build failed.' }

    $candidate = Join-Path $projectRoot 'build/app/outputs/flutter-apk/app-release.apk'
    $verifyArgs = @((Join-Path $PSScriptRoot 'verify-apk.py'), $candidate, '--version-name', $VersionName, '--version-code', "$BuildNumber")
    if ($SdkPath) { $verifyArgs += @('--sdk', $SdkPath) }
    foreach ($scanVariable in $ForbiddenEnvironmentVariables) { $verifyArgs += @('--forbid-env', $scanVariable) }
    $verification = & $python @verifyArgs
    if ($LASTEXITCODE -ne 0) { throw 'APK verification failed; no deliverable was copied.' }
    $metadata = ($verification -join "`n") | ConvertFrom-Json
    $outputFolder = Split-Path -Parent $OutputPath
    [IO.Directory]::CreateDirectory($outputFolder) | Out-Null
    # The non-overwriting copy also protects against another build creating this name.
    [IO.File]::Copy($candidate, $OutputPath, $false)
    $checksum = "$($metadata.sha256)  $([IO.Path]::GetFileName($OutputPath))`n"
    [IO.File]::WriteAllText("$OutputPath.sha256", $checksum, [Text.Encoding]::ASCII)
    Write-Output "Verified ARM64 APK: $OutputPath"
    Write-Output "SHA256: $($metadata.sha256)"
} finally {
    Pop-Location
}
