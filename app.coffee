# Pixelpulse controller
# (C) 2011 Nonolith Labs
# Author: Kevin Mehall <km@kevinmehall.net>
# Distributed under the terms of the GNU GPLv3

pixelpulse = (window.pixelpulse ?= {})

pixelpulse.init = (server, params) ->
	ts = $("#timeseries").get(0)
	meters = $("#meters").get(0)

	if !window.WebSocket
		document.getElementById('loading').innerHTML = "Pixelpulse requires WebSockets and currently only works in Chrome and Safari"
		return

	server.connect()
	 
	server.connected.listen ->
		document.title = "Pixelpulse (Connected)"
		document.body.className = "connected"
		$('#loading').hide()

	server.disconnected.listen ->
		document.title = "Pixelpulse (Disconnected)"
		document.body.className = "disconnected"
		$('#loading').text('Disconnected').show()

	server.deviceAdded.listen (d) ->
		console.info "device added", d
		if not server.device
			server.selectDevice(d)

			server.device.channelHandler (c) ->
				console.info "channel added"
				c.inputStreamHandler (s) ->
					console.info "stream added"
					s = new pixelpulse.TileView(s)
					$(meters).append(s.el)			
	
	# Init drag-and-drop
	handleDragOver = (self, e, draggedElem, draggableMatch, posFunc) ->
		if $(e.target).hasClass('insertion-cursor')
			# No need to do anything if dragging over the existing insertion highlight
			return e.preventDefault()
			
		tgt = $(e.target).closest(draggableMatch)
		
		getCursor = ->
			$(".insertion-cursor").remove()
			return $("<div class='insertion-cursor'>").addClass(window.draggedChannel.cssClass)
		
		if tgt.length
			if draggedElem == tgt.get(0)
				tgt.addClass('dnd-oldpos').hide().after(getCursor())
			if tgt.is('#timesection')
				if not tgt.parent().children('.insertion-cursor:last-child').length
					tgt.parent().append(getCursor())
			else if posFunc(tgt)
				if not tgt.prev().hasClass('insertion-cursor')
					tgt.before(getCursor())
			else
				if not tgt.next().hasClass('insertion-cursor')
					tgt.after(getCursor())
		else
			$(self).prepend(getCursor())
					
		e.preventDefault()
	
	ts.ondragover = (e) ->
		draggedElem = window.draggedChannel.showGraph and window.draggedChannel.tsRow.get(0)
		handleDragOver(this, e, draggedElem, 'section', (tgt) -> e.offsetY < tgt.get(0).offsetHeight/2)
		
	ts.ondrop = (e) ->
		cur = $(this).find(".insertion-cursor")
		if cur.length
			cur.replaceWith(window.draggedChannel.showTimeseries())

	meters.ondragover = (e) ->
		draggedElem = window.draggedChannel.tile.get(0)
		handleDragOver(this, e, draggedElem, '.meter', (tgt) -> e.offsetX < tgt.get(0).offsetWidth/2)
		
	meters.ondrop = (e) ->
		cur = $(this).find(".insertion-cursor")
		if cur.length
			cur.replaceWith(window.draggedChannel.hideTimeseries())
			
	meters.ondragend = ts.ondragend = (e) ->
		$('.insertion-cursor').remove()
		$('.dnd-oldpos').show().removeClass('dnd-oldpos')
			
		
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

