# =====================================================================
#  Upgrade Edge back to 149 (latest). Undoes the earlier 148 downgrade
#  lock first (UpdateDefault / TargetVersionPrefix / firewall block),
#  then installs latest Edge. Self-elevates. ASCII only.
#     powershell -ExecutionPolicy Bypass -File .\upgrade_to_149.ps1
# =====================================================================
param([string]$LogPath="")
$selfPath=$MyInvocation.MyCommand.Path; $selfDir=Split-Path -Parent $selfPath
if(-not $LogPath){ $LogPath=Join-Path $selfDir "upgrade_149_log.txt" }
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){
    $psExe="$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
    try{ Start-Process $psExe -Verb RunAs -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$selfPath`"","-LogPath","`"$LogPath`"") }catch{}
    Read-Host "Enter to close"; return
}
$Out=$LogPath; $log=New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try{ $log.ToString()|Out-File -FilePath $Out -Encoding UTF8 }catch{} }
function OK($b){ if($b){"[OK]"}else{"[FAIL]"} }

W "Upgrade Edge back to 149  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "================================================"
$cur=(Get-ItemProperty "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" -EA SilentlyContinue).VersionInfo.ProductVersion
W "Current Edge: $cur"

# 1. remove the 148 update lock
W ""
W "[1] Remove 148 update lock"
$euk="HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate"
if(Test-Path $euk){
    foreach($vn in @("UpdateDefault","TargetVersionPrefixStable","Update{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}")){
        try{ Remove-ItemProperty -Path $euk -Name $vn -ErrorAction SilentlyContinue; W "  removed $vn" }catch{}
    }
}else{ W "  no EdgeUpdate policy key" }
# remove firewall block on the updater
netsh advfirewall firewall delete rule name="Block Edge Update" 2>$null | Out-Null
W "  removed firewall block on updater"
Flush

# 2. upgrade via winget (gets latest stable = 149)
W ""
W "[2] Upgrade Edge via winget"
$p = Start-Process winget.exe -ArgumentList "install --id Microsoft.Edge --accept-source-agreements --accept-package-agreements --disable-interactivity --force" -Wait -PassThru
W "  winget exit: $($p.ExitCode)"
Flush

# 3. fallback: trigger EdgeUpdate directly if winget didn't bump version
Start-Sleep -Seconds 3
$mid=(Get-ItemProperty "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" -EA SilentlyContinue).VersionInfo.ProductVersion
if($mid -notlike "149.*" -and $mid -notlike "15*"){
    W ""
    W "[3] winget didn't bump; trigger EdgeUpdate directly"
    $upd="C:\Program Files (x86)\Microsoft\EdgeUpdate\MicrosoftEdgeUpdate.exe"
    if(Test-Path $upd){
        Start-Process $upd -ArgumentList "/silent /install appguid={56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}&appname=Microsoft%20Edge&needsadmin=True&ap=stable-arch_x64" -Wait
        W "  EdgeUpdate triggered"
        Start-Sleep -Seconds 30
    }else{ W "  EdgeUpdate.exe not found" }
}
Flush

# 4. verify
W ""
W "[4] Verify"
$new=(Get-ItemProperty "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" -EA SilentlyContinue).VersionInfo.ProductVersion
$verOk = ($new -like "149.*" -or $new -like "15*")
W "  Edge version now: $new  $(OK $verOk)"

# 5. test IE COM on 149
W ""
W "[5] Test IE COM after upgrade"
Get-Process iexplore -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
Start-Sleep 2
try{
    $ie=New-Object -ComObject InternetExplorer.Application -EA Stop
    W "  [OK] IE COM created on $new !"
    try{ $ie.Quit()|Out-Null }catch{}
}catch{
    $hr=$_.Exception.HResult; if($_.Exception.InnerException){$hr=$_.Exception.InnerException.HResult}
    W ("  [FAIL] IE COM: 0x{0:X8}" -f ($hr -band 0xFFFFFFFF))
}
Flush

W ""
W "================================================"
W "  Edge: $cur -> $new  $(OK $verOk)"
W "  NEXT: reboot, then test EBS."
Flush
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Read-Host "Press Enter to close"
