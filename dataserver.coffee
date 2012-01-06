# Websocket interface to dataserver
# (C) 2011 Nonolith Labs
# Author: Kevin Mehall <km@kevinmehall.net>
# Distributed under the terms of the GNU LGPLv3

class Event
	constructor: () ->
		@listeners = []

	listen: (func) ->
		@listeners.push(func)

	unListen: (func) ->
		i = @listeners.indexOf(func)
		if i!=-1
			@listeners.splice(i, 1)

	notify: (args...) ->
		func(args...) for func in @listeners
		return

class Dataserver
	constructor: (@host) ->
		@connected = new Event()
		@disconnected = new Event()
		@devicesChanged = new Event()
		@captureStateChanged = new Event()
		@samplesReset = new Event()

		@captureState = false

		@devices = {}
		@listenersById = {}
		@callbacks = {}

	connect: ->
		@ws = new WebSocket("ws://" + @host + "/ws/v0")
		@ws.onopen = => 
			console.log('connected')
			@connected.notify()
		@ws.onclose = =>
			console.log('disconnected')
			@disconnected.notify()

		@ws.onmessage = (evt) =>
			#console.log 'm', evt.data
			m = JSON.parse(evt.data)
			switch m._action
				when "devices"
					# note that this only refreshes the device list, not
					# the active device
					@devices =  for devId, devInfo of m.devices
						new Device(devInfo, this)
					@devicesChanged.notify(@devices)
					
				when "deviceConfig"
					@device.onInfo(m.device)
					
				when "captureState"
					@captureState = m.state
					@captureStateChanged.notify(@captureState)
					
				when "captureReset"
					@samplesReset.notify()
					for id, i of @listenersById
						i.onReset()
						
				when "update"
					for d in m.listeners
						@listenersById[d.id].onMessage(d)
						
				when "outputChanged"
					channel = @device.channels[m.channel]
					channel.onOutputChanged(m)
					
				when "controlTransferReturn"
					@runCallback m.id, m
					
				when "deviceDisconnected"
					@device.removed.notify()
					@device = null
					
	
	send: (cmd, m={})->
		m._cmd = cmd
		@ws.send(JSON.stringify m)

	selectDevice: (device) ->
		@send 'selectDevice',
			id: device.id
		if @device
			@device.onRemove()
		@device = new ActiveDevice(this)
		return @device

	configure: (mode=0, sampleTime=0.00004, samples=250000, continuous=false, raw=false) ->
		@send 'configure', {mode, sampleTime, samples, continuous, raw}
		
	startCapture: ->
		@send 'startCapture'

	pauseCapture: ->
		@send 'pauseCapture'
		
	createCallback: (fn) ->
		if fn
			id = +new Date() + Math.round(Math.random()*100000)
			@callbacks[id] = fn
			return id
		else
			return ''
		
	runCallback: (id, data, remove=yes) ->
		if @callbacks[id]
			@callbacks[id](data)
			if remove
				delete @callbacks[id]
		

class Device
	constructor: (info) ->
		for i in ['id', 'model', 'hwVersion', 'fwVersion', 'serial']
			this[i] = info[i]

class ActiveDevice
	constructor: (@parent) ->
		@changed = new Event()
		@removed = new Event()
		@channels = {}

	onInfo: (info) ->
		for i in ['id', 'model', 'hwVersion', 'fwVersion', 'serial', 'sampleTime']
			this[i] = info[i]
		
		@channels = {}
		for chanId, chanInfo of info.channels
			@channels[chanId] = new Channel(chanInfo, this)

		@changed.notify(this)

	onRemoved: ->
		for cId, channel of @channels
			channel.onRemoved()
		@removed.notify(this)
		
	controlTransfer: (bmRequestType, bRequest, wValue, wIndex, data=[], wLength=64, callback) ->
		id = server.createCallback callback
		server.send 'controlTransfer', {bmRequestType, bRequest, wValue, wIndex, data, wLength, id}

class Channel
	constructor: (info, @parent) ->
		@streams = {}
		@removed = new Event()
		@outputChanged = new Event()

		@onInfo(info)

	onInfo: (info)->
		for i in ['id', 'displayName']
			this[i] = info[i]

		@streams = {}
		for streamId, streamInfo of info.streams
			@streams[streamId] = new Stream(streamInfo, this)
	
	onRemoved: ->
		for sId, stream of @streams
			stream.onRemoved()
		@removed.notify(this)
		
	set: (mode, source, dict) ->
		dict['mode'] = mode
		dict['source'] = source
		dict['channel'] = @id
		server.send 'set', dict

	setConstant: (mode, val) ->
		@set mode, 'constant', {value:val}
		
	# switch to a source type, picking appropriate parameters
	guessSourceOptions:  (sourceType) ->
		m = @source.mode
		value = 0
		period = Math.round(1/@parent.sampleTime)
		amplitude = 1
		switch @source.source
			when 'constant'
				value = @source.value
			when 'sine', 'triangle'
				value = @source.offset
				period = @source.period
				amplitude = @source.amplitude
			when 'square'
				value = (@source.high + @source.low)/2
				period = @source.highSamples + @source.lowSamples
				amplitude = (@source.high - @source.low)/2
		switch sourceType
			when 'constant'
				@setConstant(m, value)
			when 'sine', 'triangle'
				@set m, sourceType, {offset:value, amplitude, period}
			when 'square'
				@set(m, sourceType, {high:value+amplitude, low: value-amplitude, highSamples:period/2, lowSamples:period/2})
		
			
				
				
			
	onOutputChanged: (m) ->
		@source = m
		@outputChanged.notify(m)

class Stream
	constructor: (info, @parent) ->
		@onRemoved = new Event()
		@onInfo(info)

	onInfo: (info) ->
		for i in ['id', 'displayName', 'units', 'min', 'max', 'outputMode']
			this[i] = info[i]

	onRemoved: ->
		@removed.notify()

	calcDecimate: (requestedSampleTime) ->
		devSampleTime = @parent.parent.sampleTime
		decimateFactor = Math.max(1, Math.floor(requestedSampleTime/devSampleTime))
		sampleTime = devSampleTime * decimateFactor
		return [decimateFactor, sampleTime]

	listen: (fn, sampleTime=0.1) ->
		channel = @parent
		device = channel.parent
		server = device.parent
		l = new Listener(server, device, channel, this, sampleTime)
		if fn
			l.updated.listen(fn)
			l.submit()
		return l

	series: -> new TimeDataSeries(this)
		

nextListenerId = 100

class Listener
	constructor: (@server, @device, @channel, @stream, @requestedSampleTime) ->
		@id ='w'+(nextListenerId++)
		@updated = new Event()
		@lastData = NaN

	submit: (startTime=null, count=-1) ->
		@server.listenersById[@id] = this
		[@decimateFactor, @sampleTime] = @stream.calcDecimate(@requestedSampleTime)
		if startTime?
			startSample = Math.round(startTime/@device.sampleTime)
		else
			startSample = -1
		@server.send 'listen'
			id: @id
			channel: @channel.id
			stream: @stream.id
			decimateFactor: @decimateFactor
			start: startSample
			count: count

	onReset: ->
		console.log 'onReset'
		@lastData = NaN
		@updated.notify([], 0)
		
	onMessage: (m) ->
		@lastData = m.data[m.data.length-1]
		@updated.notify(m.data, m.idx)

	cancel: ->
		@server.send 'cancelListen'
			id: @id
		if @server.listenersById[@id]
			delete @server.listenersById[@id]

class TimeDataSeries
	constructor: (@series) ->
		@listener = @series.listen()
		@listener.updated.listen(@onData)
		@server = @listener.server
		@updated = new Event()
		@xdata = []
		@ydata = []
		@requestedPoints = 0
	
	submit: ->
		time = @xmax - @xmin
		requestedSampleTime = time/@requestedPoints
		[decimateFactor, @sampleTime] = @series.calcDecimate(requestedSampleTime)
		@len = Math.ceil(time/@sampleTime)
		
		@listener.requestedSampleTime = requestedSampleTime
		
		# At end of "recent" stream means get new data
		reqLen = if @xmin < 0 and @xmax==0 then -1 else @len
		
		@listener.submit(@xmin, reqLen)
		return
	
	onData: (d, idx) =>
		if idx == 0
			@ydata = new Float32Array(@len)
			@xdata = new Float32Array(@len)
			for i in [0...@len]
				@xdata[i] = @xmin + i*@sampleTime

		if d.length and @xmin < 0
			@ydata.set(@ydata.subarray(d.length)) #shift array element left
			idx = @ydata.length-d.length

		for i in d
			@ydata[idx++] = i
		
		@updated.notify()

	
	configure: (@xmin, @xmax, @requestedPoints) ->
		# negative xmin, xmax==0 means to always show the last -xmin seconds
		@submit()

	destroy: ->
		@listener.cancel()

window.server = new Dataserver('localhost:9003')	
