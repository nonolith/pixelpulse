
stepTimeRatio = 0.25

sampleScale = 8192

window.nowebgl = true
		
class App
	constructor: ->
		@time_axis = new livegraph.Axis(-0.005, 0.015, 's', true)
		@value_axis = new livegraph.Axis(0, 1)
		@diff_axis = new livegraph.Axis(-0.01, 0.02)
		@freq_axis = new livegraph.LogAxis(0, 4, 'Hz')
		@gain_axis = new livegraph.Axis(-45, 45, 'dB')
		@phase_axis = new livegraph.Axis(-180, 180, "\u00B0")
		
		@source = 
			stream: null
			acc: null
			step_series: new livegraph.Series([], [], [0, 0, 255])
			imp_series:  new livegraph.Series([], [], [0, 0, 255])
			
		@sense = 
			stream: null
			acc: null
			step_series: new livegraph.Series([], [], [255, 0, 0])
			imp_series:  new livegraph.Series([], [], [255, 0, 0])

		@v1 = 0
		@v2 = 4
		
		@mag_series = new livegraph.Series([], [], [0, 0, 0])
		@phase_series = new livegraph.Series([], [], [0, 0, 0])
		
		@step_plot = new livegraph.canvas(
			$('#step_plot').get(0), 
			@time_axis, @value_axis,
			[@source.step_series, @sense.step_series]
			{xbottom:yes, yright:no, xgrid:yes}
		)
		
		@imp_plot = new livegraph.canvas(
			$('#impulse_plot').get(0), 
			@time_axis, @diff_axis,
			[@source.imp_series, @sense.imp_series]
			{xbottom:yes, yright:no, xgrid:yes}
		)

		@mag_plot = new livegraph.canvas(
			$('#bode_magnitude_plot').get(0), 
			@freq_axis, @gain_axis,
			[@mag_series]
			{xbottom:yes, yright:no, xgrid:yes}
		)

		@phase_plot = new livegraph.canvas(
			$('#bode_phase_plot').get(0), 
			@freq_axis, @phase_axis,
			[@phase_series]
			{xbottom:yes, yright:no, xgrid:yes}
		)

		@running = false
		$('#startpause').click =>
			if not @running then @start() else @stop()

		$(window).on 'resize', @resized

		$('#source_stream, #sense_stream, #v1, #v2').change @updateParams

	initDevice: (@device) ->
		@resized()

		@listener = false
		@afterStop()

		populateStreamSelect = (device, sel, defaultVal) ->
			beforeVal = sel.get(0).value || defaultVal
			$(sel).empty()
			for k, channel of device.channels
				for k, stream of channel.streams
					$("<option>").attr(value:"#{channel.id}.#{stream.id}")
					             .text("#{stream.displayName}")
					             .appendTo(sel)
			sel.val(beforeVal)

		populateStreamSelect(@device, $('#source_stream'), 'a.v')
		populateStreamSelect(@device, $('#sense_stream'), 'b.v')

		if not $('#v1').val() then $('#v1').val(0.5)
		if not $('#v2').val() then $('#v2').val(4.5)

		@updateParams()

		if @pendingStart
			@pendingStart = false
			@start()

	updateParams: =>
		getStream = (device, sel) ->
			[chId, sId] = sel.val().split('.')
			return device.channels[chId].streams[sId]

		@source.stream = getStream(@device, $('#source_stream'))
		@sense.stream  = getStream(@device, $('#sense_stream'))

		$('#v1-unit, #v2-unit').text(@source.stream.units)

		@v1 = parseFloat($('#v1').val(), 10)
		@v2 = parseFloat($('#v2').val(), 10)

	resized: =>
		@step_plot.resized()
		@imp_plot.resized()
		@mag_plot.resized()
		@phase_plot.resized()

	start: =>
		@running = true
		$(document.body).toggleClass 'capturing', true
		$("#startpause").attr('title', 'Stop')
		$('#source_stream, #sense_stream, #v1, #v2').attr('disabled', true)

		targetSampleTime = 1/80e3
		if @device.sampleTime != targetSampleTime
			console.log("Setting sample rate")
			@device.configure(sampleTime:targetSampleTime)
			# Wait for the server to reconfigure the device, then start it
			@pendingStart = true
			return

		@device.startCapture()

		@sweepCount = 0

		sampleTime = app.device.sampleTime

		@time_axis.min = - sampleScale * stepTimeRatio * sampleTime
		@time_axis.max = sampleScale * (1-stepTimeRatio) * sampleTime
		@tdata = arange(@time_axis.min, @time_axis.max, @device.sampleTime)

		@time_axis.visibleMin = @time_axis.min * 0.1
		@time_axis.visibleMax = @time_axis.max * 0.3

		@freq_axis.visibleMin = @freq_axis.min = 0
		@fdata = new Float32Array(sampleScale/2) #arange(0, sampleScale/2, 1)
		for i in [0...sampleScale/2]
			@fdata[i] = Math.max(0, Math.log(i / sampleTime / sampleScale)) / Math.LN10
		@freq_axis.visibleMax = @freq_axis.max = Math.min(@fdata[@fdata.length-1], 4) 

		initSignal = (s) =>
			s.step_series.xdata = @tdata
			s.imp_series.xdata = @tdata

			s.step_series.ydata = new Float32Array(sampleScale)
			s.imp_series.ydata = new Float32Array(sampleScale)

			s.acc = new Float32Array(sampleScale)
			s.fft = new FFT(sampleScale, 1/app.device.sampleTime)

		@mag_series.xdata = @fdata
		@mag_series.ydata = new Float32Array(sampleScale/2)

		@phase_series.xdata = @fdata
		@phase_series.ydata = new Float32Array(sampleScale/2)

		initSignal(@source)
		initSignal(@sense)

		if @source.stream.parent != @sense.stream.parent
			# if measuring from another channel than the source, allow sense channel to float
			@sense.stream.parent.setConstant(0, 0)

		@step_plot.needsRedraw(true)
		@imp_plot.needsRedraw(true)
		@mag_plot.needsRedraw(true)
		@phase_plot.needsRedraw(true)

		@source.stream.parent.set @source.stream.outputMode, 'arb',
			{values: [
				{t:0, v:@v1}
				{t:stepTimeRatio * sampleScale, v:@v1}
				{t:stepTimeRatio * sampleScale, v:@v2}
				{t:1    * sampleScale, v:@v2}
				{t:1.25 * sampleScale, v:@v1}
				{t:2  * sampleScale, v:@v1} # the period > the requested length, so bug isn't triggered
			]
			phase: 0
			relPhase: 0
			repeat: -1},
			(d) =>
				@listener = new server.DataListener(app.device, [@source.stream, @sense.stream])
				#listener.configure()
				@listener.startSample = d.startSample + 1
				@listener.len = @listener.count = sampleScale
				@listener.decimateFactor = 1
				@listener.trigger = 
					type: 'out'
					stream: @source.stream
					holdoff: 0
					offset: 0
					force: 0
				@listener.submit()
				@listener.sweepDone.listen @handleData

	handleData: =>
		[data1, data2] = @listener.data

		@sweepCount += 1
		updateUI = (@sweepCount % 4 == 2)

		processSignal = (s, d) =>
			vAccumulate(d, s.acc, s.stream.min, s.stream.max-s.stream.min)

			if updateUI
				vMul(s.acc, s.step_series.ydata, 1/@sweepCount)
				vDiff(s.step_series.ydata, s.imp_series.ydata)
				s.fft.forward(s.imp_series.ydata)

		processSignal(@source, data1)
		processSignal(@sense,  data2)

		if updateUI
			fftMagPhase(@sense.fft, @source.fft, @mag_series.ydata, @phase_series.ydata)

			@step_plot.needsRedraw()
			@imp_plot.needsRedraw()
			@mag_plot.needsRedraw()
			@phase_plot.needsRedraw()

			$('#samplecount').text(@sweepCount)


	stop: =>
		@device.pauseCapture()

	afterStop: =>
		$(document.body).toggleClass 'capturing', false
		$("#startpause").attr('title', 'Start')
		$('#source_stream, #sense_stream, #v1, #v2').removeAttr('disabled')
		@running = false

		if @listener
			@listener.cancel()
			@listener = null

	
vDiff = (inArray, outArray) ->
	for i in [0...inArray.length-1]
		outArray[i] = inArray[i+1] - inArray[i]
	return

vAccumulate = (inArray, outArray, min=0, range=1) ->
	for i in [0...inArray.length]
		outArray[i] += (inArray[i] - min) / range
	return
	
vMul = (inArray, outArray, fac) ->
	for i in [0...inArray.length]
		outArray[i] = inArray[i] * fac
	return

fftMagPhase = (fft1, fft2, outMag, outPhase) ->
	r1a = fft1.real
	i1a = fft1.imag
	r2a = fft2.real
	i2a = fft2.imag

	log = Math.log
	atan2 = Math.atan2

	magScale = 10 / Math.LN10 # avoid square root, so an extra power of 2
	phaseScale = 180 / Math.PI

	for x in [0...fft1.bufferSize/2]
		[r1, i1, r2, i2] = [r1a[x], i1a[x], r2a[x], i2a[x]]
		# Complex number division
		d = r2*r2 + i2*i2
		r = (r1*r2 + i1*i2)/d
		i = (r2*i1 - r1*i2)/d
		outMag[x] = log(r*r + i*i) * magScale
		outPhase[x] = atan2(i, r) * phaseScale
		
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
