# =====================================================================
# Hunt for ANY working IE-engine path on this machine (ASCII only)
# User confirmed EBS Java forms WORKED here before -> the capability
# still exists somewhere. Search exhaustively. Read-only. No admin.
# Output: hunt_ie_log.txt
# =====================================================================

$Out = Join-Path $PSScriptRoot "hunt_ie_log.txt"
if (-not $PSScriptRoot) { $Out = "hunt_ie_log.txt" }
$log = New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function RegGet($p,$n){ try { if(Test-Path $p){ $v=(Get-ItemProperty $p -Name $n -EA SilentlyContinue).$n; if($null -ne $v){return $v} } } catch {}; return $null }

W "IE engine hunt  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Machine: $env:COMPUTERNAME  User: $env:USERNAME"
W "OS Build: $([System.Environment]::OSVersion.Version)"

# 1. Edge IE-mode REAL state (settings-level, not just policy)
W ""
W "==== 1. Edge IE-mode actual config ===="
# policy level
W "  [policy] HKLM IntegrationLevel = $(RegGet 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'InternetExplorerIntegrationLevel')"
W "  [policy] HKCU IntegrationLevel = $(RegGet 'HKCU:\SOFTWARE\Policies\Microsoft\Edge' 'InternetExplorerIntegrationLevel')"
W "  [policy] HKLM SiteList = $(RegGet 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'InternetExplorerIntegrationSiteList')"
W "  [policy] HKCU SiteList = $(RegGet 'HKCU:\SOFTWARE\Policies\Microsoft\Edge' 'InternetExplorerIntegrationSiteList')"
# Edge user prefs file may hold ie-mode user opt-in + site list
$prefDirs = @("$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default",
              "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Profile 1")
foreach($d in $prefDirs){
    $pf = Join-Path $d "Preferences"
    if(Test-Path $pf){
        W "  Pref file: $pf"
        try {
            $txt = Get-Content $pf -Raw -EA SilentlyContinue
            foreach($kw in @("internet_explorer_integration","ie_mode","enterprise_site_list","ebsprod")){
                $idx = $txt.IndexOf($kw)
                if($idx -ge 0){ W "    contains '$kw' at $idx -> snippet: $($txt.Substring($idx,[Math]::Min(120,$txt.Length-$idx)))" }
            }
        } catch { W "    read err: $_" }
    }
}
# user-level enterprise mode site list cache
$emie = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\IEMode"
if(Test-Path $emie){ W "  IEMode cache dir exists: $emie"; Get-ChildItem $emie -Recurse -EA SilentlyContinue | ForEach-Object { W "    $($_.FullName)" } }

# 2. IE COM registration present?
W ""
W "==== 2. IE COM class registration ===="
foreach($clsid in @("HKLM:\SOFTWARE\Classes\CLSID\{0002DF01-0000-0000-C000-000000000046}\LocalServer32",
                    "HKLM:\SOFTWARE\Classes\Wow6432Node\CLSID\{0002DF01-0000-0000-C000-000000000046}\LocalServer32")){
    if(Test-Path $clsid){ W "  $clsid = $((Get-ItemProperty $clsid).'(default)')" } else { W "  $clsid (not found)" }
}

# 3. ALL browser-like exes installed (incl 360, IE-core browsers)
W ""
W "==== 3. installed browsers / IE-core candidates ===="
$names = @("iexplore.exe","360se.exe","360se6.exe","360se7.exe","360chrome.exe","360ChromeX.exe",
           "msedge.exe","chrome.exe","TheWorld.exe","sogouexplorer.exe","QQBrowser.exe","2345Explorer.exe","greenbrowser.exe")
$roots = @("C:\Program Files","C:\Program Files (x86)","$env:LOCALAPPDATA","$env:APPDATA")
$hits=@()
foreach($r in $roots){
    if(-not(Test-Path $r)){continue}
    try { Get-ChildItem $r -Recurse -Include $names -EA SilentlyContinue -Depth 4 | ForEach-Object { $hits += $_.FullName } } catch {}
}
$hits = $hits | Sort-Object -Unique
if($hits.Count){ foreach($h in $hits){ W "  $h" } } else { W "  none found (depth-limited)" }

# 4. default http/https handler (who opens links)
W ""
W "==== 4. default url handler ===="
W "  http  ProgId = $(RegGet 'HKCU:\SOFTWARE\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice' 'ProgId')"
W "  https ProgId = $(RegGet 'HKCU:\SOFTWARE\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice' 'ProgId')"

# 5. Java deployment trace (confirms which container ran applets)
W ""
W "==== 5. Java deployment cache (applet run history) ===="
$jc = "$env:USERPROFILE\AppData\LocalLow\Sun\Java\Deployment\cache"
if(Test-Path $jc){ W "  Java cache exists: $jc" } else { W "  no Java deployment cache" }
$dp = "$env:USERPROFILE\AppData\LocalLow\Sun\Java\Deployment\deployment.properties"
if(Test-Path $dp){ W "  deployment.properties:"; Get-Content $dp -EA SilentlyContinue | ForEach-Object { W "    $_" } }

# 6. Desktop / Start shortcuts pointing to EBS or IE (you may have made one)
W ""
W "==== 6. shortcuts mentioning EBS / IE / 360 ===="
$lnkDirs = @("$env:USERPROFILE\Desktop","$env:PUBLIC\Desktop",
             "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
             "$env:USERPROFILE\Documents")
$sh = New-Object -ComObject WScript.Shell
foreach($d in $lnkDirs){
    if(-not(Test-Path $d)){continue}
    try {
        Get-ChildItem $d -Recurse -Filter *.lnk -EA SilentlyContinue | ForEach-Object {
            try {
                $t = $sh.CreateShortcut($_.FullName)
                $blob = "$($t.TargetPath) $($t.Arguments)"
                if($blob -match "ebsprod|iexplore|360|ie |IEMode|bytedance"){
                    W "  LNK: $($_.FullName)"
                    W "      Target: $($t.TargetPath)"
                    W "      Args  : $($t.Arguments)"
                }
            } catch {}
        }
    } catch {}
}

W ""
W "==== Verdict hints ===="
W "  - Section1 SiteList/Pref has ebsprod  -> Edge IE-mode WAS configured, just needs re-trigger"
W "  - Section3 lists 360se*.exe           -> 360 compat mode is the prior working path"
W "  - Section6 shortcut with ebsprod+args -> that is exactly how it was opened before; reuse it"

$log.ToString() | Out-File -FilePath $Out -Encoding UTF8
Write-Host ""
Write-Host "Log written: $Out (commit back)" -ForegroundColor Green
