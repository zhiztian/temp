#!/usr/bin/env bash
# =====================================================================
# 尝试用 IE11 本体打开 EBS (Git Bash / mingw64)
# 背景: 机器已装 Java 8(1.8.0_333) + EBS 已在 Java exception.sites,
#       说明 IT 方案是 IE11 + Java 插件。此脚本尝试用 iexplore.exe
#       直接打开 EBS 主页,验证 Win11 上 IE 是否还能真正启动。
#
# 注意: Win11 可能把 iexplore.exe 重定向到 Edge。脚本会启动并提示
#       你观察:真起了 IE,还是跳成了 Edge。
#
# 运行: bash launch_ie.sh
# =====================================================================

IE="/c/Program Files/Internet Explorer/iexplore.exe"
EBS_HOME="http://ebsprod.bytedance.net:8000/OA_HTML/OA.jsp?OAFunc=OANEWHOMEPAGE"

echo "=========================================="
echo " 尝试用 IE 打开 EBS"
echo "=========================================="
echo "IE 路径: $IE"
echo "目标:    $EBS_HOME"
echo ""

if [ ! -f "$IE" ]; then
    echo "!! iexplore.exe 不存在,无法尝试。"
    exit 1
fi

echo ">> 正在启动 IE 打开 EBS 主页..."
echo "   (启动后请观察:)"
echo "   - 真的弹出 IE 窗口(经典蓝色 e 图标) -> 方案可行"
echo "   - 跳成 Edge / 没反应       -> Win11 拦了 IE,需走 Edge IE 模式"
echo ""

# 用 cmd start 后台拉起,避免阻塞 bash
( cmd.exe /c start "" "$IE" "$EBS_HOME" >/dev/null 2>&1 & ) 2>/dev/null
sleep 3

echo ">> 已发出启动命令。"
echo ""
echo "如果 IE 没起来 / 跳成 Edge,告诉我,我给你配 Edge IE 模式(用户级,不需管理员)。"
echo "如果 IE 起来了:"
echo "   1. 清掉 IE 对 ebsprod + sso 的 cookie:"
echo "      IE 设置(齿轮) -> Internet 选项 -> 常规 -> 删除 -> 勾 Cookie 和网站数据 -> 删除"
echo "   2. 重新打开 EBS 登录,进 Main Menu,点开财务表单看 Java 表单是否起来"
