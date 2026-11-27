# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

include $(TOPDIR)/rules.mk

LUCI_TITLE:=Design Theme
LUCI_DEPENDS:=+luci-mod-status
PKG_LICENSE:=Apache-2.0
PKG_VERSION:=7.1
PKG_RELEASE:=20261109

LUCI_MINIFY_CSS:=
CONFIG_LUCI_CSSTIDY:=

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature

define Package/luci-theme-design/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] && exit 0
SRC="/www/luci-static/design/override/status"
DST="/www/luci-static/resources/view/status/include"
mkdir -p "$$DST"
[ -f "$$SRC/30_network.js" ] && cp -f "$$SRC/30_network.js" "$$DST/30_network.js"
[ -f "$$SRC/40_dhcp.js" ] && cp -f "$$SRC/40_dhcp.js" "$$DST/40_dhcp.js"
uci -q set luci.main.mediaurlbase='/luci-static/design'
uci -q commit luci
exit 0
endef

define Package/luci-theme-design/prerm
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] && exit 0
rm -f /www/luci-static/resources/view/status/include/30_network.js
rm -f /www/luci-static/resources/view/status/include/40_dhcp.js
uci -q set luci.main.mediaurlbase='/luci-static/bootstrap'
uci -q commit luci
exit 0
endef
