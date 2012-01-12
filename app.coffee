# Pixelpulse controller
# (C) 2011 Nonolith Labs
# Author: Kevin Mehall <km@kevinmehall.net>
# Distributed under the terms of the GNU GPLv3

pixelpulse = (window.pixelpulse ?= {})

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
	console.info "Selected device", dev
	pixelpulse.overlay("Loading Device...")
	dev.changed.listen ->
		pixelpulse.overlay()
		console.info "device updated", dev
		pixelpulse.reset()
		pixelpulse.onCaptureStateChange(dev.captureState)
		pixelpulse.channelviews = []
		pixelpulse.initView(dev)
		i = 0
		for chId, channel of dev.channels
			s = new pixelpulse.ChannelView(channel, i++)
			pixelpulse.channelviews.push(s)
			$('#streams').append(s.el)
		pixelpulse.finishViewInit()
	
	dev.removed.listen ->
		pixelpulse.reset()
		pixelpulse.chooseDevice()
		
	dev.captureStateChanged.listen pixelpulse.onCaptureStateChange
		
pixelpulse.onCaptureStateChange = (s) ->
	if s
		$('#startpause').removeClass('startbtn').addClass('stopbtn').attr('title', 'Pause')
	else
		$('#startpause').removeClass('stopbtn').addClass('startbtn').attr('title', 'Start')
	

pixelpulse.init = (server, params) ->
	ts = $("#timeseries").get(0)
	meters = $("#meters").get(0)

	if !window.WebSocket
		pixelpulse.overlay "Pixelpulse requires WebSockets and currently only works in Chrome and Safari"
		return

	server.connect()
	
	hasConnected = no
	
	server.connected.listen ->
		document.title = "Pixelpulse (Connected)"
		hasConnected = yes

	server.disconnected.listen ->
		document.title = "Pixelpulse (Disconnected)"
		if not hasConnected
			pixelpulse.overlay "Dataserver not detected"
		else
			pixelpulse.overlay "Connection lost"

	server.devicesChanged.listen (l) ->
		console.info "Device list changed", l
		
		if not server.device
			pixelpulse.chooseDevice()
			
	$('#startpause').click ->
		if server.device.captureState
			server.device.pauseCapture()
		else
			server.device.startCapture()
				
pixelpulse.channelviews = []			
		
#URL params
params = {}
for pair in document.location.search.slice(1).split('&')
	[key,params[key]] = pair.split('=')

$(document).ready ->	
	if not params.timebar
		$('#timesection').hide()
		
	if params.perfstat
		$('#perfstat').show()
		
	if params.demohint
		$('#info').show()
	
	pixelpulse.init(server, params)

