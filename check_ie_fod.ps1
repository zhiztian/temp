# =====================================================================
# Check Windows 11 IE-mode Feature-on-Demand (FoD) status (ASCII only)
# Root cause per Oracle/MS docs: Edge IE mode needs the "Internet Explorer
# mode" FoD installed. If NotPresent -> that's why IE mode fails.
# READ-ONLY. No admin needed for checking. Output: check_ie_fod_log.txt
# =====================================================================
$Out = Join-Path $PSScriptRoot "check_ie_fod_log.txt"
if (-not $PSScriptRoot) { $Out = "check_ie_fod_log.txt" }
$log = New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }

W "IE-mode FoD check  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Machine: $env:COMPUTERNAME  User: $env:USERNAME"

# admin?
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
W "Running as admin: $isAdmin"

W ""
W "==== 1. IE FoD capability state ===="
try {
    $cap = Get-WindowsCapability -Online -Name 'Browser.InternetExplorer~~~~0.0.11.0' -ErrorAction Stop
    W "  Name : $($cap.Name)"
    W "  State: $($cap.State)"
} catch {
    W "  Get-WindowsCapability failed: $($_.Exception.Message)"
}

W ""
W "==== 2. all InternetExplorer related capabilities ===="
try {
    Get-WindowsCapability -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'InternetExplorer' } |
        ForEach-Object { W "  $($_.Name) = $($_.State)" }
} catch { W "  enum failed: $_" }

W ""
W "==== 3. legacy optional feature (Win10-style, may not exist on Win11) ===="
try {
    $f = Get-WindowsOptionalFeature -Online -FeatureName 'Internet-Explorer-Optional-amd64' -ErrorAction SilentlyContinue
    if ($f) { W "  Internet-Explorer-Optional-amd64 = $($f.State)" } else { W "  (feature not listed - normal on Win11)" }
} catch { W "  $_" }

W ""
W "==== 4. Java bitness (EBS Forms often needs 32-bit JRE) ===="
$j32 = "HKLM:\SOFTWARE\WOW6432Node\JavaSoft\Java Runtime Environment\1.8"
$j64 = "HKLM:\SOFTWARE\JavaSoft\Java Runtime Environment\1.8"
if (Test-Path $j32) { W "  32-bit JRE 1.8: PRESENT ($((Get-ItemProperty $j32 -EA SilentlyContinue).JavaHome))" } else { W "  32-bit JRE 1.8: not found" }
if (Test-Path $j64) { W "  64-bit JRE 1.8: PRESENT ($((Get-ItemProperty $j64 -EA SilentlyContinue).JavaHome))" } else { W "  64-bit JRE 1.8: not found" }

W ""
W "==== 5. mshtml (IE engine dll) present? ===="
$m = "C:\Windows\System32\mshtml.dll"
if (Test-Path $m) { W "  mshtml.dll present, ver=$((Get-Item $m).VersionInfo.FileVersion)" } else { W "  mshtml.dll MISSING" }
$ieframe = "C:\Windows\System32\ieframe.dll"
if (Test-Path $ieframe) { W "  ieframe.dll present, ver=$((Get-Item $ieframe).VersionInfo.FileVersion)" } else { W "  ieframe.dll MISSING" }

W ""
W "==== Verdict ===="
W "  - Section1 State=Installed -> FoD OK, problem is just enabling Edge IE mode (next step, no admin)"
W "  - Section1 State=NotPresent -> THIS is the root cause. Need admin to run:"
W "        Add-WindowsCapability -Online -Name 'Browser.InternetExplorer~~~~0.0.11.0'"
W "  - Section4: if EBS needs 32-bit Java and only 64-bit present, that's a second issue"

$log.ToString() | Out-File -FilePath $Out -Encoding UTF8
Write-Host ""
Write-Host "Log written: $Out (commit back)" -ForegroundColor Green
