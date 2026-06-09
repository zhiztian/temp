# =====================================================================
# Find old IE ONLY - does a standalone IE still exist & can it launch?
# Does NOT touch EBS. ASCII only. Read-only except launching iexplore
# with a BLANK page to observe what actually starts. Output: find_old_ie_log.txt
# =====================================================================
$Out = Join-Path $PSScriptRoot "find_old_ie_log.txt"
if (-not $PSScriptRoot) { $Out = "find_old_ie_log.txt" }
$log = New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }

W "Find old IE  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Machine: $env:COMPUTERNAME  Build: $([System.Environment]::OSVersion.Version)"

# 1. iexplore.exe files on disk
W ""
W "==== 1. iexplore.exe files ===="
foreach($p in @("C:\Program Files\Internet Explorer\iexplore.exe",
                "C:\Program Files (x86)\Internet Explorer\iexplore.exe")){
    if(Test-Path $p){
        $v=(Get-Item $p).VersionInfo
        W "  EXISTS: $p"
        W "    FileVersion=$($v.FileVersion) ProductVersion=$($v.ProductVersion)"
    } else { W "  missing: $p" }
}

# 2. IE engine DLLs (the actual old-IE rendering core)
W ""
W "==== 2. IE engine DLLs ===="
foreach($d in @("C:\Windows\System32\mshtml.dll","C:\Windows\System32\ieframe.dll","C:\Windows\System32\jscript9.dll")){
    if(Test-Path $d){ W "  $d  ver=$((Get-Item $d).VersionInfo.FileVersion)" } else { W "  MISSING: $d" }
}

# 3. IE mode FoD (the only supported IE engine container on Win11)
W ""
W "==== 3. Win11 IE-mode Feature-on-Demand ===="
try {
    $cap = Get-WindowsCapability -Online -Name 'Browser.InternetExplorer~~~~0.0.11.0' -EA Stop
    W "  $($cap.Name) = $($cap.State)"
} catch { W "  query failed: $($_.Exception.Message)" }

# 4. who hijacked IE COM
W ""
W "==== 4. IE COM owner ===="
$c="HKLM:\SOFTWARE\Classes\CLSID\{0002DF01-0000-0000-C000-000000000046}\LocalServer32"
if(Test-Path $c){ W "  InternetExplorer.Application -> $((Get-ItemProperty $c).'(default)')" } else { W "  (default IE COM, not overridden)" }

# 5. LAUNCH TEST: start iexplore with BLANK page, see what really opens
W ""
W "==== 5. launch test (about:blank, NOT EBS) ===="
$ie="C:\Program Files\Internet Explorer\iexplore.exe"
if(Test-Path $ie){
    $b_ie=@(Get-Process iexplore -EA SilentlyContinue).Count
    $b_ed=@(Get-Process msedge -EA SilentlyContinue).Count
    $b_360=@(Get-Process -EA SilentlyContinue | Where-Object{$_.ProcessName -match '360'}).Count
    try { Start-Process $ie "about:blank" } catch { W "  start error: $_" }
    Start-Sleep -Seconds 6
    $a_ie=@(Get-Process iexplore -EA SilentlyContinue).Count
    $a_ed=@(Get-Process msedge -EA SilentlyContinue).Count
    $a_360=@(Get-Process -EA SilentlyContinue | Where-Object{$_.ProcessName -match '360'}).Count
    W "  iexplore proc: $b_ie -> $a_ie"
    W "  msedge   proc: $b_ed -> $a_ed"
    W "  360*     proc: $b_360 -> $a_360"
    if($a_ie -gt $b_ie){ W "  >> RESULT: real standalone IE LAUNCHED. old IE works." }
    elseif($a_ed -gt $b_ed){ W "  >> RESULT: redirected to Edge. standalone IE does NOT run." }
    elseif($a_360 -gt $b_360){ W "  >> RESULT: redirected to 360. standalone IE does NOT run." }
    else{ W "  >> RESULT: nothing new started / exited instantly." }
} else { W "  iexplore.exe not found, cannot test" }

W ""
W "==== Conclusion ===="
W "  Old standalone IE = usable ONLY if section5 says 'real standalone IE LAUNCHED'."
W "  Otherwise the ONLY IE engine available is via section3 FoD + Edge IE mode."

$log.ToString() | Out-File -FilePath $Out -Encoding UTF8
Write-Host ""
Write-Host "Log written: $Out (commit back)" -ForegroundColor Green
