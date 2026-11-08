#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
# 修改：改用官方 feed 方式引入 linkease，修复若干隐患

# 安装和更新软件包
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
		local FOUND_DIRS
		FOUND_DIRS=$(find ./feeds/luci/ ./feeds/packages/ ./feeds/istore/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)

		# 【修复】find 无匹配会读到空行，rm -rf "" 会删根目录，必须判空
		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				[ -n "$DIR" ] && rm -rf "$DIR" && echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not found directory: $NAME"
		fi
	done

	# 克隆 GitHub 仓库
	git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "https://github.com/$PKG_REPO.git" "$REPO_PATH"

	# 处理克隆的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find "$REPO_PATH"/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./package \;
		rm -rf "$REPO_PATH"
	fi
}

# 调用示例
# UPDATE_PACKAGE "OpenAppFilter" "destan19/OpenAppFilter" "master" "" "custom_name1 custom_name2"

UPDATE_PACKAGE "aurora" "eamonxg/luci-theme-aurora" "master"
UPDATE_PACKAGE "vantage" "anothaDev/luci-theme-vantage" "main"
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "axonhub miniupnpd luci-app-upnp"
UPDATE_PACKAGE "netwizard" "sirpdboy/luci-app-netwizard" "main"
UPDATE_PACKAGE "open-app-filter" "destan19/OpenAppFilter" "master" "" "open-app-filter luci-app-oaf oaf"
# 文件管理：Harbor File（单包仓库，直接克隆）
UPDATE_PACKAGE "luci-app-harbor-file" "destan19/luci-app-harbor-file" "master"
# 集客 AC 控制器（含主程序 gecoosac + 界面 luci-app-gecoosac）
UPDATE_PACKAGE "gecoosac" "laipeng668/luci-app-gecoosac" "main" "" "gecoosac luci-app-gecoosac"

# ============================================================
# 易有云 linkease —— 官方 feed 方式（推荐）
#   https://github.com/linkease/nas-packages       (服务侧：linkease / linkeasefull / linkease-app-entry / linkease-common-bin)
#   https://github.com/linkease/nas-packages-luci  (界面：luci-app-linkease 等)
# 说明：nas-packages 官方已把 luci 包迁到 nas-packages-luci，两个源必须都加，
#       否则 luci-app-linkease 编不出来。版本以官方仓库为准，不要手工下旧包。
#       19.07+ 还需要在 make menuconfig 里勾选 luci-compat。
# ============================================================
SETUP_LINKEASE_FEED() {
	# 1) 清掉之前用 UPDATE_PACKAGE 硬塞进来的残留（含 feeds 索引里的旧版）
	local _d _dir _fdir
	for _d in linkease linkeasefull linkease-app-entry linkease-common-bin \
	          luci-app-linkease luci-app-linkeasefull luci-app-linkeasefull-embed \
	          luci-lib-linkeasefile luci-lib-linkeaseauth linkease-runtime-transition; do
		for _dir in ./package/$_d ./package/nas-packages/$_d ./package/nas-packages-luci/$_d; do
			if [ -e "$_dir" ]; then rm -rf "$_dir" && echo "Delete: $_dir"; fi
		done
		while read -r _fdir; do
			[ -n "$_fdir" ] && rm -rf "$_fdir" && echo "Delete feed: $_fdir"
		done <<< "$(find ./feeds/ -maxdepth 5 -type d -iname "*$_d*" 2>/dev/null)"
	done

	# 2) 追加 feed 源（幂等：已存在则跳过）
	if ! grep -q "^src-git nas " feeds.conf.default 2>/dev/null; then
		echo 'src-git nas https://github.com/linkease/nas-packages.git;master' >> feeds.conf.default
		echo "Add feed: nas"
	else
		echo "Feed nas already exists, skip."
	fi
	if ! grep -q "^src-git nas_luci " feeds.conf.default 2>/dev/null; then
		echo 'src-git nas_luci https://github.com/linkease/nas-packages-luci.git;main' >> feeds.conf.default
		echo "Add feed: nas_luci"
	else
		echo "Feed nas_luci already exists, skip."
	fi

	# 3) 更新并安装（只动这两个源，不干扰其他 feeds）
	./scripts/feeds update nas nas_luci
	./scripts/feeds install -a -p nas
	./scripts/feeds install -a -p nas_luci

	# 4) 验证
	echo "=== linkease 相关包已注册列表 ==="
	./scripts/feeds list | grep -iE "linkease" || \
		find package/feeds/ -maxdepth 3 -type l -iname "*linkease*" 2>/dev/null
}

SETUP_LINKEASE_FEED

# ============================================================
# iStore 应用商店（官方 feeds 方式，依赖跟随主干 commit）
# 官方仓库仅支持 x86_64 / aarch64，其余架构集成了也装不上应用
# 19.07 及以上还需要在 make menuconfig 中勾选 luci-compat
# ============================================================
if ! grep -q "^src-git istore " feeds.conf.default 2>/dev/null; then
	echo 'src-git istore https://github.com/linkease/istore;main' >> feeds.conf.default
	echo "Add feed: istore"
else
	echo "Feed istore already exists, skip."
fi
./scripts/feeds update istore
./scripts/feeds install -d y -p istore luci-app-store
./scripts/feeds install -d y -p istore luci-lib-taskd

# 更新软件包版本
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}

	# 【修复】非 Debian 环境可能没有 dpkg，提前判断
	if ! command -v dpkg >/dev/null 2>&1; then
		echo "WARNING: dpkg not found, version compare disabled, skip $PKG_NAME"
		return
	fi

	local PKG_FILES
	PKG_FILES=$(find ./package/ ./feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile")

	if [ -z "$PKG_FILES" ]; then
		echo "$PKG_NAME not found!"
		return
	fi

	echo -e "\n$PKG_NAME version update has started!"

	for PKG_FILE in $PKG_FILES; do
		local PKG_REPO
		PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)" "$PKG_FILE")
		local PKG_TAG
		PKG_TAG=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases" | jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name")

		local OLD_VER
		OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
		local OLD_URL
		OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
		local OLD_FILE
		OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")
		local OLD_HASH
		OLD_HASH=$(grep -Po "PKG_HASH:=\K.*" "$PKG_FILE")

		local PKG_URL
		PKG_URL=$([[ "$OLD_URL" == *"releases"* ]] && echo "${OLD_URL%/}/$OLD_FILE" || echo "${OLD_URL%/}")

		local NEW_VER
		NEW_VER=$(echo "$PKG_TAG" | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
		local NEW_URL
		NEW_URL=$(echo "$PKG_URL" | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")
		local NEW_HASH
		NEW_HASH=$(curl -sL "$NEW_URL" | sha256sum | cut -d ' ' -f 1)

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

# 引入私有扩展脚本
if [ -f "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh"
fi

# ============================================================
# 收尾提醒
# ============================================================
echo ""
echo "===== 后续步骤 ====="
echo "1) make menuconfig 里务必勾选："
echo "     LuCI -> 3. Applications -> luci-app-linkease"
echo "     LuCI -> Libraries        -> luci-lib-linkeasefile / luci-lib-linkeaseauth"
echo "     LuCI                     -> luci-compat   (19.07+ 必选)"
echo "     Network -> Web Servers   -> linkease / linkeasefull / linkease-app-entry / linkease-common-bin"
echo "2) dl/ 是本地编译缓存，不要 git add，建议加入 .gitignore："
echo "     echo '/dl/' >> .gitignore && git rm -r --cached dl 2>/dev/null"
echo "3) 官方版本已更新，旧版(1.7.6/3.0.23)的 dl 包需重新下载，执行："
echo "     rm -f dl/linkease*.tar.gz dl/linkease-*.tar.gz 2>/dev/null"
echo "     make package/feeds/nas/linkease-common-bin/compile V=s"
