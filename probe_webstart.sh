#!/usr/bin/env bash
# =====================================================================
# 探测 EBS Forms 是否有 Java Web Start (.jnlp) 入口
# 有则可绕开 IE/Edge,双击 jnlp 用本地 Java 直接跑 Forms。
# 运行: bash probe_webstart.sh   产出: webstart_probe.txt + 抓到的 jnlp/页面
# =====================================================================

HOST="ebsprod.bytedance.net"; PORT=8000; BASE="http://${HOST}:${PORT}"
DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"; [ -z "$DIR" ] && DIR="."
OUT="$DIR/webstart_probe.txt"; JAR="$(mktemp 2>/dev/null || echo "$DIR/.c.$$")"; : > "$OUT"
W(){ printf '%s\n' "$*" | tee -a "$OUT"; }; SEC(){ W ""; W "==== $* ===="; }
trap '[ -f "$JAR" ] && rm -f "$JAR"' EXIT

W "EBS Web Start 探测  $(date '+%F %T')"

SEC "0. 本地 javaws"
ls "/c/Program Files (x86)/Java/jre1.8.0_333/bin/javaws.exe" 2>/dev/null && W "javaws 在" || W "javaws 缺"

SEC "1. 登录(复用本地表单,拿会话)"
printf '用户名: ' >/dev/tty; read -r U </dev/tty
printf '口令(不回显): ' >/dev/tty; read -rs P </dev/tty; printf '\n' >/dev/tty
curl -s -c "$JAR" -o /dev/null -m 20 "${BASE}/OA_HTML/AppsLocalLogin.jsp"
# 经典本地登录提交端点(EBS 标准)
code=$(curl -s -b "$JAR" -c "$JAR" -o "$DIR/ws_login_after.html" -w "%{http_code}|%{url_effective}" -m 30 -L \
  --data-urlencode "username=${U}" --data-urlencode "password=${P}" \
  --data-urlencode "usernameField=${U}" --data-urlencode "passwordField=${P}" \
  "${BASE}/OA_HTML/OA.jsp?akRegionApplicationId=0&akRegionCode=FND_TOP_SSO_LOCAL_LOGIN&_FROM_LOGIN=Y")
unset P
W "登录提交结果: $code"
W "会话 cookie:"; grep -v '^#' "$JAR" 2>/dev/null | awk '{print "  "$6}' | tee -a "$OUT"

SEC "2. 取主页,找 Forms / Web Start 线索"
curl -s -b "$JAR" -o "$DIR/ws_home.html" -m 30 -L "${BASE}/OA_HTML/OA.jsp?OAFunc=OANEWHOMEPAGE"
W "主页大小: $(wc -c < "$DIR/ws_home.html" 2>/dev/null) 字节"
W "--- 命中关键字 ---"
for kw in jnlp javaws frmservlet "Forms Servlet" forms "config=" runform webutil JNLP; do
  n=$(grep -o -i "$kw" "$DIR/ws_home.html" 2>/dev/null | wc -l)
  [ "$n" -gt 0 ] && W "  $kw : $n 次"
done
W "--- 含 jnlp/frmservlet/forms 的链接 ---"
grep -o -i 'href="[^"]*"' "$DIR/ws_home.html" 2>/dev/null | grep -i -E 'jnlp|frmservlet|forms' | sort -u | sed 's/^/  /' | tee -a "$OUT"

SEC "3. 直接探 Forms Servlet 端点"
for p in "/forms/frmservlet?config=webutil" "/forms/frmservlet" "/forms/frmservlet?ifcmd=startsession" "/OA_HTML/frmservlet"; do
  c=$(curl -s -b "$JAR" -o "$DIR/ws_frm.tmp" -w "%{http_code}|%{content_type}" -m 20 -L "${BASE}${p}")
  W "[$p] -> $c"
  if grep -qi 'jnlp\|<application-desc\|<jnlp' "$DIR/ws_frm.tmp" 2>/dev/null; then
    W "  >> 命中 JNLP! 保存为 ws_${p//\//_}.jnlp"
    cp "$DIR/ws_frm.tmp" "$DIR/ws_frmservlet.jnlp"
  fi
done
rm -f "$DIR/ws_frm.tmp"

SEC "判定"
W "若 ws_frmservlet.jnlp 生成 / 第2步有 jnlp 链接 -> 走 Web Start:"
W "  下载该 jnlp,右键用 javaws.exe 打开即可跑 Forms,绕开浏览器。"
W "回传: webstart_probe.txt, ws_home.html, ws_login_after.html, *.jnlp(若有)"
echo ""; read -n 1 -s -r -p "按任意键退出..." </dev/tty 2>/dev/null||true; echo ""
