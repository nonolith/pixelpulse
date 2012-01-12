# Firmware update
# (C) 2011 Nonolith Labs
# Author: Kevin Mehall <km@kevinmehall.net>
# Distributed under the terms of the GNU GPLv3

app = (window.app ?= {})

app.init = (server, params) ->
	server.connect()

	server.disconnected.listen ->
		if not hasConnected
			console.log "Dataserver not detected"
		else
			console.log "Connection lost"

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
	
app.initBL = (dev) ->
	$(document.body).empty().append("Bootloader: " )
	
	$("<button>Reset</button>").appendTo(document.body).click ->
		dev.reset()
		
	indata = $("<div>").appendTo("body")
		
	te = $("<textarea>").appendTo(indata).change ->
		app.fw = JSON.parse(te.val())
		in_info.text("CRC: #{app.fw.crc}")
	
	in_info = $("<div>").appendTo(indata)
	
	outdata = $("<div>").appendTo("body")
	
	outLine = (t) ->
		$("<div>").text(t).appendTo(outdata)
	
	$("<button>App CRC</button>").appendTo(outdata).click ->
		dev.crcApp (m) ->
			outLine("App CRC: #{m.crc}")
	
	$("<button>Erase</button>").appendTo(outdata).click ->
		dev.erase (m) ->
			outLine("Erased")
			
	$("<button>Write</button>").appendTo(outdata).click ->
		dev.write app.fw.data, (m) ->
			outLine("Wrote flash, status #{m.result}")
			
	dev.changed.listen ->
		outLine("Connected: #{dev.hw_product} #{dev.hw_version}")

	window.d = dev
	
#URL params
params = {}
for pair in document.location.search.slice(1).split('&')
	[key,params[key]] = pair.split('=')

$(document).ready ->
	app.init(server, params)

