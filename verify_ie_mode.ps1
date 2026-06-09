# =====================================================================
# Post-restart verify: is Edge IE-mode policy actually in effect?
# Does NOT touch EBS. Read-only. No admin needed. ASCII only.
# Output: verify_ie_mode_log.txt
# =====================================================================
$Out = Join-Path $PSScriptRoot "verify_ie_mode_log.txt"
if (-not $PSScriptRoot) { $Out = "$env:USERPROFILE\Documents\verify_ie_mode_log.txt" }
$log = New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try { $log.ToString() | Out-File -FilePath $Out -Encoding UTF8 } catch {} }

W "Verify Edge IE-mode  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Machine: $env:COMPUTERNAME  User: $env:USERNAME"

# 1. policy value still set (HKLM)?
W ""
W "==== 1. Edge IE-mode policy (HKLM) ===="
$polOk = $false
try {
    $v = (Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name InternetExplorerIntegrationLevel -EA Stop).InternetExplorerIntegrationLevel
    W "  InternetExplorerIntegrationLevel = $v"
    if ($v -eq 1) { $polOk = $true }
} catch { W "  not set / read failed: $($_.Exception.Message)" }

# 2. IE-mode FoD still installed?
W ""
W "==== 2. IE-mode FoD ===="
$fodOk = $false
try {
    $cap = Get-WindowsCapability -Online -Name 'Browser.InternetExplorer~~~~0.0.11.0' -EA Stop
    W "  State: $($cap.State)"
    if ($cap.State -eq 'Installed') { $fodOk = $true }
} catch { W "  query failed (may need admin to query): $($_.Exception.Message)" }

# 3. Edge managed-policy cache: does Edge SEE the policy?
#    Edge mirrors active policies under this key when it loads them.
W ""
W "==== 3. does Edge actually see the policy ===="
$seen = $false
foreach($k in @("HKLM:\SOFTWARE\Policies\Microsoft\Edge","HKCU:\SOFTWARE\Policies\Microsoft\Edge")){
    if(Test-Path $k){
        $p = Get-ItemProperty $k -EA SilentlyContinue
        if($null -ne $p.InternetExplorerIntegrationLevel){
            W "  $k InternetExplorerIntegrationLevel = $($p.InternetExplorerIntegrationLevel)"
            $seen = $true
        }
        if($null -ne $p.InternetExplorerIntegrationSiteList){
            W "  $k SiteList = $($p.InternetExplorerIntegrationSiteList)"
        }
    }
}
if(-not $seen){ W "  no IntegrationLevel found in policy keys" }

# 4. Edge version + running procs
W ""
W "==== 4. Edge state ===="
$edgeExe = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
if(Test-Path $edgeExe){ W "  Edge ver: $((Get-Item $edgeExe).VersionInfo.ProductVersion)" }
$ep = @(Get-Process msedge -EA SilentlyContinue)
W "  msedge processes running: $($ep.Count)"
W "  (if >0, Edge must be fully closed once for fresh policy load - or just rely on this restart)"

Flush

# 5. self-check
W ""
W "==== SELF-CHECK ===="
W "  [$(if($fodOk){'PASS'}else{'FAIL'})] IE-mode FoD installed"
W "  [$(if($polOk){'PASS'}else{'FAIL'})] IE-mode policy = 1"
if($fodOk -and $polOk){
    W "  >> READY. Open Edge -> edge://settings/defaultBrowser ->"
    W "     'Allow sites to be reloaded in Internet Explorer mode' should be set/locked to Allow."
    W "     If it shows 'managed by your organization' = policy is live."
} else {
    W "  >> NOT READY. See which line FAILED above."
}

Flush
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Write-Host "Send back: git add -A && git commit -m log && git push" -ForegroundColor Cyan
Read-Host "Press Enter to close"
