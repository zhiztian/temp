# =====================================================================
#  Daily EBS launcher - clean launch in IE mode.
#  Some IE-mode iexplore procs run at higher integrity and refuse to die
#  without admin -> this script self-elevates and uses taskkill /F /T.
#  Root cause (cdb): dual_engine_adapter NULL-deref on IE-mode exit leaves
#  bad state in resident Edge; killing ALL edge+ie = clean first launch.
#  ASCII only.   powershell -ExecutionPolicy Bypass -File .\open_ebs.ps1
# =====================================================================
param([string]$Stage = "")
$selfPath=$MyInvocation.MyCommand.Path
$EBS = "http://ebsprod.bytedance.net:8000"

# --- self-elevate so we can kill higher-integrity iexplore ---
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){
    Write-Host "Elevating to kill IE-mode processes (click Yes on UAC)..." -ForegroundColor Yellow
    $psExe="$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
    try{ Start-Process $psExe -Verb RunAs -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$selfPath`"") -Wait }
    catch{ Write-Host "Elevation failed: $($_.Exception.Message)" -ForegroundColor Red; Read-Host "Enter"; return }
    return
}

Write-Host "=== Clean launch EBS in IE mode (admin) ===" -ForegroundColor Cyan

# 1. force-kill ALL Edge + IE-mode processes with taskkill /F /T (tree, force)
$names = @("msedge.exe","iexplore.exe","ie_to_edge_stub.exe","msedgewebview2.exe")
foreach($n in $names){
    cmd /c "taskkill /F /T /IM $n >nul 2>&1"
}
Start-Sleep -Seconds 2
# second pass
foreach($n in $names){ cmd /c "taskkill /F /T /IM $n >nul 2>&1" }
Start-Sleep -Seconds 1

# report leftovers (if any still survive even with admin)
$left=@()
foreach($n in @("msedge","iexplore")){ $left += @(Get-Process -Name $n -ErrorAction SilentlyContinue) }
if($left.Count){
    Write-Host "  WARNING: still alive after force-kill:" -ForegroundColor Red
    foreach($p in $left){ Write-Host ("    {0} PID={1}" -f $p.ProcessName,$p.Id) }
}else{
    Write-Host "  all Edge/IE processes cleared." -ForegroundColor Green
}

# 2. locate Edge
$edge = $null
foreach($p in @("C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
                "C:\Program Files\Microsoft\Edge\Application\msedge.exe")){ if(Test-Path $p){$edge=$p;break} }
if(-not $edge){ Write-Host "Edge not found!" -ForegroundColor Red; Read-Host "Enter"; return }

# 3. open EBS (no flags; IE mode from site list policy)
Write-Host "  opening EBS ..." -ForegroundColor Cyan
Start-Process $edge -ArgumentList @($EBS)
Write-Host "Done. EBS should open and auto-switch to IE mode." -ForegroundColor Green
Write-Host ""
Write-Host "Next time: run THIS script again to open EBS (do NOT just click Edge icon)." -ForegroundColor Yellow
Start-Sleep -Seconds 2
