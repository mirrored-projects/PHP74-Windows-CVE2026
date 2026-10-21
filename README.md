# PHP 7.4 für Windows mit CVE-2026-109618 / CVE-2026-109619-Backport

PHP 7.4 ist End-of-Life; windows.php.net liefert keine Builds mehr. Das PHP-Projekt hat den Fix für
CVE-2026-109618 und CVE-2026-109619 trotzdem als minimalen Quell-Backport veröffentlicht
(Branch `PHP-7.4-CVE-2026-109618-109619`, Commit `712e60f9ed`, Autor Arnaud Le Blanc). Dieses Repo baut daraus
Windows-Binaries, so wie windows.php.net es tun würde.

**Nur diese eine Lücke ist gefixt.** Alle anderen seit 2022 in 7.4 gefundenen Probleme bleiben. Das ist eine
Überbrückung, kein Grund, auf 7.4 zu bleiben.

## Was gebaut wird

| Artefakt | Einsatz |
|---|---|
| `php-7.4.33-nts-Win32-vc15-x64.zip` | IIS FastCGI (`php-cgi.exe`), CLI |
| `php-7.4.33-Win32-vc15-x64.zip` | Apache-Modul (`php7apache2_4.dll`), XAMPP |

configure entspricht dem offiziellen Build (`--enable-snapshot-build --enable-com-dotnet=shared --without-analyzer`,
NTS: `--disable-zts`) – ohne OCI8/PDO_OCI (Oracle Instant Client) und ohne PGO. Extensions: alle, die die
offiziellen Deps hergeben (bcmath, curl, gd, intl, mbstring, mysqli, openssl, pdo_mysql, soap, zip, …).

Der Tarball-SHA256 ist in `build.ps1` gepinnt, der Patch liegt unter `patches/` im Repo.

## Build auslösen

- **Release:** Tag pushen, z. B. `git tag v7.4.33-cve.1 && git push --tags` → Workflow baut NTS+TS und legt ein
  GitHub-Release mit ZIPs, `.sha256`-Dateien, Modullisten und `SHA256SUMS` an.
- **Test-Build ohne Release:** Actions → *Run workflow* → Version eintragen, „Release“ aus → Artefakte am Job.

Dauer ca. 40 Minuten je Variante (davon ~10 Minuten VS2017-Build-Tools-Installation auf dem Runner).

## Lokal bauen (Windows, PowerShell als Administrator)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\bootstrap.ps1                       # einmalig: VS2017 Build Tools, 7-Zip, Git, php-sdk
.\build.ps1 -Version 7.4.33 -Nts      # IIS
.\build.ps1 -Version 7.4.33           # Apache/XAMPP
```

Ergebnis in `C:\out`.

## Auf IIS einspielen (versioniertes Verzeichnis, Rollback in einer Minute)

```powershell
# 1. Entpacken neben die alte Version
Expand-Archive php-7.4.33-nts-Win32-vc15-x64.zip -DestinationPath C:\Library\PHP\v7.4.33
Copy-Item C:\Library\PHP\v7.4.5\php.ini C:\Library\PHP\v7.4.33\php.ini      # eigene php.ini übernehmen
C:\Library\PHP\v7.4.33\php.exe -v
C:\Library\PHP\v7.4.33\php.exe -c C:\Library\PHP\v7.4.33\php.ini -m         # muss der alten Modulliste entsprechen

# 2. IIS: neue FastCGI-Anwendung registrieren und Handler umhängen
$A = "$env:windir\system32\inetsrv\appcmd.exe"
& $A set config /section:system.webServer/fastCgi "/+[fullPath='C:\Library\PHP\v7.4.33\php-cgi.exe',instanceMaxRequests='10000']" /commit:apphost
& $A set config /section:system.webServer/fastCgi "/+[fullPath='C:\Library\PHP\v7.4.33\php-cgi.exe'].environmentVariables.[name='PHP_FCGI_MAX_REQUESTS',value='10000']" /commit:apphost
& $A set config /section:system.webServer/fastCgi "/+[fullPath='C:\Library\PHP\v7.4.33\php-cgi.exe'].environmentVariables.[name='PHPRC',value='C:\Library\PHP\v7.4.33']" /commit:apphost
& $A list config /section:system.webServer/handlers | Select-String 'php-cgi'     # Handler-Namen ablesen
& $A set config /section:system.webServer/handlers "/[name='PHP_via_FastCGI'].scriptProcessor:C:\Library\PHP\v7.4.33\php-cgi.exe" /commit:apphost
Get-Process php-cgi -ErrorAction SilentlyContinue | Stop-Process -Force

# 3. Prüfen: phpinfo() muss "Build Date" von heute und das PHP-Verzeichnis v7.4.33 zeigen
```

Handler-Name und Site-Scope (`/commit:apphost` vs. Site-`web.config`) je nach bestehender Konfiguration anpassen.
Rollback: `scriptProcessor` zurück auf `v7.4.5`, php-cgi-Prozesse beenden.

## Prüfen, dass der Fix drin ist

Die Versionsnummer bleibt 7.4.33 – der Nachweis ist das Build-Datum in `php -v` / `phpinfo()` und die
`SHA256SUMS` des Releases. Funktional: `build.ps1` führt eine OOM-Probe aus (Speicher bis zum `memory_limit`
füllen); ein gepatchtes PHP beendet den Request sauber und gibt `probe-ok` aus.

## Quellen

- https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w (CVE-2026-109618)
- https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp (CVE-2026-109619)
- https://github.com/php/php-src/tree/PHP-7.4-CVE-2026-109618-109619 (Backport-Branch)
- https://github.com/mpyw/php-eol-CVE-2026-109618-109619 (Patch-Dateien, Linux-Docker-Images)
- https://wiki.php.net/internals/windows/stepbystepbuild_sdk_2 (PHP-SDK-Buildanleitung)
