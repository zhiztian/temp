# =====================================================================
#  Daily EBS launcher: clear stale iexplore (Edge149 exit-crash residue)
#  then open EBS in Edge (IE mode comes from site list policy).
#  Use THIS to open EBS every day. No admin needed. ASCII only.
#     powershell -ExecutionPolicy Bypass -File .\open_ebs.ps1
# =====================================================================
$EBS = "http://ebsprod.bytedance.net:8000"

Write-Host "Clearing stale iexplore..." -ForegroundColor Cyan
$ie = @(Get-Process iexplore -ErrorAction SilentlyContinue)
if ($ie.Count) {
    Write-Host "  found $($ie.Count) stale iexplore, killing..."
    foreach($p in $ie){ try { Stop-Process -Id $p.Id -Force -ErrorAction Stop } catch {} }
    Start-Sleep -Seconds 1
} else {
    Write-Host "  none (clean)."
}

$edge = $null
foreach($p in @("C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
                "C:\Program Files\Microsoft\Edge\Application\msedge.exe")){ if(Test-Path $p){$edge=$p;break} }
if(-not $edge){ Write-Host "Edge not found!" -ForegroundColor Red; Read-Host "Enter"; return }

Write-Host "Opening EBS in Edge (IE mode via site list)..." -ForegroundColor Cyan
# NO command-line flags - IE mode comes from the site list policy
Start-Process $edge -ArgumentList @($EBS)
Write-Host "Done. EBS should open and switch to IE mode automatically." -ForegroundColor Green
Write-Host "(If it still errors: close ALL Edge + iexplore, then run this again.)"
Start-Sleep -Seconds 2
