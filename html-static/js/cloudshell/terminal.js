(function() {
	// Function to get query parameters
	// Note: This app uses ? as separator between params (not standard &)
	var urlParam = function(name, w) {
		w = w || window;
		var rx = new RegExp('[\&|\?]' + name + '=([^\&\#\?]+)'),
			val = w.location.search.match(rx);
		return !val ? '' : val[1];
	};

	// Retrieve the RouterID and RouterName query parameters
	var routerId = urlParam('RouterID');
	var routerNameForTitle = urlParam('RouterName');

	console.log("routerId:", routerId);
	console.log("routerNameForTitle:", routerNameForTitle);

	document.title = `TopoViewer::${routerNameForTitle || routerId}`;


	// Initialize the terminal with the desired options
	var terminal = new Terminal({
		screenKeys: true,
		useStyle: true,
		cursorBlink: true,
		fullscreenWin: true,
		maximizeWin: true,
		screenReaderMode: true,
		cols: 128,
	});

	// Open the terminal in the specified HTML element
	terminal.open(document.getElementById("terminal"));

	// Tell the embedding application that the user is actively working in
	// this console. The console page runs either directly iframed or as a
	// popup opened from the topology view (window.open in dev.js) — in the
	// popup case the message goes to the opener page, which relays it to its
	// own parent when embedded. Throttled to at most one message per 30
	// seconds; a standalone console (no parent, no opener) sends nothing.
	// targetOrigin "*" is acceptable: the message carries no data, and the
	// embedding application is expected to validate event.origin on its side.
	var ACTIVITY_THROTTLE_MS = 30000;
	var lastActivitySentAt = 0;
	var notifyActivity = function() {
		var target = null;
		if (window.parent !== window) {
			target = window.parent;
		} else if (window.opener) {
			target = window.opener;
		}
		if (!target) {
			return;
		}
		var now = Date.now();
		if (now - lastActivitySentAt < ACTIVITY_THROTTLE_MS) {
			return;
		}
		lastActivitySentAt = now;
		target.postMessage({ type: "netpilot:console-activity" }, "*");
	};

	// onData fires on user input only (keystrokes/paste) — never on server
	// output — so an idle open terminal emits nothing.
	terminal.onData(notifyActivity);

	// Determine the WebSocket protocol based on the page's protocol
	var protocol = (location.protocol === "https:") ? "wss://" : "ws://";
	var url = protocol + location.host + "/xterm.js";
	var ws = new WebSocket(url);

	console.log(ws);

	// Load necessary addons
	var attachAddon = new AttachAddon.AttachAddon(ws);
	var fitAddon = new FitAddon.FitAddon();
	var webLinksAddon = new WebLinksAddon.WebLinksAddon();
	var unicode11Addon = new Unicode11Addon.Unicode11Addon();
	var serializeAddon = new SerializeAddon.SerializeAddon();

	terminal.loadAddon(fitAddon);
	terminal.loadAddon(webLinksAddon);
	terminal.loadAddon(unicode11Addon);
	terminal.loadAddon(serializeAddon);

	// Define WebSocket event handlers
	ws.onclose = function(event) {
		console.log(event);
		terminal.write('\r\n\nconnection has been terminated from the server-side (hit refresh to restart)\n');
	};

	ws.onopen = function() {
		terminal.loadAddon(attachAddon);
		terminal._initialized = true;
		terminal.focus();
		setTimeout(function() {
			fitAddon.fit();
		});

		// Get parameters from URL (URL uses ? as separator, so we need to clean up)
		var routerNameRaw = urlParam('RouterName');
		var routerName = routerNameRaw.split("?")[0];  // Remove trailing ?Kind=... if present
		var nodeKind = urlParam('Kind') || 'default';
		var nodeImage = decodeURIComponent(urlParam('Image') || '');

		// SSH to the mgmt IP (RouterID) when we have one — the container-name
		// route depends on a /etc/hosts entry that may be missing — and fall
		// back to the name otherwise. docker-exec kinds always need the name.
		var routerIp = urlParam('RouterID').split("?")[0];
		if (routerIp === 'undefined' || routerIp === 'null') routerIp = '';
		var sshHost = routerIp || routerName;

		// Build command based on node kind
		// Reference: https://containerlab.dev/manual/kinds/
		var terminalCommand;
		if (nodeKind === 'linux' && nodeImage.toLowerCase().includes('frr')) {
			// FRRouting: use docker exec with vtysh for direct FRR CLI access
			terminalCommand = "docker exec -it " + routerName + " vtysh";
		} else if (nodeKind === 'linux') {
			// Linux containers: use docker exec for direct access
			terminalCommand = "docker exec -it " + routerName + " bash";
		} else if (nodeKind === 'cisco_iol') {
			// Cisco IOL: admin/admin
			terminalCommand = "sshpass -p 'admin' ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no admin@" + sshHost;
		} else if (nodeKind === 'arista_ceos') {
			// Arista cEOS: admin/admin
			terminalCommand = "sshpass -p 'admin' ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no admin@" + sshHost;
		} else if (nodeKind === 'juniper_crpd') {
			// Juniper cRPD: root/clab123
			terminalCommand = "sshpass -p 'clab123' ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@" + sshHost;
		} else if (nodeKind === 'paloalto_panos') {
			// Palo Alto PAN: admin/Admin@123
			terminalCommand = "sshpass -p 'Admin@123' ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no admin@" + sshHost;
		} else if (nodeKind === 'nokia_srlinux') {
			// Nokia SR Linux: admin/NokiaSrl1!
			terminalCommand = "sshpass -p 'NokiaSrl1!' ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no admin@" + sshHost;
		} else if (nodeKind === 'vyosnetworks_vyos') {
			// VyOS: admin/admin
			terminalCommand = "sshpass -p 'admin' ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no admin@" + sshHost;
		} else if (nodeKind === 'fortinet_fortigate') {
			// Fortinet FortiGate: admin/Fortinet!1234 (FortiOS 7.6.5+ policy-compliant)
			terminalCommand = "sshpass -p 'Fortinet!1234' ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no admin@" + sshHost;
		} else if (nodeKind === 'cisco_xrd') {
			// Cisco XRd: clab/clab@123 (containerlab-injected)
			terminalCommand = "sshpass -p 'clab@123' ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no clab@" + sshHost;
		} else if (nodeKind === 'cisco_n9kv') {
			// Cisco Nexus 9000v: admin/admin (containerlab-injected, vrnetlab-created)
			terminalCommand = "sshpass -p 'admin' ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no admin@" + sshHost;
		} else if (nodeKind === 'aruba_aoscx') {
			// Aruba AOS-CX: admin/admin (containerlab-injected, vrnetlab-created)
			terminalCommand = "sshpass -p 'admin' ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no admin@" + sshHost;
		} else if (nodeKind === 'dell_ftosv') {
			// Dell SmartFabric OS10: admin/admin (containerlab-injected, vrnetlab-created;
			// live-login verified on bench 2026-08-22)
			terminalCommand = "sshpass -p 'admin' ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no admin@" + sshHost;
		} else if (nodeKind === 'mikrotik_ros') {
			// MikroTik RouterOS CHR: admin/admin (containerlab-injected, set by the
			// NetPilot launcher at boot; live-login verified on bench 2026-10-10,
			// containerlab-mcp#288)
			terminalCommand = "sshpass -p 'admin' ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no admin@" + sshHost;
		} else if (nodeKind === 'sonic-vs') {
			// SONiC community VS: admin/YourPaSsWoRd (created by the NetPilot init
			// script — containerlab registers no credentials for the kind;
			// live-login verified on bench 2026-09-29, containerlab-mcp#219)
			terminalCommand = "sshpass -p 'YourPaSsWoRd' ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no admin@" + sshHost;
		} else {
			// Other network devices: use SSH with admin user (default fallback, no auto-password)
			terminalCommand = "ssh -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no admin@" + sshHost;
		}
		console.log("Terminal command: " + terminalCommand + " (kind: " + nodeKind + ", image: " + nodeImage + ")");
		ws.send(terminalCommand + "\n");



		terminal.onResize(function(event) {
			var rows = event.rows;
			var cols = event.cols;
			var size = JSON.stringify({
				cols: cols,
				rows: rows + 1
			});
			var send = new TextEncoder().encode("\x01" + size);
			console.log('resizing to', size);


			ws.send(send);
			fitAddon.fit(); // this code indeedd
		});

		terminal.onTitleChange(function(event) {
			console.log(event);
		});

		// Fit the terminal to the window size when the window is resized
		window.onresize = function() {
			fitAddon.fit();
		};
	};
})();