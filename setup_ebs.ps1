# =====================================================================
#  EBS IE 模式 一键配置脚本  (Windows 11 / Edge IE Mode)
#  一次跑完:修 IE COM 注册表 + 配 IE 模式策略+站点列表 + 装登录自动
#  清残留任务 + 清当前残留。配完用 open_ebs.ps1 日常打开 EBS。
#  自动提权(会弹 UAC,点"是")。用法:
#     powershell -ExecutionPolicy Bypass -File .\setup_ebs.ps1
# =====================================================================
param([string]$LogPath = "")
$selfPath=$MyInvocation.MyCommand.Path; $selfDir=Split-Path -Parent $selfPath
if(-not $LogPath){ $LogPath=Join-Path $selfDir "setup_ebs_log.txt" }

# ---- 自动提权 ----
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){
    Write-Host "需要管理员权限,正在请求提权(请在弹窗点'是')..." -ForegroundColor Yellow
    try{ Start-Process powershell -Verb RunAs -ArgumentList @("-ExecutionPolicy","Bypass","-File","`"$selfPath`"","-LogPath","`"$LogPath`"") }
    catch{ Write-Host "提权失败/被取消: $($_.Exception.Message)" -ForegroundColor Red }
    Read-Host "按回车关闭此窗口"; return
}

$Out=$LogPath; $log=New-Object System.Text.StringBuilder
function W($m){ [void]$log.AppendLine($m); Write-Host $m }
function Flush(){ try{ $log.ToString()|Out-File -FilePath $Out -Encoding UTF8 }catch{} }
function OK($b){ if($b){"[OK]"}else{"[失败]"} }

W "EBS IE 模式 一键配置  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
W "机器: $env:COMPUTERNAME  用户: $env:USERNAME"
W "================================================"

$iexplore='"C:\Program Files\Internet Explorer\iexplore.exe"'
if(-not(Test-Path "C:\Program Files\Internet Explorer\iexplore.exe")){
    W "!! 找不到 iexplore.exe,无法继续"; Flush; Read-Host "回车关闭"; return
}

# ============ 步骤1: 修复 IE COM 注册表(4个键指回 iexplore) ============
W ""
W "【步骤1】修复 IE COM 注册表"
$CLSID="{0002DF01-0000-0000-C000-000000000046}"
$keys=@(
  "Registry::HKEY_CLASSES_ROOT\CLSID\$CLSID\LocalServer32",
  "Registry::HKEY_CLASSES_ROOT\WOW6432Node\CLSID\$CLSID\LocalServer32",
  "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\$CLSID\LocalServer32",
  "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\WOW6432Node\CLSID\$CLSID\LocalServer32"
)
# 启用接管所有权所需特权(改 TrustedInstaller 保护键)
$privSig=@"
using System;using System.Runtime.InteropServices;
public class Priv{
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr h,int a,out IntPtr t);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool LookupPrivilegeValue(string s,string n,out long l);
 [DllImport("advapi32.dll",SetLastError=true)] static extern bool AdjustTokenPrivileges(IntPtr t,bool d,ref TP np,int l,IntPtr p,IntPtr r);
 [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
 [StructLayout(LayoutKind.Sequential,Pack=1)] struct TP{public int C;public long L;public int A;}
 public static bool En(string p){IntPtr t;if(!OpenProcessToken(GetCurrentProcess(),0x28,out t))return false;TP tp;tp.C=1;tp.A=2;if(!LookupPrivilegeValue(null,p,out tp.L))return false;return AdjustTokenPrivileges(t,false,ref tp,0,IntPtr.Zero,IntPtr.Zero);}
}
"@
try{ Add-Type -TypeDefinition $privSig -EA Stop; foreach($pv in @("SeTakeOwnershipPrivilege","SeRestorePrivilege")){ [void][Priv]::En($pv) } }catch{}

$fixed=0
$adminSid=New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid,$null)
foreach($k in $keys){
    try{
        # 普通方式先试
        if(-not(Test-Path $k)){ New-Item -Path $k -Force | Out-Null }
        try{ Set-Item -Path $k -Value $iexplore -EA Stop }
        catch{
            # 被拒 -> 接管所有权(针对 TrustedInstaller 保护的 WOW6432Node 键)
            $sub = $k -replace 'Registry::HKEY_LOCAL_MACHINE\\','' -replace 'Registry::HKEY_CLASSES_ROOT\\','SOFTWARE\Classes\'
            $rk=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
            $ko=$rk.OpenSubKey($sub,[Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,[System.Security.AccessControl.RegistryRights]::TakeOwnership)
            $acl=$ko.GetAccessControl([System.Security.AccessControl.AccessControlSections]::None); $acl.SetOwner($adminSid); $ko.SetAccessControl($acl); $ko.Close()
            $k2=$rk.OpenSubKey($sub,[Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,[System.Security.AccessControl.RegistryRights]::ChangePermissions)
            $a2=$k2.GetAccessControl(); $rule=New-Object System.Security.AccessControl.RegistryAccessRule($adminSid,[System.Security.AccessControl.RegistryRights]::FullControl,"None","None","Allow"); $a2.AddAccessRule($rule); $k2.SetAccessControl($a2); $k2.Close()
            $k3=$rk.OpenSubKey($sub,$true); $k3.SetValue("",$iexplore,[Microsoft.Win32.RegistryValueKind]::String); $k3.Close(); $rk.Close()
        }
        $v=(Get-ItemProperty -Path $k -Name '(default)' -EA SilentlyContinue).'(default)'
        if($v -match 'iexplore'){ $fixed++ }
    }catch{ W "  键处理异常: $($_.Exception.Message)" }
}
W "  4个键修复: $fixed/4  $(OK ($fixed -eq 4))"
Flush

# ============ 步骤2: IE 模式策略 + 站点列表 ============
W ""
W "【步骤2】配置 Edge IE 模式策略 + 站点列表"
$xmlPath="C:\ProgramData\EdgeIEMode\sitelist.xml"
$xmlDir=Split-Path $xmlPath
if(-not(Test-Path $xmlDir)){ New-Item -ItemType Directory -Path $xmlDir -Force | Out-Null }
$xml=@'
<site-list version="206">
  <site url="ebsprod.bytedance.net:8000" allow-redirect="true">
    <compat-mode>IE7Enterprise</compat-mode>
    <open-in>IE11</open-in>
  </site>
  <site url="ebsprod.bytedance.net" allow-redirect="true">
    <compat-mode>IE7Enterprise</compat-mode>
    <open-in>IE11</open-in>
  </site>
  <site url="sso.bytedance.com"><open-in>None</open-in></site>
  <site url="login.bytedance.com"><open-in>None</open-in></site>
</site-list>
'@
[System.IO.File]::WriteAllText($xmlPath,$xml,(New-Object System.Text.UTF8Encoding($false)))
$key="HKLM:\SOFTWARE\Policies\Microsoft\Edge"
if(-not(Test-Path $key)){ New-Item -Path $key -Force | Out-Null }
New-ItemProperty -Path $key -Name "InternetExplorerIntegrationLevel" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $key -Name "InternetExplorerIntegrationSiteList" -Value ("file:///"+($xmlPath -replace '\\','/')) -PropertyType String -Force | Out-Null
$lv=(Get-ItemProperty $key -Name InternetExplorerIntegrationLevel).InternetExplorerIntegrationLevel
W "  IE模式策略=1: $(OK ($lv -eq 1)) ; 站点列表已写: $(OK (Test-Path $xmlPath))"
Flush

# ============ 步骤3: 装登录自动清残留 iexplore 任务 ============
W ""
W "【步骤3】安装登录自动清理任务(解决 Edge149 退出崩溃残留)"
$taskName="ClearStaleIExplore"
$cmd='Get-Process iexplore -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue'
$enc=[Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($cmd))
schtasks /Delete /TN $taskName /F 2>$null | Out-Null
$action="powershell.exe -NoProfile -WindowStyle Hidden -EncodedCommand $enc"
$cr=schtasks /Create /TN $taskName /TR $action /SC ONLOGON /RL HIGHEST /F 2>&1
$taskOk = ($LASTEXITCODE -eq 0)
W "  计划任务 '$taskName': $(OK $taskOk)"
Flush

# ============ 步骤4: 清当前残留 ============
W ""
W "【步骤4】清理当前残留 iexplore"
$ie=@(Get-Process iexplore -EA SilentlyContinue)
W "  当前 iexplore 数: $($ie.Count),清理中..."
$ie | ForEach-Object { try{ Stop-Process -Id $_.Id -Force }catch{} }

# ============ 总结 ============
W ""
W "================================================"
W "配置完成。总结:"
W "  步骤1 修注册表 : $(OK ($fixed -eq 4))"
W "  步骤2 IE模式策略: $(OK ($lv -eq 1))"
W "  步骤3 自动清理  : $(OK $taskOk)"
W ""
W "【日常使用】以后打开 EBS,运行:"
W "    powershell -ExecutionPolicy Bypass -File .\open_ebs.ps1"
W "  或正常用 Edge 打开 http://ebsprod.bytedance.net:8000 (自动切IE模式)"
W ""
W "【若又报错】关掉所有 Edge,任务管理器结束所有 iexplore,再重开。"
W "【根因】Edge 149 的 dual_engine_adapter 退出时崩溃留残留,微软后续版本会修。"
Flush
Write-Host ""
Write-Host "日志: $Out" -ForegroundColor Green
Read-Host "按回车关闭"
