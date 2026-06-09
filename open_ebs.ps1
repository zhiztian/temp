# =====================================================================
#  Daily EBS launcher - clean launch with a FRESH throwaway Edge profile.
#  cdb proof: crash is identical even after force-killing all processes,
#  so the bad state is PERSISTENT (in Edge profile/disk), not in a process.
#  Fix: launch EBS in a brand-new temp profile each time (and kill leftovers).
#  Self-elevates (to kill higher-integrity iexplore). ASCII only.
#     powershell -ExecutionPolicy Bypass -File .\open_ebs.ps1
# =====================================================================
$selfPath=$MyInvocation.MyCommand.Path
$EBS = "http://ebsprod.bytedance.net:8000"

$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){
    Write-Host "Elevating (click Yes on UAC)..." -ForegroundColor Yellow
    $psExe="$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
    try{ Start-Process $psExe -Verb RunAs -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$selfPath`"") }
    catch{ Write-Host "Elevation failed: $($_.Exception.Message)" -ForegroundColor Red; Read-Host "Enter" }
    return
}

Write-Host "=== Clean launch EBS (fresh profile) ===" -ForegroundColor Cyan

# 1. force-kill all Edge + IE processes
foreach($n in @("msedge.exe","iexplore.exe","ie_to_edge_stub.exe","msedgewebview2.exe")){
    cmd /c "taskkill /F /T /IM $n >nul 2>&1"
}
Start-Sleep -Seconds 2
foreach($n in @("msedge.exe","iexplore.exe")){ cmd /c "taskkill /F /T /IM $n >nul 2>&1" }
Start-Sleep -Seconds 1
Write-Host "  processes cleared." -ForegroundColor Green

# 2. create a FRESH throwaway profile dir (delete old one first)
$prof = "C:\EBS_EdgeProfile"
try{
    if(Test-Path $prof){ Remove-Item $prof -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $prof -Force | Out-Null
    Write-Host "  fresh profile: $prof" -ForegroundColor Green
}catch{ Write-Host "  profile reset warn: $($_.Exception.Message)" -ForegroundColor Yellow }

# 3. locate Edge
$edge=$null
foreach($p in @("C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
                "C:\Program Files\Microsoft\Edge\Application\msedge.exe")){ if(Test-Path $p){$edge=$p;break} }
if(-not $edge){ Write-Host "Edge not found!" -ForegroundColor Red; Read-Host "Enter"; return }

# 4. open EBS in the fresh profile. IE-mode policy is machine-wide (HKLM)
#    so it still applies even with a custom user-data-dir.
Write-Host "  opening EBS in fresh profile ..." -ForegroundColor Cyan
Start-Process $edge -ArgumentList @("--user-data-dir=`"$prof`"","--no-first-run","--no-default-browser-check",$EBS)
Write-Host "Done. EBS opens in a clean profile -> bad persistent state bypassed." -ForegroundColor Green
Write-Host ""
Write-Host "Each run wipes the profile = always a clean IE-mode init." -ForegroundColor Yellow
Write-Host "(You may need to log into EBS each time since the profile is fresh.)" -ForegroundColor Yellow
Start-Sleep -Seconds 2
