# EBS 登录问题诊断

目标：`ebsprod.bytedance.net:8000`
报错：`FND_STATE_LOSS_ERROR ... OANavigatePortletAM has already been released`（OAF 会话状态损坏）

WSL 侧解析得到内网 IP `10.8.6.199` 但 TCP 8000 超时（不在字节内网路由内），故诊断在能访问 EBS 的 Windows 机器上跑，结果经 GitHub 回传。

## 运行（Git Bash / mingw64）

GitHub Desktop → `Repository → Open in Git Bash`：
```bash
bash diagnose_ebs.sh
```
生成 `ebs_diag_result.txt`，commit + push 回传。

`diagnose_ebs.ps1` 为 PowerShell 等价版（备用）。

## 脚本做什么（只读，不输密码/不改系统）
- 内网/VPN 判定：`ipconfig` 抓 IPv4，看有无 10.x
- DNS（nslookup）+ TCP 连通性（curl 退出码：7 拒绝 / 28 超时 / 6 解析失败）
- 首页 `curl -I` 不跟随跳转 → 看是否 30x 跳 SSO
- 探 `/OA_HTML/AppsLogin`、`AppsLocalLogin.jsp`、`RF.jsp` → 抓最终 URL / title / form 字段名，判定本地表单 vs SSO
- 端口不通时 tracert；代理环境变量

## v1 的判定目的
登录方式是脚本抓回的页面特征判定，不是假设：
- **本地表单**（出现 usernameField/passwordField 等）→ v2 可写 curl 自动登录验证，用干净会话证明账号+服务端正常、问题在浏览器 session
- **跳 SSO** → 自动登录基本不可行，方案转向浏览器侧清 session

> 注意：对财务系统自动登录有账号锁定风险，故 v1 先只探测登录方式，确认后再决定 v2。
