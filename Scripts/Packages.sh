#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
#安装和更新软件包
UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local PKG_LIST=("$PKG_NAME" $5)  # 第5个参数为自定义名称列表
	local REPO_NAME=${PKG_REPO#*/}
	local REPO_PATH="./package/$REPO_NAME"
	echo " "
	# 删除本地可能存在的不同名称的软件包
	for NAME in "${PKG_LIST[@]}"; do
		echo "Search directory: $NAME"
		local FOUND_DIRS=$(find ./feeds/luci/ ./feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)
		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not found directory: $NAME"
		fi
	done
	# 克隆 GitHub 仓库
	git clone --depth=1 --single-branch --branch $PKG_BRANCH "https://github.com/$PKG_REPO.git" $REPO_PATH
	# 处理克隆的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find $REPO_PATH/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./package \;
		rm -rf $REPO_PATH
	fi
}
# 调用示例
# UPDATE_PACKAGE "OpenAppFilter" "destan19/OpenAppFilter" "master" "" "custom_name1 custom_name2"
# UPDATE_PACKAGE "open-app-filter" "destan19/OpenAppFilter" "master" "" "luci-app-appfilter oaf"
# UPDATE_PACKAGE "包名" "项目地址" "项目分支" "pkg，可选，从大杂烩中单独提取包名插件"
# ==================== LuCI 主题 + 仪表盘 ====================
# aurora / vantage / carbon 已禁用，不拉
#
# 为什么不用 UPDATE_PACKAGE 的 pkg 模式：
#   pkg 模式只做单目录搬运，而这三个包的 Makefile 都是 "include ../../luci.mk"，
#   单目录搬出后 ../../ 指向 wrt 根（没有 luci.mk）→ 包注册不上 → apk 报 no such package。
# 做法：一次 clone，把包目录 + 仓库自带的 luci.mk 一起拷进包目录，
#      Makefile 改成同目录 include，自包含、不依赖 feeds 里 luci.mk 的版本。
install_luci_extras() {
	local SRC=./tmp-luci-src
	local LUCI_REPO=https://github.com/577090447/luci.git
	local LUCI_BRANCH=openwrt-25.12
	local DST
	rm -rf "$SRC"
	# 清掉 feeds 里可能存在的旧版本，避免同名冲突
	find ./feeds/luci -maxdepth 3 -type d \
		\( -name 'luci-theme-design' -o -name 'luci-mod-dashboard' -o -name 'luci-mod-rpc' \) \
		-exec rm -rf {} + 2>/dev/null
	git clone --depth=1 --single-branch -b "$LUCI_BRANCH" "$LUCI_REPO" "$SRC" || return 1
	[ -f "$SRC/luci.mk" ] || { echo ">>> ERROR: 缺 luci.mk"; rm -rf "$SRC"; return 1; }
	# ---------- 主题 design ----------
	DST=./package/luci-theme-design
	if [ -f "$SRC/themes/luci-theme-design/Makefile" ]; then
		rm -rf "$DST"; mkdir -p "$DST"
		cp -rf "$SRC/themes/luci-theme-design/." "$DST/"
		cp "$SRC/luci.mk" "$DST/luci.mk"
		sed -i 's|include ../../luci.mk|include ./luci.mk|' "$DST/Makefile"
		echo ">>> theme installed: $DST"
		grep -n 'include\|PKG_VERSION\|PKG_RELEASE' "$DST/Makefile"
	else
		echo ">>> ERROR: 缺 themes/luci-theme-design"
		rm -rf "$SRC"
		return 1
	fi
	# ---------- 仪表盘（首页在线设备） ----------
	DST=./package/luci-mod-dashboard
	if [ -f "$SRC/modules/luci-mod-dashboard/Makefile" ]; then
		rm -rf "$DST"; mkdir -p "$DST"
		cp -rf "$SRC/modules/luci-mod-dashboard/." "$DST/"
		cp "$SRC/luci.mk" "$DST/luci.mk"
		sed -i 's|include ../../luci.mk|include ./luci.mk|' "$DST/Makefile"
		echo ">>> dashboard installed: $DST"
		grep -n 'include\|LUCI_DEPENDS' "$DST/Makefile"
	else
		echo ">>> WARN: 缺 modules/luci-mod-dashboard，跳过仪表盘"
	fi
	# ---------- luci-mod-rpc 仪表盘数据源接口（在线主机+实时流量依赖） ----------
	DST=./package/luci-mod-rpc
	if [ -f "$SRC/modules/luci-mod-rpc/Makefile" ]; then
		rm -rf "$DST"; mkdir -p "$DST"
		cp -rf "$SRC/modules/luci-mod-rpc/." "$DST/"
		cp "$SRC/luci.mk" "$DST/luci.mk"
		sed -i 's|include ../../luci.mk|include ./luci.mk|' "$DST/Makefile"
		echo ">>> luci-mod-rpc installed: $DST"
		grep -n 'include\|LUCI_DEPENDS' "$DST/Makefile"
	else
		echo ">>> WARN: 缺 modules/luci-mod-rpc，仪表盘在线主机将会空白！"
	fi

	rm -rf "$SRC"
}
install_luci_extras
# ==================== 科学插件 ====================
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
# ==================== 系统工具 ====================
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "axonhub gecoosac miniupnpd sing-box luci-app-homeproxy luci-app-timewol luci-app-upnp luci-app-wolplus luci-app-wolultra"
UPDATE_PACKAGE "diskman" "sbwml/luci-app-diskman" "main"
UPDATE_PACKAGE "netwizard" "sirpdboy/luci-app-netwizard" "main"
# ==================== 网络工具 ====================
UPDATE_PACKAGE "stuntman" "muink/openwrt-stuntman" "master"
# ==================== 过滤 ====================
UPDATE_PACKAGE "open-app-filter" "destan19/OpenAppFilter" "master" "" "open-app-filter luci-app-oaf oaf"
# ==================== 文件管理 ====================
UPDATE_PACKAGE "luci-app-harbor-file" "destan19/luci-app-harbor-file" "main"
# ==================== 易有云 + iStore ====================
UPDATE_PACKAGE "linkease" "linkease/nas-packages" "master"
UPDATE_PACKAGE "luci-app-linkease" "linkease/nas-packages-luci" "main"
UPDATE_PACKAGE "luci-app-store" "linkease/istore" "main"
# ============================================
# SONiC FullCone NAT（替代 turboacc，无 SFE / 无 952 补丁）
# 适配 fw4(nftables) + 内核 6.6/6.12/6.18
# ============================================
echo " "
echo ">>> Cleaning old turboacc / 952 leftovers..."
find target/linux/generic/hack-6.18* -name "952-*" -delete 2>/dev/null
find target/linux/generic -name "*.rej" -delete 2>/dev/null
echo ">>> Adding SONiC FullCone..."
curl -sSL https://raw.githubusercontent.com/mufeng05/openwrt-sonic-fullcone/master/add_sonic_fullcone.sh -o ./add_sonic_fullcone.sh
if [ -f ./add_sonic_fullcone.sh ]; then
    bash ./add_sonic_fullcone.sh
    rm -f ./add_sonic_fullcone.sh
    echo ">>> SONiC FullCone patches applied successfully."
else
    echo ">>> ERROR: Failed to download add_sonic_fullcone.sh, skipping."
fi
# 写入 .config 选项（确保编入，同时禁用 SFE/turboacc）
# 注意：这些选项建议同时写进 Config/GENERAL.txt，
# 否则 Custom Settings 里的 make defconfig 可能把它们丢掉。
echo " "
echo ">>> Patching .config for SONiC FullCone..."
for OPT in \
    "CONFIG_PACKAGE_kmod-tcp-bbr=y" \
    "CONFIG_PACKAGE_fullconenat-sonic=y"
do
    KEY=$(echo "$OPT" | cut -d= -f1)
    if grep -q "^# $KEY is not set" .config 2>/dev/null; then
        sed -i "s|^# $KEY is not set|$OPT|" .config
    elif ! grep -q "^$KEY=" .config 2>/dev/null; then
        echo "$OPT" >> .config
    fi
done
# 显式禁用 turboacc / SFE（防御性）
for DISABLED in \
    "CONFIG_PACKAGE_luci-app-turboacc" \
    "CONFIG_PACKAGE_kmod-shortcut-fe" \
    "CONFIG_PACKAGE_kmod-fast-classifier"
do
    sed -i "/^${DISABLED}=/d" .config 2>/dev/null
    echo "# ${DISABLED} is not set" >> .config
done
echo ">>> .config tuned (BBR=y, SFE/turboacc disabled)."
#更新软件包版本
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}
	local PKG_FILES=$(find ./package/ ./feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile")
	if [ -z "$PKG_FILES" ]; then
		echo "$PKG_NAME not found!"
		return
	fi
	echo -e "\n$PKG_NAME version update has started!"
	for PKG_FILE in $PKG_FILES; do
		local PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)" $PKG_FILE)
		local PKG_TAG=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases" | jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name")
		local OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
		local OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
		local OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")
		local OLD_HASH=$(grep -Po "PKG_HASH:=\K.*" "$PKG_FILE")
		local PKG_URL=$([[ "$OLD_URL" == *"releases"* ]] && echo "${OLD_URL%/}/$OLD_FILE" || echo "${OLD_URL%/}")
		local NEW_VER=$(echo $PKG_TAG | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
		local NEW_URL=$(echo $PKG_URL | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")
		local NEW_HASH=$(curl -sL "$NEW_URL" | sha256sum | cut -d ' ' -f 1)
		echo "old version: $OLD_VER $OLD_HASH"
		echo "new version: $NEW_VER $NEW_HASH"
		if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER"; then
			sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
			sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
			echo "$PKG_FILE version has been updated!"
		else
			echo "$PKG_FILE version is already the latest!"
		fi
	done
}
#UPDATE_VERSION "软件包名" "测试版，true，可选，默认为否"
#UPDATE_VERSION "sing-box"
#引入私有扩展脚本
if [ -f "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh"
fi
