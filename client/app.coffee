# Pixelpulse browser UI
# Distributed under the terms of the BSD License
# (C) 2011 Kevin Mehall (Nonolith Labs) <km@kevinmehall.net>
# (C) 2011 Ian Daniher (Nonolith Labs) <ian@nonolithlabs.com>

class PixelpulseApp
	constructor: ->
		@channels = {}
		@data = []
		
		ts = $("#timeseries").get(0)
		
		@perfstat_count = 0
		@perfstat_acc = 0
		
		handleDragOver = (self, e, draggedElem, draggableMatch, posFunc) ->
			if $(e.target).hasClass('insertion-cursor')
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
				ts = $("#timeseries").get(0)
		
		
		mp = $('#meters').get(0)
		
		mp.ondragover = (e) ->
			draggedElem = window.draggedChannel.tile.get(0)
			handleDragOver(this, e, draggedElem, '.meter', (tgt) -> e.offsetX < tgt.get(0).offsetWidth/2)
			
		mp.ondrop = (e) ->
			cur = $(this).find(".insertion-cursor")
			if cur.length
				window.draggedChannel.hideTimeseries()
				cur.replaceWith(window.draggedChannel.tile)
				
		mp.ondragend = ts.ondragend = (e) ->
			$('.insertion-cursor').remove()
			$('.dnd-oldpos').show().removeClass('dnd-oldpos')
		
	onConfig: (o) ->
		$('.analog').remove()
		$('#meters, #meters-side').empty()
		@channels = {}
		self = this
		for c in o
			if c.id == 'time'
				n = new TimeChannel(c)
			else if c.type == 'digital'
				n = new DigitalChannel(c)
			else
				n = new AnalogChannel(c)
			@channels[n.id] = n
			n._setValue = (v, s) -> self.setChannel(this.id, v, s)
			
	onData: (data) ->
		if params.perfstat
			t1 = new Date()
		@data.push(data)
		for name, c of @channels
        	if data[name]? then c.onValue(data.time, data[name])
		if params.perfstat
			t2 = new Date()
			@perfstat_acc += t2-t1
			if (@perfstat_count += 1) == 25
				$('#perfstat').text(@perfstat_acc / 25 + "ms/render")
				@perfstat_acc = @perfstat_count = 0
		
	onState: (channel, state) ->
		@channels[channel].onState(state)
		
	setChannel: (name, value, state) -> 
		console.error("setChannel should be overridden by transport")
		
class Channel
	constructor: (o) ->
		@name = o.name
		@id = o.id
		@settable = o.settable
		@stateOptions = o.stateOptions
				
	createTile: ->
		return @tile if @tile
		
		@tile = $("<div class='meter'>").append((@h2 = $("<h2>")).text(@name))
		@addReadingUI(@tile)
		@tile.append(@stateElem = dropdownButton(@stateOptions, @setState))
		@stateElem.addClass('state')
		
		@tile.attr("title", "Drag and drop to rearrange")
		@tile.get(0).draggable = true
		@tile.get(0).ondragstart = (e) =>
			window.draggedChannel = this
			e.dataTransfer.setData('application/x-nonolith-channel-id', @id)
			i = $("<div class='meter-drag'>").text(@id).appendTo('#hidden')
			e.dataTransfer.setDragImage(i.get(0), 0, 0)
			setTimeout((-> i.remove()), 0)
				
		return @tile
		
	showTimeseries: ->
		if @showGraph
			@tsRow.detach()
			return @tsRow
		
		@tsRow = $("<section>")
			.addClass(@cssClass)
			.append(@graphDiv = $("<div class='livegraph'>"))
			.append(@tsAside = $("<aside>"))
			
		@graph = new livegraph.canvas(@graphDiv.get(0), app.channels.time.axis, @axis, app.data, [@series])
		
		$(@graph.graphCanvas).mousedown (e) =>
			[x, y] = relMousePos(@graph.graphCanvas, e)
			if x > @graph.width - 60
				$(document.body).css('cursor', 'row-resize')
				@setValue(@axis.invYtransform(y, @graph.geom))
				mousemove = (e) =>
					[x, y] = relMousePos(@graph.graphCanvas, e)
					@setValue(@axis.invYtransform(y, @graph.geom))
				mouseup =  ->
					$(document.body).unbind('mousemove', mousemove)
					                .unbind('mouseup', mouseup)
					                .unbind('mouseout', mouseout)
					                .css('cursor', 'auto')
				mouseout = (e) ->
					if e.relatedTarget.nodeName == 'HTML'
						mouseup()
						
				$(document.body).mousemove(mousemove)
				                .mouseup(mouseup)
				                .mouseout(mouseout)
		
		@tile.detach().attr('style', '').appendTo(@tsAside)
		@showGraph = true
		
		return @tsRow
	
	hideTimeseries: -> 
		if not @showGraph then return
		@tile.detach().attr('style', '').appendTo('#meters')
		@tsRow.remove()
		@showGraph = false
		@graph = false
							
	onState: (s) ->
		@stateElem.set(s)
		if s=='source' or s=='set' or s=='output'
			@series.grabDot = 'fill'
		else if 'source' in @stateOptions or 'output' in @stateOptions
			@series.grabDot = 'stroke'
			
	addToUI: (o) ->
		if o.showGraph
			@showTimeseries().appendTo('#timeseries')
		else
			@showGraph = false
			$('#meters').append(@tile)
		@onState(o.state)
		
	setValue: (v) ->
		outState = 'output'
		if 'source' in @stateOptions
			outState = 'source'
		@_setValue(v, outState)
		
	setState: (s) =>
		@_setValue(null, s)
		
	onValue: (t, v) ->
		if @showGraph
			@graph.redrawGraph()
			
class DigitalChannel extends Channel
	cssClass: 'digital'
	constructor: (o) ->
		super(o)
		@hasPullUp = o.hasPullUp
		@createTile()
		@axis = livegraph.digitalAxis
		@series = new livegraph.Series('time', @id, o.color, 'line')
		@addToUI(o)
		@value = 0
		
	addReadingUI: (tile) ->
		tile.append @reading = $("<span class='reading'>")
		
		if @settable
			@reading.attr("title", "Click to toggle")
		
		@reading.mouseup =>
			@setValue(!@value)
				
	onValue: (time, v) ->
		@value = v
		@reading.text(if v then "HIGH" else "LOW")
		super(time, v)

class AnalogChannel extends Channel
	cssClass: 'analog'
	constructor: (o) ->
		super(o)
		@unit = o.unit
		@createTile()
		@axis = new livegraph.Axis(o.min, o.max)
		@series = new livegraph.Series('time', @id, o.color, 'line')
		@addToUI(o)
		
	addReadingUI: (tile) ->
		tile.append($("<span class='reading'>")
			.append(@input = $("<input>"))
			.append($("<span class='unit'>").text(@unit)))
		
		if not @settable
			$(@input).attr('disabled', true)
		else
		@input.change (e) =>
			@setValue(parseFloat($(@input).val(), 10))
			$(@input).blur()
			
		@input.click ->
			this.select()
			
	onValue: (time, v) ->
		if !@input.is(':focus')
			@input.val(if Math.abs(v)>1 then v.toPrecision(4) else v.toFixed(3))
			if (v < 0)
				@input.addClass('negative')
			else
				@input.removeClass('negative')
		super(time, v)
		
	setvalue: (v) ->
		super(Math.min(Math.max(v, @axis.min), @axis.max))

class TimeChannel extends AnalogChannel
	constructor: (o) ->
		Channel.call(this, o)
		
		@createTile()
		
		@axis = new livegraph.Axis(o.min, o.max)
		@showGraph = false
		$("#timesection").append(@tile)
		
	onValue: (time, v) ->
		if params.timebar then super(time, v)
		

relMousePos = (elem, event) ->
	o = $(elem).offset()
	return [event.pageX-o.left, event.pageY-o.top]

dropdownButton = (options, callback) ->
	r = $("<div class='dropdownButton'>").delegate 'a', 'click', (e) ->
			if not $(this).siblings().length then return
			if not $(this).is(':first-child')
				$(this).detach().prependTo(d)
				callback($(this).text())
			else if not r.hasClass('opened')
				r.addClass('opened')
				$(document.body).one 'click', ->
					r.removeClass('opened')
				e.stopPropagation()
	d = $('<div>').appendTo(r)

	for i in options
		$("<a>").text(i).appendTo(d)
				
	r.set = (option) ->
		d.children().each ->
			if $(this).text() == option
				$(this).remove()
		d.prepend($("<a>").text(option))
		
	return r

		
setup = false

#URL params
params = {}
for pair in document.location.search.slice(1).split('&')
	[key,params[key]] = pair.split('=')

hostname = params.server || document.location.host
window.graphmode = params.graphmode || 'canvas'
window.ygrid = params.ygrid != '0'
window.xbottom = params.xbottom ? false
window.canvas_clear_width = params.clrw

websocket_start = (host, app) ->
	if !window.WebSocket
		document.getElementById('loading').innerHTML = "Pixelpulse requires WebSockets and currently only works in Chrome and Safari"

	ws = new WebSocket("ws://" + host + "/dataws")
	 
	ws.onopen = ->
		document.title = "Pixelpulse (Connected)"
		document.body.className = "connected"
		
		$('#loading').text("Waiting for data...")
		setup = false
		if reconnectTimer
			reconnectTimer = false
			clearInterval(reconnectTimer)
	
	ws.onmessage = (evt) ->
		m = JSON.parse(evt.data)
		switch m._action
			when 'update'
				if !setup
					$('#loading').hide()
					setup = true
				app.onData(m)
			when 'config'
				app.onConfig(m.channels)
			when 'state'
				app.onState(m.channel, m.state)
	
	ws.onclose = ->
		document.title = "Pixelpulse (Disconnected)"
		document.body.className = "disconnected"
		$('#loading').text('Disconnected').show()
		# setInterval(tryReconnect, 1000);
		
	app.setChannel = (chan, val, state) ->
		msg = {'_action':'set', channel:chan, value:val, state:state}
		ws.send(JSON.stringify(msg))
		

$(document).ready ->
	window.app = new PixelpulseApp()
	
	if not params.timebar
		$('#timesection').hide()
		
	if not params.layouts
		$('#layout-sel').hide()
		
	if params.perfstat
		$('#perfstat').show()
		
	if params.demohint
		$('#info').show()
	
	if hostname == 'virtualrc' or document.location.protocol == 'file:'
		virtualrc_start(app)
	else
		websocket_start(hostname, app)

