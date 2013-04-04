window.nowebgl = true

class App
	constructor: ->
		@divider = 10
		@targetSampleTime = 1/40e3
		@sweepDuration = 0.1
		@sampleCt = @sweepDuration*4*(1/@targetSampleTime)/@divider
		@current_axis = new livegraph.Axis(-200, 200, 'mA')
		@voltage_axis = new livegraph.Axis(-5, 5, 'V')
		@current_axis.visibleMin = @current_axis.min = -200
		@current_axis.visibleMax = @current_axis.max = 200
		@curve_trace_data = new livegraph.Series([], [], [0, 0, 255])
		
		@vd = new Float32Array(@sampleCt)
		@id = new Float32Array(@sampleCt)
			
		@curve_trace = new livegraph.canvas(
			$('#curve_trace').get(0),
			@voltage_axis, @current_axis,
			[@curve_trace_data],
			{xbottom:yes, yright:no, xgrid:yes}
		)
		
		@running = false
		$('#startpause').click =>
			if not @running then @start() else @stop()
		$('#download-btn-a').click =>
			if @running
				url = @exportCSV()
				fname = "export#{+new Date()}.csv" 
				$('#download-btn-a').attr('href', url).attr('download', fname) 
			
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
		@running = true
		$(document.body).toggleClass 'capturing', true
		$("#startpause").attr('title', 'Stop')

		if @device.sampleTime != @targetSampleTime
			console.log("Setting sample rate")
			@device.configure(sampleTime:@targetSampleTime)
			@pendingStart = true
			return

		@sweepCount = 0

		sampleTime = @device.sampleTime

		@curve_trace_data.xdata = new Float32Array(@sampleCt)
		@curve_trace_data.ydata = new Float32Array(@sampleCt)

		initSignal = (s) =>
			s.acc = new Float32Array(@sampleCt)
			s.data = new Float32Array(@sampleCt)

		initSignal(@vd)
		initSignal(@id)

		@curve_trace.needsRedraw(true)

		@device.channels.b.set 1, 'arb',
			{values: [
				{t:0, v:0}
				{t:2*@sweepDuration * 1/sampleTime, v:0}
				{t:3*@sweepDuration * 1/sampleTime, v:5}
				{t:4*@sweepDuration * 1/sampleTime, v:0}
			]
			phase: 0
			relPhase: 0
			repeat: -1},
			(d) =>
 
		@device.channels.a.set 1, 'arb',
			{values: [
				{t:0, v:0}
				{t:1*@sweepDuration * 1/sampleTime, v:5}
				{t:2*@sweepDuration * 1/sampleTime, v:0}
				{t:4*@sweepDuration * 1/sampleTime, v:0}
			]
			phase: 0
			relPhase: 0
			repeat: -1},
			(d) =>
				@listener = new server.DataListener(@device, [@device.channels.a.streams.v, @device.channels.a.streams.i, @device.channels.b.streams.v, @device.channels.b.streams.i])
				@listener.startSample = d.startSample + 1
				@listener.len = @listener.count = @sampleCt
				@listener.decimateFactor = @divider
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
		for i in [0..av.length]
			@vd.data[i] = av[i] - bv[i]
			if av[i] > bv[i]
				@id.data[i] = sign(ai[i]) * Math.abs(bi[i])
			if bv[i] > av[i]
				@id.data[i] = sign(ai[i]) * Math.abs(ai[i])

		vAccumulate(@id.data, @id.acc)
		vAccumulate(@vd.data, @vd.acc)

		if updateUI
			vMul(@id.acc, @curve_trace_data.ydata, 1/@sweepCount)
			vMul(@vd.acc, @curve_trace_data.xdata, 1/@sweepCount)
			@curve_trace.needsRedraw()
			$('#samplecount').text(@sweepCount)

	exportCSV: =>
		rows = for i in [0...@sampleCt]
			d = []
			for dataArr in [@curve_trace_data.xdata, @curve_trace_data.ydata]
				d.push(dataArr[i].toFixed(4))
			d.join(',') + '\n'
		header = "'V', 'mA'"
		blob = new Blob(rows, {"type":"text/csv"})
		objectURL = window.webkitURL.createObjectURL(blob)
		return objectURL

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

vAccumulate = (inArray, outArray) ->
	for i in [0...inArray.length]
		outArray[i] += inArray[i]
	return
	
vMul = (inArray, outArray, fac) ->
	for i in [0...inArray.length]
		outArray[i] = inArray[i] * fac
	return

sign = (x) ->
    if x > 0 then 1 else -1

$(document).ready ->
	window.app = app = new App()
	
	session
		app: "Pixelpulse Curve Tracer"
		model: "com.nonolithlabs.cee"
		updateMessage: "This app may not work with older versions"

		reset: ->

		updateDevsMenu: (l) ->
			$('#switchDev').toggle(l.length>1)

		initDevice:	(dev) ->
			dev.pauseCapture()
			dev.captureStateChanged.listen (s) ->
				if not s then app.afterStop()

		deviceChanged: (dev) ->
			app.initDevice(dev)

		deviceRemoved: ->
