# =====================================================================
# AUDIT/TRACE who blocks IE process creation.
# Enables process-creation auditing (4688) + command-line capture,
# triggers an IE COM launch, then dumps every process create/exit around
# iexplore, plus any AV/security/AppLocker/WDAC blocks in the event logs.
# Self-elevates (auditpol needs admin). ASCII only.
# Output: trace_ie_launch_log.txt
# =====================================================================
param([string]$LogPath = "")
$selfPath=$MyInvocation.MyCommand.Path; $selfDir=Split-Path -Parent $selfPath
if(-not $LogPath){ $LogPath=Join-Path $selfDir "trace_ie_launch_log.txt" }
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){
    Write-Host "Not admin. Relaunching elevated (approve UAC)..." -ForegroundColor Yellow
    try{ Start-Process powershell -Verb RunAs -ArgumentList @("-ExecutionPolicy","Bypass","-File","`"$selfPath`"","-LogPath","`"$LogPath`"") }catch{ Write-Host "Elevation failed: $_" }
    Read-Host "Enter to close"; return
}
$Out=$LogPath; $log=New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try{ $log.ToString()|Out-File -FilePath $Out -Encoding UTF8 }catch{} }

W "TRACE IE launch blocker (ADMIN)  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Machine: $env:COMPUTERNAME  User: $env:USERNAME"

# --- 1. enable process auditing + cmdline capture ---
W ""
W "==== 1. enable process auditing ===="
$prevAudit = (auditpol /get /subcategory:"Process Creation" 2>&1 | Out-String).Trim()
W "  prev Process Creation audit: $prevAudit"
auditpol /set /subcategory:"Process Creation" /success:enable /failure:enable | Out-Null
auditpol /set /subcategory:"Process Termination" /success:enable | Out-Null
# include command line in 4688
$cmdKey="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit"
if(-not(Test-Path $cmdKey)){ New-Item -Path $cmdKey -Force | Out-Null }
New-ItemProperty -Path $cmdKey -Name "ProcessCreationIncludeCmdLine_Enabled" -Value 1 -PropertyType DWord -Force | Out-Null
W "  process auditing + cmdline capture enabled"
Flush

$tStart=Get-Date
Start-Sleep -Seconds 2

# --- 2. trigger IE launch (COM, which is what IE mode uses) ---
W ""
W "==== 2. trigger: create IE COM object ===="
$comErr=$null
try{
    $ie=New-Object -ComObject InternetExplorer.Application -EA Stop
    W "  >> COM SUCCESS (unexpected - IE actually came up)"
    try{ $ie.Quit() }catch{}
}catch{
    $comErr=$_.Exception.Message
    W "  >> COM FAILED: $comErr"
}
# also try direct exe
try{ Start-Process "C:\Program Files\Internet Explorer\iexplore.exe" "about:blank" }catch{}
Start-Sleep -Seconds 6
Flush

# --- 3. dump process create/exit events for iexplore in the window ---
W ""
W "==== 3. process create/terminate events (iexplore) since trigger ===="
try{
    Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4688,4689; StartTime=$tStart} -EA SilentlyContinue |
        Where-Object { $_.Message -match 'iexplore|Internet Explorer|msedge|ie_to_edge|SunLogin|360' } |
        Sort-Object TimeCreated |
        ForEach-Object {
            $m=$_.Message
            $newproc = if($m -match 'New Process Name:\s*(.+)'){$matches[1].Trim()} elseif($m -match '新进程名称:\s*(.+)'){$matches[1].Trim()} else {''}
            $parent  = if($m -match 'Creator Process Name:\s*(.+)'){$matches[1].Trim()} elseif($m -match '创建者进程名称:\s*(.+)'){$matches[1].Trim()} else {''}
            $cmd     = if($m -match 'Process Command Line:\s*(.+)'){$matches[1].Trim()} elseif($m -match '进程命令行:\s*(.+)'){$matches[1].Trim()} else {''}
            W "  [$($_.TimeCreated.ToString('HH:mm:ss'))] Id=$($_.Id)"
            W "     new   : $newproc"
            W "     parent: $parent"
            if($cmd){ W "     cmd   : $cmd" }
        }
}catch{ W "  security log read failed (auditing may need a moment): $_" }
Flush

# --- 4. look for blockers: AppLocker / WDAC / Defender / SmartScreen ---
W ""
W "==== 4. block sources (AppLocker / WDAC / Defender) since trigger ===="
$blkLogs=@(
  @{L='Microsoft-Windows-AppLocker/EXE and DLL'; T='AppLocker'},
  @{L='Microsoft-Windows-CodeIntegrity/Operational'; T='WDAC/CodeIntegrity'},
  @{L='Microsoft-Windows-Windows Defender/Operational'; T='Defender'},
  @{L='Microsoft-Windows-SmartScreen/Debug'; T='SmartScreen'}
)
foreach($b in $blkLogs){
    try{
        $ev=@(Get-WinEvent -FilterHashtable @{LogName=$b.L; StartTime=$tStart} -EA SilentlyContinue |
              Where-Object { $_.Message -match 'iexplore|Internet Explorer' })
        if($ev.Count){ foreach($e in $ev){ W "  [$($b.T)] Id=$($e.Id): $(($e.Message -split "`n")[0])" } }
        else { W "  [$($b.T)] no iexplore-related blocks" }
    }catch{ W "  [$($b.T)] log not present" }
}
Flush

# --- 5. third-party security/hook software inventory ---
W ""
W "==== 5. running security/remote/hook software ===="
$susp = Get-Process -EA SilentlyContinue | Where-Object {
    $_.ProcessName -match 'sunlogin|oray|360|huorong|qqpcmgr|QQPCTray|kxescore|kxetray|baidu|av|defender|sophos|symantec|mcafee|crowdstrike|sentinel|eset|kaspersky|trend|esafe|ToDesk|todesk|anydesk|teamviewer'
}
if($susp){ foreach($p in $susp){ W "  $($p.ProcessName) PID=$($p.Id) Path=$($p.Path)" } } else { W "  none of the common ones running" }
# also list services that might hook
W "  -- security-ish services (running) --"
Get-Service -EA SilentlyContinue | Where-Object { $_.Status -eq 'Running' -and $_.Name -match 'sunlogin|oray|360|huorong|todesk|anydesk|teamviewer|sophos|defend|csagent|sentinel' } |
    ForEach-Object { W "     $($_.Name) - $($_.DisplayName)" }
Flush

# --- 6. restore previous audit setting ---
W ""
W "==== 6. restore audit settings ===="
auditpol /set /subcategory:"Process Creation" /success:disable /failure:disable | Out-Null
auditpol /set /subcategory:"Process Termination" /success:disable | Out-Null
Remove-ItemProperty -Path $cmdKey -Name "ProcessCreationIncludeCmdLine_Enabled" -EA SilentlyContinue
W "  audit settings restored to default (disabled)"

W ""
W "==== READ ===="
W "  - Section3: if iexplore (4688) is created then immediately 4689 with a"
W "    non-Edge parent killing it -> that parent is the blocker."
W "  - Section3: if new proc is msedge/ie_to_edge_bho -> it's the OS redirect."
W "  - Section4: any AppLocker/WDAC/Defender hit on iexplore = that's the block."
W "  - Section5: lists remote/security software that commonly hooks process start."
Flush
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Write-Host "Send back: git add -A && git commit -m log && git push" -ForegroundColor Cyan
Read-Host "Press Enter to close"
