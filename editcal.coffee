# EEPROM editor
# (C) 2012 Nonolith Labs
# Author: Kevin Mehall <km@kevinmehall.net>
# Distributed under the terms of the GNU GPLv3

app = (window.app ?= {})

app.device = null

app.init = (server, params) ->
	server.connect()

	server.disconnected.listen ->
		$("section").html("
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
	e = $("section")
	e.empty()
	if app.device
		$("#p1").addClass("opened")
		$("<h1>").text("Edit Resistor Values").appendTo(e)
		$("<div>").append( \
		$("<p>").text("hwVersion: #{app.device.hwVersion}")).append( \
		$("<p>").text("fwVersion: #{app.device.fwVersion}")).append( \
		$("<p>").text("serial: #{app.device.serial}")).appendTo(e)

		$("""
		
		<div>
			<p>Channel A</p>
			<p><span>Currently: <output id=now_a></span>&Omega;</p>
			<p><label for=res_a>Resistor value:</label> <input type=text id=res_a value=.07 /></p>
		</div>
		
		<div>
			<p>Channel B</p>
			<p><span>Currently: <output id=now_b></span>&Omega;</p>
			<p><label for=res_b>Resistor value:</label> <input type=text id=res_b value=.07 /></p>
		</div>
		
		<div>
			<p>Power</p>
			<p><input type=checkbox id=extpower /> <label for=extpower>Device has cleared solder jumper and external power</label></p>
		</div>
		
		<nav><button class="btn primary" id="savebtn">Save to device</button></nav>
		
		""").appendTo(e)
		
		read = ->
			server.send 'readCalibration'
				id: server.createCallback (e) ->
					app.device.eeprom = e
					$("#now_a").text(app.device.eeprom.current_gain_a/45/100000)
					$("#now_b").text(app.device.eeprom.current_gain_b/45/100000)
					$("#extpower").get(0).checked = !(app.device.eeprom.flags&1)
		
		
		update = ->
			console.log('update')
			console.log(Math.round(parseFloat($('#res_a').val(),10)*45*100000,10))
			console.log(Math.round(parseFloat($('#res_b').val(),10)*45*100000,10))
		
		read()
		update()
		
		write = ->
			app.device.eeprom.current_gain_a = Math.round(parseFloat($("#res_a").val())*45*100000, 10)
			app.device.eeprom.current_gain_b = Math.round(parseFloat($("#res_b").val())*45*100000, 10)
			usbpower = not $("#extpower").is(':checked')
			app.device.eeprom.flags = app.device.eeprom.flags&(~1) | usbpower
			
			app.device.eeprom.id = server.createCallback ->
				alert("EEPROM written. Unplug and replug the CEE to make it take effect.")
				read()
			
			server.send 'writeCalibration', app.device.eeprom
			app.device.eeprom = null
			
		$("#savebtn").click(write)
				
			
	else
		$("<h1>").text("No devices found").appendTo(e)
		

$(document).ready ->
	$("section").append("<p>Platform: #{window.navigator.userAgent}</p>");
	if not window.WebSocket
		$("section").append("<p>Your browser does not support webSocket</p>")
	else
		$("section").append("<p>Loading....</p>")
	app.init(server)

