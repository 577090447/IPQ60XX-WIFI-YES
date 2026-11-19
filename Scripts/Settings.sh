#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#移除luci-app-attendedsysupgrade
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "/attendedsysupgrade/d" {} +
#修改默认主题
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" {} +
#修改immortalwrt.lan关联IP
find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js" -exec sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" {} +
#添加编译日期标识
find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js" -exec sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" {} +

#修改默认WIFI账号密码
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
ROUTER_TOOL="./package/emortal/luci-app-router-tool/root/etc/config/router-tool"
for file in "$ROUTER_TOOL" "$WIFI_UC"; do
	[ -f "$file" ] && sed -i "s/ssid '.*'/ssid '$WRT_SSID'/g; s/key '.*'/key '$WRT_WORD'/g" "$file"
done

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

# ==================== SONiC FullCone 防御性清理（必须在 cat .config 之前） ====================
# 如果 Config/*.txt 里还有 turboacc / 952 相关残留，在这里清掉
sed -i '/^CONFIG_PACKAGE_luci-app-turboacc=/d' ./.config
sed -i '/^CONFIG_PACKAGE_kmod-nft-fullcone=/d' ./.config
sed -i '/^CONFIG_PACKAGE_kmod-shortcut-fe=/d' ./.config
sed -i '/^CONFIG_PACKAGE_kmod-fast-classifier=/d' ./.config
sed -i '/^CONFIG_PACKAGE_kmod-tcp-bbr=/d' ./.config

# ==================== 配置文件修改 ====================
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

# ==================== SONiC FullCone 写入（替代 turboacc） ====================
echo "" >> ./.config
echo "# ==================== SONiC FullCone（无 SFE / 无 952 补丁） ====================" >> ./.config
echo "CONFIG_PACKAGE_fullconenat-sonic=y" >> ./.config
echo "" >> ./.config
echo "# 防御性禁用 turboacc / SFE / Fast Classifier" >> ./.config
echo "# CONFIG_PACKAGE_luci-app-turboacc is not set" >> ./.config
echo "# CONFIG_PACKAGE_kmod-shortcut-fe is not set" >> ./.config
echo "# CONFIG_PACKAGE_kmod-fast-classifier is not set" >> ./.config
echo "# CONFIG_PACKAGE_kmod-nft-fullcone is not set" >> ./.config
echo "" >> ./.config

#引入私有扩展配置
if [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	echo "Applying private configurations from PRIVATE.txt..."
	cat $GITHUB_WORKSPACE/Config/PRIVATE.txt >> ./.config
fi

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/dts/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#无WIFI配置调整Q6大小
	if [[ "$WRT_WIFI" == "WIFI-NO" ]]; then
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
fi
