# =====================================================================
# Analyze the iexplore crash dump (.mdmp) to find WHY dual_engine_adapter
# faults with c0000005. Locates the dump, checks for a debugger (cdb),
# and if present extracts the crash call stack + faulting instruction.
# Self-elevates (dumps live under ProgramData, need admin to read fully).
# ASCII only. Output: analyze_dump_log.txt
# =====================================================================
param([string]$LogPath = "")
$selfPath=$MyInvocation.MyCommand.Path; $selfDir=Split-Path -Parent $selfPath
if(-not $LogPath){ $LogPath=Join-Path $selfDir "analyze_dump_log.txt" }
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){
    Write-Host "Not admin. Relaunching elevated (approve UAC)..." -ForegroundColor Yellow
    try{ Start-Process powershell -Verb RunAs -ArgumentList @("-ExecutionPolicy","Bypass","-File","`"$selfPath`"","-LogPath","`"$LogPath`"") }catch{ Write-Host "Elevation failed: $_" }
    Read-Host "Enter to close"; return
}
$Out=$LogPath; $log=New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try{ $log.ToString()|Out-File -FilePath $Out -Encoding UTF8 }catch{} }

W "Analyze iexplore crash dump (ADMIN)  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "Machine: $env:COMPUTERNAME"

# --- 1. trigger a fresh crash so a NEW dump is generated (with LocalDumps enabled) ---
W ""
W "==== 1. enable WER LocalDumps for iexplore (full dump) ===="
# this makes Windows keep a full dump under %LOCALAPPDATA%\CrashDumps
$ld="HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\iexplore.exe"
try{
    if(-not(Test-Path $ld)){ New-Item -Path $ld -Force | Out-Null }
    New-ItemProperty -Path $ld -Name "DumpType" -Value 2 -PropertyType DWord -Force | Out-Null  # 2=full
    New-ItemProperty -Path $ld -Name "DumpCount" -Value 5 -PropertyType DWord -Force | Out-Null
    $dumpFolder = "$env:LOCALAPPDATA\CrashDumps"
    New-ItemProperty -Path $ld -Name "DumpFolder" -Value $dumpFolder -PropertyType ExpandString -Force | Out-Null
    W "  LocalDumps enabled -> $dumpFolder"
}catch{ W "  enable LocalDumps failed: $_" }
Flush

# --- 2. trigger crash ---
W ""
W "==== 2. trigger IE COM (to generate dump) ===="
try{ $ie=New-Object -ComObject InternetExplorer.Application -EA Stop; W "  COM ok (no crash this time?)"; try{$ie.Quit()}catch{} }
catch{ W "  COM failed (expected): $($_.Exception.Message)" }
Start-Sleep -Seconds 8
Flush

# --- 3. locate dump files (both WER temp + LocalDumps) ---
W ""
W "==== 3. locate crash dumps ===="
$dumps=@()
foreach($dir in @("$env:LOCALAPPDATA\CrashDumps",
                  "$env:ProgramData\Microsoft\Windows\WER\ReportArchive",
                  "$env:ProgramData\Microsoft\Windows\WER\ReportQueue",
                  "$env:ProgramData\Microsoft\Windows\WER\Temp")){
    if(Test-Path $dir){
        Get-ChildItem $dir -Recurse -Include *.mdmp,*.dmp -EA SilentlyContinue |
            Where-Object{ $_.Name -match 'iexplore' -or $_.FullName -match 'iexplore' } |
            Sort-Object LastWriteTime -Descending | ForEach-Object { $dumps += $_ }
    }
}
$dumps = $dumps | Sort-Object LastWriteTime -Descending | Select-Object -Unique -First 5
if($dumps.Count){ foreach($d in $dumps){ W "  $($d.FullName)  ($([int]($d.Length/1KB)) KB, $($d.LastWriteTime))" } }
else { W "  no iexplore dump found yet (WER may have uploaded+purged; LocalDumps will catch the NEXT crash)" }
Flush

# --- 4. find a debugger (cdb.exe) ---
W ""
W "==== 4. find debugger (cdb.exe) ===="
$cdb=$null
foreach($c in @("C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe",
                "C:\Program Files\Windows Kits\10\Debuggers\x64\cdb.exe",
                "C:\Program Files (x86)\Windows Kits\11\Debuggers\x64\cdb.exe")){
    if(Test-Path $c){ $cdb=$c; break }
}
# also check PATH
if(-not $cdb){ $w=Get-Command cdb.exe -EA SilentlyContinue; if($w){ $cdb=$w.Source } }
if($cdb){ W "  cdb found: $cdb" } else { W "  cdb NOT installed (Windows SDK Debugging Tools needed)" }
Flush

# --- 5. if we have both dump + cdb, extract the stack ---
W ""
W "==== 5. crash call stack ===="
if($cdb -and $dumps.Count){
    $dump=$dumps[0].FullName
    W "  analyzing: $dump"
    # !analyze -v gives faulting stack + module; k gives stack
    $cmds = ".symfix; .reload; !analyze -v; k; lmvm dual_engine_adapter_x64; q"
    try{
        $res = & $cdb -z $dump -c $cmds 2>&1 | Out-String
        # keep the useful parts only
        $res -split "`n" | Where-Object { $_ -match 'FAULTING|EXCEPTION|MODULE_NAME|IMAGE_NAME|STACK_TEXT|dual_engine|mshtml|ieframe|iexplore|c0000005|Attempt to|FAILURE_BUCKET|^\s*[0-9a-f]{8}' } |
            Select-Object -First 60 | ForEach-Object { W "  $_" }
    }catch{ W "  cdb run failed: $_" }
} elseif(-not $cdb){
    W "  >> No debugger. To get the stack, install Windows SDK 'Debugging Tools for Windows':"
    W "     winget install Microsoft.WinDbg     (or install via Windows SDK)"
    W "     then re-run this script."
} else {
    W "  >> No dump captured yet. LocalDumps is now enabled - reproduce the crash"
    W "     once more (open EBS / run trigger), then re-run this script."
}
Flush
Write-Host ""
Write-Host "Log: $Out" -ForegroundColor Green
Write-Host "Send back: git add -A && git commit -m log && git push" -ForegroundColor Cyan
Read-Host "Press Enter to close"
