# =====================================================================
# Analyze WHY iexplore.exe crashes when Edge IE mode launches it.
# trace showed: IE mode DOES start iexplore via dual_engine_adapter, but
# iexplore crashes immediately (WerFault). This finds the FAULTING MODULE
# (the DLL/component causing the crash) from Event Log + WER reports.
# Self-elevates (WER dumps need admin). ASCII only.
# Output: crash_analyze_log.txt
# =====================================================================
param([string]$LogPath = "")
$selfPath=$MyInvocation.MyCommand.Path; $selfDir=Split-Path -Parent $selfPath
if(-not $LogPath){ $LogPath=Join-Path $selfDir "crash_analyze_log.txt" }
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){
    Write-Host "Not admin. Relaunching elevated (approve UAC)..." -ForegroundColor Yellow
    try{ Start-Process powershell -Verb RunAs -ArgumentList @("-ExecutionPolicy","Bypass","-File","`"$selfPath`"","-LogPath","`"$LogPath`"") }catch{ Write-Host "Elevation failed: $_" }
    Read-Host "Enter to close"; return
}
$Out=$LogPath; $log=New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try{ $log.ToString()|Out-File -FilePath $Out -Encoding UTF8 }catch{} }
function D($ev,$name){ try{ $x=[xml]$ev.ToXml(); ($x.Event.EventData.Data|Where-Object{$_.Name -eq $name}).'#text' }catch{ '' } }

W "iexplore crash analysis (ADMIN)  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Machine: $env:COMPUTERNAME"

$tStart = Get-Date

# --- trigger a fresh crash so we have a current report ---
W ""
W "==== 0. trigger IE COM (to produce a fresh crash) ===="
try{ $ie=New-Object -ComObject InternetExplorer.Application -EA Stop; W "  COM ok (no crash?)"; try{$ie.Quit()}catch{} }
catch{ W "  COM failed (expected): $($_.Exception.Message)" }
Start-Sleep -Seconds 6
Flush

# --- 1. Application Error (1000) for iexplore ---
W ""
W "==== 1. Application Error (Event 1000) iexplore ===="
try{
    Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000; StartTime=$tStart.AddMinutes(-15)} -EA SilentlyContinue |
        Where-Object { $_.Message -match 'iexplore' } | Select-Object -First 5 | ForEach-Object {
            W "  [$($_.TimeCreated.ToString('HH:mm:ss'))]"
            W "    Faulting app   : $(D $_ 'AppName')  $(D $_ 'AppVersion')"
            W "    FAULTING MODULE: $(D $_ 'ModuleName')  $(D $_ 'ModuleVersion')"
            W "    Exception code : $(D $_ 'ExceptionCode')"
            W "    Fault offset   : $(D $_ 'Offset')"
            # fallback: dump raw message lines if Data fields empty
            if(-not (D $_ 'ModuleName')){ ($_.Message -split "`n")[0..6] | ForEach-Object { W "    | $_" } }
        }
}catch{ W "  read failed: $_" }
Flush

# --- 2. WER (Event 1001) - has bucket + all parameters incl faulting module ---
W ""
W "==== 2. Windows Error Reporting (Event 1001) iexplore ===="
try{
    Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1001; StartTime=$tStart.AddMinutes(-15)} -EA SilentlyContinue |
        Where-Object { $_.Message -match 'iexplore|IE|Internet Explorer' } | Select-Object -First 5 | ForEach-Object {
            W "  [$($_.TimeCreated.ToString('HH:mm:ss'))]"
            ($_.Message -split "`n") | Select-Object -First 25 | ForEach-Object { if($_.Trim()){ W "    | $($_.Trim())" } }
            W "    ----"
        }
}catch{ W "  read failed: $_" }
Flush

# --- 3. WER local crash dumps / report archives on disk ---
W ""
W "==== 3. WER report files on disk (iexplore) ===="
$werDirs = @("$env:ProgramData\Microsoft\Windows\WER\ReportArchive",
             "$env:ProgramData\Microsoft\Windows\WER\ReportQueue",
             "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive")
foreach($wd in $werDirs){
    if(Test-Path $wd){
        Get-ChildItem $wd -Directory -EA SilentlyContinue | Where-Object{ $_.Name -match 'iexplore|IE_' } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 3 | ForEach-Object {
                W "  dir: $($_.FullName)"
                $rep = Join-Path $_.FullName "Report.wer"
                if(Test-Path $rep){
                    Get-Content $rep -EA SilentlyContinue | Where-Object{ $_ -match 'AppName|ModName|ModVer|ExceptionCode|Sig\[|EventType|FaultingModule' } |
                        Select-Object -First 20 | ForEach-Object { W "      $_" }
                }
            }
    }
}
Flush

# --- 4. list iexplore add-ons / BHOs / loaded into IE (residual 360 dll?) ---
W ""
W "==== 4. IE add-ons / BHO registry (possible crash cause) ===="
foreach($bho in @("Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Browser Helper Objects",
                  "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\Browser Helper Objects")){
    if(Test-Path $bho){
        Get-ChildItem $bho -EA SilentlyContinue | ForEach-Object {
            $clsid=$_.PSChildName
            $name=(Get-ItemProperty "Registry::HKEY_CLASSES_ROOT\CLSID\$clsid" -Name '(default)' -EA SilentlyContinue).'(default)'
            $dll=(Get-ItemProperty "Registry::HKEY_CLASSES_ROOT\CLSID\$clsid\InprocServer32" -Name '(default)' -EA SilentlyContinue).'(default)'
            W "  BHO $clsid : $name"
            W "      dll: $dll"
        }
    } else { W "  $bho (none)" }
}
# IE extensions / toolbars
foreach($ext in @("Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Internet Explorer\Extensions",
                  "Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Internet Explorer\Extensions")){
    if(Test-Path $ext){ Get-ChildItem $ext -EA SilentlyContinue | ForEach-Object { W "  IE-ext: $($_.PSChildName)" } }
}
Flush

# --- 5. quick scan: 360 dll referenced (fast, via reg.exe query) ---
W ""
W "==== 5. any 360 dll still registered (fast) ===="
try{
    $r = reg.exe query "HKLM\SOFTWARE\Classes\CLSID" /s /f "360" /d 2>$null | Select-Object -First 30
    if($r){ $r | ForEach-Object { if($_ -match '360'){ W "  $_" } } }
    else { W "  no 360 dll reference found (or query returned none)" }
}catch{ W "  skipped: $_" }

W ""
W "==== READ ===="
W "  KEY = the FAULTING MODULE in sections 1/2/3. That DLL is what crashes"
W "  iexplore. If it's a 360 dll or some add-on -> remove/unregister it."
W "  If it's a windows system dll -> likely needs sfc/DISM repair or update."
Flush
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Write-Host "Send back: git add -A && git commit -m log && git push" -ForegroundColor Cyan
Read-Host "Press Enter to close"
