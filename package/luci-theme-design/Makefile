# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

include $(TOPDIR)/rules.mk

LUCI_TITLE:=Design Theme
LUCI_DEPENDS:=+luci-mod-status
PKG_LICENSE:=Apache-2.0
PKG_VERSION:=7.1
PKG_RELEASE:=20261110

LUCI_MINIFY_CSS:=
CONFIG_LUCI_CSSTIDY:=

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature

# ---------------------------------------------------------------
# 方案B：status 页面 js 覆盖
#   编译进固件 -> root/etc/uci-defaults/31_* 首次开机 cp
#   后装 apk   -> postinst 即时 cp（uci-defaults 下次开机兜底）
#   卸载       -> prerm 删覆盖文件
#   override 源放 design/override/status/，不占 luci-mod-status 文件表
# ---------------------------------------------------------------

define Package/luci-theme-design/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] && exit 0
OV="/www/luci-static/design/override/status"
DST="/www/luci-static/resources/view/status/include"
mkdir -p "$$DST"
[ -f "$$OV/30_network.js" ] && cp -f "$$OV/30_network.js" "$$DST/30_network.js"
[ -f "$$OV/40_dhcp.js" ] && cp -f "$$OV/40_dhcp.js" "$$DST/40_dhcp.js"
uci -q set luci.themes.Design=/luci-static/design
uci -q set luci.main.mediaurlbase=/luci-static/design
uci -q commit luci
rm -f /tmp/luci-indexcache.* 2>/dev/null
rm -rf /tmp/luci-modulecache 2>/dev/null
exit 0
endef

define Package/luci-theme-design/prerm
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] && exit 0
rm -f /www/luci-static/resources/view/status/include/30_network.js
rm -f /www/luci-static/resources/view/status/include/40_dhcp.js
rm -f /tmp/luci-indexcache.* 2>/dev/null
rm -rf /tmp/luci-modulecache 2>/dev/null
exit 0
endef
