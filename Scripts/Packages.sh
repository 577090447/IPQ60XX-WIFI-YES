#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

# ==================== 基础依赖检查 ====================
command -v jq >/dev/null 2>&1 || (apt-get update -qq && apt-get install -y jq) >/dev/null 2>&1 || echo "WARNING: jq not installed, version auto-update may fail."

# ==================== 安装和更新软件包 ====================
UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local PKG_LIST=("$PKG_NAME" $5)  # 第5个参数为自定义名称列表
	local REPO_NAME=${PKG_REPO#*/}
	local REPO_PATH="./package/$REPO_NAME"
	echo " "
	# 删除本地可能存在的不同名称的软件包（已修复：增加 ./package/ 搜索路径）
	for NAME in "${PKG_LIST[@]}"; do
		echo "Search directory: $NAME"
		local FOUND_DIRS=$(find ./feeds/luci/ ./feeds/packages/ ./package/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)
		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not found directory: $NAME"
		fi
	done
	# 克隆 GitHub 仓库（已修复：增加克隆失败错误处理）
	if ! git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "https://github.com/$PKG_REPO.git" "$REPO_PATH" 2>/dev/null; then
		echo "ERROR: Failed to clone $PKG_REPO"
		return 1
	fi
	# 处理克隆的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find "$REPO_PATH"/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./package \;
		rm -rf "$REPO_PATH"
	fi
}

# ==================== 彻底清理 Turbo ACC / SFE（源码+补丁） ====================
echo ">>> Cleaning Turbo ACC / SFE sources and patches..."
find ./feeds/luci/ ./feeds/packages/ ./package/ -type d \( \
    -iname "*turboacc*" -o -iname "*turbo-acc*" \
    -o -iname "*shortcut-fe*" -o -iname "*fast-classifier*" \
    -o -iname "*flowoffload*" \
) -exec rm -rf {} + 2>/dev/null || true
# 连补丁也删除（952系列及.rej）
find ./target/linux/generic/ -type f \( -name "952-*" -o -name "*.rej" \) -delete 2>/dev/null || true

# ==================== SONiC FullCone NAT（替代 turboacc）+ BBR ====================
echo ">>> Adding SONiC FullCone & BBR..."
curl -sSL https://raw.githubusercontent.com/mufeng05/openwrt-sonic-fullcone/master/add_sonic_fullcone.sh -o ./add_sonic_fullcone.sh
if [ -f ./add_sonic_fullcone.sh ]; then
    bash ./add_sonic_fullcone.sh
    rm -f ./add_sonic_fullcone.sh
fi

# 只保留勾选的（仅写入 =y，不写任何禁用项，不残留 # not set）
for OPT in \
    "CONFIG_PACKAGE_kmod-tcp-bbr=y" \
    "CONFIG_PACKAGE_fullconenat-sonic=y"
do
    KEY=${OPT%%=*}
    sed -i "/^${KEY}=/d" .config 2>/dev/null
    sed -i "/^# ${KEY} is not set/d" .config 2>/dev/null
    echo "$OPT" >> .config
done

# ==================== 插件拉取 ====================
# 科学插件
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
# 系统工具
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "axonhub gecoosac miniupnpd sing-box luci-app-homeproxy luci-app-timewol luci-app-upnp luci-app-wolplus luci-app-wolultra"
UPDATE_PACKAGE "diskman" "sbwml/luci-app-diskman" "main"
UPDATE_PACKAGE "netwizard" "sirpdboy/luci-app-netwizard" "main"
# 网络工具
UPDATE_PACKAGE "stuntman" "muink/openwrt-stuntman" "master"
# 过滤
UPDATE_PACKAGE "open-app-filter" "destan19/OpenAppFilter" "master" "" "open-app-filter luci-app-oaf oaf"
# 文件管理
UPDATE_PACKAGE "luci-app-harbor-file" "destan19/luci-app-harbor-file" "main"
# 易有云 + iStore
UPDATE_PACKAGE "linkease" "linkease/nas-packages" "master"
UPDATE_PACKAGE "luci-app-linkease" "linkease/nas-packages-luci" "main"
UPDATE_PACKAGE "luci-app-store" "linkease/istore" "main"


# ==================== 更新软件包版本 ====================
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
		local PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)" "$PKG_FILE")
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
		# 已修复：兼容无 dpkg 环境，仅当新版本合法且大于旧版本时更新
		if [[ "$NEW_VER" =~ ^[0-9].* ]]; then
			if command -v dpkg >/dev/null 2>&1; then
				local VER_CMP=$(dpkg --compare-versions "$OLD_VER" lt "$NEW_VER" && echo "true" || echo "false")
			else
				local VER_CMP=$( [ "$OLD_VER" != "$NEW_VER" ] && echo "true" || echo "false")
			fi
			if [ "$VER_CMP" = "true" ]; then
				sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
				sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
				echo "$PKG_FILE version has been updated!"
			else
				echo "$PKG_FILE version is already the latest!"
			fi
		fi
	done
}
#UPDATE_VERSION "软件包名" "测试版，true，可选，默认为否"
#UPDATE_VERSION "sing-box"

# ==================== 引入私有扩展脚本（放最后，避免被清理逻辑覆盖） ====================
if [ -f "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh"
fi
