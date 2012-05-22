# EEPROM editor
# (C) 2012 Nonolith Labs
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

SCALE = 100000

app.update = ->
	e = $(document.body)
	e.empty()
	if app.device
		$("<h2>").text("Edit EEPROM").appendTo(e)
		$("<p>").text("hwVersion: #{app.device.hwVersion}").appendTo(e)
		$("<p>").text("fwVersion: #{app.device.fwVersion}").appendTo(e)
		$("<p>").text("serial: #{app.device.serial}").appendTo(e)

		$("""
		
		<div>
			<h3>Channel A</h3>
			<p>Currently: <output id=now_a></p>
			<label for=csa_a>CSA gain: </label><input type=text id=csa_a value=45 /> &times;
			<label for=res_a>Resistor value:</label> <input type=text id=res_a value=.07 /> &times #{SCALE} =
			<input type=text id=out_a />
		</div>
		
		<div>
			<h3>Channel B</h3>
			<p>Currently: <output id=now_b></p>
			<label for=csa_b>CSA gain: </label><input type=text id=csa_b value=45 /> &times;
			<label for=res_b>Resistor value:</label> <input type=text id=res_b value=.07 /> &times #{SCALE} = 
			<input type=text id=out_b />
		</div>
		
		<div>
			<h3>Power</h3>
			<input type=checkbox id=extpower /> <label for=extpower>Device has external power</label>
		</div>
		
		<p>
		<button id='savebtn'>Save to device</button>
		</p>
		
		""").appendTo(e)
		
		read = ->
			server.send 'readCalibration'
				id: server.createCallback (e) ->
					app.device.eeprom = e
					$("#now_a").text(app.device.eeprom.current_gain_a)
					$("#now_b").text(app.device.eeprom.current_gain_a)
					$("#extpower").get(0).checked = !(app.device.eeprom.flags&1)
		
		
		update = ->
			console.log('update')
			$("#out_a").val(Math.round(parseFloat($('#csa_a').val(),10)*parseFloat($('#res_a').val(),10)*SCALE))
			$("#out_b").val(Math.round(parseFloat($('#csa_b').val(),10)*parseFloat($('#res_b').val(),10)*SCALE))
		
		read()
		update()
		
		$("#csa_a,#csa_b,#res_a,#res_b").change(update)
		
		write = ->
			app.device.eeprom.current_gain_a = Math.round(parseFloat($("#out_a").val()), 10)
			app.device.eeprom.current_gain_b = Math.round(parseFloat($("#out_a").val()), 10)
			usbpower = not $("#extpower").is(':checked')
			app.device.eeprom.flags = app.device.eeprom.flags&(~1) | usbpower
			
			app.device.eeprom.id = server.createCallback ->
				alert("EEPROM written. Unplug and replug the CEE to make it take effect.")
				read()
			
			server.send 'writeCalibration', app.device.eeprom
			app.device.eeprom = null
			
		$("#savebtn").click(write)
				
			
	else
		$("<h2>").text("No devices found").appendTo(e)
		

$(document).ready ->
	$(document.body).append("<p>Platform: #{window.navigator.userAgent}</p>");
	if not window.WebSocket
		$(document.body).append("<p>Your browser does not support webSocket</p>")
	else
		$(document.body).append("<p>Loading....</p>")
	app.init(server)

