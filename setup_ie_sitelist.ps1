# =====================================================================
# Auto IE-mode for a fixed URL: build Enterprise Mode SiteList XML and
# point Edge policy at it, so the URL ALWAYS opens with IE engine in Edge.
# Self-elevates to admin. ASCII only. Output: setup_ie_sitelist_log.txt
# =====================================================================
param([string]$LogPath = "")

# sites that should open in IE mode (the EBS forms host)
$IE_SITES = @("ebsprod.bytedance.net:8000","ebsprod.bytedance.net")
# neutral sites: SSO/auth hosts MUST be neutral, else IE-mode login redirects
# to Edge and auth fails (EBS login bounces through sso.bytedance.com).
$NEUTRAL_SITES = @("sso.bytedance.com","login.bytedance.com")
# schema MUST be v.2; version attr is an incrementing integer
$SITELIST_VERSION = 205

$selfPath = $MyInvocation.MyCommand.Path
$selfDir  = Split-Path -Parent $selfPath
if (-not $LogPath) { $LogPath = Join-Path $selfDir "setup_ie_sitelist_log.txt" }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Not admin. Relaunching elevated (approve UAC)..." -ForegroundColor Yellow
    Write-Host "Log -> $LogPath" -ForegroundColor Cyan
    try {
        Start-Process powershell -Verb RunAs -ArgumentList @(
            "-ExecutionPolicy","Bypass","-File","`"$selfPath`"","-LogPath","`"$LogPath`""
        )
    } catch { Write-Host "Elevation failed: $($_.Exception.Message)" -ForegroundColor Red }
    Read-Host "Press Enter to close this window"
    return
}

$Out = $LogPath
$log = New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try { $log.ToString() | Out-File -FilePath $Out -Encoding UTF8 } catch {} }

W "Setup IE-mode SiteList (ADMIN)  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Machine: $env:COMPUTERNAME  User: $env:USERNAME"
W "IE-mode sites : $($IE_SITES -join ', ')"
W "Neutral sites : $($NEUTRAL_SITES -join ', ')"

# 1. build Enterprise Mode Site List XML (schema v.2)
W ""
W "==== 1. write SiteList XML (schema v.2) ===="
$xmlPath = "C:\ProgramData\EdgeIEMode\sitelist.xml"
$xmlDir  = Split-Path -Parent $xmlPath
try {
    if (-not (Test-Path $xmlDir)) { New-Item -ItemType Directory -Path $xmlDir -Force | Out-Null }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("<site-list version=`"$SITELIST_VERSION`">")
    # IE-mode sites: compat-mode IE11 + open-in IE11, allow server-side redirects
    foreach($s in $IE_SITES){
        [void]$sb.AppendLine("  <site url=`"$s`" allow-redirect=`"true`">")
        [void]$sb.AppendLine('    <compat-mode>IE7Enterprise</compat-mode>')
        [void]$sb.AppendLine('    <open-in>IE11</open-in>')
        [void]$sb.AppendLine('  </site>')
    }
    # neutral sites (SSO): open-in None so auth stays in whichever engine started
    foreach($s in $NEUTRAL_SITES){
        [void]$sb.AppendLine("  <site url=`"$s`">")
        [void]$sb.AppendLine('    <open-in>None</open-in>')
        [void]$sb.AppendLine('  </site>')
    }
    [void]$sb.AppendLine('</site-list>')
    # write WITHOUT BOM (Edge XML parser dislikes UTF-8 BOM)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($xmlPath, $sb.ToString(), $enc)
    W "  written: $xmlPath"
    W "  --- content ---"
    Get-Content $xmlPath | ForEach-Object { W "    $_" }
} catch { W "  XML write failed: $($_.Exception.Message)" }
Flush

# 2. policy: IntegrationLevel=1 + point to sitelist (file:/// url)
W ""
W "==== 2. set Edge policies (HKLM) ===="
$key = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
$fileUrl = "file:///" + ($xmlPath -replace '\\','/')
$polLevelOk = $false; $polListOk = $false
try {
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    New-ItemProperty -Path $key -Name "InternetExplorerIntegrationLevel" -Value 1 -PropertyType DWord -Force | Out-Null
    $lv = (Get-ItemProperty $key -Name InternetExplorerIntegrationLevel).InternetExplorerIntegrationLevel
    W "  InternetExplorerIntegrationLevel = $lv"
    if ($lv -eq 1) { $polLevelOk = $true }

    New-ItemProperty -Path $key -Name "InternetExplorerIntegrationSiteList" -Value $fileUrl -PropertyType String -Force | Out-Null
    $sl = (Get-ItemProperty $key -Name InternetExplorerIntegrationSiteList).InternetExplorerIntegrationSiteList
    W "  InternetExplorerIntegrationSiteList = $sl"
    if ($sl -eq $fileUrl) { $polListOk = $true }
} catch { W "  policy write failed: $($_.Exception.Message)" }
Flush

# 3. self-check
W ""
W "==== SELF-CHECK ===="
$xmlOk = Test-Path $xmlPath
# validate XML is well-formed AND has expected structure
$xmlValid = $false; $ieCount = 0; $neutralCount = 0
if ($xmlOk) {
    try {
        [xml]$doc = Get-Content $xmlPath -Raw
        $verAttr = $doc.'site-list'.version
        foreach($node in $doc.'site-list'.site){
            if ($node.'open-in' -eq 'IE11') { $ieCount++ }
            elseif ($node.'open-in' -eq 'None') { $neutralCount++ }
        }
        $xmlValid = ($null -ne $doc.'site-list' -and [int]$verAttr -ge 2 -and $ieCount -ge 1)
        W "  XML parsed OK: version=$verAttr, IE11 sites=$ieCount, neutral sites=$neutralCount"
    } catch { W "  XML parse FAILED: $($_.Exception.Message)" }
}
W "  [$(if($xmlOk){'PASS'}else{'FAIL'})] SiteList XML exists"
W "  [$(if($xmlValid){'PASS'}else{'FAIL'})] XML well-formed, schema>=2, has IE11 site(s)"
W "  [$(if($polLevelOk){'PASS'}else{'FAIL'})] IntegrationLevel=1"
W "  [$(if($polListOk){'PASS'}else{'FAIL'})] SiteList policy points to XML"
if ($xmlOk -and $xmlValid -and $polLevelOk -and $polListOk) {
    W "  >> PASS. Next (per Microsoft/Oracle standard rollout):"
    W "     1. RESTART THE PC (not just Edge). MS docs: reboot, sometimes twice,"
    W "        so the IE11 feature + policy fully register. This is the most"
    W "        common reason 'reinstall Edge' error appears - reboot fixes it."
    W "     2. After reboot, open the EBS site in Edge - it auto-loads in IE mode"
    W "        (IE 'e' icon on the tab). compat-mode is IE7Enterprise (EBS standard)."
    W "     3. Verify live policy at: edge://policy (search IntegrationSiteList)."
    W "     4. If still 'reinstall Edge': open edge://compat/iediagnostic, read"
    W "        'IE mode API version'. Old (~10) => run Windows Update fully + reboot."
} else {
    W "  >> Some step FAILED, see above."
}
Flush
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Write-Host "Send back: git add -A && git commit -m log && git push" -ForegroundColor Cyan
Read-Host "Press Enter to close"
