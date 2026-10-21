<#
  bootstrap.ps1 – macht einen Windows-Rechner (VM, Laptop, GitHub-Runner) zum PHP-Builder. Idempotent.
  PowerShell als Administrator:  Set-ExecutionPolicy -Scope Process Bypass -Force; .\bootstrap.ps1
  Installiert: VS2017 Build Tools (vc15, für PHP 7.4) nach C:\BuildTools, optional VS2019 Build Tools (vs16, für 8.0/8.1),
               MinGit + 7-Zip portable (falls nicht vorhanden), php-sdk-binary-tools nach C:\php-sdk
#>
param([switch]$WithVs16)
$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
New-Item -ItemType Directory -Force -Path C:\Tools, C:\out, C:\TEMP | Out-Null

function Install-BuildTools ($url, $path) {
  if (Test-Path "$path\VC\Auxiliary\Build\vcvarsall.bat") { Write-Host "Build Tools vorhanden: $path"; return }
  $exe = "C:\TEMP\vs_buildtools_$(Split-Path $path -Leaf).exe"
  Invoke-WebRequest $url -OutFile $exe
  $p = Start-Process $exe -Wait -PassThru -ArgumentList '--quiet', '--wait', '--norestart', '--nocache', '--installPath', $path,
       '--add', 'Microsoft.VisualStudio.Workload.VCTools', '--includeRecommended',
       '--add', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
       '--add', 'Microsoft.VisualStudio.Component.Windows10SDK.17763'
  if ($p.ExitCode -notin 0, 3010) { throw "vs_buildtools exit $($p.ExitCode)" }
  Write-Host "Build Tools installiert: $path"
}
Install-BuildTools 'https://aka.ms/vs/15/release/vs_buildtools.exe' 'C:\BuildTools'            # VS2017 / vc15
if ($WithVs16) { Install-BuildTools 'https://aka.ms/vs/16/release/vs_buildtools.exe' 'C:\BuildTools16' }  # VS2019 / vs16

if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
  Invoke-WebRequest 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/MinGit-2.47.1-64-bit.zip' -OutFile C:\TEMP\mingit.zip
  Expand-Archive C:\TEMP\mingit.zip -DestinationPath C:\Tools\git -Force
  $env:Path += ';C:\Tools\git\cmd'
}
if (-not (Get-Command 7z.exe, 7zr.exe -ErrorAction SilentlyContinue)) {
  Invoke-WebRequest 'https://www.7-zip.org/a/7zr.exe' -OutFile C:\Tools\7zr.exe
  $env:Path += ';C:\Tools'
}
[Environment]::SetEnvironmentVariable('Path', ($env:Path -replace ';;', ';'), 'Machine')

if (-not (Test-Path C:\php-sdk\phpsdk-vc15-x64.bat)) {
  git clone --depth 1 --branch php-sdk-2.3.0 https://github.com/php/php-sdk-binary-tools.git C:\php-sdk
}
Write-Host "`nBereit. Build z. B. mit:`n  .\build.ps1 -Version 7.4.33 -Apache -ApacheZipUrl <url>   (XAMPP, TS)`n  .\build.ps1 -Version 7.4.33 -Nts                         (IIS)"
