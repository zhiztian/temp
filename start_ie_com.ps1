# =====================================================================
# 用 COM 对象 InternetExplorer.Application 拉起真正的 IE11 内核
# 绕过 Win11 对 iexplore.exe 的 Edge 重定向。IE 内核才会调 Java 插件。
#
# 运行(Git Bash):  powershell -ExecutionPolicy Bypass -File ./start_ie_com.ps1
# 或右键 用 PowerShell 运行
# =====================================================================

$ErrorActionPreference = "Stop"
$EBS = "http://ebsprod.bytedance.net:8000/OA_HTML/OA.jsp?OAFunc=OANEWHOMEPAGE"

Write-Host "尝试用 COM 启动 IE 内核 ..." -ForegroundColor Cyan
try {
    $ie = New-Object -ComObject InternetExplorer.Application
    $ie.Visible = $true
    $ie.Navigate($EBS)
    Write-Host ">> 成功创建 IE COM 对象。" -ForegroundColor Green
    Write-Host "   如果弹出了带经典菜单的 IE 窗口并加载 EBS = 可用。" -ForegroundColor Green
    Write-Host ""
    Write-Host "接下来在这个 IE 窗口里:" -ForegroundColor Yellow
    Write-Host "  1. 齿轮/工具 -> Internet 选项 -> 常规 -> 删除 ->"
    Write-Host "     勾 [Cookie 和网站数据] -> 删除   (清 session)"
    Write-Host "  2. 重新访问 EBS 登录 -> 进 Main Menu -> 点开财务表单"
    Write-Host "  3. Java 表单应能起来(EBS 已在 Java 安全例外)"
    Write-Host ""
    Write-Host "窗口已交给你,本脚本不关闭它。"
}
catch {
    Write-Host ">> COM 方式失败:" -ForegroundColor Red
    Write-Host $_.Exception.Message
    Write-Host ""
    Write-Host "若报 80004005/拒绝访问 等,说明 IE COM 也被策略禁用,"
    Write-Host "本地启动 IE 内核的路基本走完,只剩找 IT 开 Edge IE 模式。"
}

Write-Host ""
Read-Host "按回车退出"
