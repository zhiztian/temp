#!/usr/bin/env bash
# =====================================================================
# EBS 本地登录验证 v2 (Git Bash / mingw64)
# 目标: http://ebsprod.bytedance.net:8000/OA_HTML/AppsLocalLogin.jsp
#
# 目的: 用【全新 cookie 会话】走一遍本地账号密码登录，验证
#       "账号 + 服务端" 是否正常 —— 若干净会话能进 Main Menu 不报
#       FND_STATE_LOSS_ERROR，则坐实问题出在浏览器里的旧 session。
#
# 安全:
#   - 口令运行时输入(read -s)，只在内存，绝不写盘/打印/进日志/进 git
#   - 全新 cookie jar，单次尝试，不重试(避免账号锁定)
#   - 不硬编码 POST 端点：抓真实登录页解析 form action 与字段名
#
# 运行: GitHub Desktop -> Open in Git Bash -> bash login_test.sh
# 产出(可 commit 回传，均不含口令):
#   - login_test_result.txt   日志
#   - login_page.html         登录页原始 HTML(供核实提交机制)
#   - after_login.html        登录后返回页(已尝试去除可能的会话串)
# =====================================================================

HOST="ebsprod.bytedance.net"
PORT=8000
BASE="http://${HOST}:${PORT}"
LOGIN_URL="${BASE}/OA_HTML/AppsLocalLogin.jsp"

DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"; [ -z "$DIR" ] && DIR="."
OUT="$DIR/login_test_result.txt"
PAGE="$DIR/login_page.html"
AFTER="$DIR/after_login.html"
JAR="$(mktemp 2>/dev/null || echo "$DIR/.cookies.$$")"
: > "$OUT"

W() { printf '%s\n' "$*" | tee -a "$OUT"; }
SEC() { W ""; W "==================== $* ===================="; }

cleanup() { [ -f "$JAR" ] && rm -f "$JAR"; }
trap cleanup EXIT

W "EBS 本地登录验证报告 v2"
W "时间: $(date '+%Y-%m-%d %H:%M:%S')"
W "登录入口: $LOGIN_URL"
W "(口令仅内存使用，不写入任何文件)"

# --- 1. 抓登录页 + 拿初始 cookie ---
SEC "1. 抓取登录页(全新会话)"
code=$(curl -s -c "$JAR" -o "$PAGE" -w "%{http_code}" -m 20 "$LOGIN_URL" 2>>"$OUT")
W "GET 状态码: $code"
W "登录页已存: $PAGE ($(wc -c < "$PAGE" 2>/dev/null) 字节)"
W "初始 cookie:"
grep -v '^#' "$JAR" 2>/dev/null | awk '{print "  "$6" (domain "$1")"}' | tee -a "$OUT"

# --- 2. 解析 form ---
SEC "2. 解析登录表单"
# form action
ACTION=$(grep -i -o '<form[^>]*action="[^"]*"' "$PAGE" 2>/dev/null | head -1 | sed -E 's/.*action="([^"]*)".*/\1/')
METHOD=$(grep -i -o '<form[^>]*method="[^"]*"' "$PAGE" 2>/dev/null | head -1 | sed -E 's/.*method="([^"]*)".*/\1/')
W "form action: ${ACTION:-(未找到，可能 JS 提交)}"
W "form method: ${METHOD:-(未标注)}"

# 所有 input 名(含 hidden)
W "页面 input 字段:"
grep -i -o '<input[^>]*>' "$PAGE" 2>/dev/null | while read -r line; do
    n=$(printf '%s' "$line" | sed -nE 's/.*name="([^"]*)".*/\1/p')
    t=$(printf '%s' "$line" | sed -nE 's/.*type="([^"]*)".*/\1/p')
    v=$(printf '%s' "$line" | sed -nE 's/.*value="([^"]*)".*/\1/p')
    [ -n "$n" ] && W "  name=$n type=${t:-?} value=${v:-}"
done

# 收集 hidden 字段为 POST 参数
HIDDEN_ARGS=()
while read -r line; do
    case "$line" in
        *type=\"hidden\"*|*type=hidden*)
            n=$(printf '%s' "$line" | sed -nE 's/.*name="([^"]*)".*/\1/p')
            v=$(printf '%s' "$line" | sed -nE 's/.*value="([^"]*)".*/\1/p')
            [ -n "$n" ] && HIDDEN_ARGS+=(--data-urlencode "${n}=${v}")
            ;;
    esac
done < <(grep -i -o '<input[^>]*>' "$PAGE" 2>/dev/null)

# 解析 action 绝对 URL
if [ -z "$ACTION" ]; then
    POST_URL="$LOGIN_URL"   # 退路：原页
elif printf '%s' "$ACTION" | grep -qi '^http'; then
    POST_URL="$ACTION"
elif printf '%s' "$ACTION" | grep -q '^/'; then
    POST_URL="${BASE}${ACTION}"
else
    POST_URL="${BASE}/OA_HTML/${ACTION}"
fi
W "推断 POST 目标: $POST_URL"

# --- 3. 输入凭据(内存) ---
SEC "3. 输入凭据"
printf '用户名: ' > /dev/tty
read -r EBS_USER < /dev/tty
printf '口令(输入时不显示): ' > /dev/tty
read -rs EBS_PASS < /dev/tty
printf '\n' > /dev/tty
if [ -z "$EBS_USER" ] || [ -z "$EBS_PASS" ]; then
    W "未输入用户名或口令，中止。"
    exit 1
fi
W "用户名: $EBS_USER"
W "口令长度: ${#EBS_PASS} 位 (内容不记录)"

# --- 4. 单次 POST 登录 ---
SEC "4. 提交登录(单次，不重试)"
# EBS 本地表单字段名常为 usernameField / passwordField；以页面实际为准
HDRS=$(curl -s -b "$JAR" -c "$JAR" -o "$AFTER" -D - -m 30 -L \
    --data-urlencode "usernameField=${EBS_USER}" \
    --data-urlencode "passwordField=${EBS_PASS}" \
    "${HIDDEN_ARGS[@]}" \
    "$POST_URL" 2>>"$OUT")
unset EBS_PASS   # 立即清除内存口令
W "登录后响应头(首部):"
printf '%s\n' "$HDRS" | head -20 | tee -a "$OUT"

# --- 5. 判定结果 ---
SEC "5. 结果判定"
if [ ! -f "$AFTER" ]; then
    W "未取得登录后页面。"
else
    SZ=$(wc -c < "$AFTER")
    W "登录后页面大小: $SZ 字节"
    if grep -qi 'FND_STATE_LOSS_ERROR\|has already been released' "$AFTER"; then
        W ">> 命中 FND_STATE_LOSS_ERROR：干净会话下也复现 => 偏向服务端/账号侧问题，需提 IT。"
    elif grep -qi 'invalid\|incorrect\|认证失败\|用户名或密码\|Login failed\|AUTH' "$AFTER"; then
        W ">> 出现疑似认证失败提示：可能字段名不是 usernameField/passwordField，"
        W "   或本地登录被禁用。请看 login_page.html 与 after_login.html 核实。"
    elif grep -qi 'Main Menu\|Navigator\|Home\|responsibilit\|主页\|导航' "$AFTER"; then
        W ">> 疑似登录成功并进入主页/导航：干净会话 OK => 坐实问题在浏览器旧 session。"
    else
        W ">> 无法自动判定，请人工查看 after_login.html 标题与内容。"
    fi
    t=$(grep -i -o '<title>[^<]*</title>' "$AFTER" 2>/dev/null | head -1)
    [ -n "$t" ] && W "登录后页面标题: $t"
fi

# 去掉回传文件里的 jsessionid 串(尽量，不保证彻底)
for f in "$PAGE" "$AFTER"; do
    [ -f "$f" ] && sed -i -E 's/jsessionid=[A-Za-z0-9_!-]+/jsessionid=__REDACTED__/g' "$f" 2>/dev/null
done

SEC "结束"
W "回传文件: login_test_result.txt, login_page.html, after_login.html"
W "(口令未写入任何文件；cookie jar 已删除)"

echo ""
read -n 1 -s -r -p "按任意键退出..." < /dev/tty
echo ""
