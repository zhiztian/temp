# =====================================================================
#  Disable Edge Startup Boost + Background Mode so Edge actually EXITS
#  when you close the window (instead of staying resident with the bad
#  IE-mode state). Run ONCE. Self-elevates (writes HKLM policy). ASCII.
#     powershell -ExecutionPolicy Bypass -File .\disable_edge_background.ps1
# =====================================================================
param([string]$LogPath = "")
$selfPath=$MyInvocation.MyCommand.Path; $selfDir=Split-Path -Parent $selfPath
if(-not $LogPath){ $LogPath=Join-Path $selfDir "disable_edge_bg_log.txt" }
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){
    $psExe="$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
    try{ Start-Process $psExe -Verb RunAs -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$selfPath`"","-LogPath","`"$LogPath`"") }catch{}
    Read-Host "Press Enter to close"; return
}
$Out=$LogPath; $log=New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try{ $log.ToString()|Out-File -FilePath $Out -Encoding UTF8 }catch{} }
function OK($b){ if($b){"[OK]"}else{"[FAIL]"} }

W "Disable Edge background/startup-boost  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "================================================"

# write both HKLM (machine) and HKCU (user) to be safe
foreach($hive in @("HKLM:\SOFTWARE\Policies\Microsoft\Edge","HKCU:\SOFTWARE\Policies\Microsoft\Edge")){
    try{
        if(-not(Test-Path $hive)){ New-Item -Path $hive -Force | Out-Null }
        New-ItemProperty -Path $hive -Name "StartupBoostEnabled" -Value 0 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $hive -Name "BackgroundModeEnabled" -Value 0 -PropertyType DWord -Force | Out-Null
        W "  $hive : StartupBoost=0, BackgroundMode=0  [OK]"
    }catch{ W "  $hive failed: $($_.Exception.Message)" }
}
Flush

# verify
W ""
W "Verify (HKLM):"
$k="HKLM:\SOFTWARE\Policies\Microsoft\Edge"
$sb=(Get-ItemProperty $k -Name StartupBoostEnabled -EA SilentlyContinue).StartupBoostEnabled
$bg=(Get-ItemProperty $k -Name BackgroundModeEnabled -EA SilentlyContinue).BackgroundModeEnabled
W "  StartupBoostEnabled=$sb  BackgroundModeEnabled=$bg  $(OK ($sb -eq 0 -and $bg -eq 0))"

W ""
W "================================================"
W "Done. Now Edge will fully exit when you close it."
W "Next: use open_ebs.ps1 to open EBS (it kills any leftover Edge first)."
W "Verify live at edge://policy (StartupBoostEnabled / BackgroundModeEnabled = false)."
Flush
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Read-Host "Press Enter to close"
