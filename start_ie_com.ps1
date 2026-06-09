# =====================================================================
# 启动 IE 内核 (Win11) —— 自动验证并写日志,无需人工看屏幕
# 多种方式依次尝试,记录每种是否真正拉起了 IE 内核(MSHTML)。
# 产出: ie_start_log.txt  (commit 回传即可)
# =====================================================================

$Out = Join-Path $PSScriptRoot "ie_start_log.txt"
if (-not $PSScriptRoot) { $Out = "ie_start_log.txt" }
$EBS = "http://ebsprod.bytedance.net:8000/OA_HTML/OA.jsp?OAFunc=OANEWHOMEPAGE"
$log = New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }

W "IE 内核启动诊断  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "目标: $EBS"

# --- 方式 1: COM InternetExplorer.Application ---
W ""
W "==== 方式1: COM InternetExplorer.Application ===="
$ieProcBefore = @(Get-Process iexplore -ErrorAction SilentlyContinue).Count
try {
    $ie = New-Object -ComObject InternetExplorer.Application
    $ie.Visible = $true
    $ie.Navigate($EBS)
    Start-Sleep -Seconds 6
    W "COM 创建: 成功"
    try { W "  Visible    : $($ie.Visible)" } catch { W "  Visible 读取失败: $_" }
    try { W "  LocationURL: $($ie.LocationURL)" } catch { W "  LocationURL 读取失败: $_" }
    try { W "  Busy       : $($ie.Busy)" } catch {}
    try { W "  HWND       : $($ie.HWND)" } catch {}
    # 判定是否真加载了 EBS
    Start-Sleep -Seconds 4
    try {
        $url = $ie.LocationURL
        if ($url -match "ebsprod|bytedance") {
            W "  >> 判定: IE 内核已启动并导航到 EBS (URL=$url)"
        } elseif ($url) {
            W "  >> IE 起来了但 URL=$url (可能被拦/跳转)"
        } else {
            W "  >> COM 对象在但无 URL,可能未真正渲染"
        }
    } catch { W "  二次读取 URL 失败: $_" }
}
catch {
    W "COM 失败: $($_.Exception.Message)"
    W "  HResult: $($_.Exception.HResult)"
}
$ieProcAfter = @(Get-Process iexplore -ErrorAction SilentlyContinue)
W "iexplore 进程数 (前->后): $ieProcBefore -> $($ieProcAfter.Count)"
foreach($p in $ieProcAfter){ W "  iexplore PID=$($p.Id) 路径=$($p.Path)" }

# --- 方式 2: 直接跑 iexplore.exe (看是否被重定向) ---
W ""
W "==== 方式2: 直接 iexplore.exe ===="
$iePath = "C:\Program Files\Internet Explorer\iexplore.exe"
if (Test-Path $iePath) {
    $before2 = @(Get-Process iexplore -ErrorAction SilentlyContinue).Count
    $beforeEdge = @(Get-Process msedge -ErrorAction SilentlyContinue).Count
    Start-Process $iePath $EBS
    Start-Sleep -Seconds 5
    $after2 = @(Get-Process iexplore -ErrorAction SilentlyContinue).Count
    $afterEdge = @(Get-Process msedge -ErrorAction SilentlyContinue).Count
    W "iexplore 进程 (前->后): $before2 -> $after2"
    W "msedge   进程 (前->后): $beforeEdge -> $afterEdge"
    if ($after2 -gt $before2) { W "  >> iexplore 进程增加 = IE 可能真起来了" }
    elseif ($afterEdge -gt $beforeEdge) { W "  >> 是 Edge 进程增加 = 被重定向到 Edge(IE 未起)" }
    else { W "  >> 无新进程 = 启动失败/秒退" }
} else {
    W "iexplore.exe 不存在: $iePath"
}

# --- 环境补充 ---
W ""
W "==== 环境 ===="
W "FEATURE_BROWSER_EMULATION 注册表(IE 兼容模式设置):"
$femu = "HKCU:\Software\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION"
if (Test-Path $femu) { (Get-Item $femu).Property | ForEach-Object { W "  $_ = $((Get-ItemProperty $femu).$_)" } } else { W "  (无此键)" }

W ""
W "==== 判定 ===="
W "方式1 LocationURL 含 ebsprod 或 方式2 iexplore 进程增加 -> IE 内核可用,接下去清cookie+登录"
W "两者都失败/全被重定向到 msedge -> 本地起 IE 内核的路走完,只剩 IT 开 Edge IE 模式"

$log.ToString() | Out-File -FilePath $Out -Encoding UTF8
Write-Host ""
Write-Host "日志已写: $Out  (commit 回传)" -ForegroundColor Green
