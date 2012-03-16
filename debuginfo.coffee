# Firmware update
# (C) 2011 Nonolith Labs
# Author: Kevin Mehall <km@kevinmehall.net>
# Distributed under the terms of the GNU GPLv3

app = (window.app ?= {})

app.device = null

app.init = (server, params) ->
	server.connect()

	server.disconnected.listen ->
		$(document.body).html("
		<h1>Nonolith Connect not found</h1>
		<p>Make sure it is running or
		<a href='http://www.nonolithlabs.com/connect/'>Install it</a></p>
		<p>Platform: #{window.navigator.userAgent}</p>
		")

	server.connected.listen app.update
	server.devicesChanged.listen app.chooseDevice
	
app.chooseDevice = ->
	app.device = null
	for dev in server.devices
		if dev.model == 'com.nonolithlabs.cee'
			app.device = server.selectDevice(dev)
			app.device.changed.listen app.update
			return
	app.update()


hex = (n) ->
	t = n.toString(16)
	if t.length == 1
		t = '0'+t
	return t

app.update = ->
	e = $(document.body)
	e.empty()
	e.append("<h2>Nonolith Connect</h2>")
	$("<p>").text("Version: #{server.version}").appendTo(e)
	$("<p>").text("Platform: #{window.navigator.userAgent}").appendTo(e)
	if app.device
		$("<h2>").text("CEE").appendTo(e)
		$("<p>").text("hwVersion: #{app.device.hwVersion}").appendTo(e)
		$("<p>").text("fwVersion: #{app.device.fwVersion}").appendTo(e)
		$("<p>").text("serial: #{app.device.serial}").appendTo(e)
		$("<p>").text("EEPROM data:").appendTo(e)
		eepromStatus = $("<pre>loading</pre>").appendTo(e)
		eeprom = $("<pre></pre>").appendTo(e)
		
		app.device.controlTransfer 0xC0, 0xE0, 0, 0, data=[], wLength=64, (m) ->
			eepromStatus.text("Status #{m.status}")
			l = for i in [0...8]
				"#{hex(i*8)}: " + (hex(j) for j in m.data.slice(i*8, i*8+8)).join(" ")
			eeprom.text(l.join '\n')
			
	else
		$("<h2>").text("No devices found").appendTo(e)
		

$(document).ready ->
	$(document.body).append("<p>Platform: #{window.navigator.userAgent}</p>");
	if not window.WebSocket
		$(document.body).append("<p>Your browser does not support webSocket</p>")
	else
		$(document.body).append("<p>Loading....</p>")
	app.init(server)

