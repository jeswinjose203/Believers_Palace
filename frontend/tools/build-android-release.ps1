param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')][string]$Version,
    [Parameter(Mandatory)][ValidateRange(1,2100000000)][int]$Build,
    [Parameter(Mandatory)][uri]$ApiUrl,
    [Parameter(Mandatory)][string]$Keystore,
    [Parameter(Mandatory)][string]$KeyAlias,
    [Parameter(Mandatory)][string]$ApkSigner,
    [string]$DefinesFile
)

$ErrorActionPreference = 'Stop'
if (!$ApiUrl.IsAbsoluteUri -or $ApiUrl.Scheme -ne 'https' -or $ApiUrl.IsLoopback -or
    $ApiUrl.UserInfo -or $ApiUrl.Query -or $ApiUrl.Fragment) {
    throw 'Provide the public HTTPS application API URL.'
}
if (!$env:BP_ANDROID_STORE_PASSWORD -or !$env:BP_ANDROID_KEY_PASSWORD) {
    throw 'Set BP_ANDROID_STORE_PASSWORD and BP_ANDROID_KEY_PASSWORD in your shell.'
}
$keystorePath = (Resolve-Path -LiteralPath $Keystore).Path
$signerPath = (Get-Command $ApkSigner -CommandType Application).Source
$buildArgs = @('build','apk','--release',"--build-name=$Version","--build-number=$Build",
    "--dart-define=APP_RELEASE_BUILD=$Build","--dart-define=API_BASE_URL=$($ApiUrl.AbsoluteUri.TrimEnd('/'))")
if ($DefinesFile) {
    $definesPath = (Resolve-Path -LiteralPath $DefinesFile).Path
    $buildArgs += "--dart-define-from-file=$definesPath"
}
Push-Location (Join-Path $PSScriptRoot '..')
try {
    & flutter @buildArgs
    if ($LASTEXITCODE -ne 0) { throw 'Flutter release build failed.' }
    $unsigned = 'build/app/outputs/flutter-apk/app-release.apk'
    $output = 'build/app/outputs/flutter-apk/believers-palace.apk'
    & $signerPath sign --ks $keystorePath --ks-key-alias $KeyAlias --ks-pass env:BP_ANDROID_STORE_PASSWORD --key-pass env:BP_ANDROID_KEY_PASSWORD --out $output $unsigned
    if ($LASTEXITCODE -ne 0) { throw 'APK signing failed.' }
    $verification = & $signerPath verify --print-certs $output
    if ($LASTEXITCODE -ne 0 -or ($verification -join "`n") -match 'CN=Android Debug') {
        throw 'APK signature verification failed or the certificate is an Android debug key.'
    }
    Write-Output "Signed release v$Version+$Build"
    Get-FileHash -LiteralPath $output -Algorithm SHA256
} finally {
    Pop-Location
}
