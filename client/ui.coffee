
class Channel
	constructor: (o) ->
		@name = o.name
		@id = o.id
		@unit = o.unit
		@editable = true
		@state = ''
		
		if @id == 'time'
			@axis = new livegraph.XAxis(@id, o.min, o.max)
			@showGraph = false
		else
			@axis = new livegraph.YAxis(@id, 'blue', o.min, o.max)
			@showGraph = o.showGraph
		
		@div = $("<div class='meter'>")
			.append((@h2 = $("<h2>")).text(@name))
			.append($("<span class='reading'>")
				.append(@input = $("<input>")))
			.append($("<span class='unit'>").text(@unit))
			.append(@stateElem = $("<small>"))
			.appendTo('#meters')
			
		@onState(o.state)	
			
		@input.change (e) =>
			@setValue(parseFloat($(@input).val(), 10))
			$(@input).blur()
			
		@input.click ->
			this.select()
		
		if @id != 'time'
			@div.get(0).draggable = true
			@div.get(0).ondragstart = (e) =>
				e.dataTransfer.setData('text/plain', @id)
				i = $("<div class='meter-drag'>").text(@id).appendTo('#hidden')
				e.dataTransfer.setDragImage(i.get(0), 0, 0)
				setTimeout((-> i.remove()), 0)
			
	onValue: (v) ->
		if !@input.is(':focus')
			@input.val(if Math.abs(v)>1 then v.toPrecision(4) else v.toFixed(3))
			if (v < 0)
				@input.addClass('negative')
			else
				@input.removeClass('negative')
				
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
		@graph = new livegraph.canvas(document.getElementById('graph'), {}, [])
		$(window).resize(@onResized)
		
		dnd_target(document.getElementById('meters-side'),@showChannel)
		dnd_target(document.getElementById('meters'),@collapseChannel)
		
		$(@graph.graphCanvas).mousedown (e) =>
			[x, y] = relMousePos(@graph.graphCanvas, e)
			if x > @graph.width - 50
				channel = @findChannelAtPos(x, y)
				if channel
					channel.setValue(channel.axis.invTransform(y))
					mousemove = (e) =>
						[x, y] = relMousePos(@graph.graphCanvas, e)
						ch = @findChannelAtPos(x, y)
						if ch != channel then return
						channel.setValue(channel.axis.invTransform(y))
					mouseup = =>
						$(document.body).unbind('mousemove', mousemove)
						                .unbind('mouseup', mouseup)
					$(document.body).mousemove(mousemove)
					$(document.body).mouseup(mouseup)
					
					
			
	findChannelAtPos: (x,y) ->
		for name, c of @channels
			if c.showGraph and y>c.axis.ytop and y<c.axis.ybottom
				return c
		return false
		
	onConfig: (o) ->
		$('#meters, #meters-side').empty()
		@channels = {}
		@graph.yaxes = []
		self = this
		for c in o
			n = new Channel(c)
			@channels[n.id] = n
			n.setValue = (v) -> self.setChannel(this.id, v)
			if n.id == 'time'
				@graph.xaxis = n.axis
	
			if n.showGraph
				@graph.yaxes.push(n.axis)
				$('#meters-side').append(n.div)
			else
				$('#meters').append(n.div)
			
		@onResized()
			
	onData: (data) ->
		for name, c of @channels
			if data[name]?
				c.onValue(data[name])
		@graph.pushData(data)
		
	onState: (channel, state) ->
		@channels[channel].onState(state)
		
	setChannel: (name, value) -> 
		console.error("setChannel should be overridden by transport")
		
	onResized: =>
		@graph.resized()
		for name, c of @channels
			if c.showGraph
				c.div.css('top', c.axis.ytop).css('height', c.axis.ybottom-c.axis.ytop)
				
	showChannel: (name) =>
		c = @channels[name]
		if not c then return
		if c.showGraph then return
		c.div.detach().attr('style', '').appendTo('#meters-side')
		c.showGraph = true
		@graph.yaxes.push(c.axis)
		@onResized()
	
	collapseChannel: (name) =>
		c = @channels[name]
		if not c then return
		if not c.showGraph then return
		c.div.detach().attr('style', '').appendTo('#meters')
		i = @graph.yaxes.indexOf(c.axis)
		if i!=-1 then @graph.yaxes.splice(i, 1)
		c.showGraph = false
		@onResized()
		
			

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
			},
			{
				'id': 'current',
				'name': 'Current',
				'unit': 'mA',
				'min': -200,
				'max': 200,
				'state': 'measure',
				'showGraph': true,
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

