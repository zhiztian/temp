#!/usr/bin/env bash
# =====================================================================
# EBS Java/Forms 客户端环境检查 (Git Bash / mingw64)
# 目的: 查清这台机器能不能跑 Oracle Forms (Java Applet) ——
#       Java 装没装/哪个版本、IE 内核在不在、Edge IE 模式策略、
#       Web Start 可用性。据此决定怎么让财务表单跑起来。
#
# 运行: GitHub Desktop -> Open in Git Bash -> bash check_java_env.sh
# 产出: java_env_result.txt  (只读检查，不装/不改任何东西，commit 回传)
# =====================================================================

DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"; [ -z "$DIR" ] && DIR="."
OUT="$DIR/java_env_result.txt"
: > "$OUT"

W() { printf '%s\n' "$*" | tee -a "$OUT"; }
SEC() { W ""; W "==================== $* ===================="; }

W "EBS Java/Forms 客户端环境检查"
W "时间: $(date '+%Y-%m-%d %H:%M:%S')"
W "机器: ${COMPUTERNAME:-?}  用户: ${USERNAME:-?}"
W "OS:   $(uname -s -r 2>/dev/null)"

# --- 1. Java 安装目录 ---
SEC "1. Java 安装目录"
found_java=0
for d in "/c/Program Files/Java" "/c/Program Files (x86)/Java" \
         "/c/Program Files/Common Files/Oracle/Java" ; do
    if [ -d "$d" ]; then
        W "[$d] 下:"
        ls -1 "$d" 2>/dev/null | sed 's/^/    /' | tee -a "$OUT"
        found_java=1
    fi
done
[ "$found_java" -eq 0 ] && W ">> 标准 Java 目录都不存在 —— 可能没装 Java。"

# --- 2. java / javaws 可执行 ---
SEC "2. java / javaws 可执行文件"
if command -v java >/dev/null 2>&1; then
    W "PATH 中 java: $(command -v java)"
    java -version 2>&1 | sed 's/^/    /' | tee -a "$OUT"
else
    W "java 不在 PATH。逐个找已装版本的 java.exe / javaws.exe:"
fi
# 直接枚举各 Java 版本下的 bin
for base in "/c/Program Files/Java" "/c/Program Files (x86)/Java"; do
    [ -d "$base" ] || continue
    for v in "$base"/*; do
        [ -d "$v" ] || continue
        je="$v/bin/java.exe"; jw="$v/bin/javaws.exe"
        if [ -f "$je" ]; then
            W ""
            W "  发现: $je"
            "$je" -version 2>&1 | sed 's/^/      /' | tee -a "$OUT"
            [ -f "$jw" ] && W "      javaws 存在(支持 Web Start): $jw" || W "      无 javaws(此版本不支持 Web Start)"
        fi
    done
done

# --- 3. .jnlp 关联(Web Start 是否可双击运行) ---
SEC "3. Java Web Start (.jnlp) 关联"
if command -v cmd.exe >/dev/null 2>&1; then
    assoc=$(cmd.exe /c "assoc .jnlp" 2>/dev/null | tr -d '\r')
    W "assoc .jnlp : ${assoc:-(无关联)}"
    if [ -n "$assoc" ]; then
        ftype=$(printf '%s' "$assoc" | sed 's/.*=//')
        ft=$(cmd.exe /c "ftype $ftype" 2>/dev/null | tr -d '\r')
        W "ftype       : ${ft:-(无)}"
    fi
else
    W "cmd.exe 不可用,跳过"
fi
W "(若 .jnlp 已关联 javaws,则财务表单可走 Web Start,不依赖浏览器插件)"

# --- 4. IE 内核 ---
SEC "4. Internet Explorer 内核"
ls -la "/c/Program Files/Internet Explorer/iexplore.exe" 2>/dev/null | tee -a "$OUT" && W "IE 主程序存在" || W "无 IE 主程序(Win11 正常,IE 模式走 Edge)"

# --- 5. Edge ---
SEC "5. Microsoft Edge"
for e in "/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \
         "/c/Program Files/Microsoft/Edge/Application/msedge.exe"; do
    [ -f "$e" ] && W "Edge: $e"
done

# --- 6. Edge IE 模式 策略(注册表) ---
SEC "6. Edge IE 模式 策略"
if command -v reg >/dev/null 2>&1 || command -v reg.exe >/dev/null 2>&1; then
    REG=reg.exe; command -v reg >/dev/null 2>&1 && REG=reg
    W "--- InternetExplorerIntegrationLevel (是否允许 IE 模式) ---"
    $REG query "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v InternetExplorerIntegrationLevel 2>/dev/null | tee -a "$OUT" || W "  HKLM 无此策略"
    $REG query "HKCU\SOFTWARE\Policies\Microsoft\Edge" /v InternetExplorerIntegrationLevel 2>/dev/null | tee -a "$OUT" || W "  HKCU 无此策略"
    W ""
    W "--- 企业站点列表 SiteList (IT 是否预置了 EBS 走 IE 模式) ---"
    $REG query "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v InternetExplorerIntegrationSiteList 2>/dev/null | tee -a "$OUT" || W "  HKLM 无 SiteList"
    $REG query "HKCU\SOFTWARE\Policies\Microsoft\Edge" /v InternetExplorerIntegrationSiteList 2>/dev/null | tee -a "$OUT" || W "  HKCU 无 SiteList"
else
    W "reg 命令不可用,跳过注册表检查"
fi

# --- 7. Java 部署配置文件(用户级) ---
SEC "7. Java 部署配置 (deployment.properties)"
for dp in "$HOME/AppData/LocalLow/Sun/Java/Deployment/deployment.properties" \
          "/c/Users/$USERNAME/AppData/LocalLow/Sun/Java/Deployment/deployment.properties"; do
    if [ -f "$dp" ]; then
        W "存在: $dp"
        grep -i 'security\|console\|version' "$dp" 2>/dev/null | sed 's/^/    /' | tee -a "$OUT"
        break
    fi
done
[ -f "$dp" ] || W "无用户级 deployment.properties(Java 可能没配过 applet 安全例外)"

# --- 8. Java 控制面板的站点例外列表 ---
SEC "8. Java 站点例外列表 (Exception Site List)"
for es in "$HOME/AppData/LocalLow/Sun/Java/Deployment/security/exception.sites" \
          "/c/Users/$USERNAME/AppData/LocalLow/Sun/Java/Deployment/security/exception.sites"; do
    if [ -f "$es" ]; then
        W "存在: $es"
        cat "$es" 2>/dev/null | sed 's/^/    /' | tee -a "$OUT"
        break
    fi
done
[ -f "$es" ] || W "无 exception.sites(若 applet 被 Java 安全拦截,需把 EBS 网址加进来)"

SEC "判定提示"
W "把 java_env_result.txt 贴回 / commit。我会据此判断:"
W "  A) 没装 Java -> 先装 JRE 8"
W "  B) 装了 Java + 有 javaws + .jnlp 已关联 -> 走 Web Start,最省事"
W "  C) 装了 Java 但只能插件模式 -> 配 Edge IE 模式"
W "  D) IT 已预置 SiteList -> EBS 本应自动 IE 模式,排查为何没生效"

echo ""
read -n 1 -s -r -p "按任意键退出..." < /dev/tty 2>/dev/null || true
echo ""
