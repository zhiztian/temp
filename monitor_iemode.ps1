# =====================================================================
#  Continuous monitor: every N seconds, snapshot IE-mode critical state
#  to find WHEN/WHAT breaks it (explains "occasionally works").
#  Logs: IE COM regkeys, IE-COM-create test, process list delta.
#  Run in a window and leave it; Ctrl+C to stop. Self-elevates. ASCII.
#     powershell -ExecutionPolicy Bypass -File .\monitor_iemode.ps1
#  optional: -IntervalSec 30 -Minutes 30
# =====================================================================
param([int]$IntervalSec=30,[int]$Minutes=30,[string]$LogPath="")
$selfPath=$MyInvocation.MyCommand.Path; $selfDir=Split-Path -Parent $selfPath
if(-not $LogPath){ $LogPath=Join-Path $selfDir "monitor_iemode_log.txt" }
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){
    $psExe="$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
    try{ Start-Process $psExe -Verb RunAs -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$selfPath`"","-IntervalSec","$IntervalSec","-Minutes","$Minutes","-LogPath","`"$LogPath`"") }catch{}
    return
}
$Out=$LogPath
function Append($m){ $m | Out-File -FilePath $Out -Encoding UTF8 -Append; Write-Host $m }

$CLSID="{0002DF01-0000-0000-C000-000000000046}"
$comKey="Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\WOW6432Node\CLSID\$CLSID\LocalServer32"
$polKey="HKLM:\SOFTWARE\Policies\Microsoft\Edge"

function Snapshot {
    $t=Get-Date -Format 'HH:mm:ss'
    # 1. IE COM LocalServer32 (WOW6432Node = the one that got hijacked before)
    $com="?"; try{ $com=(Get-ItemProperty -Path $comKey -Name '(default)' -EA SilentlyContinue).'(default)' }catch{}
    $comTag = if($com -match 'iexplore'){'iexplore-OK'}elseif($com -match '360'){'360!!'}else{"OTHER:$com"}
    # 2. IE mode policy
    $lv="?"; try{ $lv=(Get-ItemProperty $polKey -Name InternetExplorerIntegrationLevel -EA SilentlyContinue).InternetExplorerIntegrationLevel }catch{}
    # 3. try create IE COM (the actual test) - but only if no msedge/iexplore running to avoid noise
    $comTest="skip"
    try{
        $ie=New-Object -ComObject InternetExplorer.Application -EA Stop
        $comTest="OK"
        try{ $ie.Quit(); [System.Runtime.InteropServices.Marshal]::ReleaseComObject($ie)|Out-Null }catch{}
    }catch{
        $hr=$_.Exception.HResult; if($_.Exception.InnerException){$hr=$_.Exception.InnerException.HResult}
        $comTest=("FAIL_0x{0:X8}" -f ($hr -band 0xFFFFFFFF))
    }
    # 4. edge/iexplore proc count
    $me=@(Get-Process msedge -EA SilentlyContinue).Count
    $ie2=@(Get-Process iexplore -EA SilentlyContinue).Count
    Append ("[{0}] COM={1} policy={2} IEtest={3} msedge={4} iexplore={5}" -f $t,$comTag,$lv,$comTest,$me,$ie2)
}

Append "==== monitor start $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') interval=${IntervalSec}s for ${Minutes}min ===="
Append "Watching: IE COM regkey, IE policy, IE-COM-create test, proc counts"
Append "Tip: use EBS normally during this; note when it breaks vs the log timeline."
$end=(Get-Date).AddMinutes($Minutes)
while((Get-Date) -lt $end){
    Snapshot
    Start-Sleep -Seconds $IntervalSec
}
Append "==== monitor end $(Get-Date -Format 'HH:mm:ss') ===="
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Read-Host "Press Enter to close"
