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

tdata = fdata = null
time_axis = value_axis = freq_axis = gain_axis = null
step_plot = imp_plot = mag_plot = phase_plot = null

mag_series = phase_series = null

stepTimeRatio = 0.25

source = null
sense = null

sweepCount = 0

listener = null
v1 = 0
v2 = 5

sampleScale = 2048

window.nowebgl = true
		
initView = ->
	$('#with_device').show()

	time_axis = new livegraph.Axis(-0.005, 0.015, 's', true)
	value_axis = new livegraph.Axis(0, 5)
	diff_axis = new livegraph.Axis(-0.5, 0.5)
	freq_axis = new livegraph.Axis()
	gain_axis = new livegraph.Axis(0, 1)
	phase_axis = new livegraph.Axis(-Math.PI, Math.PI)
	
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
	
	mag_series = new livegraph.Series([], [], [0, 0, 0])
	phase_series = new livegraph.Series([], [], [0, 0, 0])
	
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

	mag_plot = new livegraph.canvas(
		$('#bode_magnitude_plot').get(0), 
		freq_axis, gain_axis,
		[mag_series]
		{xbottom:yes, yright:no, xgrid:yes}
	)

	phase_plot = new livegraph.canvas(
		$('#bode_phase_plot').get(0), 
		freq_axis, phase_axis,
		[phase_series]
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

fftMagPhase = (fft1, fft2, outMag, outPhase) ->
	r1a = fft1.real
	i1a = fft1.imag
	r2a = fft2.real
	i2a = fft2.imag

	sqrt = Math.sqrt
	atan2 = Math.atan2

	for x in [0...fft1.bufferSize/2]
		[r1, i1, r2, i2] = [r1a[x], i1a[x], r2a[x], i2a[x]]
		# Complex number division
		d = r2*r2 + i2*i2
		r = (r1*r2 + i1*i2)/d
		i = (r2*i1 - r1*i2)/d
		outMag[x] = sqrt(r*r + i*i)
		outPhase[x] = atan2(i, r)
		
dataTimeout = null
start = ->
	app.device.startCapture()

	sweepCount = 0

	sampleTime = app.device.sampleTime

	time_axis.visibleMin = time_axis.min = - sampleScale * stepTimeRatio * sampleTime
	time_axis.visibleMax = time_axis.max = sampleScale * (1-stepTimeRatio) * sampleTime
	tdata = arange(time_axis.min, time_axis.max, app.device.sampleTime)

	freq_axis.visibleMin = freq_axis.min = 0
	fdata = new Float32Array(sampleScale/2) #arange(0, sampleScale/2, 1)
	for i in [0...sampleScale/2]
		fdata[i] = Math.max(0, Math.log(i / sampleTime / sampleScale)) / Math.LN10
	freq_axis.visibleMax = freq_axis.max = fdata[fdata.length-1] #sampleScale/2 # 

	console.log(fdata)

	initSignal = (s) ->
		s.step_series.xdata = tdata
		s.imp_series.xdata = tdata

		s.step_series.ydata = new Float32Array(sampleScale)
		s.imp_series.ydata = new Float32Array(sampleScale)

		s.acc = new Float32Array(sampleScale)
		s.fft = new FFT(sampleScale, 1/app.device.sampleTime)

	mag_series.xdata = fdata
	mag_series.ydata = new Float32Array(sampleScale/2)

	phase_series.xdata = fdata
	mag_series.ydata = new Float32Array(sampleScale/2)

	initSignal(source)
	initSignal(sense)

	if source.stream.parent != sense.stream.parent
		sense.stream.parent.setConstant(0, 0)

	step_plot.needsRedraw(true)
	imp_plot.needsRedraw(true)
	mag_plot.needsRedraw(true)

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

		#return if not window.update
		vMul(s.acc, s.step_series.ydata, 1/sweepCount)
		vDiff(s.step_series.ydata, s.imp_series.ydata)
		s.fft.forward(s.imp_series.ydata)
		#console.log(s.fft)

	processSignal(source, listener.data[0])
	processSignal(sense,  listener.data[1])

	#return if not window.update
	
	fftMagPhase(sense.fft, source.fft, mag_series.ydata, phase_series.ydata)

	step_plot.needsRedraw()
	imp_plot.needsRedraw()
	mag_plot.needsRedraw()
	phase_plot.needsRedraw()

	window.update = false

stop = ->
	app.device.pauseCapture()
	listener.cancel()

$(document).ready ->
	app.findDevice()

	$('#start').click(start)
	$('#stop').click(stop)

