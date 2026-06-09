# =====================================================================
# Enable Win11 IE-mode Feature-on-Demand (FoD) - the prerequisite for
# Edge IE mode (the international standard way to run legacy IE-engine
# apps like Oracle EBS Forms). Self-elevates to admin. ASCII only.
# Output: enable_ie_fod_log.txt   (does NOT touch EBS)
# =====================================================================

# --- accept log path as param so elevated child writes to SAME repo dir ---
param([string]$LogPath = "")

# resolve the repo dir of THIS script (works before elevation)
$selfPath = $MyInvocation.MyCommand.Path
$selfDir  = Split-Path -Parent $selfPath
if (-not $LogPath) { $LogPath = Join-Path $selfDir "enable_ie_fod_log.txt" }

# --- self-elevate to admin, passing the log path through ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Not admin. Relaunching elevated (UAC prompt will appear)..." -ForegroundColor Yellow
    Write-Host "Log will be written to: $LogPath" -ForegroundColor Cyan
    try {
        Start-Process powershell -Verb RunAs -ArgumentList @(
            "-ExecutionPolicy","Bypass","-File","`"$selfPath`"","-LogPath","`"$LogPath`""
        )
        Write-Host "Elevated window opened. When it finishes, the log is at the path above." -ForegroundColor Cyan
    } catch {
        Write-Host "Elevation failed/cancelled: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "You must be a local admin and approve the UAC prompt." -ForegroundColor Red
    }
    Read-Host "Press Enter to close this (non-admin) window"
    return
}

# --- now running as admin ---
$Out = $LogPath
$log = New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
# flush helper: write log to disk immediately so a crash still leaves a log
function Flush(){ try { $log.ToString() | Out-File -FilePath $Out -Encoding UTF8 } catch {} }
W "Log target: $Out"

W "Enable IE-mode FoD (ADMIN)  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Machine: $env:COMPUTERNAME  User: $env:USERNAME"
W "Build: $([System.Environment]::OSVersion.Version)"

# 1. check current state
W ""
W "==== 1. current IE-mode FoD state ===="
$cap = $null
try {
    $cap = Get-WindowsCapability -Online -Name 'Browser.InternetExplorer~~~~0.0.11.0' -ErrorAction Stop
    W "  Name : $($cap.Name)"
    W "  State: $($cap.State)"
} catch {
    W "  query failed: $($_.Exception.Message)"
}
Flush

# 2. install if not present
W ""
W "==== 2. install if needed ===="
if ($cap -and $cap.State -eq 'Installed') {
    W "  Already Installed. No install needed."
    W "  >> If Edge IE mode still failed before, the issue is just enabling it"
    W "     in Edge settings (no admin) - not the FoD."
} else {
    W "  State is '$($cap.State)'. Attempting Add-WindowsCapability..."
    try {
        $r = Add-WindowsCapability -Online -Name 'Browser.InternetExplorer~~~~0.0.11.0' -ErrorAction Stop
        W "  Add-WindowsCapability result: $($r.RestartNeeded)"
        W "  RestartNeeded: $($r.RestartNeeded)"
    } catch {
        W "  Add via Capability failed: $($_.Exception.Message)"
        W "  Trying DISM fallback..."
        $d = dism.exe /Online /Add-Capability /CapabilityName:Browser.InternetExplorer~~~~0.0.11.0 2>&1
        W ($d | Out-String)
    }
}
Flush

# 3. verify after
W ""
W "==== 3. verify after ===="
$stateNow = "unknown"
try {
    $cap2 = Get-WindowsCapability -Online -Name 'Browser.InternetExplorer~~~~0.0.11.0' -ErrorAction Stop
    $stateNow = $cap2.State
    W "  State now: $stateNow"
} catch { W "  re-query failed: $($_.Exception.Message)" }
Flush

# 4. set Edge IE-mode policy at HKLM (admin can write here; HKCU was denied)
W ""
W "==== 4. enable Edge IE-mode policy (HKLM) ===="
try {
    if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge")) {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Force | Out-Null
    }
    New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "InternetExplorerIntegrationLevel" -Value 1 -PropertyType DWord -Force | Out-Null
    $v = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name InternetExplorerIntegrationLevel).InternetExplorerIntegrationLevel
    $policyVal = $v
    W "  InternetExplorerIntegrationLevel = $v  (1 = IE mode allowed)"
} catch {
    $policyVal = "FAILED"
    W "  policy write failed: $($_.Exception.Message)"
}
Flush

# --- SELF-CHECK: explicit PASS/FAIL ---
W ""
W "==== SELF-CHECK ===="
$fodOk    = ($stateNow -eq 'Installed')
$polOk    = ($policyVal -eq 1)
W "  [$(if($fodOk){'PASS'}else{'FAIL'})] IE-mode FoD installed   (State=$stateNow)"
W "  [$(if($polOk){'PASS'}else{'FAIL'})] Edge IE-mode policy set  (InternetExplorerIntegrationLevel=$policyVal)"
if ($fodOk -and $polOk) {
    W "  >> OVERALL: PASS. Restart PC, then Edge IE mode is ready (enable in edge://settings/defaultBrowser)."
} elseif (-not $fodOk) {
    W "  >> OVERALL: FAIL. FoD not installed - likely no internet for FoD download, or blocked by WSUS/IT."
    W "     Ask IT for the matching Win11 FoD source, or check internet connectivity."
} else {
    W "  >> OVERALL: PARTIAL. FoD ok but policy write failed - check admin rights / managed policy."
}

W ""
W "==== Next (no admin needed) ===="
W "  1. Restart the PC if any install happened above."
W "  2. Open Edge -> edge://settings/defaultBrowser"
W "  3. 'Allow sites to be reloaded in Internet Explorer mode' -> Allow."
W "  4. Then you have the same IE engine the rest of the world uses for EBS."
W ""
W "  (This script did NOT open EBS, per your request.)"

Flush
Write-Host ""
Write-Host "Log written: $Out" -ForegroundColor Green
Write-Host "To send back, in Git Bash repo dir: git add -A && git commit -m log && git push" -ForegroundColor Cyan
Read-Host "Press Enter to close"
