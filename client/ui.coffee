
if !window.WebSocket
	document.getElementById('loading').innerHTML = "This demo requires WebSockets and currently only works in Chrome and Safari"

meters={}
metersByName = {}
graph = false
ws = false

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
		msg = {'_action':'set'}
		msg[m.name] = parseFloat($(m.input).val(), 10)
		ws.send(JSON.stringify(msg))
		$(m.input).blur()
		console.log('sent', m.name)
	
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

$(document).ready ->
	graph = new LiveGraph_canvas(document.getElementById('graph'))
	
	setup_dnd_target(graph.axes.xbottom)
	setup_dnd_target(graph.axes.yleft)
	setup_dnd_target(graph.axes.yright)

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
	
	$(window).resize -> graph.resized()

