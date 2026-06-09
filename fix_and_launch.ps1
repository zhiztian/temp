# =====================================================================
# Fix the intermittent "reinstall Edge" IE-mode error and launch EBS.
# Root cause (per MS): stale iexplore.exe left over from a previous IE-mode
# tab. Kill all iexplore + edge, then relaunch EBS in IE mode.
# ASCII only. Output: fix_and_launch_log.txt
#
# Run this whenever the "reinstall Edge" error shows up.
# =====================================================================
param([string]$Url = "http://ebsprod.bytedance.net:8000")

$Out = Join-Path $PSScriptRoot "fix_and_launch_log.txt"
if (-not $PSScriptRoot) { $Out = "$env:USERPROFILE\Documents\fix_and_launch_log.txt" }
$log = New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try { $log.ToString() | Out-File -FilePath $Out -Encoding UTF8 } catch {} }

W "Fix + launch EBS in IE mode  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Machine: $env:COMPUTERNAME  User: $env:USERNAME"
W "URL: $Url"

# locate Edge
$edge=$null
foreach($p in @("C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
                "C:\Program Files\Microsoft\Edge\Application\msedge.exe")){ if(Test-Path $p){$edge=$p;break} }
if(-not $edge){ W "FATAL: msedge.exe not found"; Flush; Read-Host "Enter"; return }
W "Edge: $edge ($((Get-Item $edge).VersionInfo.ProductVersion))"

# 1. kill stale iexplore (the actual fix)
W ""
W "==== 1. kill stale iexplore.exe ===="
$iep=@(Get-Process iexplore -EA SilentlyContinue)
W "  iexplore before: $($iep.Count)"
foreach($p in $iep){ W "    PID=$($p.Id) start=$($p.StartTime)" }
foreach($p in $iep){ try{ Stop-Process -Id $p.Id -Force -EA Stop; W "    killed $($p.Id)" }catch{ W "    kill $($p.Id) failed: $_" } }

# 2. close all Edge so policy + IE-mode host restart cleanly
W ""
W "==== 2. close all Edge ===="
$ep=@(Get-Process msedge -EA SilentlyContinue)
W "  msedge before: $($ep.Count)"
foreach($p in $ep){ try{ Stop-Process -Id $p.Id -Force -EA Stop }catch{} }
Start-Sleep -Seconds 3
W "  msedge after close: $(@(Get-Process msedge -EA SilentlyContinue).Count)"
Flush

# 3. relaunch EBS NORMALLY (NO command-line flags!)
#    Using any flag (e.g. --ie-mode-force) DISABLES IE mode for the whole
#    Edge session until restart. Site list already routes EBS to IE mode,
#    so we just open the URL normally and let policy do its job.
W ""
W "==== 3. relaunch EBS normally (no flags) ===="
$ok=$false
try {
    Start-Process $edge -ArgumentList @($Url)
    W "  launched: msedge `"$Url`"  (no flags - IE mode comes from site list policy)"
    W "  waiting up to 25s for IE-mode tab to spawn iexplore..."
    for($i=0; $i -lt 5; $i++){
        Start-Sleep -Seconds 5
        $iepA=@(Get-Process iexplore -EA SilentlyContinue)
        if($iepA.Count -gt 0){ break }
    }
    W "  iexplore after launch: $($iepA.Count)"
    foreach($p in $iepA){ W "    PID=$($p.Id)" }
    if($iepA.Count -gt 0){ W "  >> SUCCESS: IE engine running, EBS is in IE mode."; $ok=$true }
    else { W "  >> no iexplore yet - may need you to log in first (forms page triggers IE mode)." }
} catch { W "  launch error: $($_.Exception.Message)" }
Flush

# 4. on fail, capture diagnostics
if(-not $ok){
    W ""
    W "==== FAILURE DIAGNOSTICS ===="
    $key="HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    if(Test-Path $key){ $p=Get-ItemProperty $key
        W "  IntegrationLevel=$($p.InternetExplorerIntegrationLevel)  SiteList=$($p.InternetExplorerIntegrationSiteList)" }
    try{ $cv=Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
        W "  Windows build.UBR = $($cv.CurrentBuild).$($cv.UBR) ($($cv.DisplayVersion))" }catch{}
    W "  >> open edge://compat/iediagnostic, read 'IE mode API version'."
}

# 5. self-check
W ""
W "==== SELF-CHECK ===="
W "  [$(if($ok){'PASS'}else{'FAIL'})] EBS opened, IE engine running"
W "  NOTE: This script uses NO command-line flags (that was the bug before)."
W "  The fix for the recurring error is just: kill stale iexplore, then open"
W "  Edge normally. You can also do it by hand: close Edge, end any iexplore"
W "  in Task Manager, reopen Edge, go to EBS."
if($ok){ W "  >> If it recurs every restart, ask me to auto-clear iexplore at logon." }
Flush
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Write-Host "Send back: git add -A && git commit -m log && git push" -ForegroundColor Cyan
Read-Host "Press Enter to close"
