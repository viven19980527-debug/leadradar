param(
    [Parameter(Mandatory = $true)][string]$Ipa,
    [string]$Out,
    [switch]$Install,
    [string]$P12Pass = "1234",
    [string]$SigningDir = "E:\deepseeek\signing",
    [string]$Udid = "00008150-000C590602F2401C"
)

$ErrorActionPreference = "Continue"

$zsign   = Join-Path $SigningDir "tools\zsign.exe"
$idev    = Join-Path $SigningDir "tools\limd\ideviceinstaller.exe"
$p12     = Join-Path $SigningDir "sign.p12"
$profile = Join-Path $SigningDir "TrackerSweepAdHoc-auto.mobileprovision"

foreach ($f in @($zsign, $p12, $profile)) {
    if (-not (Test-Path $f)) { throw "missing signing material: $f" }
}
if (-not (Test-Path $Ipa)) { throw "ipa not found: $Ipa" }

if (-not $Out) {
    $Out = Join-Path (Split-Path $Ipa) ((Split-Path $Ipa -Leaf) -replace '\.ipa$', '-signed.ipa')
}
if (Test-Path $Out) { Remove-Item $Out -Force }

Write-Host "signing: $Ipa"
& $zsign -k $p12 -p $P12Pass -m $profile -o $Out $Ipa 2>&1 | Select-Object -Last 6 | Out-String | Write-Host

if (-not (Test-Path $Out)) { throw "sign failed, no output: $Out" }
Write-Host ("output: {0} ({1} B)" -f $Out, (Get-Item $Out).Length)

# verify embedded entitlements without extra deps
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($Out)
try {
    $entry = $zip.Entries | Where-Object { $_.FullName -like "*embedded.mobileprovision" } | Select-Object -First 1
    if ($entry) {
        $sr = New-Object System.IO.StreamReader($entry.Open())
        $text = $sr.ReadToEnd()
        $sr.Close()
        foreach ($k in @("HotspotConfiguration", "com.lab.trackersweep")) {
            if ($text.Contains($k)) { Write-Host "OK  $k" } else { Write-Host "NO  $k" }
        }
    } else {
        Write-Host "NO  embedded.mobileprovision (unsigned build?)"
    }
} finally {
    $zip.Dispose()
}

if ($Install) {
    Write-Host "installing..."
    & $idev -i $Out 2>&1 | Select-String "Install:|ERROR|Complete" | ForEach-Object { $_.Line }
}
