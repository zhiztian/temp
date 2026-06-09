# =====================================================================
#  Scan for anything that might periodically break IE-mode state:
#  all processes (flag unsigned / non-MS / security-optimizer-mgmt),
#  services, scheduled tasks, autoruns. Read-only. Self-elevates. ASCII.
#  Output: scan_processes_log.txt
# =====================================================================
param([string]$LogPath = "")
$selfPath=$MyInvocation.MyCommand.Path; $selfDir=Split-Path -Parent $selfPath
if(-not $LogPath){ $LogPath=Join-Path $selfDir "scan_processes_log.txt" }
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){
    $psExe="$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
    try{ Start-Process $psExe -Verb RunAs -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$selfPath`"","-LogPath","`"$LogPath`"") }catch{}
    Read-Host "Enter to close"; return
}
$Out=$LogPath; $log=New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try{ $log.ToString()|Out-File -FilePath $Out -Encoding UTF8 }catch{} }

W "System scan for IE-mode breakers  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Machine: $env:COMPUTERNAME"
W "================================================"

# suspicious keywords: security/optimizer/management/cleaner/CN-vendors
$suspPat = 'sunlogin|oray|360|huorong|qihoo|qqpc|tencent|kingsoft|kxe|baidu|2345|sogou|wps|lenovo|dell|hp|asus|driver|booster|cleaner|optimi|guard|protect|defend|secur|antivir|endpoint|edr|crowdstrike|sentinel|carbon|cylance|sophos|symantec|mcafee|eset|kaspersky|trend|bitdefender|todesk|anydesk|teamviewer|vnc|intune|sccm|mecm|ccmexec|gpo|policy|agent|monitor|inventory|patch|sccm'

# --- 1. all processes, flag non-Microsoft / unsigned ---
W ""
W "[1] Processes (NON-Microsoft / suspicious flagged)"
$procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path }
$seen=@{}
foreach($p in ($procs | Sort-Object Path -Unique)){
    $path=$p.Path
    if($seen.ContainsKey($path)){ continue }; $seen[$path]=1
    $sig=$null; $company=$null
    try{ $sig=(Get-AuthenticodeSignature $path -EA SilentlyContinue).Status }catch{}
    try{ $company=(Get-Item $path).VersionInfo.CompanyName }catch{}
    $isMS = ($company -match 'Microsoft')
    $flag = ""
    if("$path $company $($p.ProcessName)" -match $suspPat){ $flag="  <<< SUSPICIOUS" }
    elseif($sig -ne 'Valid'){ $flag="  <<< UNSIGNED/$sig" }
    elseif(-not $isMS){ $flag="  (non-MS)" }
    # only print non-MS or flagged (skip clean MS to keep log short)
    if(-not $isMS -or $flag -match 'SUSPICIOUS|UNSIGNED'){
        W ("  {0,-22} {1}" -f $p.ProcessName, $company)
        W ("       {0}{1}" -f $path, $flag)
    }
}
Flush

# --- 2. services: running, non-MS / suspicious ---
W ""
W "[2] Running services (non-MS / suspicious)"
try{
    $svcs = Get-CimInstance Win32_Service -EA SilentlyContinue | Where-Object { $_.State -eq 'Running' -and $_.PathName }
    foreach($s in $svcs){
        $pn=$s.PathName -replace '^"',''; $pn=($pn -split '"')[0]; $pn=($pn -split ' /')[0].Trim()
        $comp=$null; try{ if(Test-Path $pn){ $comp=(Get-Item $pn).VersionInfo.CompanyName } }catch{}
        if($comp -match 'Microsoft' -and "$($s.Name) $($s.PathName)" -notmatch $suspPat){ continue }
        $flag = if("$($s.Name) $($s.DisplayName) $($s.PathName)" -match $suspPat){"  <<< SUSPICIOUS"}else{""}
        W ("  {0} [{1}]{2}" -f $s.Name, $comp, $flag)
        W ("       {0}" -f $s.PathName)
    }
}catch{ W "  service scan failed: $_" }
Flush

# --- 3. scheduled tasks: enabled, non-MS path / suspicious ---
W ""
W "[3] Scheduled tasks (enabled, suspicious or frequent)"
try{
    $tasks = Get-ScheduledTask -EA SilentlyContinue | Where-Object { $_.State -ne 'Disabled' }
    foreach($t in $tasks){
        $exec = ($t.Actions | ForEach-Object { $_.Execute }) -join ' '
        $blob = "$($t.TaskName) $($t.TaskPath) $exec"
        if($t.TaskPath -match '^\\Microsoft\\' -and $blob -notmatch $suspPat){ continue }
        $flag = if($blob -match $suspPat){"  <<< SUSPICIOUS"}else{""}
        W ("  {0}{1}{2}" -f $t.TaskPath, $t.TaskName, $flag)
        if($exec){ W ("       -> {0}" -f $exec) }
    }
}catch{ W "  task scan failed: $_" }
Flush

# --- 4. autorun entries ---
W ""
W "[4] Autorun (Run keys)"
foreach($rk in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
                 "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
                 "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run")){
    if(Test-Path $rk){
        foreach($name in (Get-Item $rk).Property){
            $val=(Get-ItemProperty $rk -Name $name).$name
            $flag = if("$name $val" -match $suspPat){"  <<< SUSPICIOUS"}else{""}
            W ("  [$rk] $name = $val$flag")
        }
    }
}
Flush

W ""
W "================================================"
W "Look for <<< SUSPICIOUS lines, esp. anything that could periodically"
W "modify IE/registry (cleaner/optimizer/security/management agent)."
Flush
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Read-Host "Press Enter to close"
