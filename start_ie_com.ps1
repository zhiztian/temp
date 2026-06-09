# =====================================================================
# Launch IE engine on Win11 - auto verify + write log (ASCII only)
# Goal: bring up real IE11 (MSHTML) so the Java plugin can run Forms.
# Tries multiple methods, verifies each really started IE (not Edge
# hijack), writes everything to ie_start_log.txt. No admin needed.
# =====================================================================

$Out = Join-Path $PSScriptRoot "ie_start_log.txt"
if (-not $PSScriptRoot) { $Out = "ie_start_log.txt" }
$EBS = "http://ebsprod.bytedance.net:8000/OA_HTML/OA.jsp?OAFunc=OANEWHOMEPAGE"
$log = New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Hex($n){ try { "0x{0:X8}" -f ([int64]$n -band 0xFFFFFFFF) } catch { "$n" } }

$sig = @"
using System;
using System.Runtime.InteropServices;
public class W32 {
  [DllImport("user32.dll")]
  public static extern int GetWindowThreadProcessId(IntPtr hWnd, out int pid);
}
"@
try { Add-Type -TypeDefinition $sig -ErrorAction Stop } catch {}

function ProcOfHwnd($hwnd){
    try {
        $pid2 = 0
        [void][W32]::GetWindowThreadProcessId([IntPtr]$hwnd, [ref]$pid2)
        if ($pid2 -gt 0) {
            $p = Get-Process -Id $pid2 -ErrorAction SilentlyContinue
            if ($p) { return "$($p.ProcessName) (PID=$pid2)" }
            return "PID=$pid2 (process gone)"
        }
    } catch {}
    return "unknown"
}

W "IE engine launch diagnostic  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Machine: $env:COMPUTERNAME  User: $env:USERNAME"
W "Target: $EBS"

# ---------- Method 1: COM, try both ProgIDs ----------
foreach ($progid in @("InternetExplorer.Application","InternetExplorerMedium")) {
    W ""
    W "==== Method1: COM [$progid] ===="
    $ie = $null
    try {
        $ie = New-Object -ComObject $progid -ErrorAction Stop
        $ie.Visible = $true
        $ie.Navigate($EBS)
        W "COM create: OK"
        $url = ""; $hwnd = 0
        for ($i=0; $i -lt 6; $i++) {
            Start-Sleep -Seconds 2
            try { $url = $ie.LocationURL } catch { $url = "(read failed: $_)" }
            try { $hwnd = [int64]$ie.HWND } catch {}
            if ($url -match "ebsprod|bytedance") { break }
        }
        try { W "  Visible    : $($ie.Visible)" } catch {}
        W "  LocationURL: $url"
        W "  HWND       : $hwnd"
        $owner = ""
        if ($hwnd -ne 0) { $owner = ProcOfHwnd $hwnd; W "  HWND owner proc: $owner" }
        if ($url -match "ebsprod|bytedance" -and $owner -match "iexplore") {
            W "  >> SUCCESS: real IE engine loaded EBS. This is what we want."
        } elseif ($owner -match "msedge") {
            W "  >> HIJACKED: COM window belongs to msedge, not real IE."
        } elseif ($url -match "ebsprod|bytedance") {
            W "  >> Navigated to EBS but window owner=$owner, confirm if IE."
        } else {
            W "  >> Navigation did not succeed (URL=$url)."
        }
        break
    }
    catch {
        W "COM [$progid] failed: $($_.Exception.Message)"
        W "  HResult: $(Hex $_.Exception.HResult)"
    }
}

W ""
W "---- iexplore / msedge process snapshot ----"
foreach($n in @("iexplore","msedge")){
    $ps = @(Get-Process $n -ErrorAction SilentlyContinue)
    W "  $n : $($ps.Count)"
    foreach($p in $ps){ W "      PID=$($p.Id) Path=$($p.Path)" }
}

# ---------- Method 2: direct iexplore.exe ----------
W ""
W "==== Method2: direct iexplore.exe ===="
$iePath = "C:\Program Files\Internet Explorer\iexplore.exe"
if (Test-Path $iePath) {
    $b_ie = @(Get-Process iexplore -ErrorAction SilentlyContinue).Count
    $b_ed = @(Get-Process msedge   -ErrorAction SilentlyContinue).Count
    try { Start-Process $iePath $EBS } catch { W "  start error: $_" }
    Start-Sleep -Seconds 6
    $a_ie = @(Get-Process iexplore -ErrorAction SilentlyContinue).Count
    $a_ed = @(Get-Process msedge   -ErrorAction SilentlyContinue).Count
    W "  iexplore proc (before->after): $b_ie -> $a_ie"
    W "  msedge   proc (before->after): $b_ed -> $a_ed"
    if ($a_ie -gt $b_ie)      { W "  >> iexplore proc increased = real IE started" }
    elseif ($a_ed -gt $b_ed)  { W "  >> msedge proc increased = redirected to Edge (IE not started)" }
    else                      { W "  >> no new proc = exited immediately / failed" }
} else { W "  iexplore.exe not found: $iePath" }

# ---------- Env: IE->Edge redirection registry (read only) ----------
W ""
W "==== Env: IE->Edge redirection registry (read only) ===="
$checks = @(
  @{P="HKLM:\SOFTWARE\Microsoft\Internet Explorer\Main"; N="RedirectionMode"},
  @{P="HKCU:\SOFTWARE\Microsoft\Internet Explorer\Main"; N="RedirectionMode"},
  @{P="HKLM:\SOFTWARE\Policies\Microsoft\Internet Explorer\Main"; N="DisableInternetExplorerApp"},
  @{P="HKLM:\SOFTWARE\Policies\Microsoft\Edge"; N="InternetExplorerIntegrationLevel"},
  @{P="HKCU:\SOFTWARE\Policies\Microsoft\Edge"; N="InternetExplorerIntegrationLevel"}
)
foreach($c in $checks){
    try {
        if (Test-Path $c.P) {
            $v = (Get-ItemProperty -Path $c.P -Name $c.N -ErrorAction SilentlyContinue).$($c.N)
            if ($null -ne $v) { W "  $($c.P)\$($c.N) = $v" } else { W "  $($c.P)\$($c.N) = (no value)" }
        } else { W "  $($c.P) (key not found)" }
    } catch { W "  $($c.P)\$($c.N) read error: $_" }
}

W ""
W "==== Verdict ===="
W "  - any 'real IE engine loaded EBS' or 'iexplore proc increased' -> works, next clear cookie + login + open finance form"
W "  - all hijacked to msedge / DisableInternetExplorerApp=1 -> local IE-engine path exhausted, need IT to enable Edge IE mode"

$log.ToString() | Out-File -FilePath $Out -Encoding UTF8
Write-Host ""
Write-Host "Log written: $Out  (commit to send back)" -ForegroundColor Green
