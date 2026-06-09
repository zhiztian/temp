#!/usr/bin/env bash
# =====================================================================
# 配置 Edge IE 模式 跑 EBS Forms (Git Bash / mingw64)
# 背景: Win11 把 iexplore.exe 重定向到 Edge,IE 本体起不来。
#       走 Edge 内置的 IE 模式(IE11 内核),配合已装的 Java 8 跑 Forms。
#
# 本脚本只写 HKCU(当前用户),不需管理员,可逆。
# 做两件事:
#   1. 打开 "允许在 IE 模式重新加载网站" 开关
#   2. (可选)把 EBS 加进自动 IE 模式站点列表
#
# 运行: bash setup_ie_mode.sh
# =====================================================================

REG=reg.exe; command -v reg >/dev/null 2>&1 && REG=reg
EDGE_KEY="HKCU\\SOFTWARE\\Policies\\Microsoft\\Edge"

echo "=========================================="
echo " 配置 Edge IE 模式 (用户级,无需管理员)"
echo "=========================================="
echo ""

# --- 1. 允许 IE 模式 ---
echo ">> 1. 打开 '允许在 Internet Explorer 模式下重新加载网站'..."
$REG add "$EDGE_KEY" //v InternetExplorerIntegrationLevel //t REG_DWORD //d 1 //f 2>&1
rc1=$?
if [ $rc1 -eq 0 ]; then
    echo "   OK"
else
    echo "   写入失败(rc=$rc1)。可能策略受企业管控,需手动在 Edge 设置里开。"
fi

echo ""
echo ">> 验证写入:"
$REG query "$EDGE_KEY" //v InternetExplorerIntegrationLevel 2>&1 | sed 's/^/   /'

echo ""
echo "=========================================="
echo " 接下来手动操作(策略改动需重启 Edge 生效)"
echo "=========================================="
cat <<'STEPS'

1. 完全关闭 Edge(所有窗口),重新打开。

2. 验证 IE 模式开关已开:
   地址栏输入:  edge://settings/defaultBrowser
   找到 "允许在 Internet Explorer 模式下重新加载网站 (Allow sites to
   be reloaded in Internet Explorer mode)" -> 应为 "允许 / Allow"
   (若是灰的且已=允许,说明上面注册表生效了)

3. 打开 EBS:
   地址栏输入:  http://ebsprod.bytedance.net:8000

4. 用 IE 模式重新加载这个页面:
   右上角 ... 菜单 -> "在 Internet Explorer 模式下重新加载
   (Reload in Internet Explorer mode)"
   -> 标签页左上出现 IE 的 "e" 图标 = 成功进入 IE 内核

5. 关键:先清干净会话再登录(避免 FND_STATE_LOSS_ERROR 复发)
   IE 模式下点 ... -> 设置,或直接清 Edge 对 ebsprod + sso 的 cookie。
   最稳:先在 InPrivate 窗口里做第 3-4 步。

6. 登录 -> 进 Main Menu -> 点开财务表单。
   这次浏览器是 IE 内核,会去调已装的 Java 8 插件,Forms 应能起来。
   首次可能弹 Java 安全提示(EBS 已在例外列表),允许运行即可。

STEPS

echo "如果第 4 步没有 'Reload in IE mode' 选项,或表单仍起不来,告诉我现象。"
echo ""
echo "(撤销本配置: reg delete \"$EDGE_KEY\" //v InternetExplorerIntegrationLevel //f)"
