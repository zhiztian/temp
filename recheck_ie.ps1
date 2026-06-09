# =====================================================================
# Re-check IE COM after restart: did the fix hold? Is something else
# still hijacking IE process creation? Broad read-only scan + live test.
# ASCII only. Output: recheck_ie_log.txt. (read-only; no admin needed to read)
# =====================================================================
$Out = Join-Path $PSScriptRoot "recheck_ie_log.txt"
if (-not $PSScriptRoot) { $Out = "$env:USERPROFILE\Documents\recheck_ie_log.txt" }
$log=New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try { $log.ToString() | Out-File -FilePath $Out -Encoding UTF8 } catch {} }

W "Re-check IE COM  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Machine: $env:COMPUTERNAME  User: $env:USERNAME  (READ ONLY)"

$CLSID="{0002DF01-0000-0000-C000-000000000046}"

# 1. the 4 LocalServer32 keys - did our fix hold after restart?
W ""
W "==== 1. IE COM LocalServer32 (did fix hold?) ===="
$paths=@(
  "Registry::HKEY_CLASSES_ROOT\CLSID\$CLSID\LocalServer32",
  "Registry::HKEY_CLASSES_ROOT\WOW6432Node\CLSID\$CLSID\LocalServer32",
  "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\$CLSID\LocalServer32",
  "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\WOW6432Node\CLSID\$CLSID\LocalServer32"
)
$bad=0
foreach($p in $paths){
    if(Test-Path $p){
        $v=(Get-ItemProperty -Path $p -Name '(default)' -EA SilentlyContinue).'(default)'
        $tag="(?)"
        if($v -match '360'){$tag="<-- STILL 360!";$bad++}
        elseif($v -match 'sunlogin|oray'){$tag="<-- SUNLOGIN HIJACK!";$bad++}
        elseif($v -match 'iexplore'){ $exe=($v -replace '"','').Trim(); if(Test-Path $exe){$tag="(ok)"}else{$tag="<-- iexplore MISSING";$bad++} }
        else{$tag="<-- unexpected";$bad++}
        W "  $v   $tag"
    } else { W "  [missing key] $p"; $bad++ }
}
Flush

# 2. broader: scan ALL CLSID LocalServer32/InprocServer32 pointing to 360 or sunlogin
W ""
W "==== 2. any COM server still pointing to 360 / sunlogin ===="
$hits=0
foreach($base in @("Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID",
                   "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\WOW6432Node\CLSID")){
    try {
        Get-ChildItem $base -EA SilentlyContinue | ForEach-Object {
            foreach($srv in @("LocalServer32","InprocServer32")){
                $sp=Join-Path $_.PSPath $srv
                if(Test-Path $sp){
                    $val=(Get-ItemProperty -Path $sp -Name '(default)' -EA SilentlyContinue).'(default)'
                    if($val -match '360se|sunlogin|oray'){
                        W "  $($_.PSChildName)\$srv = $val"; $hits++
                    }
                }
            }
        }
    } catch {}
}
if($hits -eq 0){ W "  none found (good)" } else { W "  >> $hits COM servers still hijacked" }
Flush

# 3. ProgID + TypeLib for IE
W ""
W "==== 3. IE ProgID / TypeLib ===="
foreach($pp in @("Registry::HKEY_CLASSES_ROOT\InternetExplorer.Application\CLSID",
                 "Registry::HKEY_CLASSES_ROOT\CLSID\$CLSID\TypeLib",
                 "Registry::HKEY_CLASSES_ROOT\CLSID\$CLSID\Programmable")){
    if(Test-Path $pp){ $v=(Get-ItemProperty -Path $pp -Name '(default)' -EA SilentlyContinue).'(default)'; W "  $pp = $v" }
    else { W "  $pp (MISSING)" }
}

# 4. sunlogin: what is it actually registered as? (is it really touching IE?)
W ""
W "==== 4. sunlogin footprint (is it even IE-related?) ===="
$sun=@(Get-Process -EA SilentlyContinue | Where-Object{$_.ProcessName -match 'sunlogin'})
W "  sunlogin processes: $($sun.Count)"
foreach($p in $sun){ W "    $($p.ProcessName) PID=$($p.Id) Path=$($p.Path)" }
# search registry Run keys
foreach($rk in @("Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
                 "Registry::HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Run")){
    if(Test-Path $rk){
        (Get-Item $rk).Property | ForEach-Object {
            $val=(Get-ItemProperty $rk -Name $_).$_
            if($val -match 'sunlogin|oray|360'){ W "  Run: $_ = $val" }
        }
    }
}

# 5. live COM test: try to actually create the IE object
W ""
W "==== 5. live test: create InternetExplorer.Application ===="
try {
    $ie=New-Object -ComObject InternetExplorer.Application -EA Stop
    W "  >> SUCCESS creating IE COM object. LocalServer32 is good now."
    try { $ie.Quit() } catch {}
} catch {
    W "  >> FAILED: $($_.Exception.Message)"
    W "     HResult: 0x$('{0:X8}' -f ($_.Exception.HResult -band 0xFFFFFFFF))"
}

W ""
W "==== VERDICT ===="
W "  section1 bad-count = $bad ; section2 hijack hits = $hits"
if($bad -eq 0 -and $hits -eq 0){
    W "  >> registry is clean. If IE mode STILL fails, cause is NOT COM hijack -"
    W "     re-check edge://compat/iediagnostic error code and report it."
} else {
    W "  >> something still hijacks IE COM. See sections above."
}
Flush
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Write-Host "Send back: git add -A && git commit -m log && git push" -ForegroundColor Cyan
Read-Host "Press Enter to close"
