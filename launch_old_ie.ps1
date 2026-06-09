# =====================================================================
# Launch "old IE" = open a page using Edge IE mode (the only IE-engine
# path on Win11). On ANY problem, capture full diagnostics to log.
# ASCII only. Output: launch_old_ie_log.txt
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File ./launch_old_ie.ps1
#   (optional) -Url "http://ebsprod.bytedance.net:8000"
# =====================================================================
param([string]$Url = "http://ebsprod.bytedance.net:8000")

$Out = Join-Path $PSScriptRoot "launch_old_ie_log.txt"
if (-not $PSScriptRoot) { $Out = "$env:USERPROFILE\Documents\launch_old_ie_log.txt" }
$log = New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try { $log.ToString() | Out-File -FilePath $Out -Encoding UTF8 } catch {} }

W "Launch old IE (Edge IE mode)  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Machine: $env:COMPUTERNAME  User: $env:USERNAME  Build: $([System.Environment]::OSVersion.Version)"
W "Target URL: $Url"

# locate Edge
$edge = $null
foreach($p in @("C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
                "C:\Program Files\Microsoft\Edge\Application\msedge.exe")){
    if(Test-Path $p){ $edge=$p; break }
}
if(-not $edge){ W "FATAL: msedge.exe not found"; Flush; Read-Host "Enter to close"; return }
W "Edge: $edge ($((Get-Item $edge).VersionInfo.ProductVersion))"

# pre-clean stale iexplore (top cause of the 'reinstall Edge' error)
$iep=@(Get-Process iexplore -EA SilentlyContinue)
if($iep.Count){ W "killing $($iep.Count) stale iexplore..."; $iep|ForEach-Object{ try{Stop-Process -Id $_.Id -Force}catch{} } }
Flush

# ---- attempt launch in IE mode ----
W ""
W "==== launch attempt: Edge --ie-mode-force ===="
$ok=$false
try {
    # --ie-mode-force opens the URL directly in IE mode (needs IE-mode allowed by policy)
    Start-Process $edge -ArgumentList @("--ie-mode-force", $Url)
    Start-Sleep -Seconds 8
    # verify: an IE-mode tab spins up an iexplore.exe child under Edge
    $iepAfter=@(Get-Process iexplore -EA SilentlyContinue)
    W "  iexplore procs after launch: $($iepAfter.Count)"
    foreach($p in $iepAfter){ W "    PID=$($p.Id) start=$($p.StartTime)" }
    $edgeAfter=@(Get-Process msedge -EA SilentlyContinue)
    W "  msedge procs: $($edgeAfter.Count)"
    if($iepAfter.Count -gt 0){
        W "  >> SUCCESS: IE engine (iexplore child) is running = page is in IE mode."
        $ok=$true
    } else {
        W "  >> NO iexplore child spawned = IE mode did NOT engage."
    }
} catch {
    W "  launch error: $($_.Exception.Message)"
}
Flush

# ---- if failed, capture root-cause diagnostics ----
if(-not $ok){
    W ""
    W "==== FAILURE DIAGNOSTICS ===="
    # 1) policy in effect?
    $key="HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    if(Test-Path $key){
        $p=Get-ItemProperty $key
        W "  IntegrationLevel = $($p.InternetExplorerIntegrationLevel)"
        W "  SiteList         = $($p.InternetExplorerIntegrationSiteList)"
    } else { W "  no Edge policy key (IE mode not enabled by policy!)" }
    # 2) IE-mode FoD (needs admin to query; note if denied)
    try {
        $cap=Get-WindowsCapability -Online -Name 'Browser.InternetExplorer~~~~0.0.11.0' -EA Stop
        W "  IE-mode FoD State = $($cap.State)"
    } catch { W "  FoD query needs admin: $($_.Exception.Message)" }
    # 3) Windows build/UBR (old = missing cumulative update => the reinstall error)
    try {
        $cv=Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
        W "  Windows build.UBR = $($cv.CurrentBuild).$($cv.UBR)  ($($cv.DisplayVersion))"
    } catch {}
    # 4) IE engine dll versions
    foreach($d in @("C:\Windows\System32\mshtml.dll","C:\Windows\System32\ieframe.dll")){
        if(Test-Path $d){ W "  $((Split-Path $d -Leaf)) ver=$((Get-Item $d).VersionInfo.FileVersion)" }
    }
    W ""
    W "  >> NEXT: open edge://compat/iediagnostic in Edge and read 'IE mode API version'."
    W "     If it is old (~10), the fix is full Windows Update + reboot (NOT reinstalling Edge)."
}
Flush

Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Write-Host "Send back: git add -A && git commit -m log && git push" -ForegroundColor Cyan
Read-Host "Press Enter to close"
