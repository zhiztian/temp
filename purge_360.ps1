# =====================================================================
#  Purge ALL 360 / Qihoo leftovers (the real culprit breaking IE mode).
#  360 was "uninstalled" but leftovers persist: 360huabao autorun,
#  Qihoo scheduled task, and it has a history of hijacking IE COM.
#  Kills procs, removes autoruns, disables tasks, optionally deletes dirs.
#  Self-elevates. ASCII only. Output: purge_360_log.txt
#     powershell -ExecutionPolicy Bypass -File .\purge_360.ps1
#     powershell -ExecutionPolicy Bypass -File .\purge_360.ps1 -DeleteFiles
# =====================================================================
param([switch]$DeleteFiles,[string]$LogPath="")
$selfPath=$MyInvocation.MyCommand.Path; $selfDir=Split-Path -Parent $selfPath
if(-not $LogPath){ $LogPath=Join-Path $selfDir "purge_360_log.txt" }
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){
    $psExe="$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
    $extra=@(); if($DeleteFiles){ $extra=@("-DeleteFiles") }
    try{ Start-Process $psExe -Verb RunAs -ArgumentList (@("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$selfPath`"","-LogPath","`"$LogPath`"")+$extra) }catch{}
    Read-Host "Enter to close"; return
}
$Out=$LogPath; $log=New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try{ $log.ToString()|Out-File -FilePath $Out -Encoding UTF8 }catch{} }

W "Purge 360/Qihoo leftovers  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Mode: $(if($DeleteFiles){'KILL + REMOVE autoruns/tasks + DELETE files'}else{'KILL + REMOVE autoruns/tasks (files kept)'})"
W "================================================"
$pat='360|qihoo|huabao'

# --- 1. kill 360 processes ---
W ""
W "[1] Kill 360 processes"
$procs=@(Get-Process -EA SilentlyContinue | Where-Object { $_.ProcessName -match $pat -or ($_.Path -and $_.Path -match $pat) })
if($procs.Count){
    foreach($p in $procs){
        W "  $($p.ProcessName) PID=$($p.Id) Path=$($p.Path)"
        try{ Stop-Process -Id $p.Id -Force -EA Stop; W "    killed" }catch{ cmd /c "taskkill /F /T /PID $($p.Id) >nul 2>&1"; W "    force-killed via taskkill" }
    }
}else{ W "  none running" }
Flush

# --- 2. remove Run autostart entries ---
W ""
W "[2] Remove Run autostart entries"
foreach($rk in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
                 "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
                 "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run")){
    if(Test-Path $rk){
        foreach($name in (Get-Item $rk).Property){
            $val=(Get-ItemProperty $rk -Name $name).$name
            if("$name $val" -match $pat){
                W "  [$rk] $name = $val"
                try{ Remove-ItemProperty -Path $rk -Name $name -EA Stop; W "    removed" }catch{ W "    remove failed: $($_.Exception.Message)" }
            }
        }
    }
}
Flush

# --- 3. disable + delete scheduled tasks ---
W ""
W "[3] Scheduled tasks"
try{
    $tasks=@(Get-ScheduledTask -EA SilentlyContinue | Where-Object { $_.TaskName -match $pat -or ($_.Actions.Execute -join ' ') -match $pat })
    if($tasks.Count){
        foreach($t in $tasks){
            W "  $($t.TaskPath)$($t.TaskName)"
            try{ Unregister-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Confirm:$false -EA Stop; W "    deleted" }
            catch{ try{ Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -EA Stop|Out-Null; W "    disabled (delete failed)" }catch{ W "    failed: $($_.Exception.Message)" } }
        }
    }else{ W "  none" }
}catch{ W "  task scan failed: $_" }
Flush

# --- 4. services ---
W ""
W "[4] Services"
$svcs=@(Get-CimInstance Win32_Service -EA SilentlyContinue | Where-Object { ($_.Name -match $pat) -or ($_.PathName -match $pat) -or ($_.DisplayName -match $pat) })
if($svcs.Count){
    foreach($s in $svcs){
        W "  $($s.Name) - $($s.PathName)"
        cmd /c "sc stop `"$($s.Name)`" >nul 2>&1"
        cmd /c "sc config `"$($s.Name)`" start= disabled >nul 2>&1"
        cmd /c "sc delete `"$($s.Name)`" >nul 2>&1"
        W "    stopped + disabled + delete attempted"
    }
}else{ W "  none" }
Flush

# --- 5. leftover dirs ---
W ""
W "[5] Leftover 360 directories"
$dirs=@(
  "$env:APPDATA\360huabao","$env:LOCALAPPDATA\360huabao",
  "$env:APPDATA\360se6","$env:LOCALAPPDATA\360se6","$env:APPDATA\360se",
  "$env:APPDATA\360safe","$env:LOCALAPPDATA\360safe",
  "C:\Program Files (x86)\360","C:\Program Files\360",
  "C:\ProgramData\360safe","C:\360Downloads","C:\360SANDBOX"
)
foreach($d in $dirs){
    if(Test-Path $d){
        W "  EXISTS: $d"
        if($DeleteFiles){
            try{ Remove-Item $d -Recurse -Force -EA Stop; W "    deleted" }catch{ W "    delete failed: $($_.Exception.Message)" }
        }else{ W "    (kept - run with -DeleteFiles to remove)" }
    }
}
Flush

# --- 6. re-verify IE COM is still pointing to iexplore (360 may have re-hijacked) ---
W ""
W "[6] Re-check IE COM registration (360 may have re-hijacked it)"
$CLSID="{0002DF01-0000-0000-C000-000000000046}"
foreach($p in @("Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\$CLSID\LocalServer32",
                "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\WOW6432Node\CLSID\$CLSID\LocalServer32")){
    if(Test-Path $p){
        $v=(Get-ItemProperty -Path $p -Name '(default)' -EA SilentlyContinue).'(default)'
        $tag=if($v -match '360'){'<<< STILL 360 - re-run setup_ebs.ps1 to fix!'}elseif($v -match 'iexplore'){'(ok)'}else{"(?: $v)"}
        W "  $v   $tag"
    }
}

W ""
W "================================================"
W "Done. Remaining 360 processes:"
$still=@(Get-Process -EA SilentlyContinue | Where-Object { $_.ProcessName -match $pat })
W "  $($still.Count)"
W ""
W "If files still exist, re-run with -DeleteFiles."
W "Then REBOOT and test EBS with open_ebs.ps1."
Flush
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Read-Host "Press Enter to close"
