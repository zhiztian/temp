# =====================================================================
# Collect ANY iexplore/IE-mode crash dump from all known locations.
# Run this AFTER reproducing the crash by opening EBS in Edge.
# Also re-confirms LocalDumps is set for BOTH iexplore.exe paths.
# Self-elevates. ASCII only. Output: collect_dump_log.txt + zip
# =====================================================================
param([string]$LogPath = "")
$selfPath=$MyInvocation.MyCommand.Path; $selfDir=Split-Path -Parent $selfPath
if(-not $LogPath){ $LogPath=Join-Path $selfDir "collect_dump_log.txt" }
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){
    Write-Host "Not admin. Relaunching elevated (approve UAC)..." -ForegroundColor Yellow
    try{ Start-Process powershell -Verb RunAs -ArgumentList @("-ExecutionPolicy","Bypass","-File","`"$selfPath`"","-LogPath","`"$LogPath`"") }catch{ Write-Host "Elevation failed: $_" }
    Read-Host "Enter to close"; return
}
$Out=$LogPath; $log=New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try{ $log.ToString()|Out-File -FilePath $Out -Encoding UTF8 }catch{} }

W "Collect IE crash dump (ADMIN)  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# 1. ensure LocalDumps is set globally (catch-all) + per iexplore
W ""
W "==== 1. ensure LocalDumps (global + iexplore) ===="
$dumpFolder="C:\IEDumps"
if(-not(Test-Path $dumpFolder)){ New-Item -ItemType Directory -Path $dumpFolder -Force | Out-Null }
foreach($app in @("","\iexplore.exe")){
    $k="HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps$app"
    try{
        if(-not(Test-Path $k)){ New-Item -Path $k -Force | Out-Null }
        New-ItemProperty -Path $k -Name "DumpType" -Value 1 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $k -Name "DumpCount" -Value 20 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $k -Name "DumpFolder" -Value $dumpFolder -PropertyType ExpandString -Force | Out-Null
        W "  set: LocalDumps$app -> $dumpFolder"
    }catch{ W "  set LocalDumps$app failed: $_" }
}
W "  NOTE: LocalDumps applies to processes started AFTER this point."
Flush

# 2. scan ALL dump locations for iexplore dumps
W ""
W "==== 2. scan for existing dumps (all locations) ===="
$scanDirs = @("C:\IEDumps",
              "$env:LOCALAPPDATA\CrashDumps",
              "C:\Users\admin\AppData\Local\CrashDumps",
              "$env:ProgramData\Microsoft\Windows\WER\ReportArchive",
              "$env:ProgramData\Microsoft\Windows\WER\ReportQueue",
              "$env:ProgramData\Microsoft\Windows\WER\Temp",
              "$env:WINDIR\Temp")
$found=@()
foreach($d in $scanDirs){
    if(Test-Path $d){
        Get-ChildItem $d -Recurse -Include *.dmp,*.mdmp -EA SilentlyContinue |
            Where-Object { $_.Name -match 'iexplore|IE' -or $_.FullName -match 'iexplore' } |
            ForEach-Object { $found += $_ }
    }
}
$found = $found | Sort-Object LastWriteTime -Descending | Select-Object -Unique
if($found.Count){
    foreach($f in $found | Select-Object -First 10){ W "  $($f.FullName)  $([int]($f.Length/1KB))KB  $($f.LastWriteTime)" }
}else{ W "  none found yet" }
Flush

# 3. zip the newest dump if small enough
W ""
W "==== 3. package newest dump ===="
if($found.Count){
    $newest=$found[0]
    $zip=Join-Path $selfDir "iexplore_dump.zip"
    if(Test-Path $zip){ Remove-Item $zip -Force }
    try{
        Compress-Archive -Path $newest.FullName -DestinationPath $zip -Force
        $zkb=[int]((Get-Item $zip).Length/1KB)
        W "  zipped: $zip  ($zkb KB)  from $($newest.Name)"
        if($zkb -gt 95000){ W "  WARNING: >95MB, too big for git. tell me and I give split method." }
    }catch{ W "  zip failed: $_" }
}else{
    W "  >> NO DUMP YET. Do this:"
    W "     1. Open Edge, go to the EBS site so IE mode triggers the crash"
    W "        (or edge://compat/iediagnostic -> retry until it fails)."
    W "     2. Re-run THIS script. The crash AFTER step 1 will be captured to C:\IEDumps."
}
Flush
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Write-Host "If zip created: git add iexplore_dump.zip collect_dump_log.txt && git commit -m dump && git push" -ForegroundColor Cyan
Read-Host "Press Enter to close"
