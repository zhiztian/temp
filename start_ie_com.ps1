# =====================================================================
# 启动 IE 内核 (Win11) —— 自动验证并写日志,无需人工看屏幕
# 目标: 在 Win11 上拉起真正的 IE11 内核(MSHTML)以加载 Java 插件跑 Forms。
# 多方式依次尝试,核实每种是否真起了 IE(而非被 Edge 劫持),全部落日志。
# 产出: ie_start_log.txt  (commit 回传即可)。不需管理员,只读不改系统。
# =====================================================================

$Out = Join-Path $PSScriptRoot "ie_start_log.txt"
if (-not $PSScriptRoot) { $Out = "ie_start_log.txt" }
$EBS = "http://ebsprod.bytedance.net:8000/OA_HTML/OA.jsp?OAFunc=OANEWHOMEPAGE"
$log = New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Hex($n){ try { "0x{0:X8}" -f ([int64]$n -band 0xFFFFFFFF) } catch { "$n" } }

# 用 Win32 API 把 HWND 反查进程,核实 COM 窗口到底是 IE 还是 Edge
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
            return "PID=$pid2 (进程已退)"
        }
    } catch {}
    return "未知"
}

W "IE 内核启动诊断  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "机器: $env:COMPUTERNAME  用户: $env:USERNAME"
W "目标: $EBS"

# ---------- 方式 1: COM,两个 ProgID 都试 ----------
foreach ($progid in @("InternetExplorer.Application","InternetExplorerMedium")) {
    W ""
    W "==== 方式1: COM [$progid] ===="
    $ie = $null
    try {
        $ie = New-Object -ComObject $progid -ErrorAction Stop
        $ie.Visible = $true
        $ie.Navigate($EBS)
        W "COM 创建: 成功"
        # 轮询最多 12 秒等导航
        $url = ""; $hwnd = 0
        for ($i=0; $i -lt 6; $i++) {
            Start-Sleep -Seconds 2
            try { $url = $ie.LocationURL } catch { $url = "(读取失败: $_)" }
            try { $hwnd = [int64]$ie.HWND } catch {}
            if ($url -match "ebsprod|bytedance") { break }
        }
        try { W "  Visible    : $($ie.Visible)" } catch {}
        W "  LocationURL: $url"
        W "  HWND       : $hwnd"
        if ($hwnd -ne 0) { W "  HWND 归属进程: $(ProcOfHwnd $hwnd)" }
        # 核实:窗口必须属于 iexplore 才算真 IE 内核
        $owner = if ($hwnd -ne 0) { ProcOfHwnd $hwnd } else { "" }
        if ($url -match "ebsprod|bytedance" -and $owner -match "iexplore") {
            W "  >> 成功: 真 IE 内核已加载 EBS。这是要的结果。"
        } elseif ($owner -match "msedge") {
            W "  >> 被劫持: COM 起来的窗口属于 msedge,不是真 IE。"
        } elseif ($url -match "ebsprod|bytedance") {
            W "  >> 导航到 EBS 但窗口归属=$owner,需人工确认是否 IE。"
        } else {
            W "  >> 未导航成功 (URL=$url)。"
        }
        break  # 第一个 ProgID 成功创建就不试第二个
    }
    catch {
        W "COM [$progid] 失败: $($_.Exception.Message)"
        W "  HResult: $(Hex $_.Exception.HResult)"
    }
}

# 进程快照
W ""
W "---- iexplore / msedge 进程快照 ----"
foreach($n in @("iexplore","msedge")){
    $ps = @(Get-Process $n -ErrorAction SilentlyContinue)
    W "  $n : $($ps.Count) 个"
    foreach($p in $ps){ W "      PID=$($p.Id) 路径=$($p.Path)" }
}

# ---------- 方式 2: 直接 iexplore.exe ----------
W ""
W "==== 方式2: 直接 iexplore.exe ===="
$iePath = "C:\Program Files\Internet Explorer\iexplore.exe"
if (Test-Path $iePath) {
    $b_ie = @(Get-Process iexplore -ErrorAction SilentlyContinue).Count
    $b_ed = @(Get-Process msedge   -ErrorAction SilentlyContinue).Count
    try { Start-Process $iePath $EBS } catch { W "  启动异常: $_" }
    Start-Sleep -Seconds 6
    $a_ie = @(Get-Process iexplore -ErrorAction SilentlyContinue).Count
    $a_ed = @(Get-Process msedge   -ErrorAction SilentlyContinue).Count
    W "  iexplore 进程 (前->后): $b_ie -> $a_ie"
    W "  msedge   进程 (前->后): $b_ed -> $a_ed"
    if ($a_ie -gt $b_ie)      { W "  >> iexplore 进程增加 = 真 IE 起来了" }
    elseif ($a_ed -gt $b_ed)  { W "  >> msedge 进程增加 = 被重定向到 Edge(IE 未起)" }
    else                      { W "  >> 无新进程 = 启动后秒退/失败" }
} else { W "  iexplore.exe 不存在: $iePath" }

# ---------- 环境: IE→Edge 重定向开关 (只读) ----------
W ""
W "==== 环境: IE→Edge 重定向相关注册表 (只读) ===="
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
            if ($null -ne $v) { W "  $($c.P)\$($c.N) = $v" } else { W "  $($c.P)\$($c.N) = (无此值)" }
        } else { W "  $($c.P) (键不存在)" }
    } catch { W "  $($c.P)\$($c.N) 读取异常: $_" }
}

W ""
W "==== 总判定 ===="
W "看回传:"
W "  - 任一方式出现 '真 IE 内核已加载 EBS' 或 'iexplore 进程增加' -> 通了,接下来清 cookie + 登录点财务表单"
W "  - 全部被劫持到 msedge / DisableInternetExplorerApp=1 -> 本地起 IE 内核的路走完,只剩 IT 开 Edge IE 模式"

$log.ToString() | Out-File -FilePath $Out -Encoding UTF8
Write-Host ""
Write-Host "日志已写: $Out  (commit 回传)" -ForegroundColor Green
