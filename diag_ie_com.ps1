# =====================================================================
# DIAGNOSE ONLY - confirm whether IE COM registration is the cause of
# 0x8000FFFF "cannot create IE process". Reads registry, changes NOTHING.
# Theory to confirm: LocalServer32 of IE COM CLSID still points to a
# (now-uninstalled) 360 path, so Edge IE mode cannot spawn iexplore.exe.
# ASCII only. No admin needed for reading HKCR/HKLM Classes. Output: diag_ie_com_log.txt
# =====================================================================
$Out = Join-Path $PSScriptRoot "diag_ie_com_log.txt"
if (-not $PSScriptRoot) { $Out = "$env:USERPROFILE\Documents\diag_ie_com_log.txt" }
$log = New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try { $log.ToString() | Out-File -FilePath $Out -Encoding UTF8 } catch {} }

W "Diagnose IE COM registration  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Machine: $env:COMPUTERNAME  User: $env:USERNAME"
W "(READ ONLY - this script changes nothing)"

$CLSID = "{0002DF01-0000-0000-C000-000000000046}"
$paths = @(
  "Registry::HKEY_CLASSES_ROOT\CLSID\$CLSID\LocalServer32",
  "Registry::HKEY_CLASSES_ROOT\WOW6432Node\CLSID\$CLSID\LocalServer32",
  "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\$CLSID\LocalServer32",
  "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\WOW6432Node\CLSID\$CLSID\LocalServer32"
)

# 1. the smoking gun: where does IE COM LocalServer32 point?
W ""
W "==== 1. IE COM LocalServer32 values ===="
$hijack=0; $okPoint=0; $missing=0; $dangling=0
foreach($p in $paths){
    if(Test-Path $p){
        $v = (Get-ItemProperty -Path $p -Name '(default)' -EA SilentlyContinue).'(default)'
        $tag = "(?)"
        if($v -match '360'){ $tag="<-- still points to 360 (HIJACK RESIDUE)"; $hijack++ }
        elseif($v -match 'iexplore'){
            # does the file it points to actually exist?
            $exe = ($v -replace '"','').Trim()
            if(Test-Path $exe){ $tag="(ok, points to existing iexplore.exe)"; $okPoint++ }
            else { $tag="<-- points to iexplore.exe but FILE MISSING"; $dangling++ }
        } else { $tag="<-- points to something else / empty" }
        W "  [$p]"
        W "     = $v   $tag"
    } else { W "  [$p] (key not present)"; $missing++ }
}
Flush

# 2. ProgID mapping (InternetExplorer.Application -> CLSID)
W ""
W "==== 2. ProgID InternetExplorer.Application ===="
foreach($pp in @("Registry::HKEY_CLASSES_ROOT\InternetExplorer.Application\CLSID",
                 "Registry::HKEY_CLASSES_ROOT\InternetExplorer.Application.1\CLSID")){
    if(Test-Path $pp){
        $v=(Get-ItemProperty -Path $pp -Name '(default)' -EA SilentlyContinue).'(default)'
        W "  $pp = $v"
    } else { W "  $pp (not present)" }
}

# 3. App Paths for iexplore.exe (another thing 360 often changes)
W ""
W "==== 3. App Paths\iexplore.exe ===="
foreach($ap in @("Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\iexplore.exe",
                 "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\iexplore.exe")){
    if(Test-Path $ap){
        $v=(Get-ItemProperty -Path $ap -Name '(default)' -EA SilentlyContinue).'(default)'
        $tag = if($v -match '360'){'<-- 360 RESIDUE'}elseif($v -match 'iexplore'){'(ok)'}else{'(?)'}
        W "  $ap = $v  $tag"
    } else { W "  $ap (not present)" }
}

# 4. leftover 360 files/dirs?
W ""
W "==== 4. leftover 360 traces ===="
foreach($d in @("$env:APPDATA\360se6","$env:LOCALAPPDATA\360se6","$env:APPDATA\360se","C:\Program Files (x86)\360")){
    if(Test-Path $d){ W "  EXISTS: $d" } else { W "  gone: $d" }
}

# 5. real iexplore.exe locations (what we WOULD point to)
W ""
W "==== 5. real iexplore.exe on disk ===="
foreach($p in @("C:\Program Files\Internet Explorer\iexplore.exe",
                "C:\Program Files (x86)\Internet Explorer\iexplore.exe")){
    if(Test-Path $p){ W "  EXISTS: $p" } else { W "  missing: $p" }
}

# verdict
W ""
W "==== VERDICT ===="
W "  hijack(360)=$hijack  dangling(iexplore missing)=$dangling  ok=$okPoint  missingKey=$missing"
if($hijack -gt 0){
    W "  >> CONFIRMED: IE COM still points to 360 residue. THIS is the 0x8000FFFF cause."
    W "     Fix = restore LocalServer32 to real iexplore.exe (run fix_ie_com.ps1)."
} elseif($dangling -gt 0){
    W "  >> LIKELY: points to iexplore path but file missing/bad. Fix = repoint to real iexplore.exe."
} elseif($okPoint -gt 0 -and $hijack -eq 0){
    W "  >> NOT this cause: IE COM already points to valid iexplore.exe."
    W "     0x8000FFFF is from something else - report back, we look elsewhere."
} else {
    W "  >> IE COM keys missing entirely - needs re-registration. report back."
}

Flush
Write-Host ""
Write-Host "Log: $Out  (READ-ONLY, nothing changed)" -ForegroundColor Green
Write-Host "Send back: git add -A && git commit -m log && git push" -ForegroundColor Cyan
Read-Host "Press Enter to close"
