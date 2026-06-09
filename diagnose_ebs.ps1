# =====================================================================
# EBS 登录诊断脚本 (Windows PowerShell)
# 目标系统: ebsprod.bytedance.net:8000
# 用途: 在 Dandan 电脑上跑，采集网络/会话/登录方式信息，回传日志
#
# 运行方法（任选其一）:
#   1) 右键本文件 -> "使用 PowerShell 运行"
#   2) 打开 PowerShell，cd 到本文件目录，执行: .\diagnose_ebs.ps1
#      如提示执行策略被禁止，先运行:
#         powershell -ExecutionPolicy Bypass -File .\diagnose_ebs.ps1
#
# 本脚本【只读诊断】，不输入密码、不改任何系统设置、不动浏览器数据。
# 结束后会生成 ebs_diag_result.txt，把这个文件发回即可。
# =====================================================================

$ErrorActionPreference = "Continue"
$Host_   = "ebsprod.bytedance.net"
$Port    = 8000
$BaseUrl = "http://${Host_}:${Port}"
$OutFile = Join-Path $PSScriptRoot "ebs_diag_result.txt"
if (-not $PSScriptRoot) { $OutFile = "ebs_diag_result.txt" }

# 日志缓冲
$script:Log = New-Object System.Text.StringBuilder
function W([string]$msg) {
    [void]$script:Log.AppendLine($msg)
    Write-Host $msg
}
function Section([string]$title) {
    W ""
    W "==================== $title ===================="
}

W "EBS 登录诊断报告"
W "生成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "目标: $BaseUrl"

# --- 0. 机器与网络环境 ---
Section "0. 本机环境"
try {
    W "计算机名: $env:COMPUTERNAME"
    W "用户名:   $env:USERNAME"
    W "OS:       $((Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption)"
    W "PowerShell 版本: $($PSVersionTable.PSVersion)"
} catch { W "本机环境采集异常: $_" }

Section "0b. 网络接口 / 是否在内网/VPN"
try {
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -ne "127.0.0.1" } |
        ForEach-Object { W ("IP: {0,-18} 接口: {1}" -f $_.IPAddress, $_.InterfaceAlias) }
} catch { W "网络接口采集异常: $_" }
# 字节内网 10.x 网段提示
W "(若上面没有 10.x.x.x 的内网地址，可能未连入字节内网/VPN)"

# --- 1. DNS 解析 ---
Section "1. DNS 解析"
try {
    $dns = Resolve-DnsName -Name $Host_ -ErrorAction Stop
    $dns | Where-Object { $_.IPAddress } | ForEach-Object { W "解析到 IP: $($_.IPAddress)" }
    if (-not ($dns | Where-Object { $_.IPAddress })) { W "未解析到 A 记录: $($dns | Out-String)" }
} catch {
    W "DNS 解析失败: $_"
    W ">> 结论: 域名都解析不了，通常是没连内网/VPN，或 DNS 配置问题。后面步骤大概率也不通。"
}

# --- 2. TCP 端口连通性 ---
Section "2. TCP 8000 端口连通性"
$tcpOk = $false
try {
    $t = Test-NetConnection -ComputerName $Host_ -Port $Port -WarningAction SilentlyContinue -ErrorAction Stop
    W "TcpTestSucceeded: $($t.TcpTestSucceeded)"
    W "远端地址:        $($t.RemoteAddress)"
    W "Ping(ICMP)成功:  $($t.PingSucceeded)"
    $tcpOk = $t.TcpTestSucceeded
    if (-not $t.TcpTestSucceeded) {
        W ">> 结论: 端口连不上。可能未连内网/VPN、防火墙拦截、或服务端 8000 未监听。"
    }
} catch { W "TCP 测试异常: $_" }

# --- 3. HTTP 探测（不带凭据，看登录页长什么样）---
Section "3. HTTP 登录页探测（只读，不输密码）"
if (-not $tcpOk) {
    W "端口不通，跳过 HTTP 探测。"
} else {
    try {
        # 用 session 变量保留 cookie，模拟首次访问
        $resp = Invoke-WebRequest -Uri $BaseUrl -MaximumRedirection 0 -TimeoutSec 20 `
                  -SessionVariable sess -UseBasicParsing -ErrorAction Stop
        W "首页 HTTP 状态: $($resp.StatusCode) $($resp.StatusDescription)"
        W "最终 URL:       $($resp.BaseResponse.ResponseUri)"
    } catch {
        # 30x 跳转会在这里被捕获，正好用来判断是否 SSO
        $r = $_.Exception.Response
        if ($r) {
            $code = [int]$r.StatusCode
            $loc  = $r.Headers["Location"]
            W "首页返回: HTTP $code"
            if ($loc) { W "重定向到: $loc" }
            if ($code -ge 300 -and $code -lt 400) {
                W ">> 提示: 发生跳转。如果跳到 SSO/单点登录域名，说明这套 EBS 走 SSO，"
                W "         不能用账号密码直接表单登录，需走公司统一身份认证。"
            }
        } else {
            W "HTTP 探测异常: $_"
        }
    }

    # 探测 EBS 经典登录入口
    Section "3b. EBS 经典登录入口探测"
    $loginPaths = @(
        "/OA_HTML/AppsLogin",
        "/OA_HTML/AppsLocalLogin.jsp",
        "/OA_HTML/RF.jsp?function_id=1032925"
    )
    foreach ($p in $loginPaths) {
        $u = "$BaseUrl$p"
        try {
            $lr = Invoke-WebRequest -Uri $u -MaximumRedirection 3 -TimeoutSec 20 `
                    -UseBasicParsing -ErrorAction Stop
            W ""
            W "[$p] -> HTTP $($lr.StatusCode), 最终URL: $($lr.BaseResponse.ResponseUri)"
            # 找表单字段名（判断是不是本地表单登录）
            $names = ([regex]::Matches($lr.Content, 'name="([^"]+)"') |
                      ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
            if ($names) { W "    页面表单字段: $($names -join ', ')" }
            # 标题
            $m = [regex]::Match($lr.Content, '<title>(.*?)</title>', 'IgnoreCase')
            if ($m.Success) { W "    页面标题: $($m.Groups[1].Value.Trim())" }
        } catch {
            $r = $_.Exception.Response
            if ($r) {
                $loc = $r.Headers["Location"]
                W ""
                W "[$p] -> HTTP $([int]$r.StatusCode)$(if($loc){" 跳转: $loc"})"
            } else {
                W ""
                W "[$p] -> 访问异常: $($_.Exception.Message)"
            }
        }
    }
}

# --- 4. 路由/链路（端口不通时帮助定位）---
Section "4. 链路追踪 (tracert，最多 10 跳)"
if (-not $tcpOk) {
    try {
        $tr = tracert -d -h 10 -w 1000 $Host_ 2>&1 | Out-String
        W $tr
    } catch { W "tracert 异常: $_" }
} else {
    W "端口已连通，跳过 tracert。"
}

# --- 5. 系统代理设置（EBS 偶尔受代理影响）---
Section "5. 系统代理设置"
try {
    $pk = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    $pe = (Get-ItemProperty -Path $pk -Name ProxyEnable -ErrorAction SilentlyContinue).ProxyEnable
    $ps = (Get-ItemProperty -Path $pk -Name ProxyServer -ErrorAction SilentlyContinue).ProxyServer
    W "ProxyEnable: $pe"
    W "ProxyServer: $ps"
} catch { W "代理设置读取异常: $_" }

# --- 写文件 ---
Section "诊断结束"
W "请把同目录下的文件发回: ebs_diag_result.txt"
try {
    $script:Log.ToString() | Out-File -FilePath $OutFile -Encoding UTF8
    Write-Host ""
    Write-Host "已保存到: $OutFile" -ForegroundColor Green
} catch {
    Write-Host "保存文件失败: $_" -ForegroundColor Red
    Write-Host "请手动复制上面窗口里的全部文字发回。"
}

Write-Host ""
Write-Host "按回车键退出..." -ForegroundColor Yellow
Read-Host
