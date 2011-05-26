
if !window.WebSocket
	document.getElementById('loading').innerHTML = "This demo requires WebSockets and currently only works in Chrome and Safari"

meters={}
metersByName = {}
graph = false
ws = false

channelSet = ->

addMeter = (m) ->
	metersByName[m.name] = m;
	m.div = $("<div>")
		.append(m.h2 = $("<h2>").text(m.displayname))
		.append($("<span class='reading'>")
			.append(m.input = $("<input>")))
		.append(m.unit = $("<span class='unit'>").text(m.units))
		.append($("<small>"))
		.appendTo('#meters')
	
	m.input.change (e) ->
		channelSet(m.name, parseFloat($(m.input).val(), 10))
		$(m.input).blur()
	
	m.input.click ->
		this.select()
	
	m.h2.get(0).draggable = true
	m.h2.get(0).ondragstart = (e) ->
		e.dataTransfer.setData('text/plain', m.name)


setup_dnd_target = (axisconfig) ->
	elem = axisconfig.labelDiv
	elem.ondragover = (e) ->
	 	e.preventDefault()

	elem.ondrop = (e) ->
		channel = e.dataTransfer.getData('text/plain')
		bindAxis(axisconfig, channel)
		e.preventDefault()
		return false

bindAxis = (axis, channel) ->
	meter=metersByName[channel]
	graph.setAxis(axis, meter.displayname + ' ('+meter.units+')', meter.name, meter.axisMin, meter.axisMax, axis.color)

updateAxis = (axisconfig, defaultchan) ->
	if !axisconfig.name || !meters[axisconfig.name]
		bindAxis(axisconfig, defaultchan);
	else
		bindAxis(axisconfig, axisconfig.name);

configChannels = (s) ->
	meters = s
	$('#meters').empty()
	
	for m in meters
		addMeter(m)

	graph.axes.yleft.color = 'blue'
	graph.axes.yright.color = 'red'
	updateAxis(graph.axes.xbottom, 'time')
	updateAxis(graph.axes.yleft, 'voltage')
	updateAxis(graph.axes.yright, 'current')

renderTime = 0
renders = 0
lastDriving = null

update = (data) ->
	for m in meters
		if data[m.name]?
			setInput(m.input, data[m.name])
		
		if data._driving != lastDriving
			if m.name == data._driving
				$(m.div).find('small').text("Source")
			else if m.name != 'time'
				$(m.div).find('small').text("Measure")
			else
				$(m.div).find('small').text("Live")
	
	t1 =new Date()
	graph.pushData(data)
	t2 = new Date()
	
	renderTime += t2 - t1
	renders++; 

if console
	setInterval((-> console.log('avg:', renderTime/renders); renderTime=renders=0), 5000);

#URL params

params = {}

for pair in document.location.search.slice(1).split('&')
	[key,params[key]] = pair.split('=')


hostname = params.server || document.location.host
window.graphmode = params.graphmode || 'canvas'

xspan = 30;
setup = false;

setInput = (input, number) ->
	if !input.is(':focus')
		input.val(number.toFixed(3))
		if (number < 0)
			input.addClass('negative')
		else
			input.removeClass('negative')
			
websocket_start = ->
	ws = new WebSocket("ws://" + hostname + "/dataws")
	 
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
		if m._action == 'update'
			if !setup
				$('#loading').hide()
				setup = true
			update(m)
		else if(m._action == 'config')
			configChannels(m.channels)
	
	ws.onclose = ->
		document.title = "Nonolith Client(Disconnected)"
		document.body.className = "disconnected"
		$('#loading').text('Disconnected').show()
		# setInterval(tryReconnect, 1000);
		
	channelSet = (chan, val) ->
		msg = {'_action':'set'}
		msg[chan] = val
		ws.send(JSON.stringify(msg))
		console.log('sent', chan)
		
virtualrc_start = ->
	$('#loading').hide()
	setup = true
	
	configChannels [
			{
				'name': 'time',
				'displayname': 'Time',
				'units': 's',
				'type': 'linspace',
				'axisMin': -30,
				'axisMax': 'auto',
			},
			{
				'name': 'voltage',
				'displayname': 'Voltage',
				'units': 'V',
				'type': 'device',
				'axisMin': -10,
				'axisMax': 10,
			},
			{
				'name': 'current',
				'displayname': 'Current',
				'units': 'mA',
				'type': 'device',
				'axisMin': -200,
				'axisMax': 200,
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
		result = {
			'time': t,
			'voltage': voltage,
			'current': current*1000.0,
			'_driving': source
		}
		
		update(result)
		
	channelSet = (chan, val) ->
		switch chan
			when 'voltage'
				voltage = val
			when 'current'
				current = val/1000
			else
				return
		source = chan
		
	
	setInterval(step, 80)
	

$(document).ready ->
	graph = new LiveGraph_canvas(document.getElementById('graph'))
	
	setup_dnd_target(graph.axes.xbottom)
	setup_dnd_target(graph.axes.yleft)
	setup_dnd_target(graph.axes.yright)

	if hostname == 'virtualrc'
		virtualrc_start()
	else
		websocket_start()
	$(window).resize -> graph.resized()

