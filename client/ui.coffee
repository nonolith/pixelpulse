
class Channel
	constructor: (o) ->
		@name = o.name
		@id = o.id
		@unit = o.unit
		@settable = o.settable
		@state = ''
		
		@createTile()
		
		if @id == 'time'
			@axis = new livegraph.XAxis(@id, o.min, o.max)
			@showGraph = false
			$("#timesection").append(@tile)
		else
			@axis = new livegraph.YAxis(@id, 'blue', o.min, o.max)
			if o.showGraph
				@showTimeseries().appendTo('#timeseries')
			else
				@showGraph = false
				$('#meters').append(@tile)
		
			
		@onState(o.state)
		
		
				
	createTile: ->
		return @tile if @tile
		
		@tile = $("<div class='meter'>")
			.append((@h2 = $("<h2>")).text(@name))
			.append($("<span class='reading'>")
				.append(@input = $("<input>")))
			.append($("<span class='unit'>").text(@unit))
			.append(@stateElem = $("<small>&nbsp;</small>"))
			.appendTo('#meters')
			
		@input.change (e) =>
			@setValue(parseFloat($(@input).val(), 10))
			$(@input).blur()
			
		@input.click ->
			this.select()
		
		if not @settable
			$(@input).attr('disabled', true)
			
		@tile.get(0).draggable = true
		@tile.get(0).ondragstart = (e) =>
			window.draggedChannel = this
			e.dataTransfer.setData('text/plain', @id)
			i = $("<div class='meter-drag'>").text(@id).appendTo('#hidden')
			e.dataTransfer.setDragImage(i.get(0), 0, 0)
			setTimeout((-> i.remove()), 0)
				
		return @tile
		
	showTimeseries: ->
		if @showGraph
			@tsRow.detach()
			return @tsRow
		
		@tsRow = $("<section>")
			.append(@graphDiv = $("<div class='livegraph'>"))
			.append(@tsAside = $("<aside>"))
		@graph = new livegraph.canvas(@graphDiv.get(0), app.channels.time.axis, [@axis])
		
		$(@graph.graphCanvas).mousedown (e) =>
			[x, y] = relMousePos(@graph.graphCanvas, e)
			if x > @graph.width - 50
				@setValue(@axis.invTransform(y))
				mousemove = (e) =>
					[x, y] = relMousePos(@graph.graphCanvas, e)
					@setValue(@axis.invTransform(y))
				mouseup = =>
					$(document.body).unbind('mousemove', mousemove)
					                .unbind('mouseup', mouseup)
				$(document.body).mousemove(mousemove)
				$(document.body).mouseup(mouseup)
		
		@tile.detach().attr('style', '').appendTo(@tsAside)
		@showGraph = true
		
		return @tsRow
	
	hideTimeseries: -> 
		if not @showGraph then return
		@tile.detach().attr('style', '').appendTo('#meters')
		@tsRow.remove()
		@showGraph = false
			
	onValue: (time, v) ->
		if !@input.is(':focus')
			@input.val(if Math.abs(v)>1 then v.toPrecision(4) else v.toFixed(3))
			if (v < 0)
				@input.addClass('negative')
			else
				@input.removeClass('negative')
		if @showGraph
			o = {time:time}
			o[@id] = v
			@graph.pushData(o) 
				
	onState: (s) ->
		@stateElem.text(s)
		if s=='source' or s=='set' or s=='output'
			@axis.grabDot = 'fill'
		else if s=='measure'
			@axis.grabDot = 'stroke'


relMousePos = (elem, event) ->
	o = $(elem).offset()
	return [event.pageX-o.left, event.pageY-o.top]

class LiveData
	constructor: ->
		@channels = {}
		
		ts = $("#timeseries").get(0)
		
		handleDragOver = (self, e, draggedElem, draggableMatch, posFunc) ->
			if $(e.target).hasClass('insertion-cursor')
				return e.preventDefault()
				
			tgt = $(e.target).closest(draggableMatch)
			
			if tgt.length
				if draggedElem == tgt.get(0)
					$(".insertion-cursor").remove()
					tgt.addClass('dnd-oldpos').hide().after("<div class='insertion-cursor'>")
				else if posFunc(tgt)
					if not tgt.prev().hasClass('insertion-cursor')
						$(".insertion-cursor").remove()
						tgt.before("<div class='insertion-cursor'>")
				else
					if not tgt.next().hasClass('insertion-cursor')
						$(".insertion-cursor").remove()
						tgt.after("<div class='insertion-cursor'>")
			else
				$(".insertion-cursor").remove()
				$(self).prepend("<div class='insertion-cursor'>")
						
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
			$('.dnd-oldpos').show().removeClass('.dnd-oldpos')
		
	onConfig: (o) ->
		$('#meters, #meters-side').empty()
		@channels = {}
		self = this
		for c in o
			n = new Channel(c)
			@channels[n.id] = n
			n.setValue = (v) -> self.setChannel(this.id, v)
			
	onData: (data) ->
		for name, c of @channels
			if data[name]?
				c.onValue(data.time, data[name])
		
	onState: (channel, state) ->
		@channels[channel].onState(state)
		
	setChannel: (name, value) -> 
		console.error("setChannel should be overridden by transport")
		
			

dnd_target = (elem, callback) ->
	elem.ondragover = (e) ->
	 	e.preventDefault()

	elem.ondrop = (e) ->
		data = e.dataTransfer.getData('text/plain')
		e.preventDefault()
		callback(data)
		return false
		
setup = false

#URL params
params = {}

for pair in document.location.search.slice(1).split('&')
	[key,params[key]] = pair.split('=')


hostname = params.server || document.location.host
window.graphmode = params.graphmode || 'canvas'


websocket_start = (host, app) ->
	if !window.WebSocket
		document.getElementById('loading').innerHTML = "This demo requires WebSockets and currently only works in Chrome and Safari"

	ws = new WebSocket("ws://" + host + "/dataws")
	 
	ws.onopen = ->
		document.title = "Nonolith Client (Connected)"
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
		document.title = "Nonolith Client(Disconnected)"
		document.body.className = "disconnected"
		$('#loading').text('Disconnected').show()
		# setInterval(tryReconnect, 1000);
		
	app.setChannel = (chan, val) ->
		msg = {'_action':'set'}
		msg[chan] = val
		ws.send(JSON.stringify(msg))
		
	
		
virtualrc_start = (app) ->
	$('#loading').hide()
	setup = true
	
	app.onConfig [
			{
				'id': 'time',
				'name': 'Time',
				'unit': 's',
				'min': -30,
				'max': 'auto',
				'state': 'live',
			},
			{
				'id': 'voltage',
				'name': 'Voltage',
				'unit': 'V',
				'min': -10,
				'max': 10,
				'state': 'source',
				'showGraph': true,
				'settable': true,
			},
			{
				'id': 'current',
				'name': 'Current',
				'unit': 'mA',
				'min': -200,
				'max': 200,
				'state': 'measure',
				'showGraph': true,
				'settable': true,
			},
			{
				'id': 'resistance',
				'name': 'Resistance',
				'unit': '\u03A9',
				'min': 0,
				'max': 10000,
				'state': 'computed',
			},
		]
		
	r = 100.0
	c = 100e-4
	q = 0.0
	
	source = 'voltage'
	
	voltage = current = 0
	lastTime = 0
	tstart = new Date()
	
	step = ->
		t = (new Date() - tstart) / 1000
		dt = lastTime-t
		switch source
			when 'current'
				voltage = q/c
			
				if (voltage>=10 and current<0) or (voltage<=-10 and current>0)
					current = 0
			
				q += current*dt
			when 'voltage'
				current = -(voltage-q/c)/r
				q += current*dt
			
		lastTime = t
		imp = Math.min(Math.abs(voltage/(current)), 9999)
		if isNaN(imp) then imp = 9999
		app.onData {
			'time': t,
			'voltage': voltage,
			'current': current*1000.0,
			'resistance':imp,
		}
		
		
	app.setChannel = (chan, val) ->
		switch chan
			when 'voltage'
				voltage = val
			when 'current'
				current = val/1000
			else
				return
		if source != chan
			source = chan
			switch source
				when 'voltage'
					app.onState('voltage', 'source')
					app.onState('current', 'measure')
				when 'current'
					app.onState('current', 'source')
					app.onState('voltage', 'measure')
					
	setInterval(step, 80)
	

$(document).ready ->
	window.app = new LiveData()
	
	if hostname == 'virtualrc' or document.location.protocol == 'file:'
		virtualrc_start(app)
	else
		websocket_start(hostname, app)

