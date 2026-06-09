# =====================================================================
#  PASSIVE monitor (no IE-COM test, so it doesn't pollute with crashes).
#  Records: process appear/disappear events + IE COM regkey changes +
#  360/qihoo activity. Find who touches IE state. Self-elevates. ASCII.
#     powershell -ExecutionPolicy Bypass -File .\monitor_passive.ps1
#  optional: -IntervalSec 15 -Minutes 20
# =====================================================================
param([int]$IntervalSec=15,[int]$Minutes=20,[string]$LogPath="")
$selfPath=$MyInvocation.MyCommand.Path; $selfDir=Split-Path -Parent $selfPath
if(-not $LogPath){ $LogPath=Join-Path $selfDir "monitor_passive_log.txt" }
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){
    $psExe="$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"
    try{ Start-Process $psExe -Verb RunAs -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File","`"$selfPath`"","-IntervalSec","$IntervalSec","-Minutes","$Minutes","-LogPath","`"$LogPath`"") }catch{}
    return
}
$Out=$LogPath
function A($m){ $m | Out-File -FilePath $Out -Encoding UTF8 -Append; Write-Host $m }

$CLSID="{0002DF01-0000-0000-C000-000000000046}"
$comKey="Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\WOW6432Node\CLSID\$CLSID\LocalServer32"
function GetCom { try{ (Get-ItemProperty -Path $comKey -Name '(default)' -EA SilentlyContinue).'(default)' }catch{ '?' } }

A "==== PASSIVE monitor start $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') interval=${IntervalSec}s for ${Minutes}min ===="
A "Records: process appear(+)/disappear(-), IE COM regkey changes, 360 activity."
A "Use EBS normally during this. NO IE-COM test (won't self-pollute)."

# baseline
$prevProcs=@{}
foreach($p in (Get-Process -EA SilentlyContinue)){ $prevProcs[$p.Id]="$($p.ProcessName)" }
$prevCom=GetCom
A ("[start] IE-COM-regkey = {0}" -f $prevCom)
A ("[start] processes: {0}" -f $prevProcs.Count)

$end=(Get-Date).AddMinutes($Minutes)
$suspPat='360|qihoo|huabao|sunlogin|oray|iexplore|msedge|ie_to_edge'
while((Get-Date) -lt $end){
    Start-Sleep -Seconds $IntervalSec
    $t=Get-Date -Format 'HH:mm:ss'
    $cur=@{}
    foreach($p in (Get-Process -EA SilentlyContinue)){ $cur[$p.Id]="$($p.ProcessName)" }
    # new processes
    foreach($id in $cur.Keys){
        if(-not $prevProcs.ContainsKey($id)){
            $n=$cur[$id]
            $mark = if($n -match $suspPat){'  <<<'}else{''}
            # only log suspicious or all? log suspicious always, others brief
            if($n -match $suspPat){ A ("[{0}] + {1} (PID {2}){3}" -f $t,$n,$id,$mark) }
        }
    }
    # gone processes (only suspicious)
    foreach($id in $prevProcs.Keys){
        if(-not $cur.ContainsKey($id)){
            $n=$prevProcs[$id]
            if($n -match $suspPat){ A ("[{0}] - {1} (PID {2})" -f $t,$n,$id) }
        }
    }
    # IE COM regkey change
    $com=GetCom
    if($com -ne $prevCom){ A ("[{0}] !! IE-COM-regkey CHANGED: {1} -> {2}" -f $t,$prevCom,$com); $prevCom=$com }
    $prevProcs=$cur
}
A "==== monitor end $(Get-Date -Format 'HH:mm:ss') ===="
# final snapshot of 360 presence
$f=@(Get-Process -EA SilentlyContinue | Where-Object { $_.ProcessName -match '360|qihoo|huabao' })
A ("360 procs at end: {0}" -f $f.Count)
foreach($p in $f){ A ("  {0} PID={1} {2}" -f $p.ProcessName,$p.Id,$p.Path) }
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Read-Host "Press Enter to close"
