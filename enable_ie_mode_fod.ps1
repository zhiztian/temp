# =====================================================================
# Enable Win11 IE-mode Feature-on-Demand (FoD) - the prerequisite for
# Edge IE mode (the international standard way to run legacy IE-engine
# apps like Oracle EBS Forms). Self-elevates to admin. ASCII only.
# Output: enable_ie_fod_log.txt   (does NOT touch EBS)
# =====================================================================

# --- self-elevate to admin ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Not admin. Relaunching elevated (UAC prompt will appear)..." -ForegroundColor Yellow
    $scriptPath = $MyInvocation.MyCommand.Path
    try {
        Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy","Bypass","-File","`"$scriptPath`""
        Write-Host "Elevated process started in a new window. Watch that window." -ForegroundColor Cyan
    } catch {
        Write-Host "Elevation failed/cancelled: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "You must be a local admin and approve the UAC prompt." -ForegroundColor Red
    }
    Read-Host "Press Enter to close this (non-admin) window"
    return
}

# --- now running as admin ---
$Out = Join-Path $PSScriptRoot "enable_ie_fod_log.txt"
if (-not $PSScriptRoot) { $Out = "$env:USERPROFILE\Documents\enable_ie_fod_log.txt" }
$log = New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }

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

# 3. verify after
W ""
W "==== 3. verify after ===="
try {
    $cap2 = Get-WindowsCapability -Online -Name 'Browser.InternetExplorer~~~~0.0.11.0' -ErrorAction Stop
    W "  State now: $($cap2.State)"
} catch { W "  re-query failed: $($_.Exception.Message)" }

# 4. set Edge IE-mode policy at HKLM (admin can write here; HKCU was denied)
W ""
W "==== 4. enable Edge IE-mode policy (HKLM) ===="
try {
    if (-not (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge")) {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Force | Out-Null
    }
    New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "InternetExplorerIntegrationLevel" -Value 1 -PropertyType DWord -Force | Out-Null
    $v = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name InternetExplorerIntegrationLevel).InternetExplorerIntegrationLevel
    W "  InternetExplorerIntegrationLevel = $v  (1 = IE mode allowed)"
} catch {
    W "  policy write failed: $($_.Exception.Message)"
}

W ""
W "==== Next (no admin needed) ===="
W "  1. Restart the PC if section2 said RestartNeeded=True."
W "  2. Open Edge -> edge://settings/defaultBrowser"
W "  3. 'Allow sites to be reloaded in Internet Explorer mode' should now be available -> Allow."
W "  4. Then you have the same IE engine the rest of the world uses for EBS."
W ""
W "  (This script did NOT open EBS, per your request.)"

$log.ToString() | Out-File -FilePath $Out -Encoding UTF8
Write-Host ""
Write-Host "Log written: $Out (commit back)" -ForegroundColor Green
Read-Host "Press Enter to close"
