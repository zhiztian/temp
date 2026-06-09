#!/usr/bin/env bash
# =====================================================================
# Edge IE 模式 配置诊断 + 日志收集 (Git Bash / mingw64)
# 目的: 搞清 setup_ie_mode.sh 到底有没有生效 —— 是注册表没写进去,
#       还是写了 Edge 不认。把所有相关注册表键 dump 出来回传。
#
# 只读为主(第 5 步会尝试写一次并立刻回读验证)。
# 运行: bash diag_ie_mode.sh   产出: ie_mode_diag.txt
# =====================================================================

DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"; [ -z "$DIR" ] && DIR="."
OUT="$DIR/ie_mode_diag.txt"
: > "$OUT"
REG=reg.exe; command -v reg >/dev/null 2>&1 && REG=reg

W() { printf '%s\n' "$*" | tee -a "$OUT"; }
SEC() { W ""; W "==================== $* ===================="; }
# 跑一条命令,stdout+stderr+退出码 全记录
RUN() {
    W "\$ $*"
    local o; o=$(timeout 15 "$@" 2>&1); local rc=$?
    printf '%s\n' "$o" | sed 's/^/  /' | tee -a "$OUT"
    W "  [退出码 rc=$rc]"
    return $rc
}

W "Edge IE 模式 配置诊断"
W "时间: $(date '+%Y-%m-%d %H:%M:%S')"
W "机器: ${COMPUTERNAME:-?}  用户: ${USERNAME:-?}"
W "reg 命令: $REG"

SEC "1. reg 命令本身能用吗(写一个无害测试键再删)"
RUN $REG add "HKCU\\Software\\_ebs_reg_test" //v probe //t REG_SZ //d ok //f
RUN $REG query "HKCU\\Software\\_ebs_reg_test" //v probe
RUN $REG delete "HKCU\\Software\\_ebs_reg_test" //f

SEC "2. HKCU Edge 策略键 现状(setup 应该写这里)"
RUN $REG query "HKCU\\SOFTWARE\\Policies\\Microsoft\\Edge" //v InternetExplorerIntegrationLevel
W "--- 整个 HKCU Edge 策略键全部值 ---"
RUN $REG query "HKCU\\SOFTWARE\\Policies\\Microsoft\\Edge"

SEC "3. HKLM Edge 策略键(企业管控通常在这,会覆盖 HKCU)"
RUN $REG query "HKLM\\SOFTWARE\\Policies\\Microsoft\\Edge" //v InternetExplorerIntegrationLevel
W "--- 整个 HKLM Edge 策略键全部值 ---"
RUN $REG query "HKLM\\SOFTWARE\\Policies\\Microsoft\\Edge"

SEC "4. IE 模式 站点列表 策略(SiteList,二选一来源)"
RUN $REG query "HKCU\\SOFTWARE\\Policies\\Microsoft\\Edge" //v InternetExplorerIntegrationSiteList
RUN $REG query "HKLM\\SOFTWARE\\Policies\\Microsoft\\Edge" //v InternetExplorerIntegrationSiteList

SEC "5. 现在尝试写 HKCU 开关,并立即回读验证"
RUN $REG add "HKCU\\SOFTWARE\\Policies\\Microsoft\\Edge" //v InternetExplorerIntegrationLevel //t REG_DWORD //d 1 //f
W "--- 写后立即回读 ---"
RUN $REG query "HKCU\\SOFTWARE\\Policies\\Microsoft\\Edge" //v InternetExplorerIntegrationLevel

SEC "6. Edge 是否被企业管控(看 cloud management / 是否 managed)"
RUN $REG query "HKLM\\SOFTWARE\\Microsoft\\Enrollments" //s //f "Edge"
RUN $REG query "HKLM\\SOFTWARE\\Policies\\Microsoft\\Edge" //s

SEC "7. Edge 版本"
for e in "/c/Program Files (x86)/Microsoft/Edge/Application" "/c/Program Files/Microsoft/Edge/Application"; do
    [ -d "$e" ] && ls -1 "$e" 2>/dev/null | grep -E '^[0-9]+\.' | sed 's/^/  Edge 版本目录: /' | tee -a "$OUT"
done

SEC "判定线索"
W "看回传后我重点判断:"
W "  - 第1步 rc=0 -> reg 写权限正常"
W "  - 第5步写后回读到 0x1 -> HKCU 确实写进去了"
W "  - 第3步 HKLM 若有 InternetExplorerIntegrationLevel 且=0 -> 企业策略禁用了IE模式,HKCU无效,必须找IT"
W "  - 第6步若显示 managed/enrollment -> Edge 受公司云策略管控"

echo ""
read -n 1 -s -r -p "按任意键退出..." < /dev/tty 2>/dev/null || true
echo ""
