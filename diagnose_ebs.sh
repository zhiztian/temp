#!/usr/bin/env bash
# =====================================================================
# EBS 登录诊断脚本 (Git Bash / mingw64 版)
# 目标系统: ebsprod.bytedance.net:8000
#
# 运行方法:
#   - GitHub Desktop: Repository -> Open in Git Bash
#   - 然后执行:  bash diagnose_ebs.sh
#
# 本脚本【只读诊断】: 不输密码、不改系统、不动浏览器数据。
# 结束后生成 ebs_diag_result.txt，把它发回 / commit 推上来即可。
# =====================================================================

HOST="ebsprod.bytedance.net"
PORT=8000
BASE="http://${HOST}:${PORT}"

# 输出文件放在脚本所在目录
DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -z "$DIR" ] && DIR="."
OUT="$DIR/ebs_diag_result.txt"
: > "$OUT"   # 清空

# 同时输出到屏幕和文件
W() { printf '%s\n' "$*" | tee -a "$OUT"; }
SEC() { W ""; W "==================== $* ===================="; }

W "EBS 登录诊断报告 (Git Bash 版)"
W "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
W "目标: $BASE"

# --- 0. 本机环境 ---
SEC "0. 本机环境"
W "计算机名: ${COMPUTERNAME:-未知}"
W "用户名:   ${USERNAME:-未知}"
W "uname:    $(uname -a 2>/dev/null)"
W "curl:     $(curl --version 2>/dev/null | head -1)"

SEC "0b. 网络接口 / 是否在内网·VPN"
# 调用 Windows ipconfig 取 IPv4
if command -v ipconfig >/dev/null 2>&1; then
    ipconfig 2>/dev/null | grep -i "IPv4" | tee -a "$OUT"
else
    W "ipconfig 不可用"
fi
W "(若上面没有 10.x.x.x 的内网地址，可能未连入字节内网/VPN)"

# --- 1. DNS 解析 ---
SEC "1. DNS 解析"
if command -v nslookup >/dev/null 2>&1; then
    nslookup "$HOST" 2>&1 | tee -a "$OUT"
else
    W "nslookup 不可用"
fi

# --- 2. TCP 端口连通性 (用 curl 退出码判断) ---
SEC "2. TCP ${PORT} 端口连通性"
# --connect-timeout 仅测 TCP 握手；忽略 body
curl -s -o /dev/null --connect-timeout 6 "$BASE" 2>>"$OUT"
rc=$?
TCP_OK=0
case $rc in
    0)  W "curl 退出码 0  -> 端口可连且有响应"; TCP_OK=1 ;;
    7)  W "curl 退出码 7  -> 连接被拒/连不上 (Failed to connect)" ;;
    28) W "curl 退出码 28 -> 超时 (未连内网/VPN 或被防火墙静默丢弃)" ;;
    6)  W "curl 退出码 6  -> 域名解析失败" ;;
    *)  W "curl 退出码 $rc -> 见 curl 文档" ;;
esac

# --- 3. HTTP 探测：看首页是否跳转 (判断 SSO) ---
SEC "3. HTTP 首页探测（只读，不输密码）"
if [ "$TCP_OK" -ne 1 ]; then
    W "端口不通，跳过 HTTP 探测。"
else
    # -I 取响应头；-s 静默；-m 总超时；不自动跟随跳转，看 Location
    W "--- 首页响应头 (不跟随跳转) ---"
    curl -s -I -m 20 "$BASE" 2>>"$OUT" | tee -a "$OUT"
    W ""
    W "提示: 若上面出现 30x + Location 指向 SSO/单点登录域名，"
    W "      说明这套 EBS 走 SSO，不能脚本直接账号密码登录。"

    # --- 3b. EBS 经典登录入口 ---
    SEC "3b. EBS 登录入口探测"
    for P in "/OA_HTML/AppsLogin" "/OA_HTML/AppsLocalLogin.jsp" "/OA_HTML/RF.jsp?function_id=1032925"; do
        U="${BASE}${P}"
        W ""
        W "[$P]"
        # 跟随跳转，抓最终状态码与最终 URL
        code=$(curl -s -L -o /tmp/ebs_page.$$ -w "%{http_code}|%{url_effective}" -m 20 "$U" 2>>"$OUT")
        W "  HTTP状态|最终URL: $code"
        if [ -f /tmp/ebs_page.$$ ]; then
            # 抓 <title>
            title=$(grep -i -o '<title>[^<]*</title>' /tmp/ebs_page.$$ 2>/dev/null | head -1)
            [ -n "$title" ] && W "  页面标题: $title"
            # 抓表单字段名 name="..."
            names=$(grep -o 'name="[^"]*"' /tmp/ebs_page.$$ 2>/dev/null | sort -u | tr '\n' ' ')
            [ -n "$names" ] && W "  表单字段: $names"
            rm -f /tmp/ebs_page.$$
        fi
    done
fi

# --- 4. 链路追踪 (端口不通时定位) ---
SEC "4. 链路追踪 tracert (最多 10 跳)"
if [ "$TCP_OK" -ne 1 ] && command -v tracert >/dev/null 2>&1; then
    tracert -d -h 10 -w 1000 "$HOST" 2>&1 | tee -a "$OUT"
else
    W "端口已通或 tracert 不可用，跳过。"
fi

# --- 5. 代理设置 ---
SEC "5. 代理相关环境变量"
W "http_proxy=${http_proxy:-(空)}"
W "https_proxy=${https_proxy:-(空)}"
W "HTTP_PROXY=${HTTP_PROXY:-(空)}"
W "no_proxy=${no_proxy:-(空)}"

SEC "诊断结束"
W "结果已保存到: $OUT"
W "请把 ebs_diag_result.txt 发回（或在 GitHub Desktop 里 commit + push）。"

echo ""
read -n 1 -s -r -p "按任意键退出..."
echo ""
