# =====================================================================
# Diagnose "reinstall Edge with admin" IE-mode error.
# Real cause is usually: missing Windows cumulative update (old IE mode
# API version) OR stale iexplore.exe procs. NOT a real reinstall need.
# ASCII only. Output: diag_ie_mode_error_log.txt
# =====================================================================
$Out = Join-Path $PSScriptRoot "diag_ie_mode_error_log.txt"
if (-not $PSScriptRoot) { $Out = "$env:USERPROFILE\Documents\diag_ie_mode_error_log.txt" }
$log = New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try { $log.ToString() | Out-File -FilePath $Out -Encoding UTF8 } catch {} }

W "IE-mode error diagnostic  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Machine: $env:COMPUTERNAME  User: $env:USERNAME"
W "OS Build: $([System.Environment]::OSVersion.Version)"

# 1. exact Windows build + UBR (update revision) - this is the key number
W ""
W "==== 1. Windows build + update revision (UBR) ===="
try {
    $cv = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
    W "  ProductName : $($cv.ProductName)"
    W "  DisplayVersion: $($cv.DisplayVersion)"
    W "  CurrentBuild: $($cv.CurrentBuild)"
    W "  UBR (revision): $($cv.UBR)"
    W "  -> full build: $($cv.CurrentBuild).$($cv.UBR)"
} catch { W "  read failed: $_" }
Flush

# 2. last installed hotfixes (did cumulative updates actually land?)
W ""
W "==== 2. recent installed updates (HotFix) ===="
try {
    Get-HotFix -ErrorAction SilentlyContinue | Sort-Object InstalledOn -Descending |
        Select-Object -First 8 | ForEach-Object { W "  $($_.HotFixID)  $($_.Description)  $($_.InstalledOn)" }
} catch { W "  Get-HotFix failed: $_" }
Flush

# 3. Edge install path + version (per-user vs system)
W ""
W "==== 3. Edge install location & version ===="
foreach($p in @("C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
                "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe")){
    if(Test-Path $p){
        W "  $p"
        W "    ProductVersion=$((Get-Item $p).VersionInfo.ProductVersion)"
        if($p -like "*LOCALAPPDATA*" -or $p -like "*$env:USERNAME*"){ W "    >> WARNING: per-user install - IE mode prefers system-wide (Program Files)" }
    }
}
Flush

# 4. stale iexplore.exe processes (intermittent-error cause)
W ""
W "==== 4. stale iexplore.exe processes ===="
$iep = @(Get-Process iexplore -ErrorAction SilentlyContinue)
W "  iexplore running: $($iep.Count)"
foreach($p in $iep){ W "    PID=$($p.Id) start=$($p.StartTime)" }
if($iep.Count -gt 0){
    W "  >> killing stale iexplore.exe ..."
    foreach($p in $iep){ try { Stop-Process -Id $p.Id -Force -ErrorAction Stop; W "    killed PID=$($p.Id)" } catch { W "    kill PID=$($p.Id) failed: $_" } }
}
Flush

# 5. mshtml / ieframe version (IE engine patch level)
W ""
W "==== 5. IE engine dll versions ===="
foreach($d in @("C:\Windows\System32\mshtml.dll","C:\Windows\System32\ieframe.dll")){
    if(Test-Path $d){ W "  $d  ver=$((Get-Item $d).VersionInfo.FileVersion)" } else { W "  MISSING: $d" }
}
Flush

# 6. policy snapshot
W ""
W "==== 6. Edge IE-mode policy snapshot ===="
$key="HKLM:\SOFTWARE\Policies\Microsoft\Edge"
if(Test-Path $key){
    $p=Get-ItemProperty $key
    W "  InternetExplorerIntegrationLevel = $($p.InternetExplorerIntegrationLevel)"
    W "  InternetExplorerIntegrationSiteList = $($p.InternetExplorerIntegrationSiteList)"
} else { W "  no Edge policy key" }

W ""
W "==== MANUAL CHECK (do this in Edge) ===="
W "  Open:  edge://compat/iediagnostic"
W "  Look at 'IE mode API version'. If it shows ~10 (old) -> missing Windows"
W "  cumulative update is the root cause. Run Windows Update fully + reboot."
W ""
W "==== What this script did ===="
W "  - Captured exact build/UBR + recent updates (to judge if WU is behind)"
W "  - Killed stale iexplore.exe (fixes the intermittent variant)"
W "  - After this: fully close Edge, reopen, try the site again."

Flush
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Write-Host "Also paste what edge://compat/iediagnostic shows for 'IE mode API version'." -ForegroundColor Cyan
Read-Host "Press Enter to close"
