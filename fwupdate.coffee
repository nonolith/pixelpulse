# Firmware update
# (C) 2011 Nonolith Labs
# Author: Kevin Mehall <km@kevinmehall.net>
# Distributed under the terms of the GNU GPLv3

app = (window.app ?= {})

app.init = (server, params) ->
	server.connect()

	server.disconnected.listen ->
		$(document.body).html("Disconnected")

	server.devicesChanged.listen (l) ->
		app.chooseDevice()
		
	app.chooseDevice()
		
app.chooseDevice = ->
	for dev in server.devices
		if dev.model == 'com.nonolithlabs.cee'
			return app.initCEE(server.selectDevice(dev))
		else if dev.model == 'com.nonolithlabs.bootloader'
			return app.initBL(server.selectDevice(dev))
	$(document.body).html("No devices")

app.initCEE = (dev) ->
	b = $("<button>Enter bootloader</button>").click ->
		server.send 'enterBootloader'
	$(document.body).empty().append("CEE: " ).append(b)
	window.d = dev

app.erase = (cb) ->
	server.device.erase (m) ->
		outLine("Erased")
		if $.isFunction(cb) then cb()
		
app.checkCRC = (cb) ->
	server.device.crcApp (m) ->
		valid = (m.crc == app.fw.crc)
		vs = if valid then 'Valid' else 'INVALID'
		console.log(m.crc, app.fw.crc)
		outLine("App CRC: #{m.crc} - #{vs}")
		if valid and $.isFunction(cb) then cb()

app.write = (cb) ->
	server.device.write app.fw.data, (m) ->
		outLine("Wrote flash, status #{m.result}")
		if $.isFunction(cb) then cb()

app.flash_and_check = ->
	app.erase ->
		app.write ->
			app.checkCRC ->
				server.device.reset()

outdata = null
outLine = (t) ->
	$("<div>").text(t).appendTo(outdata)
	
app.initBL = (dev) ->
	$(document.body).empty().append("Bootloader: " )
	
	$("<button>Reset</button>").appendTo(document.body).click ->
		dev.reset()
		
	indata = $("<div>").appendTo("body")
		
	te = $("<textarea>").appendTo(indata).change ->
		app.fw = JSON.parse(te.val())
		in_info.text("CRC: #{app.fw.crc}")
		
	$.get 'cee.json', (data) ->
		te.val(data)
		te.change()
		
		if params.auto
			app.flash_and_check()
		
	outdata = $("<div>").appendTo("body")
	
	in_info = $("<div>").appendTo(indata)

	$("<button>App CRC</button>").appendTo(outdata).click(app.checkCRC)
	
	$("<button>Erase</button>").appendTo(outdata).click(app.erase)
			
	$("<button>Write</button>").appendTo(outdata).click(app.write)
	
	$("<button>Write, check, and reset</button>").appendTo(outdata).click(app.flash_and_check)
			
	dev.changed.listen ->
		outLine("Connected: #{dev.hw_product} #{dev.hw_version}")

	window.d = dev
	
#URL params
params = {}
for flag in document.location.hash.slice(1).split('&')
	params[flag]=true

$(document).ready ->		
	app.init(server, params)

