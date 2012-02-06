# Pixelpulse controller
# (C) 2011 Nonolith Labs
# Author: Kevin Mehall <km@kevinmehall.net>
# Distributed under the terms of the GNU GPLv3

pixelpulse = (window.pixelpulse ?= {})

pixelpulse.captureState = new Event()
pixelpulse.layoutChanged = new Event()
pixelpulse.triggeringChanged = new Event()

pixelpulse.overlay = (message) ->
	if not message
		$("#error-overlay").hide()
	else
		$("#error-overlay").children().hide()
		$("#error-status").show().text(message)
		$("#error-overlay").fadeIn(300)
		
pixelpulse.reset = ->
	pixelpulse.triggering = false
	$(document.body).removeClass('triggering')
	pixelpulse.destroyView()
	
pixelpulse.chooseDevice = ->
	if server.ceeDevs.length == 1
		pixelpulse.initDevice(server.ceeDevs[0])
	else if server.ceeDevs.length > 1
		pixelpulse.showDeviceChooser()
	else
		pixelpulse.overlay "No devices found"
		
pixelpulse.showDeviceChooser = ->
	$("#error-overlay").children().hide()
	$('#chooseDevices').show()
	
	ul = $('#chooseDevices ul').empty()
	for d in server.ceeDevs then do (d) ->
		ul.append $("<li>").text(d.serial).click ->
			pixelpulse.initDevice(d)
	
	$('#error-overlay').fadeIn(300)
	
pixelpulse.updateDevsMenu = (l) ->
	$('#switchDev').toggle(l.length>1)
		
pixelpulse.initDevice = (dev) ->
	if server.device and dev.id == server.device.id
		pixelpulse.overlay()
		return
		
	pixelpulse.overlay("Loading Device...")
	dev = server.selectDevice(dev)
	dev.changed.listen ->
		pixelpulse.overlay()
		pixelpulse.reset()
		pixelpulse.initView(dev)
		pixelpulse.captureState.notify(dev.captureState)
	
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
		$("#error-overlay").children().hide()
		$('#connectError').show()
		$('#error-overlay').fadeIn(300)

	server.devicesChanged.listen (l) ->
		console.info "Device list changed", l
		server.ceeDevs = (d for d in server.devices when d.model == 'com.nonolithlabs.cee')
		pixelpulse.updateDevsMenu(server.ceeDevs)
		
		if not server.device
			pixelpulse.chooseDevice()
				
pixelpulse.channelviews = []

#URL params
params = {}
for flag in document.location.hash.slice(1).split('&')
	params[flag]=true

console.log('l', navigator.userAgent.indexOf("Linux") >= 0)
if navigator.userAgent.indexOf("Windows") >= 0 then $(document.body).addClass('os-windows')
if navigator.userAgent.indexOf("Linux") >= 0  then $(document.body).addClass('os-linux')
if navigator.userAgent.indexOf("Mac") >= 0 then $(document.body).addClass('os-mac')

$(document).ready ->
	if params.perfstat
		$('#perfstat').show()
		
	if params.demohint
		$('#info').show()
		
	if params.nowebgl
		window.nowebgl=true
	
	pixelpulse.init(server, params)

