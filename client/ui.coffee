
class Channel
	constructor: (o) ->
		@name = o.name
		@displayName = o.displayname
		@unit = o.units
		@editable = true
		@state = ''
		
		if @name == 'time'
			@axis = new livegraph.XAxis(@name, o.axisMin, o.axisMax)
			@showGraph = false
		else
			@axis = new livegraph.YAxis(@name, 'blue', o.axisMin, o.axisMax)
			@showGraph = true
		
		@div = $("<div class='meter'>")
			.append((@h2 = $("<h2>")).text(@displayName))
			.append($("<span class='reading'>")
				.append(@input = $("<input>")))
			.append($("<span class='unit'>").text(@unit))
			.append(@stateElem = $("<small>").text(o.state))
			.appendTo('#meters')	
			
		@input.change (e) =>
			@setValue(parseFloat($(@input).val(), 10))
			$(@input).blur()
			
		@input.click ->
			this.select()
			
		@div.get(0).draggable = true
		@div.get(0).ondragstart = (e) =>
			e.dataTransfer.setData('text/plain', @name)
			i = $("<div class='meter-drag'>").text(@displayName).appendTo('#hidden')
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

class LiveData
	constructor: ->
		@channels = {}
		@graph = new livegraph.canvas(document.getElementById('graph'), {}, [])
		$(window).resize(@onResized)
		
	onConfig: (o) ->
		$('#meters, #meters-side').empty()
		@channels = {}
		@graph.yaxes = []
		self = this
		for c in o
			n = new Channel(c)
			@channels[n.name] = n
			n.setValue = (v) -> self.setChannel(this.name, v)
			if n.name != 'time'
				@graph.yaxes.push(n.axis)
			else
				@graph.xaxis = n.axis
				
			if n.showGraph
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
		
			

setup_dnd_target = (elem, callback) ->
	elem.ondragover = (e) ->
	 	e.preventDefault()

	elem.ondrop = (e) ->
		channel = e.dataTransfer.getData('text/plain')
		console.log(channel, e.dataTransfer)
		e.preventDefault()
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
				app.onState(m.chan, m.state)
	
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
				'name': 'time',
				'displayname': 'Time',
				'units': 's',
				'type': 'linspace',
				'axisMin': -30,
				'axisMax': 'auto',
				'state': 'live',
			},
			{
				'name': 'voltage',
				'displayname': 'Voltage',
				'units': 'V',
				'type': 'device',
				'axisMin': -10,
				'axisMax': 10,
				'state': 'source',
			},
			{
				'name': 'current',
				'displayname': 'Current',
				'units': 'mA',
				'type': 'device',
				'axisMin': -200,
				'axisMax': 200,
				'state': 'measure',
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
		app.onData {
			'time': t,
			'voltage': voltage,
			'current': current*1000.0,
		}
		
		
	app.setChannel = (chan, val) ->
		console.log('setChannel', chan, val)
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
					
	setInterval(step, 100)
	

$(document).ready ->
	window.app = new LiveData()
	
	if hostname == 'virtualrc'
		virtualrc_start(app)
	else
		websocket_start(hostname, app)
		
	setup_dnd_target(document.getElementById('meters-side'))
