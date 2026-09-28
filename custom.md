# PonWrt (ImmortalWrt) 固件定制与维护文档

本文档汇总记录了本项目固件结构分析、插件扩展、自动化上游同步、GitHub Actions CI/CD 工作流定制以及开机默认网络配置等全部定制内容。

---

## 一、 项目背景与架构定位

* **固件体系**：基于 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) 定制的 **PonWrt** 发行版。
* **目标芯片平台**：Airoha（达发/联发科生态）系列 10G PON 终端芯片，主要面向 **AN7581** 与 **AN7583** 架构。
* **上游主干仓库**：`https://github.com/pbs05/ponwrt.git`（包含专用 PON 驱动 `openwrt-pon-drivers` 与用户态组件 `openwrt-pon-userspace`）。

---

## 二、 新增常用插件与组件配置

在公共增量配置文件 [`configs/release.config`](file:///c:/develop/ponwrt/configs/release.config) 中追加了 5 套主流网络插件，每套均包含**底层核心程序**、**LuCI 管理界面**以及**简体中文语言包**：

```ini
# ZeroTier (虚拟局域网异地组网)
CONFIG_PACKAGE_zerotier=y
CONFIG_PACKAGE_luci-app-zerotier=y
CONFIG_PACKAGE_luci-i18n-zerotier-zh-cn=y

# Vlmcsd (KMS 本地激活服务)
CONFIG_PACKAGE_vlmcsd=y
CONFIG_PACKAGE_luci-app-vlmcsd=y
CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn=y

# rtp2httpd (IPTV 组播/单播转 HTTP 流)
CONFIG_PACKAGE_rtp2httpd=y
CONFIG_PACKAGE_luci-app-rtp2httpd=y
CONFIG_PACKAGE_luci-i18n-rtp2httpd-zh-cn=y

# FRP (frpc 高性能内网穿透客户端)
CONFIG_PACKAGE_frpc=y
CONFIG_PACKAGE_luci-app-frpc=y
CONFIG_PACKAGE_luci-i18n-frpc-zh-cn=y

# HomeProxy (ImmortalWrt 代理平台及 sing-box 内核)
CONFIG_PACKAGE_luci-app-homeproxy=y
CONFIG_PACKAGE_luci-i18n-homeproxy-zh-cn=y
```

> **构建机制**：CI 或本地编译时，执行 `./scripts/kconfig.pl + "configs/${target}.config" configs/release.config > .config`，结合 `make defconfig` 即可全自动补全所有内核驱动与 Golang/C++ 依赖并打包进固件。

---

## 三、 本地 Git 上游同步工具 (`sync_upstream`)

为了方便在 Windows 本地快速跟进上游 `pbs05/ponwrt` 的更新，编写了专用同步脚本：
* **核心脚本**：[`sync_upstream.ps1`](file:///c:/develop/ponwrt/sync_upstream.ps1)（原生 UTF-8 支持，彩色提示）
* **双击引导器**：[`sync_upstream.bat`](file:///c:/develop/ponwrt/sync_upstream.bat)

### 核心特性
1. **自动保护本地工作区**：同步前自动 `git stash` 保护未提交的修改，拉取合并 `upstream/master` 后再自动恢复。
2. **轻量极速**：去除了在 Windows 本地无效的 feeds 拉取步骤，feeds 依赖交由 GitHub Actions 云端 Ubuntu 容器处理。
3. **配置文件冲突智能自愈与交互确认**：
   * 自动识别属于配置清单类（`.config`、`configs/`、`feeds.conf`）的非互斥文件冲突；
   * 在合并前显式列出冲突文件并询问：`是否尝试自动保留双方配置并合并? (Y/N)`；
   * 用户确认后，脚本自动提取上游新增与本地新增的配置项同时保留拼接，清理冲突符号并执行 `git add` 自动解决冲突；
   * 普通 C 代码与内核补丁冲突依然独立提示手动检查。
4. **Git 合并驱动支持**：在 [`.gitattributes`](file:///c:/develop/ponwrt/.gitattributes) 中配置了 `configs/*.config merge=union`，辅助底层自动合并。

---

## 四、 GitHub Actions 固件构建与发布工作流

构建工作流配置文件：[`.github/workflows/build-firmware.yml`](file:///c:/develop/ponwrt/.github/workflows/build-firmware.yml)

### 核心特性
1. **可视化参数选择 (`workflow_dispatch`)**：
   * **编译目标架构 (`target`)**：可选 `all`（全部编译）、`an7581` 或 `an7583`。
   * **AN7581 具体型号单选 (`device`)**：
     * 默认 `all`（生成当前平台所有支持设备的刷机镜像）；
     * 支持精准单选特定设备（如 `nokia_xg-040g-md-ubi`、`fiberhome_hg5585f-ct`、`znxt_zn515xg-d` 等），配置阶段自动过滤其它设备，显著缩短编译与打包时间。
   * **自动 Release 发布**：可自由勾选是否自动发布至 GitHub Releases，Tag 留空则自动按日期生成（如 `v2026.09.28-1010`）。
2. **设备型号“带 sfp”与“不带 sfp”技术原理解析**：
   * **芯片 SerDes 引脚复用机制**：AN7581 内部的高速通道 SerDes 既可作为 USB 3.0，也可复用为 2.5G 以太网 PCS（2500Base-X）。
   * **不带 `-usb-sfp`（如 `nokia_xg-040g-md-ubi`）**：出厂标准版，板载 USB 为满速 USB 3.0，适合原封未动光猫。
   * **带 `-usb-sfp`（如 `nokia_xg-040g-md-ubi-usb-sfp`）**：魔改/硬改扩展版，SerDes 通道被复用为额外的 2.5G 网口 `lan5`，板载 USB 降为 USB 2.0，适合加焊/加装了 SFP 光模块插座的光猫。
3. **CI 运行优化与故障解决**：
   * **磁盘清理**：构建前清理 Ubuntu 虚拟机中无用的 Android/DotNet 环境，释放 40GB+ 磁盘空间。
   * **双重产物备份**：无论 Release 是否发布，所有构建出的 `.bin` / `.ubi` / `.tar.zst` 镜像均会在 Actions 详情页底部的 **Artifacts** 区域保留 14 天。
   * **Release 发布修复**：
     * 仓库权限：需在 GitHub 仓库 `Settings -> Actions -> General -> Workflow permissions` 中勾选 **`Read and write permissions`**；
     * 组件重构：使用社区主流标准的 `softprops/action-gh-release@v2`，并在打包归集时自动重命名多目标的同名 `sha256sums`，彻底解决 HTTP 404 与资产覆盖冲突。

---

## 五、 开机默认网络初始化配置

配置文件路径：[`package/base-files/files/etc/uci-defaults/99-custom-network`](file:///c:/develop/ponwrt/package/base-files/files/etc/uci-defaults/99-custom-network)

### 脚本内容
```sh
#!/bin/sh
# Custom default settings for PonWrt

# 1. 设置 LAN 口 IP 为 192.168.6.88，子网掩码 255.255.255.0，网关与 DNS 为 192.168.6.1
uci -q batch <<-EOF
	set network.lan.ipaddr='192.168.6.88'
	set network.lan.netmask='255.255.255.0'
	set network.lan.gateway='192.168.6.1'
	delete network.lan.dns
	add_list network.lan.dns='192.168.6.1'
	commit network
EOF

# 2. 禁用 LAN 口 DHCP 服务 (IPv4 忽略 + IPv6 禁用)
uci -q batch <<-EOF
	set dhcp.lan.ignore='1'
	set dhcp.lan.dhcpv6='disabled'
	set dhcp.lan.ra='disabled'
	commit dhcp
EOF

exit 0
```

### 运行机制与特性
1. **出厂/首次初始化**：基于 OpenWrt `uci-defaults` 规范，固件刷机后首次启动或按 Reset 恢复出厂设置时自动触发；
2. **旁设备友好**：
   * 管理 IP 固定为 `192.168.6.88`；
   * 上级网关与 DNS 指向主路由 `192.168.6.1`；
   * 彻底关闭 LAN 口的 IPv4 DHCP 地址分配与 IPv6 RA 广播，开机后直接接入主网即可通信，绝不扰乱局域网主 DHCP 秩序。
