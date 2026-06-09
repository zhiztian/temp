# =====================================================================
# Try to launch IE (via COM + via Edge IE mode) and CAPTURE the failure
# logs: COM HRESULT, Windows Event Log entries, and Edge iediagnostic XML.
# ASCII only. Output: launch_ie_capture_log.txt (+ iediag_export.xml)
# Read-only diagnostics; no registry changes.
# =====================================================================
$Out = Join-Path $PSScriptRoot "launch_ie_capture_log.txt"
if (-not $PSScriptRoot) { $Out = "$env:USERPROFILE\Documents\launch_ie_capture_log.txt" }
$log=New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try { $log.ToString() | Out-File -FilePath $Out -Encoding UTF8 } catch {} }

W "Launch IE + capture logs  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Machine: $env:COMPUTERNAME  User: $env:USERNAME"
$tStart = Get-Date

# 1. attempt 1: create IE COM object directly (this is what IE mode does)
W ""
W "==== 1. attempt: New-Object InternetExplorer.Application ===="
try {
    $ie = New-Object -ComObject InternetExplorer.Application -EA Stop
    W "  >> COM SUCCESS. IE object created."
    try { W "  LocationName: $($ie.Name)" } catch {}
    try { $ie.Quit() } catch {}
} catch {
    W "  >> COM FAILED: $($_.Exception.Message)"
    W "     HResult: 0x$('{0:X8}' -f ($_.Exception.HResult -band 0xFFFFFFFF))"
}
Flush

# 2. attempt 2: launch iexplore.exe directly, watch what spawns
W ""
W "==== 2. attempt: start iexplore.exe about:blank ===="
$ie_exe="C:\Program Files\Internet Explorer\iexplore.exe"
$b_ie=@(Get-Process iexplore -EA SilentlyContinue).Count
$b_ed=@(Get-Process msedge -EA SilentlyContinue).Count
try { Start-Process $ie_exe "about:blank"; W "  launched iexplore.exe" } catch { W "  start error: $_" }
Start-Sleep -Seconds 5
W "  iexplore proc: $b_ie -> $(@(Get-Process iexplore -EA SilentlyContinue).Count)"
W "  msedge   proc: $b_ed -> $(@(Get-Process msedge -EA SilentlyContinue).Count)"
Flush

# 3. capture Windows Event Log entries around now (IE / Edge / AppModel / sidebyside)
W ""
W "==== 3. recent Application event log (last 3 min, IE/Edge related) ===="
try {
    $since=$tStart.AddMinutes(-3)
    Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$since} -EA SilentlyContinue |
        Where-Object { $_.Message -match 'Internet Explorer|iexplore|IE mode|Edge|MSHTML|0x8000FFFF|SideBySide|Application Error' } |
        Select-Object -First 15 |
        ForEach-Object { W "  [$($_.TimeCreated.ToString('HH:mm:ss'))] $($_.ProviderName)/$($_.Id): $(($_.Message -split "`n")[0])" }
} catch { W "  event read failed: $_" }
Flush

# 4. System event log too (driver/service issues)
W ""
W "==== 4. recent System event log (last 3 min, relevant) ===="
try {
    $since=$tStart.AddMinutes(-3)
    Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=$since} -EA SilentlyContinue |
        Where-Object { $_.Message -match 'Internet Explorer|iexplore|Edge|DCOM|10016|class not registered' } |
        Select-Object -First 10 |
        ForEach-Object { W "  [$($_.TimeCreated.ToString('HH:mm:ss'))] $($_.ProviderName)/$($_.Id): $(($_.Message -split "`n")[0])" }
} catch { W "  event read failed: $_" }
Flush

# 5. DCOM errors specifically (10010/10016/10001 - 'server did not register')
W ""
W "==== 5. DCOM errors (10010/10016/10001) last 10 min ===="
try {
    $since=$tStart.AddMinutes(-10)
    Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-DistributedCOM'; StartTime=$since} -EA SilentlyContinue |
        Select-Object -First 10 |
        ForEach-Object { W "  [$($_.TimeCreated.ToString('HH:mm:ss'))] Id=$($_.Id): $(($_.Message -split "`n")[0..1] -join ' ')" }
} catch { W "  no DCOM events or read failed" }
Flush

# 6. current IE COM LocalServer32 snapshot (did it revert?)
W ""
W "==== 6. IE COM LocalServer32 now ===="
$CLSID="{0002DF01-0000-0000-C000-000000000046}"
foreach($p in @("Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\$CLSID\LocalServer32",
                "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\WOW6432Node\CLSID\$CLSID\LocalServer32")){
    if(Test-Path $p){ W "  $p`n     = $((Get-ItemProperty $p -Name '(default)' -EA SilentlyContinue).'(default)')" }
}

W ""
W "==== NOTE: also export Edge's own diagnostic ===="
W "  In Edge open edge://compat/iediagnostic -> click the Export button"
W "  -> save the XML, commit it too (richest detail on why IE mode fails)."

Flush
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Write-Host "Send back: git add -A && git commit -m log && git push" -ForegroundColor Cyan
Read-Host "Press Enter to close"
