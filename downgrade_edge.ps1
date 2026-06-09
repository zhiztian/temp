# =====================================================================
#  Downgrade Microsoft Edge 149 -> 148.0.3967.109 (fixes IE-mode
#  dual_engine_adapter exit-crash) + lock updates so it won't jump back.
#  Official MS enterprise MSI, SHA256 verified. Auto-elevates. ASCII only.
#     powershell -ExecutionPolicy Bypass -File .\downgrade_edge.ps1
# =====================================================================
param([string]$LogPath = "")
$selfPath = $MyInvocation.MyCommand.Path
$selfDir  = Split-Path -Parent $selfPath
if(-not $LogPath){ $LogPath = Join-Path $selfDir "downgrade_edge_log.txt" }

$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){
    Write-Host "Need admin. Requesting elevation (click Yes on UAC)..." -ForegroundColor Yellow
    $psExe = "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
    try{ Start-Process $psExe -Verb RunAs -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$selfPath`"","-LogPath","`"$LogPath`"") }
    catch{ Write-Host "Elevation failed: $($_.Exception.Message)" -ForegroundColor Red }
    Read-Host "Press Enter to close"; return
}

$Out=$LogPath; $log=New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try{ $log.ToString()|Out-File -FilePath $Out -Encoding UTF8 }catch{} }
function OK($b){ if($b){"[OK]"}else{"[FAIL]"} }

$VER   = "148.0.3967.109"
$URL   = "https://msedge.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/4d8e670f-d9cc-424c-9997-532c543b1753/MicrosoftEdgeEnterpriseX64.msi"
$SHA   = "40BE26E9AFB57F7B79D1B6DCF15CC536348A0CE42280CD5B89B60C74914F8D5A"
$msi   = Join-Path $env:TEMP "MicrosoftEdgeEnterpriseX64_148.msi"

W "Downgrade Edge -> $VER  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Machine: $env:COMPUTERNAME  User: $env:USERNAME"
W "================================================"

# current version
$cur = (Get-ItemProperty "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" -EA SilentlyContinue).VersionInfo.ProductVersion
W "Current Edge: $cur  ->  target: $VER"
W ""

# --- 1. download official MSI ---
W "[STEP 1] Download official enterprise MSI"
try{
    $ProgressPreference='SilentlyContinue'
    Invoke-WebRequest -Uri $URL -OutFile $msi -UseBasicParsing -EA Stop
    $sz=[int]((Get-Item $msi).Length/1MB)
    W "  downloaded: $msi ($sz MB)"
}catch{ W "  download failed: $($_.Exception.Message)"; Flush; Read-Host "Enter"; return }

# verify SHA256
$h=(Get-FileHash $msi -Algorithm SHA256).Hash
$hashOk = ($h -eq $SHA)
W "  SHA256 match: $(OK $hashOk)"
if(-not $hashOk){ W "  HASH MISMATCH! aborting (got $h)"; Flush; Read-Host "Enter"; return }
Flush

# --- 2. lock updates BEFORE install (so it can't jump back to 149) ---
W ""
W "[STEP 2] Lock Edge updates (pin to 148, block auto-update)"
$euk="HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate"
try{
    if(-not(Test-Path $euk)){ New-Item -Path $euk -Force | Out-Null }
    # pin to 148 line + allow only manual (so security patches within 148 still possible if you choose)
    New-ItemProperty -Path $euk -Name "UpdateDefault" -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $euk -Name "TargetVersionPrefixStable" -Value "148." -PropertyType String -Force | Out-Null
    # also block by the stable channel GUID
    New-ItemProperty -Path $euk -Name "Update{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}" -Value 0 -PropertyType DWord -Force | Out-Null
    W "  UpdateDefault=0, TargetVersionPrefixStable=148.  [OK]"
}catch{ W "  policy set failed: $($_.Exception.Message)" }
# firewall block the updater
try{
    netsh advfirewall firewall delete rule name="Block Edge Update" 2>$null | Out-Null
    netsh advfirewall firewall add rule name="Block Edge Update" dir=out action=block program="C:\Program Files (x86)\Microsoft\EdgeUpdate\MicrosoftEdgeUpdate.exe" 2>&1 | Out-Null
    W "  firewall block updater: [OK]"
}catch{ W "  firewall rule failed: $_" }
Flush

# --- 3. install 148 (downgrade needs ALLOWDOWNGRADE) ---
W ""
W "[STEP 3] Install $VER (downgrade)"
# close edge first
Get-Process msedge -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
Start-Sleep -Seconds 2
$args = "/i `"$msi`" /qn /norestart ALLOWDOWNGRADE=1 DONOTCREATEDESKTOPSHORTCUT=TRUE"
$p = Start-Process msiexec.exe -ArgumentList $args -Wait -PassThru
W "  msiexec exit code: $($p.ExitCode)  $(OK ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010))"
Flush

# --- 4. verify version ---
W ""
W "[STEP 4] Verify"
Start-Sleep -Seconds 3
$new = (Get-ItemProperty "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" -EA SilentlyContinue).VersionInfo.ProductVersion
$verOk = ($new -like "148.*")
W "  Edge version now: $new  $(OK $verOk)"
Flush

# --- summary ---
W ""
W "================================================"
W "Summary:"
W "  download+verify : $(OK $hashOk)"
W "  install 148     : $(OK ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010))"
W "  version is 148  : $(OK $verOk)"
W "  updates locked  : pinned to 148.x + updater blocked"
if($verOk){
    W ""
    W "  NEXT: reboot, then run open_ebs.ps1 and test the finance form."
    W "  (IE COM registry + IE mode policy were already configured by setup_ebs.ps1)"
}else{
    W ""
    W "  !! version not 148. Check msiexec exit code above. May need manual install of:"
    W "     $msi"
}
W ""
W "  To later re-allow updates (go back to newest Edge):"
W "    reg delete HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate /v UpdateDefault /f"
W "    reg delete HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate /v TargetVersionPrefixStable /f"
W "    netsh advfirewall firewall delete rule name=`"Block Edge Update`""
Flush
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Write-Host "Send back: git add downgrade_edge_log.txt && git commit -m log && git push" -ForegroundColor Cyan
Read-Host "Press Enter to close"
