# Pixelpulse controller
# (C) 2011 Nonolith Labs
# Author: Kevin Mehall <km@kevinmehall.net>
# Distributed under the terms of the GNU GPLv3

pixelpulse = (window.pixelpulse ?= {})

pixelpulse.captureState = new Event()
pixelpulse.layoutChanged = new Event()

pixelpulse.overlay = (message) ->
	if not message
		$("#error-overlay").hide()
	else
		$("#error-overlay").fadeIn(300)
		$("#error-status").text(message)
		
pixelpulse.reset = ->
	pixelpulse.destroyView()
	
pixelpulse.chooseDevice = ->
	ndevices = server.devices.length
	for dev in server.devices
		# select the "first" device
		if dev.model == "com.nonolithlabs.cee"
			dev = server.selectDevice(server.devices[0])
			return pixelpulse.deviceSelected(dev)
	pixelpulse.overlay "No devices found"
		
pixelpulse.deviceSelected = (dev) ->
	pixelpulse.overlay("Loading Device...")
	dev.changed.listen ->
		pixelpulse.overlay()
		pixelpulse.reset()
		pixelpulse.captureState.notify(dev.captureState)
		pixelpulse.initView(dev)
	
	dev.removed.listen ->
		pixelpulse.reset()
		pixelpulse.chooseDevice()
		
	dev.captureStateChanged.listen (s) -> pixelpulse.captureState.notify(s)
		
pixelpulse.init = (server, params) ->
	if !window.WebSocket
		pixelpulse.overlay "Pixelpulse requires WebSockets and currently only works in Chrome and Safari"
		return

	server.connect()
	
	hasConnected = no
	
	server.connected.listen ->
		hasConnected = yes

	server.disconnected.listen ->
		if not hasConnected
			pixelpulse.overlay "Dataserver not detected"
		else
			pixelpulse.overlay "Connection lost"

	server.devicesChanged.listen (l) ->
		console.info "Device list changed", l
		
		if not server.device
			pixelpulse.chooseDevice()
				
pixelpulse.channelviews = []

#URL params
params = {}
for pair in document.location.search.slice(1).split('&')
	[key,params[key]] = pair.split('=')

$(document).ready ->
	if params.perfstat
		$('#perfstat').show()
		
	if params.demohint
		$('#info').show()
	
	pixelpulse.init(server, params)

