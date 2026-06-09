# =====================================================================
# Daily-use launcher: clear stale iexplore (left by the Edge 149
# dual_engine_adapter exit-crash), then open EBS in Edge (IE mode via
# site list policy). Use THIS to open EBS every day.
# No admin needed (killing own iexplore is allowed). ASCII only.
# =====================================================================
$EBS = "http://ebsprod.bytedance.net:8000"

Write-Host "Clearing stale iexplore..." -ForegroundColor Cyan
$ie = @(Get-Process iexplore -ErrorAction SilentlyContinue)
if ($ie.Count) {
    Write-Host "  found $($ie.Count) stale iexplore, killing..."
    $ie | ForEach-Object { try { Stop-Process -Id $_.Id -Force -EA Stop } catch {} }
    Start-Sleep -Seconds 1
} else {
    Write-Host "  none (clean)."
}

# locate Edge
$edge = $null
foreach($p in @("C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
                "C:\Program Files\Microsoft\Edge\Application\msedge.exe")){ if(Test-Path $p){$edge=$p;break} }
if(-not $edge){ Write-Host "Edge not found!" -ForegroundColor Red; Read-Host "Enter"; return }

Write-Host "Opening EBS in Edge (IE mode via site list)..." -ForegroundColor Cyan
# NO command-line flags - IE mode comes from the site list policy
Start-Process $edge -ArgumentList @($EBS)
Write-Host "Done. EBS should open and switch to IE mode automatically." -ForegroundColor Green
Write-Host "(If it still errors, close ALL Edge + iexplore and run this again.)"
Start-Sleep -Seconds 2
