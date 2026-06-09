# =====================================================================
# Fix IE COM registration hijacked by (now-uninstalled) 360 browser.
# Symptom: edge://compat/iediagnostic -> "cannot create IE process",
# error 0x8000FFFF. Cause: LocalServer32 of IE COM CLSID still points to
# 360se.exe (gone), so Edge IE mode cannot spawn iexplore.exe.
# This script: backs up, diagnoses, restores to microsoft iexplore.exe.
# Self-elevates. ASCII only. Output: fix_ie_com_log.txt
# =====================================================================
param([string]$LogPath = "")

$selfPath = $MyInvocation.MyCommand.Path
$selfDir  = Split-Path -Parent $selfPath
if (-not $LogPath) { $LogPath = Join-Path $selfDir "fix_ie_com_log.txt" }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Not admin. Relaunching elevated (approve UAC)..." -ForegroundColor Yellow
    Write-Host "Log -> $LogPath" -ForegroundColor Cyan
    try {
        Start-Process powershell -Verb RunAs -ArgumentList @(
            "-ExecutionPolicy","Bypass","-File","`"$selfPath`"","-LogPath","`"$LogPath`"")
    } catch { Write-Host "Elevation failed: $($_.Exception.Message)" -ForegroundColor Red }
    Read-Host "Press Enter to close this window"
    return
}

$Out = $LogPath
$log = New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try { $log.ToString() | Out-File -FilePath $Out -Encoding UTF8 } catch {} }

W "Fix IE COM registration (ADMIN)  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Machine: $env:COMPUTERNAME  User: $env:USERNAME"

$CLSID = "{0002DF01-0000-0000-C000-000000000046}"
# the registry locations where IE COM LocalServer32 lives
$targets = @(
  "Registry::HKEY_CLASSES_ROOT\CLSID\$CLSID\LocalServer32",
  "Registry::HKEY_CLASSES_ROOT\WOW6432Node\CLSID\$CLSID\LocalServer32",
  "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\$CLSID\LocalServer32",
  "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\WOW6432Node\CLSID\$CLSID\LocalServer32"
)

# pick the real iexplore.exe (prefer 64-bit Program Files)
$iexplore = $null
foreach($p in @("C:\Program Files\Internet Explorer\iexplore.exe",
                "C:\Program Files (x86)\Internet Explorer\iexplore.exe")){
    if(Test-Path $p){ $iexplore=$p; break }
}
W ""
W "==== target iexplore.exe ===="
if(-not $iexplore){ W "  FATAL: iexplore.exe not found, cannot fix."; Flush; Read-Host "Enter"; return }
W "  will set LocalServer32 -> `"$iexplore`""
$desired = "`"$iexplore`""

# 1. DIAGNOSE current values
W ""
W "==== 1. current LocalServer32 values (before) ===="
$before = @{}
foreach($t in $targets){
    if(Test-Path $t){
        try {
            $v = (Get-ItemProperty -Path $t -Name '(default)' -EA Stop).'(default)'
            $before[$t] = $v
            $flag = if($v -match '360'){ "  <-- HIJACKED by 360" } elseif($v -match 'iexplore'){ "  (ok)" } else { "  (?)" }
            W "  [$t]"
            W "     = $v$flag"
        } catch { W "  [$t] read error: $($_.Exception.Message)" }
    } else { W "  [$t] (key not present)" }
}
Flush

# 2. BACKUP (export the CLSID tree to a .reg file)
W ""
W "==== 2. backup before changing ===="
$bak = Join-Path $selfDir ("ie_com_backup_{0}.reg" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
foreach($root in @("HKEY_CLASSES_ROOT\CLSID\$CLSID","HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\$CLSID")){
    $tmp = "$bak.part"
    $r = reg.exe export $root $tmp /y 2>&1
    if(Test-Path $tmp){
        Get-Content $tmp | Add-Content $bak
        Remove-Item $tmp -Force
        W "  backed up: $root"
    } else { W "  backup skip (key may not exist): $root" }
}
W "  backup file: $bak"
Flush

# 3. REPAIR: set every LocalServer32 to real iexplore.exe
W ""
W "==== 3. repair (set LocalServer32 -> iexplore.exe) ===="
foreach($t in $targets){
    try {
        # create the key path if missing
        if(-not (Test-Path $t)){ New-Item -Path $t -Force | Out-Null; W "  created key: $t" }
        # set the (default) value reliably
        Set-Item -Path $t -Value $desired -EA Stop
        W "  set: $t"
    } catch {
        # fallback to reg.exe (most robust for default value)
        $regPath = $t -replace '^Registry::',''
        $r = reg.exe add "$regPath" /ve /d $desired /f 2>&1
        W "  set via reg.exe: $t -> $($r | Out-String).Trim()"
    }
}
Flush

# 4. VERIFY (after)
W ""
W "==== 4. verify (after) ===="
$allOk = $true
foreach($t in $targets){
    if(Test-Path $t){
        $v = (Get-ItemProperty -Path $t -Name '(default)' -EA SilentlyContinue).'(default)'
        $ok = ($v -eq $desired)
        if(-not $ok){ $allOk = $false }
        W "  [$(if($ok){'PASS'}else{'FAIL'})] $t = $v"
    }
}
Flush

# 5. SELF-CHECK
W ""
W "==== SELF-CHECK ===="
$noHijack = $true
foreach($t in $targets){
    if(Test-Path $t){
        $v=(Get-ItemProperty -Path $t -Name '(default)' -EA SilentlyContinue).'(default)'
        if($v -match '360'){ $noHijack=$false }
    }
}
W "  [$(if($allOk){'PASS'}else{'FAIL'})] all LocalServer32 point to iexplore.exe"
W "  [$(if($noHijack){'PASS'}else{'FAIL'})] no remaining 360 reference"
if($allOk -and $noHijack){
    W "  >> PASS. Next:"
    W "     1. RESTART the PC (so COM re-registers cleanly)."
    W "     2. Open Edge -> edge://compat/iediagnostic -> click the retry button."
    W "        'Attempt to start IE mode' should now SUCCEED (no 0x8000FFFF)."
    W "     3. Then open EBS normally - forms should work."
} else {
    W "  >> Some step FAILED. Backup is at: $bak (double-click to restore if needed)."
}
Flush
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Write-Host "Backup: $bak" -ForegroundColor Green
Write-Host "Send back: git add -A && git commit -m log && git push" -ForegroundColor Cyan
Read-Host "Press Enter to close"
