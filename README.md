# EBS 登录问题诊断

目标系统：`ebsprod.bytedance.net:8000`

报错：`FND_STATE_LOSS_ERROR ... OANavigatePortletAM has already been released`

这一步只做**诊断采集**，脚本是只读的——不输密码、不改系统、不动浏览器数据。

---

## 怎么运行（Windows）

**前提：在那台平时能打开 EBS 的电脑上运行（要连着公司内网/VPN）。**

### 方法 A：右键运行（最简单）
1. 下载本仓库（或单独下 `diagnose_ebs.ps1`）。
2. 右键 `diagnose_ebs.ps1` → **使用 PowerShell 运行**。
3. 等它跑完（几十秒），窗口里会有结果。
4. 同目录会生成 **`ebs_diag_result.txt`**，把这个文件发回。

### 方法 B：如果方法 A 提示"无法加载/执行策略被禁止"
1. 开始菜单搜 **PowerShell**，打开。
2. `cd` 到脚本所在目录，例如：
   ```powershell
   cd $HOME\Downloads\temp
   ```
3. 运行：
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\diagnose_ebs.ps1
   ```
4. 跑完后把同目录的 `ebs_diag_result.txt` 发回。

---

## 它会查什么
- 本机是否在公司内网/VPN（有没有 10.x 内网 IP）
- 域名能不能解析、8000 端口通不通
- EBS 登录页是**本地账号密码表单**还是**跳 SSO 单点登录**（决定下一步能不能脚本自动验证）
- 链路追踪、系统代理设置

> 第一版故意不自动输账号密码：登录方式还没确认，且对财务系统跑自动登录有账号锁定风险。等看清登录方式，第二版再做精确的登录验证。
