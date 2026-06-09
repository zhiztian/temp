# =====================================================================
# Reproduce the iexplore crash and grab a MINI dump (small, ~MB) so it
# can be committed and analyzed offline with cdb on another machine.
# LocalDumps was enabled last run; this sets mini-dump and triggers crash.
# Self-elevates. ASCII only. Output: grab_dump_log.txt + zipped dump.
# =====================================================================
param([string]$LogPath = "")
$selfPath=$MyInvocation.MyCommand.Path; $selfDir=Split-Path -Parent $selfPath
if(-not $LogPath){ $LogPath=Join-Path $selfDir "grab_dump_log.txt" }
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){
    Write-Host "Not admin. Relaunching elevated (approve UAC)..." -ForegroundColor Yellow
    try{ Start-Process powershell -Verb RunAs -ArgumentList @("-ExecutionPolicy","Bypass","-File","`"$selfPath`"","-LogPath","`"$LogPath`"") }catch{ Write-Host "Elevation failed: $_" }
    Read-Host "Enter to close"; return
}
$Out=$LogPath; $log=New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try{ $log.ToString()|Out-File -FilePath $Out -Encoding UTF8 }catch{} }

W "Grab iexplore mini-dump (ADMIN)  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# 1. set MINI dump (type 1) so file is small enough to commit
$ld="HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\iexplore.exe"
$dumpFolder="$env:LOCALAPPDATA\CrashDumps"
try{
    if(-not(Test-Path $ld)){ New-Item -Path $ld -Force | Out-Null }
    # DumpType: 1 = mini (small, has stack), 2 = full (big)
    New-ItemProperty -Path $ld -Name "DumpType" -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $ld -Name "DumpCount" -Value 10 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $ld -Name "DumpFolder" -Value $dumpFolder -PropertyType ExpandString -Force | Out-Null
    if(-not(Test-Path $dumpFolder)){ New-Item -ItemType Directory -Path $dumpFolder -Force | Out-Null }
    W "  mini-dump configured -> $dumpFolder"
}catch{ W "  config failed: $_" }
Flush

# 2. note existing dumps, then trigger crash
$before = @(Get-ChildItem $dumpFolder -Filter *.dmp -EA SilentlyContinue | Select-Object -ExpandProperty FullName)
W ""
W "==== trigger crash (a few times to be sure) ===="
for($i=1;$i -le 3;$i++){
    try{ $ie=New-Object -ComObject InternetExplorer.Application -EA Stop; W "  try $i COM ok?"; try{$ie.Quit()}catch{} }
    catch{ W "  try $i COM failed (expected)" }
    Start-Sleep -Seconds 4
}
# also direct launch (this is what produced the crash in trace)
try{ Start-Process "C:\Program Files\Internet Explorer\iexplore.exe" "-Embedding" }catch{}
Start-Sleep -Seconds 6
Flush

# 3. find new dump(s)
W ""
W "==== new dumps ===="
$after = @(Get-ChildItem $dumpFolder -Filter *.dmp -EA SilentlyContinue | Sort-Object LastWriteTime -Descending)
$new = $after | Where-Object { $before -notcontains $_.FullName }
if(-not $new){ $new = $after | Select-Object -First 1 }  # fall back to latest
if($new){
    foreach($d in $new){ W "  $($d.FullName)  $([int]($d.Length/1KB)) KB" }
    # copy newest into repo + zip
    $newest = ($new | Sort-Object LastWriteTime -Descending)[0]
    $destZip = Join-Path $selfDir "iexplore_dump.zip"
    try{
        if(Test-Path $destZip){ Remove-Item $destZip -Force }
        Compress-Archive -Path $newest.FullName -DestinationPath $destZip -Force
        $zkb=[int]((Get-Item $destZip).Length/1KB)
        W "  zipped -> $destZip ($zkb KB)"
        if($zkb -gt 95000){ W "  WARNING: zip >95MB, too big for GitHub. Will need split or other transfer." }
    }catch{ W "  zip failed: $_" }
} else {
    W "  no dump captured. The crash may happen in a child iexplore not covered by"
    W "  LocalDumps name filter, OR COM fails before iexplore is spawned at all."
    W "  Next: reproduce by actually opening EBS in Edge IE mode, then re-run."
}
Flush
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Write-Host "If iexplore_dump.zip was created:" -ForegroundColor Cyan
Write-Host "  git add iexplore_dump.zip grab_dump_log.txt && git commit -m dump && git push" -ForegroundColor Cyan
Read-Host "Press Enter to close"
