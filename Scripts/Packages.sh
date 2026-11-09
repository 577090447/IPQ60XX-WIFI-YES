#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
# 修改：改用官方 feed 方式引入 linkease，修复若干隐患

set -euo pipefail

# ============================================================
# 工具函数
# ============================================================

# 安全删除目录（判空 + 存在检查）
safe_rm_dirs() {
	local base_paths=("$@")
	local dir
	for base in "${base_paths[@]}"; do
		if [ -e "$base" ]; then
			rm -rf "$base"
			echo "Deleted: $base"
		fi
	done
}

# GitHub API 请求（自动带 token，带重试）
github_api() {
	local url="$1"
	local attempt=0
	local max_attempts=3
	local wait_sec=2

	while [ $attempt -lt $max_attempts ]; do
		attempt=$((attempt + 1))
		local headers=()
		if [ -n "${GITHUB_TOKEN:-}" ]; then
			headers+=(-H "Authorization: token $GITHUB_TOKEN")
		elif [ -n "${GH_TOKEN:-}" ]; then
			headers+=(-H "Authorization: token $GH_TOKEN")
		fi
		# 加 Accept header 避免 406
		headers+=(-H "Accept: application/vnd.github+json")

		local response
		response=$(curl -sL --connect-timeout 10 --max-time 30 \
			"${headers[@]}" "$url" 2>/dev/null)

		# 检查是否被限流
		if echo "$response" | grep -qi "rate limit"; then
			echo "WARNING: GitHub API rate limit hit (attempt $attempt/$max_attempts)" >&2
			if [ $attempt -lt $max_attempts ]; then
				sleep $((wait_sec * attempt))
				continue
			fi
			echo "ERROR: GitHub API rate limit exhausted, skipping version check" >&2
			return 1
		fi

		# 检查空响应
		if [ -z "$response" ] || echo "$response" | grep -qi "Not Found"; then
			echo "WARNING: GitHub API returned empty/not found for $url" >&2
			return 1
		fi

		echo "$response"
		return 0
	done
	return 1
}

# ============================================================
# 安装和更新软件包
# ============================================================
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

		# find 无匹配会读到空行，rm -rf "" 会删根目录，必须判空
		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				[ -n "$DIR" ] && [ -d "$DIR" ] && rm -rf "$DIR" && echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not found directory: $NAME"
		fi
	done

	# 克隆 GitHub 仓库
	if ! git clone --depth=1 --single-branch --branch "$PKG_BRANCH" \
		"https://github.com/$PKG_REPO.git" "$REPO_PATH" 2>/dev/null; then
		echo "ERROR: Failed to clone $PKG_REPO, skipping $PKG_NAME"
		return 1
	fi

	# 处理克隆的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find "$REPO_PATH"/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./package \;
		[ -d "$REPO_PATH" ] && rm -rf "$REPO_PATH"
	fi
}

# 调用示例
# UPDATE_PACKAGE "OpenAppFilter" "destan19/OpenAppFilter" "master" "" "custom_name1 custom_name2"

UPDATE_PACKAGE "aurora" "eamonxg/luci-theme-aurora" "master"
UPDATE_PACKAGE "vantage" "anothaDev/luci-theme-vantage" "main"
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
# viking 搜索词收窄为精确仓库名，避免误删
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "VIKINGYFY-packages"
UPDATE_PACKAGE "netwizard" "sirpdboy/luci-app-netwizard" "main"
UPDATE_PACKAGE "open-app-filter" "destan19/OpenAppFilter" "master" "" "open-app-filter luci-app-oaf oaf"
# 文件管理：Harbor File（单包仓库，直接克隆）
UPDATE_PACKAGE "luci-app-harbor-file" "destan19/luci-app-harbor-file" "master"
# 集客 AC 控制器（含主程序 gecoosac + 界面 luci-app-gecoosac）
UPDATE_PACKAGE "gecoosac" "laipeng668/luci-app-gecoosac" "main" "" "gecoosac luci-app-gecoosac"

# ============================================================
# 易有云 linkease —— 官方 feed 方式（推荐）
# ============================================================
SETUP_LINKEASE_FEED() {
	local NAS_FEED_URL="https://github.com/linkease/nas-packages.git"
	local NAS_LUCI_FEED_URL="https://github.com/linkease/nas-packages-luci.git"

	echo "=== Setting up Linkease feeds ==="

	# 1) 清掉之前用 UPDATE_PACKAGE 硬塞进来的残留
	local _d _dir _fdir
	for _d in linkease linkeasefull linkease-app-entry linkease-common-bin \
	          luci-app-linkease luci-app-linkeasefull luci-app-linkeasefull-embed \
	          luci-lib-linkeasefile luci-lib-linkeaseauth linkease-runtime-transition; do
		for _dir in ./package/$_d ./package/nas-packages/$_d ./package/nas-packages-luci/$_d; do
			if [ -e "$_dir" ]; then rm -rf "$_dir" && echo "Delete: $_dir"; fi
		done
		while read -r _fdir; do
			[ -n "$_fdir" ] && [ -d "$_fdir" ] && rm -rf "$_fdir" && echo "Delete feed: $_fdir"
		done <<< "$(find ./feeds/ -maxdepth 5 -type d -iname "*$_d*" 2>/dev/null)"
	done

	# 2) 追加 / 替换 feed 源（URL 校验，旧源自动注释）
	if grep -q "^src-git nas " feeds.conf.default 2>/dev/null; then
		if grep -q "^src-git nas $NAS_FEED_URL" feeds.conf.default 2>/dev/null; then
			echo "Feed nas already correct, skip."
		else
			sed -i '/^src-git nas /s/^/#OLD_/' feeds.conf.default
			echo "Commented out old nas feed entry"
			echo "src-git nas $NAS_FEED_URL;master" >> feeds.conf.default
			echo "Add feed: nas (replaced old entry)"
		fi
	else
		echo "src-git nas $NAS_FEED_URL;master" >> feeds.conf.default
		echo "Add feed: nas"
	fi

	if grep -q "^src-git nas_luci " feeds.conf.default 2>/dev/null; then
		if grep -q "^src-git nas_luci $NAS_LUCI_FEED_URL" feeds.conf.default 2>/dev/null; then
			echo "Feed nas_luci already correct, skip."
		else
			sed -i '/^src-git nas_luci /s/^/#OLD_/' feeds.conf.default
			echo "Commented out old nas_luci feed entry"
			echo "src-git nas_luci $NAS_LUCI_FEED_URL;main" >> feeds.conf.default
			echo "Add feed: nas_luci (replaced old entry)"
		fi
	else
		echo "src-git nas_luci $NAS_LUCI_FEED_URL;main" >> feeds.conf.default
		echo "Add feed: nas_luci"
	fi

	# 3) 更新并安装（失败立即退出）
	echo "Updating feeds nas nas_luci..."
	./scripts/feeds update nas nas_luci || { echo "ERROR: feeds update failed"; exit 1; }

	echo "Installing nas packages..."
	./scripts/feeds install -a -p nas || { echo "ERROR: feeds install nas failed"; exit 1; }

	echo "Installing nas_luci packages..."
	./scripts/feeds install -a -p nas_luci || { echo "ERROR: feeds install nas_luci failed"; exit 1; }

	# 4) 架构守卫：linkease-common-bin 预编译二进制可能缺 aarch64
	if [ -f .config ]; then
		local TARGET_ARCH
		TARGET_ARCH=$(grep "^CONFIG_TARGET_ARCH_PACKAGES" .config 2>/dev/null | cut -d'"' -f2)
		if [ -n "$TARGET_ARCH" ]; then
			case "$TARGET_ARCH" in
				aarch64_*|arm_*|mipsel_*|mips_*)
					echo ""
					echo "⚠️  ARCH GUARD: Target is $TARGET_ARCH"
					echo "   linkease-common-bin is a prebuilt binary package."
					echo "   Official releases may NOT include $TARGET_ARCH binaries."
					echo "   If 'make package/download' fails, deselect it in .config:"
					echo "     # CONFIG_PACKAGE_linkease-common-bin is not set"
					echo "   luci-app-linkease (pure Lua) works without it."
					echo ""
					;;
				x86_64)
					echo "✓ Target is x86_64, linkease-common-bin should have prebuilt binaries."
					;;
				*)
					echo "ℹ️  Target is $TARGET_ARCH, verify linkease-common-bin availability."
					;;
			esac
		fi
	fi

	# 5) 验证
	echo "=== linkease related packages registered ==="
	./scripts/feeds list 2>/dev/null | grep -iE "linkease" || \
		find package/feeds/ -maxdepth 3 -type l -iname "*linkease*" 2>/dev/null || \
		echo "No linkease packages found in feed list (may need menuconfig to enable)"
}

SETUP_LINKEASE_FEED

# ============================================================
# iStore 应用商店（官方 feeds 方式）
# ============================================================
echo "=== Setting up iStore feed ==="
if grep -q "^src-git istore " feeds.conf.default 2>/dev/null; then
	if grep -q "^src-git istore https://github.com/linkease/istore;main" feeds.conf.default 2>/dev/null; then
		echo "Feed istore already correct, skip."
	else
		sed -i '/^src-git istore /s/^/#OLD_/' feeds.conf.default
		echo "Commented out old istore feed entry"
		echo 'src-git istore https://github.com/linkease/istore;main' >> feeds.conf.default
		echo "Add feed: istore (replaced old entry)"
	fi
else
	echo 'src-git istore https://github.com/linkease/istore;main' >> feeds.conf.default
	echo "Add feed: istore"
fi

./scripts/feeds update istore || { echo "ERROR: feeds update istore failed"; exit 1; }
./scripts/feeds install -d y -p istore luci-app-store || echo "WARNING: luci-app-store install failed"
./scripts/feeds install -d y -p istore luci-lib-taskd || echo "WARNING: luci-lib-taskd install failed"

# ============================================================
# 更新软件包版本
# ============================================================
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}

	# 依赖检查
	if ! command -v dpkg >/dev/null 2>&1; then
		echo "WARNING: dpkg not found, version compare disabled, skip $PKG_NAME"
		return
	fi
	if ! command -v jq >/dev/null 2>&1; then
		echo "WARNING: jq not found, version update skipped for $PKG_NAME"
		return
	fi

	local PKG_FILES
	PKG_FILES=$(find ./package/ ./feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile" 2>/dev/null)

	if [ -z "$PKG_FILES" ]; then
		echo "$PKG_NAME not found!"
		return
	fi

	echo -e "\n$PKG_NAME version update has started!"

	for PKG_FILE in $PKG_FILES; do
		[ -f "$PKG_FILE" ] || continue

		local PKG_REPO
		PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)" "$PKG_FILE" || true)
		if [ -z "$PKG_REPO" ]; then
			echo "  $PKG_FILE: cannot extract repo from PKG_SOURCE_URL, skip"
			continue
		fi

		local API_RESP
		API_RESP=$(github_api "https://api.github.com/repos/$PKG_REPO/releases")
		if [ $? -ne 0 ] || [ -z "$API_RESP" ]; then
			echo "  $PKG_FILE: API request failed, skip"
			continue
		fi

		local PKG_TAG
		PKG_TAG=$(echo "$API_RESP" | jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name // empty" 2>/dev/null)
		if [ -z "$PKG_TAG" ]; then
			echo "  $PKG_FILE: no suitable release tag found, skip"
			continue
		fi

		local OLD_VER OLD_URL OLD_FILE OLD_HASH
		OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE" || true)
		OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE" || true)
		OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE" || true)
		OLD_HASH=$(grep -Po "PKG_HASH:=\K.*" "$PKG_FILE" || true)

		[ -z "$OLD_VER" ] && { echo "  $PKG_FILE: no PKG_VERSION found, skip"; continue; }

		local PKG_URL
		PKG_URL=$([[ "$OLD_URL" == *"releases"* ]] && echo "${OLD_URL%/}/$OLD_FILE" || echo "${OLD_URL%/}")

		local NEW_VER
		NEW_VER=$(echo "$PKG_TAG" | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
		[ -z "$NEW_VER" ] && { echo "  $PKG_FILE: cannot parse version from tag $PKG_TAG, skip"; continue; }

		local NEW_URL
		NEW_URL=$(echo "$PKG_URL" | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")
		local NEW_HASH=""
		if [ -n "$NEW_URL" ]; then
			NEW_HASH=$(curl -sL --connect-timeout 10 --max-time 60 "$NEW_URL" | sha256sum | cut -d ' ' -f 1 || true)
		fi

		echo "  old version: $OLD_VER ${OLD_HASH:-(no hash)}"
		echo "  new version: $NEW_VER ${NEW_HASH:-(hash fetch failed)}"

		if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER" 2>/dev/null; then
			sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
			if [ -n "$NEW_HASH" ]; then
				sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
			else
				echo "  WARNING: hash fetch failed, PKG_HASH not updated (manual fix needed)"
			fi
			echo "  ✓ $PKG_FILE version updated: $OLD_VER → $NEW_VER"
		else
			echo "  - $PKG_FILE already latest ($OLD_VER >= $NEW_VER)"
		fi
	done
}

# UPDATE_VERSION "软件包名" "测试版，true，可选，默认为否"
# UPDATE_VERSION "sing-box"

# ============================================================
# 引入私有扩展脚本
# ============================================================
if [ -f "${GITHUB_WORKSPACE:-.}/Scripts/PRIVATE.sh" ]; then
	source "${GITHUB_WORKSPACE:-.}/Scripts/PRIVATE.sh"
fi

# ============================================================
# 收尾提醒
# ============================================================
echo ""
echo "===== Post-setup checklist ====="
echo "1) make menuconfig selections:"
echo "     LuCI → 3. Applications → luci-app-linkease"
echo "     LuCI → Libraries        → luci-lib-linkeasefile / luci-lib-linkeaseauth"
echo "     LuCI                   → luci-compat   (19.07+ required)"
echo "     Network → Web Servers  → linkease / linkeasefull / linkease-app-entry"
echo "     (linkease-common-bin: prebuilt only, skip on non-x86_64 if download fails)"
echo ""
echo "2) Verify all packages can download:"
echo "     make package/download -j\$(nproc) V=s"
echo ""
echo "3) Clean old dl cache if needed:"
echo "     rm -f dl/linkease*.tar.gz dl/linkease-*.tar.gz 2>/dev/null"
echo ""
echo "4) .gitignore recommendation:"
echo "     echo '/dl/' >> .gitignore && git rm -r --cached dl 2>/dev/null || true"
echo ""
echo "===== Packages.sh completed ====="
