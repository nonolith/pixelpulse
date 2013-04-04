window.nowebgl = true
divider = 100
targetSampleTime = 1/40e3
sampleCt = (1/targetSampleTime)/divider

class App

	constructor: ->
		@current_axis = new livegraph.Axis(-200, 200, 'i')
		@voltage_axis = new livegraph.Axis(-5, 5, 'v')
		@current_axis.visibleMin = @current_axis.min = -200
		@current_axis.visibleMax = @current_axis.max = 200
		@curve_trace_data = new livegraph.Series([], [], [0, 0, 255])
		
		@vd = new Float32Array(sampleCt)
		@id = new Float32Array(sampleCt)
			
		@curve_trace = new livegraph.canvas(
			$('#curve_trace').get(0),
			@voltage_axis, @current_axis,
			[@curve_trace_data],
			{xbottom:yes, yright:no, xgrid:yes}
		)
		
		@running = false
		$('#startpause').click =>
			if not @running then @start() else @stop()

		$(window).on 'resize', @resized

	initDevice: (@device) ->
		@resized()

		@listener = false
		@afterStop()

		if @pendingStart
			@pendingStart = false
			@start()

	resized: =>
		@curve_trace.resized()

	start: =>
		#@device.pauseCapture()
		@running = true
		$(document.body).toggleClass 'capturing', true
		$("#startpause").attr('title', 'Stop')

		if @device.sampleTime != targetSampleTime
			console.log("Setting sample rate")
			@device.configure(sampleTime:targetSampleTime)
			@pendingStart = true
			return

		@sweepCount = 0

		sampleTime = @device.sampleTime

		@curve_trace_data.xdata = new Float32Array(sampleCt)
		@curve_trace_data.ydata = new Float32Array(sampleCt)

		initSignal = (s) =>
			s.acc = new Float32Array(sampleCt)

		initSignal(@vd)
		initSignal(@id)

		@curve_trace.needsRedraw(true)

		@device.channels.b.set 1, 'arb',
			{values: [
				{t:0, v:0}
				{t:2 * 1/sampleTime, v:0}
				{t:3 * 1/sampleTime, v:5}
				{t:4 * 1/sampleTime, v:0} # the period > the requested length, so bug isn't triggered
			]
			phase: 0
			relPhase: 0
			repeat: -1},
			(d) =>
 
		@device.channels.a.set 1, 'arb',
			{values: [
				{t:0, v:0}
				{t:1 * 1/sampleTime, v:5}
				{t:2 * 1/sampleTime, v:0}
				{t:4 * 1/sampleTime, v:0} # the period > the requested length, so bug isn't triggered
			]
			phase: 0
			relPhase: 0
			repeat: -1},
			(d) =>
				@listener = new server.DataListener(@device, [@device.channels.a.streams.v, @device.channels.a.streams.i, @device.channels.b.streams.v, @device.channels.b.streams.i])
				@listener.startSample = d.startSample + 1
				@listener.len = @listener.count = sampleCt
				@listener.decimateFactor = divider
				@listener.trigger =
					type: 'out'
					stream: @device.channels.a.streams.v
					holdoff: 0
					offset: 0
					force: 0
				@listener.submit()
				@listener.sweepDone.listen @handleData

		@device.startCapture()

	handleData: =>
		[av, ai, bv, bi] = @listener.data
		@sweepCount += 1
		updateUI = (@sweepCount % 4 == 2)

		processSignal = (s, d) =>
			vAccumulate(d, s.acc, s.stream.min, s.stream.max-s.stream.min)
			if updateUI
				vMul(s.acc, s.curve_trace.ydata, 1/@sweepCount)

		for i in [0..av.length]
			@vd[i] = av[i] - bv[i]
			@id[i] = (ai[i] + bi[i])/2

		@curve_trace_data.ydata = @id
		@curve_trace_data.xdata = @vd
		#processSignal(@vd, av)
		#processSignal(@id, bi)

		if updateUI
			@curve_trace.needsRedraw()
			$('#samplecount').text(@sweepCount)


	stop: =>
		@device.pauseCapture()

	afterStop: =>
		$(document.body).toggleClass 'capturing', false
		$("#startpause").attr('title', 'Start')
		@running = false

		if @listener
			@listener.cancel()
			@listener = null

	
vDiff = (inArray, outArray) ->
	for i in [0...inArray.length-1]
		outArray[i] = inArray[i+1] - inArray[i]
	return

vSub = (inArray, outArray) ->
	for i in [0...inArray.length]
		outArray[i] -= inArray[i]
	return

vAccumulate = (inArray, outArray, min=0, range=1) ->
	for i in [0...inArray.length]
		outArray[i] += (inArray[i] - min) / range
	return
	
vMul = (inArray, outArray, fac) ->
	for i in [0...inArray.length]
		outArray[i] = inArray[i] * fac
	return

$(document).ready ->
	window.app = app = new App()
	
	session
		app: "Pixelpulse DSA"
		model: "com.nonolithlabs.cee"
		updateMessage: "This app may not work with older versions"

		reset: ->

		updateDevsMenu: (l) ->
			$('#switchDev').toggle(l.length>1)

		initDevice:	(dev) ->
			dev.captureStateChanged.listen (s) ->
				if not s then app.afterStop()

		deviceChanged: (dev) ->
			app.initDevice(dev)

		deviceRemoved: ->
