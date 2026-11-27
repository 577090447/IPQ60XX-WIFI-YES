'use strict';
'require baseclass';
'require fs';
'require network';
'require rpc';
'require ui';

const callOdhcp6cStats = rpc.declare({
	object: 'luci',
	method: 'getOdhcp6cStats',
	expect: { '': {} },
});

var callOnlineUsers = rpc.declare({
	object: 'luci',
	method: 'getOnlineUsers'
});

function progressbar(value, max, byte) {
	const vn = parseInt(value) || 0;
	const mn = parseInt(max) || 100;
	const fv = byte ? String.format('%1024.2mB', value) : value;
	const fm = byte ? String.format('%1024.2mB', max) : max;
	const pc = Math.floor((100 / mn) * vn);
	return E('div', { 'class': 'cbi-progressbar', 'title': '%s / %s (%d%%)'.format(fv, fm, pc) },
		E('div', { 'style': 'width:%.2f%%'.format(pc) }));
}

function renderbox(ifc, ipv6, dhcpv6_stats) {
	const dev = ifc.getL3Device();
	const active = (dev && ifc.getProtocol() != 'none');
	const addrs = (ipv6 ? ifc.getIP6Addrs() : ifc.getIPAddrs()) || [];
	const dnssrv = (ipv6 ? ifc.getDNS6Addrs() : ifc.getDNSAddrs()) || [];
	const expires = ifc.getExpiry();
	const uptime = ifc.getUptime();

	function addEntries(label, array) {
		return Array.isArray(array) ? array.flatMap((item) => [label, item]) : [label, null];
	}

	function addDhcpv6Stats() {
		if (ipv6 && ifc.getProtocol() === 'dhcpv6' && dhcpv6_stats && dhcpv6_stats[dev.device]) {
			const arr = [];
			for (const [pkt_type, count] of Object.entries(dhcpv6_stats[dev.device]))
				arr.push(pkt_type.replace('dhcp_', 'DHCPv6 '), `${count} 个数据包`);
			return ['DHCPv6 统计', E('span', { 'class': 'cbi-tooltip-container' }, ['📊',
				E('span', { 'class': 'cbi-tooltip' }, ui.itemlist(E('span'), arr))])];
		}
		return ['', null];
	}

	return E('div', { class: 'ifacebox' }, [
		E('div', { class: 'ifacebox-head center ' + (active ? 'active' : '') },
			E('strong', ipv6 ? 'IPv6 上行' : 'IPv4 上行')),
		E('div', { class: 'ifacebox-body left' }, [
			L.itemlist(E('span'), [
				'协议', ifc.getI18n() || E('em', '未连接'),
				...addEntries('委派前缀', ipv6 ? ifc.getIP6Prefixes?.() : null),
				...addEntries('地址', addrs),
				'网关', ipv6 ? (ifc.getGateway6Addr() || '::') : (ifc.getGatewayAddr() || '0.0.0.0'),
				...addEntries('DNS', dnssrv),
				'过期时间', (expires != null && expires > -1) ? '%t'.format(expires) : null,
				'已连接', (uptime > 0) ? '%t'.format(uptime) : null,
				...addDhcpv6Stats(),
			]),
			E('div', {}, renderBadge(L.resource('icons/%s.svg').format(dev ? dev.getType() : 'ethernet_disabled'), null,
				'设备', dev ? dev.getI18n() : '-',
				'MAC地址', dev.getMAC()))
		])
	]);
}

return baseclass.extend({
	title: '网络',

	wanDevices(networks) {
		const lower = new Map(), devices = new Map();
		for (const net of networks) {
			const l3 = net.getL3Device(), l2 = net.getL2Device();
			if (l3 && l2 && l3.getName() != l2.getName())
				lower.set(l3.getName(), l2);
		}
		for (const net of networks) {
			let dev = net.getL2Device() || net.getL3Device();
			const seen = new Set();
			while (dev && !seen.has(dev.getName())) {
				seen.add(dev.getName());
				const parent = lower.get(dev.getName()) || (dev.getType() == 'vlan' ? dev.getParent() : null);
				if (!parent || seen.has(parent.getName()))
					break;
				dev = parent;
			}
			if (dev)
				devices.set(dev.getName(), dev);
		}
		return devices;
	},

	wanCapacity(devices) {
		let capacity = 0;
		for (const dev of devices.values()) {
			const speed = Number(dev.getSpeed());
			capacity += Number.isFinite(speed) && speed > 0 && speed < 0xffffffff ? speed : 1000;
		}
		return capacity || 1000;
	},

	bandwidthBar(value, capacity) {
		if (value != null)
			value = Number.isFinite(value) ? Math.max(0, Math.min(value, capacity)) : null;
		const percent = value != null ? Math.max(0, value / capacity * 100) : 0;
		return E('div', {
			'class': 'cbi-progressbar',
			'title': value != null ? '%.2f Mbps / %s Gbps (%.1f%%)'.format(value, capacity / 1000, percent) : '- / %s Gbps'.format(capacity / 1000)
		}, E('div', { 'style': 'width:%.2f%%'.format(Math.min(100, percent)) }));
	},

	wanRates(devices, now) {
		const previous = this.wanSamples || new Map();
		const samples = new Map();
		let download = 0, upload = 0, ready = true;
		for (const dev of devices.values()) {
			const name = dev.getName();
			const sample = { rx: dev.getRXBytes(), tx: dev.getTXBytes(), time: now };
			const old = previous.get(name);
			samples.set(name, sample);
			if (!old || now <= old.time || sample.rx < old.rx || sample.tx < old.tx) {
				ready = false;
				continue;
			}
			download += (sample.rx - old.rx) * 8 / (now - old.time) / 1000;
			upload += (sample.tx - old.tx) * 8 / (now - old.time) / 1000;
		}
		this.wanSamples = samples;
		return ready && samples.size ? [download, upload] : [null, null];
	},

	load() {
		return Promise.all([
			fs.trimmed('/proc/sys/net/netfilter/nf_conntrack_count'),
			fs.trimmed('/proc/sys/net/netfilter/nf_conntrack_max'),
			network.getWANNetworks(),
			network.getWAN6Networks(),
			callOdhcp6cStats(),
			L.resolveDefault(callOnlineUsers(), {})
		]);
	},

	render([ct_count, ct_max, wan_nets, wan6_nets, dhcpv6_stats, onlineusers]) {
		const networks = [...wan_nets, ...wan6_nets];
		const devices = this.wanDevices(networks);
		const [download, upload] = this.wanRates(devices, performance.now());
		const capacity = this.wanCapacity(devices);

		// ✅ 这里是修复好的标签，直接全部中文
		const fields = [
			{ label: '活动连接', value: ct_max ? progressbar(ct_count, ct_max) : null },
			{ label: '在线用户数', value: onlineusers ? onlineusers.onlineusers : null },
			{ label: '总上传带宽', value: this.bandwidthBar(upload, capacity) },
			{ label: '总下载带宽', value: this.bandwidthBar(download, capacity) }
		];

		const ctstatus = E('table', { 'class': 'table' });
		for (const { label, value } of fields) {
			ctstatus.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '33%' }, [label]),
				E('td', { 'class': 'td left' }, [(value != null) ? value : '?'])
			]));
		}

		const netstatus = E('div', { 'class': 'network-status-table' });
		for (const wan_net of wan_nets)
			netstatus.appendChild(renderbox(wan_net, false));
		for (const wan6_net of wan6_nets)
			netstatus.appendChild(renderbox(wan6_net, true, dhcpv6_stats?.result));

		return E([netstatus, ctstatus]);
	}
});
