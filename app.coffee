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
		document.body.className = "connected"
		pixelpulse.overlay()
		hasConnected = yes

	server.disconnected.listen ->
		document.title = "Pixelpulse (Disconnected)"
		document.body.className = "disconnected"
		if not hasConnected
			pixelpulse.overlay "Dataserver not detected"
		else
			pixelpulse.overlay "Connection lost"

	server.deviceAdded.listen (d) ->
		console.info "device added", d
		if not server.device
			server.selectDevice(d)

			server.device.channelHandler (c) ->
				console.info "channel added"
				c.streamHandler (s) ->
					console.info "stream added"
					s = new pixelpulse.TileView(s)
					$('#timeseries').append(s.showTimeseries())
					
	server.captureStateChanged.listen (s) ->
		if s=='active'
			$('#startpause').removeClass('startbtn').addClass('stopbtn').attr('title', 'Pause')
		else
			$('#startpause').removeClass('stopbtn').addClass('startbtn').attr('title', 'Start')
			
	$('#startpause').click ->
		if server.captureState == 'active'
			server.pauseCapture()
		else
			server.startCapture()
				
			
		
#URL params
params = {}
for pair in document.location.search.slice(1).split('&')
	[key,params[key]] = pair.split('=')

hostname = params.server || document.location.host
window.graphmode = params.graphmode || 'canvas'
window.ygrid = params.ygrid != '0'
window.xbottom = params.xbottom ? false
window.canvas_clear_width = params.clrw

$(document).ready ->	
	if not params.timebar
		$('#timesection').hide()
		
	if not params.layouts
		$('#layout-sel').hide()
		
	if params.perfstat
		$('#perfstat').show()
		
	if params.demohint
		$('#info').show()
	
	pixelpulse.init(server, params)

