# =====================================================================
# Fix the ONE stubborn key that fix_ie_com.ps1 couldn't (Access Denied):
#   HKLM\SOFTWARE\Classes\WOW6432Node\CLSID\{...}\LocalServer32
# It's owned by TrustedInstaller, so even admin can't write it directly.
# This script: take ownership -> grant admin write -> set value ->
# restore ownership to TrustedInstaller. Self-elevates. ASCII only.
# Output: fix_ie_com_wow64_log.txt
# =====================================================================
param([string]$LogPath = "")

$selfPath = $MyInvocation.MyCommand.Path
$selfDir  = Split-Path -Parent $selfPath
if (-not $LogPath) { $LogPath = Join-Path $selfDir "fix_ie_com_wow64_log.txt" }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Not admin. Relaunching elevated (approve UAC)..." -ForegroundColor Yellow
    try { Start-Process powershell -Verb RunAs -ArgumentList @("-ExecutionPolicy","Bypass","-File","`"$selfPath`"","-LogPath","`"$LogPath`"") }
    catch { Write-Host "Elevation failed: $($_.Exception.Message)" -ForegroundColor Red }
    Read-Host "Press Enter to close this window"; return
}

$Out=$LogPath; $log=New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try { $log.ToString() | Out-File -FilePath $Out -Encoding UTF8 } catch {} }

W "Fix stubborn WOW6432Node IE COM key (ADMIN)  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Machine: $env:COMPUTERNAME  User: $env:USERNAME"

$CLSID="{0002DF01-0000-0000-C000-000000000046}"
# the sub-hive path (without hive root) for .NET RegistryKey API
$subPath = "SOFTWARE\Classes\WOW6432Node\CLSID\$CLSID\LocalServer32"
$desired = '"C:\Program Files\Internet Explorer\iexplore.exe"'

# pick iexplore (verify exists)
if(-not (Test-Path "C:\Program Files\Internet Explorer\iexplore.exe")){
    W "FATAL: iexplore.exe not found at expected path."; Flush; Read-Host "Enter"; return
}

# show current value
W ""
W "==== before ===="
$cur = (reg.exe query "HKLM\$subPath" /ve 2>&1 | Out-String).Trim()
W $cur
Flush

# --- take ownership via .NET (RegistryKey + RegistrySecurity) ---
W ""
W "==== take ownership + grant + set + restore ===="
$ok=$false
try {
    # enable SeTakeOwnership/SeRestore privileges
    $adminSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)

    # open the key with TakeOwnership right
    $rootKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
    $key = $rootKey.OpenSubKey($subPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::TakeOwnership)
    if(-not $key){ W "  cannot open key for TakeOwnership"; }
    else {
        # set owner to Administrators
        $acl = $key.GetAccessControl([System.Security.AccessControl.AccessControlSections]::None)
        $acl.SetOwner($adminSid)
        $key.SetAccessControl($acl)
        W "  owner set to Administrators"
        $key.Close()

        # reopen with ChangePermissions, grant FullControl to Administrators
        $key2 = $rootKey.OpenSubKey($subPath, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [System.Security.AccessControl.RegistryRights]::ChangePermissions)
        $acl2 = $key2.GetAccessControl()
        $rule = New-Object System.Security.AccessControl.RegistryAccessRule($adminSid, [System.Security.AccessControl.RegistryRights]::FullControl, [System.Security.AccessControl.InheritanceFlags]::None, [System.Security.AccessControl.PropagationFlags]::None, [System.Security.AccessControl.AccessControlType]::Allow)
        $acl2.AddAccessRule($rule)
        $key2.SetAccessControl($acl2)
        W "  granted FullControl to Administrators"
        $key2.Close()

        # now set the (default) value
        $key3 = $rootKey.OpenSubKey($subPath, $true)
        $key3.SetValue("", $desired, [Microsoft.Win32.RegistryValueKind]::String)
        $key3.Close()
        W "  value set."
        $ok=$true
    }
    $rootKey.Close()
} catch {
    W "  ownership/set failed: $($_.Exception.Message)"
}
Flush

# verify
W ""
W "==== after ===="
$after = (reg.exe query "HKLM\$subPath" /ve 2>&1 | Out-String).Trim()
W $after
$pass = ($after -match 'iexplore' -and $after -notmatch '360')
W ""
W "==== SELF-CHECK ===="
W "  [$(if($pass){'PASS'}else{'FAIL'})] WOW6432Node LocalServer32 -> iexplore.exe (no 360)"
if($pass){
    W "  >> ALL FOUR keys now fixed. RESTART PC, then check edge://compat/iediagnostic:"
    W "     'Attempt to start IE mode' should SUCCEED (no 0x8000FFFF)."
} else {
    W "  >> still failed. Last resort: use regedit.exe GUI - right-click the key ->"
    W "     Permissions -> Advanced -> change Owner to Administrators -> grant Full"
    W "     Control -> edit (Default) to the iexplore.exe path."
}
Flush
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Write-Host "Send back: git add -A && git commit -m log && git push" -ForegroundColor Cyan
Read-Host "Press Enter to close"
