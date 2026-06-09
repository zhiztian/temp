# =====================================================================
#  Stop & disable Sunlogin (Oray) auto-start, optionally uninstall it.
#  Sunlogin = 向日葵远程控制. Common names: SunloginClient.exe,
#  service "SunloginService" / "Oray SunLogin Client Service", vendor Oray.
#  Default = STOP + DISABLE autostart (reversible). Add -Uninstall to remove.
#  Self-elevates. ASCII only.  Output: remove_sunlogin_log.txt
#     powershell -ExecutionPolicy Bypass -File .\remove_sunlogin.ps1
#     powershell -ExecutionPolicy Bypass -File .\remove_sunlogin.ps1 -Uninstall
# =====================================================================
param([switch]$Uninstall,[string]$LogPath = "")
$selfPath=$MyInvocation.MyCommand.Path; $selfDir=Split-Path -Parent $selfPath
if(-not $LogPath){ $LogPath=Join-Path $selfDir "remove_sunlogin_log.txt" }
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){
    Write-Host "Need admin. Requesting elevation (click Yes on UAC)..." -ForegroundColor Yellow
    $psExe="$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
    $extra=@(); if($Uninstall){ $extra=@("-Uninstall") }
    try{ Start-Process $psExe -Verb RunAs -ArgumentList (@("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$selfPath`"","-LogPath","`"$LogPath`"")+$extra) }
    catch{ Write-Host "Elevation failed: $($_.Exception.Message)" -ForegroundColor Red }
    Read-Host "Press Enter to close"; return
}
$Out=$LogPath; $log=New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try{ $log.ToString()|Out-File -FilePath $Out -Encoding UTF8 }catch{} }

W "Remove Sunlogin autostart  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Mode: $(if($Uninstall){'UNINSTALL'}else{'STOP + DISABLE autostart (reversible)'})"
W "================================================"

$pat = 'sunlogin|oray'

# --- 1. running processes ---
W ""
W "[1] Running Sunlogin processes"
$procs=@(Get-Process -EA SilentlyContinue | Where-Object { $_.ProcessName -match $pat })
if($procs.Count){ foreach($p in $procs){ W "  $($p.ProcessName) PID=$($p.Id) Path=$($p.Path)" } }
else { W "  none running" }
# capture install path for later uninstall
$installPaths=@($procs | ForEach-Object { $_.Path } | Where-Object { $_ } | ForEach-Object { Split-Path $_ -Parent } | Sort-Object -Unique)
foreach($p in $procs){ try{ Stop-Process -Id $p.Id -Force -EA Stop; W "  killed PID=$($p.Id)" }catch{ W "  kill PID=$($p.Id) failed: $_" } }
Flush

# --- 2. services ---
W ""
W "[2] Sunlogin services"
$svcs=@(Get-Service -EA SilentlyContinue | Where-Object { $_.Name -match $pat -or $_.DisplayName -match $pat })
if($svcs.Count){
    foreach($s in $svcs){
        W "  service: $($s.Name) ($($s.DisplayName)) status=$($s.Status) start=$($s.StartType)"
        try{ Stop-Service -Name $s.Name -Force -EA SilentlyContinue }catch{}
        try{ Set-Service -Name $s.Name -StartupType Disabled -EA Stop; W "    -> stopped + set Disabled" }catch{ W "    -> set disabled failed: $($_.Exception.Message)" }
    }
}else{ W "  none" }
Flush

# --- 3. scheduled tasks ---
W ""
W "[3] Sunlogin scheduled tasks"
try{
    $tasks=@(Get-ScheduledTask -EA SilentlyContinue | Where-Object { $_.TaskName -match $pat -or ($_.Actions.Execute -join ' ') -match $pat })
    if($tasks.Count){
        foreach($t in $tasks){
            W "  task: $($t.TaskName)"
            try{ Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -EA Stop | Out-Null; W "    -> disabled" }catch{ W "    -> disable failed: $($_.Exception.Message)" }
        }
    }else{ W "  none" }
}catch{ W "  task query failed: $_" }
Flush

# --- 4. Run registry autostart entries ---
W ""
W "[4] Run-key autostart entries"
$runKeys=@(
  "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
  "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
  "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
)
foreach($rk in $runKeys){
    if(Test-Path $rk){
        $props=(Get-Item $rk).Property
        foreach($name in $props){
            $val=(Get-ItemProperty $rk -Name $name).$name
            if("$name $val" -match $pat){
                W "  found: [$rk] $name = $val"
                try{ Remove-ItemProperty -Path $rk -Name $name -EA Stop; W "    -> removed" }catch{ W "    -> remove failed: $($_.Exception.Message)" }
            }
        }
    }
}
Flush

# --- 5. optional uninstall ---
if($Uninstall){
    W ""
    W "[5] Uninstall Sunlogin"
    # try uninstall registry entries
    $uk=@("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
          "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
          "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*")
    $found=$false
    foreach($k in $uk){
        try{
            Get-ItemProperty $k -EA SilentlyContinue | Where-Object { $_.DisplayName -match $pat } | ForEach-Object {
                $found=$true
                W "  product: $($_.DisplayName)  ver=$($_.DisplayVersion)"
                $us=$_.UninstallString
                W "    uninstall string: $us"
                if($us){
                    try{
                        # run uninstaller silently if possible
                        if($us -match 'msiexec'){
                            $code = ($us -replace '.*\{','{') -replace '\}.*','}'
                            Start-Process msiexec.exe -ArgumentList "/x $code /qn /norestart" -Wait
                            W "    -> msi uninstall invoked"
                        }else{
                            W "    -> non-msi uninstaller; run it manually if needed: $us"
                        }
                    }catch{ W "    -> uninstall failed: $($_.Exception.Message)" }
                }
            }
        }catch{}
    }
    if(-not $found){ W "  no uninstall entry found (may already be removed, or installed per-user only)" }
    Flush
}

# --- summary ---
W ""
W "================================================"
W "Done. Re-scan after:"
$still=@(Get-Process -EA SilentlyContinue | Where-Object { $_.ProcessName -match $pat })
W "  sunlogin processes now: $($still.Count)"
W ""
W "  Autostart disabled. To FULLY remove, run with -Uninstall:"
W "    powershell -ExecutionPolicy Bypass -File .\remove_sunlogin.ps1 -Uninstall"
W "  (If it's a remote-control tool you still need sometimes, keep it installed;"
W "   this script already stopped it from auto-starting at boot.)"
Flush
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Read-Host "Press Enter to close"
