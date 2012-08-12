app = window.app =
	findDevice: (model = 'com.nonolithlabs.cee') ->
		server.connect()

		server.disconnected.listen ->
			$(".error").show().html "
			<h1>Nonolith Connect not found</h1>
			<div> <p>Make sure it is running or
			<a href='http://www.nonolithlabs.com/connect/'>Install it</a></p> </div>
			"

		app.noDevices()

		server.devicesChanged.listen ->
			console.log 'devicesChanged'
			if app.device
				for dev in server.devices
					return if dev.id == app.device.id
			for dev in server.devices	
				if dev.model == model
					app.device = server.selectDevice(dev)
					app.device.changed.listen app.update
					return
			app.noDevices()

	update: ->
		initView()

	noDevices: ->
		console.log('noDevices')

tdata = null
time_axis = value_axis = null
step_plot = imp_plot = null

stepTimeRatio = 0.25

source = null
sense = null

sweepCount = 0

listener = null
v1 = 0
v2 = 5

sampleScale = 128

window.nowebgl = true
		
initView = ->
	$('#with_device').show()

	time_axis = new livegraph.Axis(-0.005, 0.015)
	value_axis = new livegraph.Axis(0, 5)
	diff_axis = new livegraph.Axis(-0.5, 0.5)
	
	source = 
		stream: app.device.channels.a.streams.v
		acc: null
		step_series: new livegraph.Series([], [], [0, 0, 255])
		imp_series:  new livegraph.Series([], [], [0, 0, 255])
		
	sense = 
		stream: app.device.channels.b.streams.v
		acc: null
		step_series: new livegraph.Series([], [], [255, 0, 0])
		imp_series:  new livegraph.Series([], [], [255, 0, 0])
	
	step_plot = new livegraph.canvas(
		$('#step_plot').get(0), 
		time_axis, value_axis,
		[source.step_series, sense.step_series]
		{xbottom:yes, yright:no, xgrid:yes}
	)
	
	imp_plot = new livegraph.canvas(
		$('#impulse_plot').get(0), 
		time_axis, diff_axis,
		[source.imp_series, sense.imp_series]
		{xbottom:yes, yright:no, xgrid:yes}
	)	
	
vDiff = (inArray, outArray) ->
	for i in [0...inArray.length-1]
		outArray[i] = inArray[i+1] - inArray[i]
	return

vAccumulate = (inArray, outArray) ->
	for i in [0...inArray.length]
		outArray[i] += inArray[i]
	return
	
vMul = (inArray, outArray, fac) ->
	for i in [0...inArray.length]
		outArray[i] = inArray[i] * fac
	return
		
dataTimeout = null
start = ->
	app.device.startCapture()

	sweepCount = 0

	sampleTime = app.device.sampleTime

	time_axis.visibleMin = time_axis.min = - sampleScale * stepTimeRatio * sampleTime
	time_axis.visibleMax = time_axis.max = sampleScale * (1-stepTimeRatio) * sampleTime
	tdata = arange(time_axis.min, time_axis.max, app.device.sampleTime)

	initSignal = (s) ->
		s.step_series.xdata = tdata
		s.imp_series.xdata = tdata

		s.step_series.ydata = new Float32Array(sampleScale)
		s.imp_series.ydata = new Float32Array(sampleScale-1)

		s.acc = new Float32Array(sampleScale)

	initSignal(source)
	initSignal(sense)

	if source.stream.parent != sense.stream.parent
		sense.stream.parent.setConstant(0, 0)

	step_plot.needsRedraw(true)
	imp_plot.needsRedraw(true)

	source.stream.parent.set source.stream.outputMode, 'arb',
		{values: [
			{t:0, v:v1}
			{t:stepTimeRatio * sampleScale, v:v1}
			{t:stepTimeRatio * sampleScale, v:v2}
			{t:1    * sampleScale, v:v2}
			{t:1.25 * sampleScale, v:v1}
			{t:2  * sampleScale, v:v1}
		]
		repeat: -1},
		(d) ->
			console.log 'set arb', d
			listener = new server.DataListener(app.device, [source.stream, sense.stream])
			#listener.configure()
			listener.startSample = d.startSample + 1
			listener.len = listener.count = sampleScale
			listener.decimateFactor = 1
			listener.trigger = 
				type: 'out'
				stream: source.stream
				holdoff: 0
				offset: 0
				force: 0
			listener.submit()
			listener.sweepDone.listen handleData



handleData = ->
	#console.log('handleData', listener.startMessage)
	[data1, data2] = listener.data

	sweepCount += 1

	processSignal = (s, d) ->
		vAccumulate(d, s.acc)
		vMul(s.acc, s.step_series.ydata, 1/sweepCount)
		vDiff(s.step_series.ydata, s.imp_series.ydata)

	processSignal(source, listener.data[0])
	processSignal(sense,  listener.data[1])
	
	step_plot.needsRedraw()
	imp_plot.needsRedraw()

stop = ->
	app.device.pauseCapture()
	listener.cancel()

$(document).ready ->
	app.findDevice()

	$('#start').click(start)
	$('#stop').click(stop)

