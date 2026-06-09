# =====================================================================
#  Upgrade Edge back to latest (>=149). Undoes the earlier 148 downgrade
#  lock (all policy values + re-enable EdgeUpdate svc/tasks + firewall),
#  then upgrades and polls until version >=149. Self-elevates. ASCII only.
#     powershell -ExecutionPolicy Bypass -File .\upgrade_to_149.ps1
# =====================================================================
param([string]$LogPath="")
$selfPath=$MyInvocation.MyCommand.Path; $selfDir=Split-Path -Parent $selfPath
if(-not $LogPath){ $LogPath=Join-Path $selfDir "upgrade_149_log.txt" }
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){
    $psExe="$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
    try{ Start-Process $psExe -Verb RunAs -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$selfPath`"","-LogPath","`"$LogPath`"") }catch{}
    Read-Host "Enter to close"; return
}
$Out=$LogPath; $log=New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try{ $log.ToString()|Out-File -FilePath $Out -Encoding UTF8 }catch{} }
function OK($b){ if($b){"[OK]"}else{"[FAIL]"} }

function Get-EdgeVer {
    foreach($p in @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
                    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe")){
        if(Test-Path $p){
            $raw=(Get-Item $p).VersionInfo.ProductVersion
            $v=$null; if([version]::TryParse($raw,[ref]$v)){ return $v }
        }
    }
    return $null
}

W "Upgrade Edge to latest (>=149)  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "================================================"
$cur=Get-EdgeVer
W "Current Edge: $cur"
Flush

# --- 1. remove ALL 148 update locks (both hives + both views) ---
W ""
W "[1] Remove 148 update lock (policy values)"
$guid="{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}"
$policyNames=@("UpdateDefault","Update$guid","TargetVersionPrefix","TargetVersionPrefix$guid",
               "TargetVersionPrefixStable","RollbackToTargetVersion$guid",
               "AutoUpdateCheckPeriodMinutes","UpdatesSuppressedStartHour","UpdatesSuppressedDurationMin")
foreach($hive in @([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryHive]::CurrentUser)){
    foreach($view in @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)){
        try{
            $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view)
            $key=$base.OpenSubKey("SOFTWARE\Policies\Microsoft\EdgeUpdate",$true)
            if($key){ foreach($n in $policyNames){ try{ $key.DeleteValue($n,$false) }catch{} }; $key.Close() }
        }catch{}
    }
}
W "  policy values cleared (HKLM+HKCU, 64+32 view)"
netsh advfirewall firewall delete rule name="Block Edge Update" 2>$null | Out-Null
W "  firewall block removed"
Flush

# --- 2. re-enable EdgeUpdate services + tasks (downgrade may have disabled) ---
W ""
W "[2] Re-enable EdgeUpdate services + tasks"
cmd /c "sc config edgeupdate start= delayed-auto >nul 2>&1"
cmd /c "sc config edgeupdatem start= demand >nul 2>&1"
cmd /c "sc start edgeupdate >nul 2>&1"
foreach($t in @("MicrosoftEdgeUpdateTaskMachineCore","MicrosoftEdgeUpdateTaskMachineUA")){
    try{ Enable-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue | Out-Null }catch{}
}
W "  services + tasks re-enabled"
Flush

# --- 3. winget upgrade (background) + live progress ---
W ""
W "[3] winget upgrade Microsoft.Edge (with progress)"
$winget=(Get-Command winget.exe -ErrorAction SilentlyContinue).Source
if($winget){
    try{ Start-Process $winget -ArgumentList @("pin","remove","--id","Microsoft.Edge","--exact") -Wait -WindowStyle Hidden -EA SilentlyContinue | Out-Null }catch{}
    # run winget in background so we can show progress
    $wlog="$env:TEMP\winget_edge.log"
    $startVer = Get-EdgeVer
    try{
        $p=Start-Process $winget -ArgumentList @("upgrade","--id","Microsoft.Edge","--exact","--source","winget",
            "--accept-source-agreements","--accept-package-agreements","--silent","--include-unknown",
            "--log","`"$wlog`"") -PassThru -WindowStyle Hidden
        $spin="|/-\"; $i=0; $secs=0
        while(-not $p.HasExited){
            Start-Sleep -Seconds 3; $secs+=3
            # activity indicators: EdgeUpdate/installer running? installer size?
            $instProc = @(Get-Process -EA SilentlyContinue | Where-Object { $_.ProcessName -match 'MicrosoftEdge_X64|setup|installer|MicrosoftEdgeUpdate' }).Count
            $nowVer = Get-EdgeVer
            $c=$spin[$i % 4]; $i++
            Write-Host ("`r  [$c] winget running ${secs}s | edge-ver=$nowVer | installer-procs=$instProc   ") -NoNewline
            if($secs -gt 600){ Write-Host ""; W "  winget >10min, breaking wait"; break }
        }
        Write-Host ""
        if($p.HasExited){ W "  winget exit: $($p.ExitCode) (after ${secs}s)" }
    }catch{ W "  winget failed: $($_.Exception.Message)" }
}else{ W "  winget.exe not found" }
Flush

# --- 4. fallback: trigger EdgeUpdate /ua ---
Start-Sleep -Seconds 5
$mid=Get-EdgeVer
if(-not ($mid -and $mid.Major -ge 149)){
    W ""
    W "[4] Trigger EdgeUpdate /ua (fallback)"
    $upd=@("${env:ProgramFiles(x86)}\Microsoft\EdgeUpdate\MicrosoftEdgeUpdate.exe",
           "$env:ProgramFiles\Microsoft\EdgeUpdate\MicrosoftEdgeUpdate.exe") | Where-Object{Test-Path $_} | Select-Object -First 1
    if($upd){
        try{ Start-Process $upd -ArgumentList @("/ua","/installsource","ondemand") -Wait | Out-Null; W "  EdgeUpdate /ua triggered" }catch{ W "  /ua failed: $_" }
        try{ Start-ScheduledTask -TaskName "MicrosoftEdgeUpdateTaskMachineUA" -EA SilentlyContinue }catch{}
    }else{ W "  EdgeUpdate.exe not found" }
}
Flush

# --- 5. poll for version >=149 (up to 8 min) ---
W ""
W "[5] Waiting for Edge >=149 (poll up to 8 min)"
$deadline=(Get-Date).AddMinutes(8)
do{
    Start-Sleep -Seconds 15
    $v=Get-EdgeVer
    W "  Edge now: $v"
    Flush
}until( ($v -and $v.Major -ge 149) -or (Get-Date) -gt $deadline )
$verOk = ($v -and $v.Major -ge 149)

# --- 6. test IE COM ---
W ""
W "[6] Test IE COM after upgrade"
Get-Process iexplore -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
Start-Sleep 2
$comOk=$false
try{
    $ie=New-Object -ComObject InternetExplorer.Application -EA Stop
    $comOk=$true; W "  [OK] IE COM created on $v !"
    try{ $ie.Quit()|Out-Null }catch{}
}catch{
    $hr=$_.Exception.HResult; if($_.Exception.InnerException){$hr=$_.Exception.InnerException.HResult}
    W ("  [FAIL] IE COM: 0x{0:X8}" -f ($hr -band 0xFFFFFFFF))
}

W ""
W "================================================"
W "  Edge: $cur -> $v   version>=149 $(OK $verOk)   IE-COM $(OK $comOk)"
W "  NEXT: reboot, then test EBS with open_ebs.ps1."
Flush
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Read-Host "Press Enter to close"
