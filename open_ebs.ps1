# =====================================================================
#  Daily EBS launcher - makes every launch a "clean first launch".
#  Root cause (cdb-confirmed): dual_engine_adapter NULL-deref on IE-mode
#  exit leaves bad state in the STILL-RUNNING msedge process (Edge keeps
#  running in background after you close the window). Restart "fixes" it
#  by killing msedge. So: kill ALL edge+ie before each launch.
#  No admin needed. ASCII only.
#     powershell -ExecutionPolicy Bypass -File .\open_ebs.ps1
# =====================================================================
$EBS = "http://ebsprod.bytedance.net:8000"

Write-Host "=== Clean launch EBS in IE mode ===" -ForegroundColor Cyan

# 1. kill ALL Edge + IE-mode processes (this is the key - not just iexplore)
$names = @("msedge","iexplore","ie_to_edge_stub","msedgewebview2")
foreach($n in $names){
    $procs = @(Get-Process -Name $n -ErrorAction SilentlyContinue)
    if($procs.Count){
        Write-Host "  killing $($procs.Count) x $n ..."
        foreach($p in $procs){ try{ Stop-Process -Id $p.Id -Force -ErrorAction Stop }catch{} }
    }
}
Start-Sleep -Seconds 2
# second pass (Edge can respawn child procs)
foreach($n in $names){
    Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object { try{ Stop-Process -Id $_.Id -Force }catch{} }
}
Start-Sleep -Seconds 1
Write-Host "  all Edge/IE processes cleared." -ForegroundColor Green

# 2. locate Edge
$edge = $null
foreach($p in @("C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
                "C:\Program Files\Microsoft\Edge\Application\msedge.exe")){ if(Test-Path $p){$edge=$p;break} }
if(-not $edge){ Write-Host "Edge not found!" -ForegroundColor Red; Read-Host "Enter"; return }

# 3. open EBS (no flags - IE mode comes from site list policy)
Write-Host "  opening EBS ..." -ForegroundColor Cyan
Start-Process $edge -ArgumentList @($EBS)
Write-Host "Done. EBS should open and auto-switch to IE mode (IE 'e' icon on tab)." -ForegroundColor Green
Write-Host ""
Write-Host "IMPORTANT: when finished, close EBS, and next time just run THIS script" -ForegroundColor Yellow
Write-Host "again - do NOT just reopen Edge (background Edge keeps the bad state)." -ForegroundColor Yellow
Start-Sleep -Seconds 2
