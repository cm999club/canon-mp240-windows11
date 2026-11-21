<# : -------------------------------------------------------------------------
@echo off
rem  Canon PIXMA MP240 su Windows 10 / 11 (64 bit) - doppio clic per avviare.
rem  Questo file e' insieme batch e PowerShell: la parte batch avvia PowerShell.
setlocal
set "MP240_SCRIPT=%~f0"
set "MP240_PKG=%~1"
title Canon PIXMA MP240 - Windows 10/11
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ([IO.File]::ReadAllText($env:MP240_SCRIPT))"
exit /b %errorlevel%
#>
# =============================================================================
#  Canon PIXMA MP240 - driver per Windows 10 / Windows 11 (64 bit)   v2.0
#  https://github.com/cm999club
# -----------------------------------------------------------------------------
#  Canon non rilascia driver per Windows 10/11, ma il driver ufficiale
#  "MP Driver Ver. 1.02" per Windows 8.1 x64 funziona: e' l'installer Canon
#  a bloccarsi. Questo script:
#    - scarica il pacchetto UFFICIALE dal server Canon (o usa quello che hai);
#    - verifica firma digitale Canon e impronta SHA-256;
#    - estrae e installa driver stampante + scanner (senza modificarli);
#    - disattiva la comunicazione bidirezionale (risolve l'errore 170
#      "La risorsa richiesta e' in uso" che blocca la stampa);
#    - riavvia lo spooler e stampa una pagina di prova.
#  Include anche: riparazione, diagnostica e disinstallazione.
#
#  Pagina ufficiale Canon del driver:
#    https://asia.canon/en/support/0100135901
#  Uso a proprio rischio, nessuna garanzia. Il driver resta di Canon Inc.
# =============================================================================

$ErrorActionPreference = 'Continue'
$Version     = '2.0'
$PrinterName = 'Canon MP240 series Printer'
$PkgMask     = 'md64-win-mp240*.exe'
$PkgName     = 'md64-win-mp240-1_02-ea24.exe'
$PkgUrl      = 'https://gdlp01.c-wss.com/gds/9/0100001359/03/md64-win-mp240-1_02-ea24.exe'
$PageUrl     = 'https://asia.canon/en/support/0100135901'
$PkgSha256   = '39D327C8C8DB66BE3888000F20EAA50902CB3A2663B54F999F065124E8773E57'
$PkgSize     = 26125712
$UsbId       = 'VID_04A9&PID_1732'
$Log         = Join-Path $env:TEMP 'CanonMP240_Win11.log'
$IT          = (Get-UICulture).TwoLetterISOLanguageName -eq 'it'

# ---------------------------------------------------------------- helpers ----
function T([string]$it, [string]$en) { if ($IT) { $it } else { $en } }
function Log([string]$m) { try { Add-Content -LiteralPath $Log -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $m) } catch {} }
function Say([string]$it, [string]$en, [string]$c = 'Gray') { $m = T $it $en; Write-Host $m -ForegroundColor $c; Log $m }
function Ok([string]$it, [string]$en)   { Say ("  [OK]  " + $it) ("  [OK]  " + $en) 'Green' }
function Warn([string]$it, [string]$en) { Say ("  [!]   " + $it) ("  [!]   " + $en) 'Yellow' }
function Err([string]$it, [string]$en)  { Say ("  [X]   " + $it) ("  [X]   " + $en) 'Red' }
function Step([string]$it, [string]$en) { Write-Host ''; Say ("== " + $it) ("== " + $en) 'Cyan' }
function Ask([string]$it, [string]$en, [string]$keys = 'SN') {
    # keys: first letter = default. Accepts S/Y as yes.
    $q = T $it $en
    while ($true) {
        $a = (Read-Host "$q [$($keys.ToCharArray() -join '/')]").Trim().ToUpper()
        if ($a -eq '') { return $keys[0].ToString() }
        if ($a -eq 'Y') { $a = 'S' }
        if ($keys.Contains($a) -and $a.Length -eq 1) { return $a }
    }
}
function Pause-Key { [void](Read-Host (T 'Premi INVIO per continuare' 'Press ENTER to continue')) }
function Run-Logged([string]$exe, [string[]]$argv) {
    Log ("> $exe " + ($argv -join ' '))
    $out = & $exe @argv 2>&1 | Out-String
    Log $out.TrimEnd()
    return $LASTEXITCODE
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-CanonUsb   { Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match [regex]::Escape($UsbId) } }
function Get-CanonPrinter { Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue }
function Get-CanonWmi   { Get-CimInstance Win32_Printer -Filter "Name='$PrinterName'" -ErrorAction SilentlyContinue }

# ------------------------------------------------------------ elevation ----
if (-not (Test-Admin)) {
    Write-Host (T 'Servono i permessi di amministratore: confermo la richiesta di Windows...' 'Administrator rights are required: please accept the Windows prompt...') -ForegroundColor Yellow
    $argLine = '/c ""' + $env:MP240_SCRIPT + '" "' + $env:MP240_PKG + '""'
    try { Start-Process -FilePath $env:ComSpec -ArgumentList $argLine -Verb RunAs | Out-Null }
    catch { Write-Host (T 'Permessi negati: impossibile continuare.' 'Elevation refused: cannot continue.') -ForegroundColor Red; Start-Sleep 4 }
    exit
}

# ------------------------------------------------------------- package ----
function Find-Package {
    $dirs = @()
    if ($env:MP240_PKG -and (Test-Path -LiteralPath $env:MP240_PKG -PathType Leaf)) { return (Get-Item -LiteralPath $env:MP240_PKG) }
    $dirs += Split-Path -Parent $env:MP240_SCRIPT
    $dirs += Join-Path $env:USERPROFILE 'Downloads'
    $dirs += Join-Path $env:USERPROFILE 'Desktop'
    $dirs += $env:TEMP
    foreach ($d in $dirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $f = Get-ChildItem -LiteralPath $d -Filter $PkgMask -File -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($f) { return $f }
    }
    return $null
}

function Download-Package {
    $destDir = Join-Path $env:USERPROFILE 'Downloads'
    if (-not (Test-Path -LiteralPath $destDir)) { $destDir = $env:TEMP }
    $dest = Join-Path $destDir $PkgName
    Say "Scarico il driver ufficiale dal server Canon (25 MB)..." "Downloading the official driver from Canon's server (25 MB)..."
    Say "  $PkgUrl" "  $PkgUrl" 'DarkGray'
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (Test-Path $curl) {
        & $curl -L --fail --retry 3 -# -o $dest $PkgUrl
        $okDl = ($LASTEXITCODE -eq 0)
    } else {
        try { [Net.ServicePointManager]::SecurityProtocol = 'Tls12'; Invoke-WebRequest -Uri $PkgUrl -OutFile $dest -UseBasicParsing; $okDl = $true } catch { $okDl = $false }
    }
    if ($okDl -and (Test-Path -LiteralPath $dest)) { Ok "Scaricato in $dest" "Saved to $dest"; return (Get-Item -LiteralPath $dest) }
    Err 'Download non riuscito (connessione o server Canon non raggiungibile).' 'Download failed (no connection or Canon server unreachable).'
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue }
    return $null
}

function Get-Package {
    $pkg = Find-Package
    if ($pkg) { Ok "Pacchetto trovato: $($pkg.FullName)" "Package found: $($pkg.FullName)"; return $pkg }
    Warn "Non trovo il pacchetto Canon ($PkgName)." "Canon package not found ($PkgName)."
    Write-Host ''
    Write-Host (T '  [D] Scaricalo ora dal server ufficiale Canon (consigliato)' '  [D] Download it now from the official Canon server (recommended)')
    Write-Host (T '  [P] Apri la pagina ufficiale Canon nel browser (scarichi tu)' '  [P] Open the official Canon page in your browser (manual download)')
    Write-Host (T '  [N] Annulla' '  [N] Cancel')
    switch (Ask 'Scelta' 'Choice' 'DPN') {
        'D' { return (Download-Package) }
        'P' {
            Start-Process $PageUrl
            Say "Pagina aperta: $PageUrl" "Page opened: $PageUrl"
            Say "Spunta la casella del disclaimer, premi Download e salva il file in Download." "Tick the disclaimer box, click Download and save the file to Downloads."
            Pause-Key
            $pkg = Find-Package
            if ($pkg) { Ok "Pacchetto trovato: $($pkg.FullName)" "Package found: $($pkg.FullName)" } else { Err 'Ancora non trovato.' 'Still not found.' }
            return $pkg
        }
        default { return $null }
    }
}

function Test-Package($pkg) {
    $sig = Get-AuthenticodeSignature -LiteralPath $pkg.FullName
    $signer = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { '' }
    Log "Signature: $($sig.Status) | $signer"
    if ($sig.Status -ne 'Valid' -or $signer -notmatch 'O=Canon Inc\.') {
        Err 'Il file NON ha una firma digitale Canon valida: per sicurezza mi fermo.' 'The file does NOT carry a valid Canon digital signature: stopping for safety.'
        return $false
    }
    Ok 'Firma digitale Canon Inc. valida' 'Valid Canon Inc. digital signature'
    $hash = (Get-FileHash -LiteralPath $pkg.FullName -Algorithm SHA256).Hash
    Log "SHA256: $hash"
    if ($hash -eq $PkgSha256) { Ok 'Impronta SHA-256 identica al pacchetto ufficiale 1.02' 'SHA-256 matches the official 1.02 package' }
    else { Warn 'Versione/regione diversa dal pacchetto di riferimento, ma firmata Canon: proseguo.' 'Different version/region than the reference package, but Canon-signed: continuing.' }
    return $true
}

# -------------------------------------------------------- printer steps ----
function Wait-Printer([int]$seconds = 60) {
    $t = 0
    while (-not (Get-CanonPrinter) -and $t -lt $seconds) {
        Start-Sleep 3; $t += 3
        if ($t % 15 -eq 0) { & pnputil.exe /scan-devices *> $null }
    }
    return [bool](Get-CanonPrinter)
}

function Disable-Bidi {
    Start-Process -FilePath 'rundll32.exe' -ArgumentList ('printui.dll,PrintUIEntry /Xs /n "' + $PrinterName + '" attributes -EnableBidi') -Wait
    Start-Sleep 2
    $w = Get-CanonWmi
    if ($w -and -not $w.EnableBIDI) { Ok 'Comunicazione bidirezionale disattivata' 'Bidirectional support disabled'; return $true }
    Warn 'Non sono riuscito a disattivare la comunicazione bidirezionale.' 'Could not disable bidirectional support.'
    Warn 'Fallo a mano: Proprieta stampante > Porte > togli "Attiva supporto bidirezionale".' 'Do it manually: Printer properties > Ports > untick "Enable bidirectional support".'
    return $false
}

function Restart-Spooler {
    try { Restart-Service -Name Spooler -Force -ErrorAction Stop; Start-Sleep 3; Ok 'Spooler di stampa riavviato' 'Print spooler restarted' }
    catch { Err "Riavvio spooler non riuscito: $($_.Exception.Message)" "Spooler restart failed: $($_.Exception.Message)" }
}

function Clear-StuckJobs {
    $jobs = @(Get-PrintJob -PrinterName $PrinterName -ErrorAction SilentlyContinue)
    if ($jobs.Count -eq 0) { Ok 'Coda di stampa vuota' 'Print queue is empty'; return }
    Warn "In coda ci sono $($jobs.Count) lavori:" "There are $($jobs.Count) jobs in the queue:"
    $jobs | ForEach-Object { Write-Host ("        #{0}  {1}  [{2}]" -f $_.Id, $_.DocumentName, $_.JobStatus) }
    if ((Ask 'Li cancello per sbloccare la coda? (andranno ristampati)' 'Delete them to unblock the queue? (you will need to print them again)' 'SN') -eq 'S') {
        $jobs | ForEach-Object { try { Remove-PrintJob -InputObject $_ -ErrorAction Stop } catch {} }
        Ok 'Coda svuotata' 'Queue cleared'
    }
}

function Print-TestPage {
    Start-Process -FilePath 'rundll32.exe' -ArgumentList ('printui.dll,PrintUIEntry /k /n "' + $PrinterName + '"') -Wait
    Say 'Pagina di prova inviata: controlla il vassoio.' 'Test page sent: check the output tray.' 'Green'
    Start-Sleep 15
    $bad = @(Get-PrintJob -PrinterName $PrinterName -ErrorAction SilentlyContinue | Where-Object { "$($_.JobStatus)" -match 'Error' })
    if ($bad.Count) { Warn 'Il lavoro risulta in errore: usa l''opzione 2 (Ripara) e controlla carta e cartucce.' 'The job is in error: use option 2 (Repair) and check paper and cartridges.' }
}

# ------------------------------------------------------------- actions ----
function Do-Install {
    Step 'Controlli preliminari' 'Pre-checks'
    if (-not [Environment]::Is64BitOperatingSystem) { Err 'Serve Windows a 64 bit.' '64-bit Windows is required.'; return }
    $os = Get-CimInstance Win32_OperatingSystem
    Ok "$($os.Caption) (build $($os.BuildNumber)) 64 bit" "$($os.Caption) (build $($os.BuildNumber)) 64-bit"
    if (Get-CanonUsb) { Ok 'Canon MP240 collegata via USB' 'Canon MP240 connected via USB' }
    else {
        Warn 'La MP240 non risulta collegata.' 'The MP240 does not appear to be connected.'
        Say  '      Accendila e collega il cavo USB (meglio una porta diretta, non un hub).' '      Turn it on and plug in the USB cable (a direct port, not a hub).'
        Pause-Key
        if (Get-CanonUsb) { Ok 'Stampante rilevata' 'Printer detected' } else { Warn 'Ancora non rilevata: installo comunque i driver.' 'Still not detected: installing the drivers anyway.' }
    }

    Step 'Pacchetto driver ufficiale Canon' 'Official Canon driver package'
    $pkg = Get-Package
    if (-not $pkg) { Err 'Nessun pacchetto: installazione annullata.' 'No package: installation cancelled.'; return }
    if (-not (Test-Package $pkg)) { return }

    Step 'Estrazione' 'Extracting'
    $work = Join-Path $env:TEMP ('CanonMP240_' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $rc = Run-Logged (Join-Path $env:SystemRoot 'System32\tar.exe') @('-xf', $pkg.FullName, '-C', $work)
    $prInf = Get-ChildItem -LiteralPath $work -Recurse -Filter 'MP240PR.inf' -File | Select-Object -First 1
    $scInf = Get-ChildItem -LiteralPath $work -Recurse -Filter 'MP240SC.inf' -File | Select-Object -First 1
    if (-not $prInf) { Err "Estrazione fallita (codice $rc) o pacchetto sbagliato." "Extraction failed (code $rc) or wrong package."; return }
    Ok 'Driver estratto' 'Driver extracted'

    Step 'Installazione driver' 'Installing drivers'
    $okCodes = 0, 259, 3010
    $rc = Run-Logged 'pnputil.exe' @('/add-driver', $prInf.FullName, '/install')
    if ($okCodes -contains $rc) { Ok 'Driver stampante installato' 'Printer driver installed' } else { Err "pnputil stampante: codice $rc (vedi log)" "pnputil printer: code $rc (see log)" }
    if ($scInf) {
        $rc = Run-Logged 'pnputil.exe' @('/add-driver', $scInf.FullName, '/install')
        if ($okCodes -contains $rc) { Ok 'Driver scanner installato' 'Scanner driver installed' } else { Warn "pnputil scanner: codice $rc (vedi log)" "pnputil scanner: code $rc (see log)" }
    }
    & pnputil.exe /scan-devices *> $null
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue

    Step 'Creazione stampante' 'Creating the printer'
    Say '  Attendo che Windows crei la stampante (max 60 s)...' '  Waiting for Windows to create the printer (up to 60 s)...'
    if (-not (Wait-Printer 60)) {
        Warn 'La stampante non e'' ancora comparsa.' 'The printer has not appeared yet.'
        Say  '      Scollega e ricollega il cavo USB (stampante accesa), poi premi INVIO.' '      Unplug and replug the USB cable (printer on), then press ENTER.'
        Pause-Key
        if (-not (Wait-Printer 45)) {
            Err 'Windows non ha creato la stampante. I driver sono installati: ricollega la stampante e usa l''opzione 2 (Ripara).' 'Windows did not create the printer. Drivers are installed: reconnect the printer and use option 2 (Repair).'
            return
        }
    }
    Ok "Stampante creata: $PrinterName" "Printer created: $PrinterName"

    Step 'Correzione errore 170 e riavvio spooler' 'Fixing error 170 and restarting the spooler'
    [void](Disable-Bidi)
    Restart-Spooler

    Write-Host ''
    Say '*** Installazione completata! ***' '*** Installation complete! ***' 'Green'
    if ((Ask 'Stampo una pagina di prova?' 'Print a test page?' 'SN') -eq 'S') { Print-TestPage }
}

function Do-Repair {
    Step 'Riparazione stampa' 'Print repair'
    if (-not (Get-CanonPrinter)) {
        Warn 'La stampante non e'' installata: cerco di farla comparire...' 'The printer is not installed: trying to detect it...'
        & pnputil.exe /scan-devices *> $null
        if (-not (Wait-Printer 30)) { Err 'Stampante non trovata: usa prima l''opzione 1 (Installa).' 'Printer not found: run option 1 (Install) first.'; return }
    }
    Clear-StuckJobs
    [void](Disable-Bidi)
    Restart-Spooler
    if ((Ask 'Stampo una pagina di prova?' 'Print a test page?' 'SN') -eq 'S') { Print-TestPage }
}

function Do-Status {
    Step 'Diagnostica' 'Diagnostics'
    $os = Get-CimInstance Win32_OperatingSystem
    Say "  Sistema      : $($os.Caption) build $($os.BuildNumber)" "  System       : $($os.Caption) build $($os.BuildNumber)"
    if (Get-CanonUsb) { Ok 'USB: MP240 collegata' 'USB: MP240 connected' } else { Warn 'USB: MP240 non collegata' 'USB: MP240 not connected' }
    $drv = Get-PrinterDriver -Name $PrinterName -ErrorAction SilentlyContinue
    if ($drv) { Ok 'Driver stampante installato' 'Printer driver installed' } else { Warn 'Driver stampante non installato' 'Printer driver not installed' }
    $scan = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match ([regex]::Escape($UsbId) + '&MI_00') }
    if ($scan) { if ($scan.Status -eq 'OK') { Ok 'Scanner pronto' 'Scanner ready' } else { Warn "Scanner: $($scan.Status)" "Scanner: $($scan.Status)" } }
    $p = Get-CanonPrinter
    if ($p) {
        Ok "Stampante: $($p.Name) su $($p.PortName)" "Printer: $($p.Name) on $($p.PortName)"
        $w = Get-CanonWmi
        if ($w.EnableBIDI) { Warn 'Bidirezionale ATTIVO (puo'' causare errore 170): usa l''opzione 2' 'Bidirectional ON (may cause error 170): use option 2' } else { Ok 'Bidirezionale disattivato' 'Bidirectional disabled' }
        $jobs = @(Get-PrintJob -PrinterName $PrinterName -ErrorAction SilentlyContinue)
        if ($jobs.Count) { Warn "Lavori in coda: $($jobs.Count)" "Jobs in queue: $($jobs.Count)" } else { Ok 'Coda vuota' 'Queue empty' }
    } else { Warn 'Stampante non presente in Windows' 'Printer not present in Windows' }
    $ev = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-PrintService/Admin'; StartTime = (Get-Date).AddDays(-1) } -ErrorAction SilentlyContinue |
          Where-Object { $_.Message -match 'MP240' } | Select-Object -First 3
    foreach ($e in $ev) { Warn ("Evento {0:dd/MM HH:mm}: {1}" -f $e.TimeCreated, ($e.Message -split "`n")[0]) ("Event {0:dd/MM HH:mm}: {1}" -f $e.TimeCreated, ($e.Message -split "`n")[0]) }
    Say "  Log: $Log" "  Log: $Log" 'DarkGray'
}

function Do-Uninstall {
    Step 'Disinstallazione' 'Uninstall'
    if ((Ask 'Rimuovo stampante e driver Canon MP240 da questo PC?' 'Remove the Canon MP240 printer and drivers from this PC?' 'NS') -ne 'S') { return }
    if (Get-CanonPrinter) { Remove-Printer -Name $PrinterName -ErrorAction SilentlyContinue; Ok 'Stampante rimossa' 'Printer removed' }
    Restart-Spooler
    Remove-PrinterDriver -Name $PrinterName -ErrorAction SilentlyContinue
    $oem = Get-WindowsDriver -Online -ErrorAction SilentlyContinue | Where-Object { $_.OriginalFileName -match 'mp240(pr|sc)\.inf$' }
    foreach ($d in $oem) {
        $rc = Run-Logged 'pnputil.exe' @('/delete-driver', $d.Driver, '/uninstall', '/force')
        if ($rc -eq 0) { Ok "Rimosso $($d.Driver) ($(Split-Path -Leaf $d.OriginalFileName))" "Removed $($d.Driver) ($(Split-Path -Leaf $d.OriginalFileName))" }
        else { Warn "Rimozione $($d.Driver): codice $rc" "Removing $($d.Driver): code $rc" }
    }
    if (-not $oem) { Ok 'Nessun driver MP240 nel driver store' 'No MP240 driver in the driver store' }
    Say 'Disinstallazione completata. Scollega la stampante.' 'Uninstall complete. Unplug the printer.' 'Green'
}

# ---------------------------------------------------------------- menu ----
Log "===== v$Version start ====="
while ($true) {
    Clear-Host
    Write-Host '=================================================================' -ForegroundColor Cyan
    Write-Host "  Canon PIXMA MP240 - Windows 10 / 11 (64 bit)        v$Version" -ForegroundColor Cyan
    Write-Host '  github.com/cm999club' -ForegroundColor DarkCyan
    Write-Host '=================================================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host (T '  1  Installa driver stampante + scanner (consigliato)' '  1  Install printer + scanner drivers (recommended)')
    Write-Host (T '  2  Ripara stampa (errore 170, coda bloccata, non stampa)' '  2  Repair printing (error 170, stuck queue, not printing)')
    Write-Host (T '  3  Stampa pagina di prova' '  3  Print a test page')
    Write-Host (T '  4  Diagnostica' '  4  Diagnostics')
    Write-Host (T '  5  Apri la pagina ufficiale Canon del driver' '  5  Open the official Canon driver page')
    Write-Host (T '  6  Disinstalla' '  6  Uninstall')
    Write-Host (T '  0  Esci' '  0  Exit')
    Write-Host ''
    $c = (Read-Host (T 'Scelta' 'Choice')).Trim()
    switch ($c) {
        '1' { Do-Install }
        '2' { Do-Repair }
        '3' { if (Get-CanonPrinter) { Print-TestPage } else { Warn 'Stampante non installata: usa l''opzione 1.' 'Printer not installed: use option 1.' } }
        '4' { Do-Status }
        '5' { Start-Process $PageUrl; Say "Aperta: $PageUrl" "Opened: $PageUrl" }
        '6' { Do-Uninstall }
        '0' { Log '===== exit ====='; exit 0 }
        default { $c = '' }
    }
    if ($c -eq '') { continue }
    Write-Host ''
    Pause-Key
}
