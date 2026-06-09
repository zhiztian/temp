# =====================================================================
#  EBS IE Mode one-click setup  (Windows 11 / Edge IE Mode)
#  Fixes IE COM registry + IE mode policy/site list + logon auto-clean
#  task + clears residue. Then use open_ebs.ps1 daily to open EBS.
#  Auto-elevates (UAC prompt -> Yes). Usage:
#     powershell -ExecutionPolicy Bypass -File .\setup_ebs.ps1
#  (ASCII only to avoid PS5.1 GBK encoding issues)
# =====================================================================
param([string]$LogPath = "")
$selfPath = $MyInvocation.MyCommand.Path
$selfDir  = Split-Path -Parent $selfPath
if(-not $LogPath){ $LogPath = Join-Path $selfDir "setup_ebs_log.txt" }

# ---- auto-elevate (force 64-bit powershell) ----
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){
    Write-Host "Need admin. Requesting elevation (click Yes on UAC)..." -ForegroundColor Yellow
    $psExe = "$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
    try{ Start-Process $psExe -Verb RunAs -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$selfPath`"","-LogPath","`"$LogPath`"") }
    catch{ Write-Host "Elevation failed/cancelled: $($_.Exception.Message)" -ForegroundColor Red }
    Read-Host "Press Enter to close this window"; return
}

$Out=$LogPath; $log=New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try{ $log.ToString()|Out-File -FilePath $Out -Encoding UTF8 }catch{} }
function OK($b){ if($b){"[OK]"}else{"[FAIL]"} }

W "EBS IE Mode setup  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Machine: $env:COMPUTERNAME  User: $env:USERNAME"
W "================================================"

$iexploreValue = '"C:\Program Files\Internet Explorer\iexplore.exe"'
$iexplorePath  = "C:\Program Files\Internet Explorer\iexplore.exe"
if(-not(Test-Path $iexplorePath)){
    W "!! iexplore.exe not found, cannot continue"; Flush; Read-Host "Enter to close"; return
}

# ============ STEP 1: fix IE COM registry (point back to iexplore) ============
W ""
W "[STEP 1] Fix IE COM registry"
$CLSID="{0002DF01-0000-0000-C000-000000000046}"
# write physical HKLM keys only (HKCR is a merged view, unreliable for writes)
$physical=@(
  "SOFTWARE\Classes\CLSID\$CLSID\LocalServer32",
  "SOFTWARE\Classes\WOW6432Node\CLSID\$CLSID\LocalServer32"
)
$adminSid=New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid,$null)

function Set-IECom($sub,$val){
    $rk=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
    try{
        # try normal write first
        $key=$rk.OpenSubKey($sub,$true)
        if($null -eq $key){ $key=$rk.CreateSubKey($sub) }
        if($null -ne $key){
            try{ $key.SetValue("",$val,[Microsoft.Win32.RegistryValueKind]::String); $key.Close(); return $true }
            catch{ $key.Close() }
        }
        # denied -> take ownership then grant then write
        $ko=$rk.OpenSubKey($sub,[Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,[System.Security.AccessControl.RegistryRights]::TakeOwnership)
        if($null -eq $ko){ W "    cannot open for ownership: $sub"; return $false }
        $acl=$ko.GetAccessControl([System.Security.AccessControl.AccessControlSections]::None); $acl.SetOwner($adminSid); $ko.SetAccessControl($acl); $ko.Close()
        $k2=$rk.OpenSubKey($sub,[Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,[System.Security.AccessControl.RegistryRights]::ChangePermissions)
        $a2=$k2.GetAccessControl(); $rule=New-Object System.Security.AccessControl.RegistryAccessRule($adminSid,[System.Security.AccessControl.RegistryRights]::FullControl,"None","None","Allow"); $a2.AddAccessRule($rule); $k2.SetAccessControl($a2); $k2.Close()
        $k3=$rk.OpenSubKey($sub,$true); $k3.SetValue("",$val,[Microsoft.Win32.RegistryValueKind]::String); $k3.Close()
        return $true
    }catch{ W "    set failed $sub -> $($_.Exception.Message)"; return $false }
    finally{ $rk.Close() }
}

$fixed=0
foreach($sub in $physical){
    $ok = Set-IECom $sub $iexploreValue
    # verify
    $rk=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
    $v=$null
    try{ $kk=$rk.OpenSubKey($sub); if($kk){ $v=$kk.GetValue(""); $kk.Close() } }catch{}
    $rk.Close()
    if($v -match 'iexplore'){ $fixed++; W "  [OK] HKLM\$sub" }
    else { W "  [FAIL] HKLM\$sub  value=$v" }
}
W "  keys fixed: $fixed/2  $(OK ($fixed -eq 2))"
Flush

# ============ STEP 2: IE mode policy + site list ============
W ""
W "[STEP 2] Configure Edge IE mode policy + site list"
$xmlPath="C:\ProgramData\EdgeIEMode\sitelist.xml"
$xmlDir=Split-Path $xmlPath
if(-not(Test-Path $xmlDir)){ New-Item -ItemType Directory -Path $xmlDir -Force | Out-Null }
# build XML by string concat (no here-string, avoids newline/encoding pitfalls)
$nl=[Environment]::NewLine
$xml = '<site-list version="207">' + $nl
$xml += '  <site url="ebsprod.bytedance.net:8000" allow-redirect="true"><compat-mode>IE7Enterprise</compat-mode><open-in>IE11</open-in></site>' + $nl
$xml += '  <site url="ebsprod.bytedance.net" allow-redirect="true"><compat-mode>IE7Enterprise</compat-mode><open-in>IE11</open-in></site>' + $nl
$xml += '  <site url="sso.bytedance.com"><open-in>None</open-in></site>' + $nl
$xml += '  <site url="login.bytedance.com"><open-in>None</open-in></site>' + $nl
$xml += '</site-list>'
[System.IO.File]::WriteAllText($xmlPath,$xml,(New-Object System.Text.UTF8Encoding($false)))
$key="HKLM:\SOFTWARE\Policies\Microsoft\Edge"
if(-not(Test-Path $key)){ New-Item -Path $key -Force | Out-Null }
New-ItemProperty -Path $key -Name "InternetExplorerIntegrationLevel" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $key -Name "InternetExplorerIntegrationSiteList" -Value ("file:///"+($xmlPath -replace '\\','/')) -PropertyType String -Force | Out-Null
$lv=(Get-ItemProperty $key -Name InternetExplorerIntegrationLevel).InternetExplorerIntegrationLevel
W "  IE mode policy=1: $(OK ($lv -eq 1)) ; site list written: $(OK (Test-Path $xmlPath))"
Flush

# ============ STEP 3: logon auto-clean task ============
W ""
W "[STEP 3] Install logon auto-clean task (for Edge149 exit-crash residue)"
$taskName="ClearStaleIExplore"
# write a small cleaner script, point the task at it (keeps /TR under 261 chars)
$cleanerPath = Join-Path $env:ProgramData "ClearStaleIExplore.ps1"
$cleanerBody = 'Get-Process iexplore -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue'
[System.IO.File]::WriteAllText($cleanerPath, $cleanerBody, (New-Object System.Text.UTF8Encoding($false)))
schtasks /Delete /TN $taskName /F 2>$null | Out-Null
$action="powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$cleanerPath`""
$createOut = schtasks /Create /TN $taskName /TR $action /SC ONLOGON /RL HIGHEST /F 2>&1
$createRc = $LASTEXITCODE
$taskOk = ($createRc -eq 0)
W "  cleaner script: $cleanerPath"
W "  task '$taskName': $(OK $taskOk) (rc=$createRc)"
if(-not $taskOk){ W ("    schtasks output: {0}" -f ($createOut | Out-String).Trim()) }
Flush

# ============ STEP 4: clear current residue ============
W ""
W "[STEP 4] Clear current stale iexplore"
$ieList=@(Get-Process iexplore -ErrorAction SilentlyContinue)
W "  current iexplore count: $($ieList.Count), clearing..."
foreach($p in $ieList){ try{ Stop-Process -Id $p.Id -Force -ErrorAction Stop }catch{} }
Flush

# ============ STEP 5: live test (create IE COM) ============
W ""
W "[STEP 5] Live test: create IE COM object"
$comOk=$false
try{
    $ieTest=New-Object -ComObject InternetExplorer.Application -ErrorAction Stop
    if($ieTest){
        $comOk=$true
        W "  [OK] IE COM created - IE mode engine works!"
        try{ $ieTest.Quit(); [System.Runtime.InteropServices.Marshal]::ReleaseComObject($ieTest)|Out-Null }catch{}
    }
}catch{
    $hr=$_.Exception.HResult
    if($_.Exception.InnerException){ $hr=$_.Exception.InnerException.HResult }
    W ("  [FAIL] IE COM create failed: 0x{0:X8}" -f ($hr -band 0xFFFFFFFF))
    W ("         {0}" -f $_.Exception.Message)
}
Start-Sleep -Seconds 5

# if failed, grab latest iexplore crash (foreach, no nested pipelines)
if(-not $comOk){
    W "  -- recent iexplore crash (WER 1000/1001) --"
    try{
        $events = Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000,1001; StartTime=(Get-Date).AddMinutes(-3)} -ErrorAction SilentlyContinue
        $ieEvents = @($events | Where-Object { $_.Message -match 'iexplore' } | Select-Object -First 2)
        foreach($ev in $ieEvents){
            $lines = $ev.Message -split "`r?`n"
            $hit = @($lines | Where-Object { $_ -match 'iexplore|dual_engine|mshtml|c0000005|P4' } | Select-Object -First 6)
            foreach($line in $hit){ W ("    | {0}" -f $line.Trim()) }
            W "    ----"
        }
    }catch{ W ("    (read crash log failed: {0})" -f $_.Exception.Message) }
    if(Test-Path "C:\IEDumps"){
        $d=@(Get-ChildItem "C:\IEDumps" -Filter *.dmp -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        if($d.Count){ W ("    latest dump: {0} ({1} KB)" -f $d[0].FullName,[int]($d[0].Length/1KB)) }
    }
}
Flush

# ============ summary ============
W ""
W "================================================"
W "Setup done. Summary:"
W "  STEP1 registry  : $(OK ($fixed -eq 2))"
W "  STEP2 IE policy : $(OK ($lv -eq 1))"
W "  STEP3 autoclean : $(OK $taskOk)"
W "  STEP5 IE test   : $(OK $comOk)"
if(-not $comOk){
    W ""
    W "  !! Live test not passed. NOTE: IE mode policy needs a REBOOT to fully apply."
    W "     After reboot, open EBS with open_ebs.ps1. If still failing, send setup_ebs_log.txt back."
}
W ""
W "[Daily use] To open EBS, run:"
W "    powershell -ExecutionPolicy Bypass -File .\open_ebs.ps1"
W "  or just open Edge to http://ebsprod.bytedance.net:8000 (auto IE mode)"
W ""
W "[If error again] Close ALL Edge, end all iexplore in Task Manager, reopen."
W "[Root cause] Edge 149 dual_engine_adapter crashes on iexplore exit; MS will fix in a later version."
Flush
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Read-Host "Press Enter to close"
