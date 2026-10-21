<#
  build.ps1 – PHP 7.4.x für Windows (x64, vc15) mit dem CVE-2026-109618/109619-Backport bauen.
  Vorher: bootstrap.ps1 (VS2017 Build Tools, 7-Zip, Git, php-sdk). Parameter:
    -Version 7.4.33     PHP-Version; der SHA256 des Tarballs muss in $KnownSha stehen (sonst -Sha256 angeben)
    -Nts                Non-Thread-Safe (IIS FastCGI) – Default: TS (Apache-Modul)
    -Sha256 <hex>       Tarball-Hash für eine Version, die nicht in $KnownSha steht
    -Extra "a,b"        zusätzliche configure-Flags (z. B. "--disable-snmp")
  configure entspricht dem offiziellen windows.php.net-Build (ohne OCI8/PDO_OCI und ohne PGO).
  Ergebnis: C:\out\php-<ver>[-nts]-Win32-vc15-x64.zip + .sha256 + build.log
#>
param(
  [string]$Version = '7.4.33',
  [switch]$Nts,
  [string]$Sha256 = '',
  [string]$Extra = ''
)
$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
$KnownSha = @{ '7.4.33' = '5a2337996f07c8a097e03d46263b5c98d2c8e355227756351421003bea8f463e' }
if (-not $Sha256) { $Sha256 = $KnownSha[$Version] }
if (-not $Sha256) { throw "Kein SHA256 für php-$Version bekannt – -Sha256 angeben (Wert von https://www.php.net/releases/)" }
$branch = ($Version -split '\.')[0..1] -join '.'
if ($branch -ne '7.4') { throw 'Dieses Repo baut nur 7.4 (vc15). Für 8.0/8.1 wäre vs16 nötig.' }
$crt = 'vc15'
$sz = (Get-Command 7zr.exe, 7z.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $sz) { throw '7-Zip (7z.exe/7zr.exe) nicht im PATH' }
$repo  = $PSScriptRoot
$patch = Join-Path $repo "patches\$branch-CVE-2026-109618-109619.patch"
if (-not (Test-Path $patch)) { throw "Patch fehlt: $patch" }
$tree = "C:\php-sdk\phpdev\$crt\x64"
$src  = "$tree\php-$Version-src"
$variant = if ($Nts) { 'nts' } else { 'ts' }
New-Item -ItemType Directory -Force -Path C:\out, $tree | Out-Null
Start-Transcript -Path "C:\out\build-$Version-$variant.log" | Out-Null
Write-Host "== PHP $Version $crt x64 $($variant.ToUpper()) =="

# --- Quelle holen, Hash prüfen, Patch anwenden --------------------------------
Set-Location $tree
if (-not (Test-Path $src)) {
  $tgz = "php-$Version.tar.gz"
  Invoke-WebRequest "https://www.php.net/distributions/$tgz" -OutFile $tgz
  $h = (Get-FileHash $tgz -Algorithm SHA256).Hash.ToLower()
  if ($h -ne $Sha256.ToLower()) { throw "SHA256 stimmt nicht: $h (erwartet $Sha256)" }
  Write-Host "Tarball-Hash OK: $h"
  & $sz x $tgz -y | Out-Null; & $sz x "php-$Version.tar" -y | Out-Null
  Rename-Item "php-$Version" "php-$Version-src"
  Set-Location $src
  # C:\php-sdk ist selbst ein Git-Klon – ohne Ceiling überspringt git apply alle Hunks still (exit 0)
  $env:GIT_CEILING_DIRECTORIES = $tree
  git apply --check $patch; if ($LASTEXITCODE) { throw "Patch passt nicht auf php-$Version" }
  git apply $patch;         if ($LASTEXITCODE) { throw 'git apply fehlgeschlagen' }
  if (-not (Select-String -Path Zend\zend_alloc.c -Pattern 'zend_mm_safe_error_ex' -Quiet)) { throw 'Patch nicht im Quellbaum angekommen' }
  Write-Host "Patch angewendet: $(Split-Path $patch -Leaf)"
}
Set-Location $src

# --- Build in der SDK-Shell (nicht-interaktiv via -t) -------------------------
$zts   = if ($Nts) { '--disable-zts' } else { '' }
$extra = (($Extra -split ',') | Where-Object { $_ }) -join ' '
$cfg   = "--enable-snapshot-build --disable-debug-pack --enable-com-dotnet=shared --without-analyzer $zts $extra".Trim()
$task = @"
@echo off
cd /d $src
call phpsdk_deps --update --branch $branch || exit /b 1
call buildconf --force || exit /b 1
call configure $cfg || exit /b 1
nmake || exit /b 1
nmake snap || exit /b 1
"@
Set-Content -Path "$tree\task.bat" -Value $task -Encoding ASCII
Write-Host "configure $cfg"
& cmd /c "C:\php-sdk\phpsdk-$crt-x64.bat -t $tree\task.bat"
if ($LASTEXITCODE) { throw "Build fehlgeschlagen (exit $LASTEXITCODE)" }

# --- Ergebnis -----------------------------------------------------------------
$outDir = @("$src\x64\Release", "$src\Release") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Nts) { $outDir = @("$src\x64\Release_TS", "$src\Release_TS") | Where-Object { Test-Path $_ } | Select-Object -First 1 }
$zip = Get-ChildItem $outDir -Filter "php-$Version*-Win32-*.zip" | Where-Object { $_.Name -notmatch 'debug|devel|test' } | Select-Object -First 1
if (-not $zip) { throw "Kein Distributions-ZIP in $outDir" }
Copy-Item $zip.FullName C:\out\
$sum = (Get-FileHash "C:\out\$($zip.Name)" -Algorithm SHA256).Hash.ToLower()
"$sum  $($zip.Name)" | Set-Content "C:\out\$($zip.Name).sha256" -Encoding ASCII
& "$outDir\php.exe" -v
& "$outDir\php.exe" -m | Set-Content "C:\out\php-$Version-$variant-modules.txt" -Encoding ASCII
# Mitigations-Probe: Patch macht OOM zum sanften Fehler statt longjmp – php.exe darf dabei nicht abstürzen
$probe = '<?php ini_set("memory_limit","8M"); $a=[]; try { while(true) $a[]=str_repeat("x",1024*1024); } catch (Throwable $e) {} echo "probe-ok\n";'
$probe | Set-Content "$env:TEMP\probe.php" -Encoding ASCII
$p = & "$outDir\php.exe" -n -d memory_limit=8M "$env:TEMP\probe.php" 2>&1; Write-Host "OOM-Probe: $p (exit $LASTEXITCODE)"
Write-Host "`nFertig: C:\out\$($zip.Name)`nSHA256: $sum"
Stop-Transcript | Out-Null
