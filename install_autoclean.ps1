# =====================================================================
# Install a scheduled task that clears stale iexplore at logon, so the
# Edge-149 dual_engine_adapter exit-crash residue never blocks next launch.
# Self-elevates (creating a scheduled task needs admin). ASCII only.
# Output: install_autoclean_log.txt
# =====================================================================
param([string]$LogPath = "")
$selfPath=$MyInvocation.MyCommand.Path; $selfDir=Split-Path -Parent $selfPath
if(-not $LogPath){ $LogPath=Join-Path $selfDir "install_autoclean_log.txt" }
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){
    Write-Host "Not admin. Relaunching elevated (approve UAC)..." -ForegroundColor Yellow
    try{ Start-Process powershell -Verb RunAs -ArgumentList @("-ExecutionPolicy","Bypass","-File","`"$selfPath`"","-LogPath","`"$LogPath`"") }catch{ Write-Host "Elevation failed: $_" }
    Read-Host "Enter to close"; return
}
$Out=$LogPath; $log=New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try{ $log.ToString()|Out-File -FilePath $Out -Encoding UTF8 }catch{} }

W "Install auto-clean iexplore task (ADMIN)  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

$taskName = "ClearStaleIExplore"
# the cleanup action: kill any iexplore that has been running > 0 (at logon there should be none legit)
# at logon, ANY iexplore is leftover/orphan -> safe to kill
$cmd = 'Get-Process iexplore -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue'
$encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($cmd))

W ""
W "==== create scheduled task: $taskName ===="
try{
    # remove old one if exists
    schtasks /Delete /TN $taskName /F 2>$null | Out-Null
    # action: powershell hidden, run the kill command
    $action = "powershell.exe -NoProfile -WindowStyle Hidden -EncodedCommand $encoded"
    # at logon of current user
    $r = schtasks /Create /TN $taskName /TR $action /SC ONLOGON /RL HIGHEST /F 2>&1
    W "  $($r | Out-String)".Trim()
}catch{ W "  create failed: $_" }
Flush

# verify
W ""
W "==== verify ===="
try{
    $q = schtasks /Query /TN $taskName /V /FO LIST 2>&1 | Select-String "TaskName|Status|Schedule Type|Task To Run|Logon"
    $q | ForEach-Object { W "  $_" }
    $ok = ($LASTEXITCODE -eq 0)
    W ""
    W "  [$(if($ok){'PASS'}else{'FAIL'})] task '$taskName' registered"
    if($ok){
        W "  >> At every logon, stale iexplore is auto-killed."
        W "     Combined with open_ebs.ps1 for launching, the 0x80080005 residue"
        W "     problem should stop recurring."
    }
}catch{ W "  verify failed: $_" }

# also run the cleanup once now
W ""
W "==== run cleanup once now ===="
$ie=@(Get-Process iexplore -EA SilentlyContinue)
W "  iexplore now: $($ie.Count)"
$ie | ForEach-Object { try{ Stop-Process -Id $_.Id -Force }catch{} }
W "  cleared."

W ""
W "  To remove later: schtasks /Delete /TN $taskName /F"
Flush
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Write-Host "Send back: git add -A && git commit -m log && git push" -ForegroundColor Cyan
Read-Host "Press Enter to close"
