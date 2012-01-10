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
		@samplesReset = new Event()

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
					@device.captureState = m.state
					@device.captureDone = m.done
					@device.captureStateChanged.notify(@device.captureState)
					
				when "captureReset"
					@samplesReset.notify()
					for id, i of @listenersById
						i.onReset()
						
				when "update"
					@listenersById[m.id].onMessage(m)
						
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
		@captureStateChanged = new Event()
		@channels = {}

	onInfo: (info) ->
		for i in ['id', 'model', 'hwVersion', 'fwVersion', 'serial',
		          'sampleTime', 'captureState', 'captureDone']
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
		
	calcDecimate: (requestedSampleTime) ->
		decimateFactor = Math.max(1, Math.floor(requestedSampleTime/@sampleTime))
		sampleTime = @sampleTime * decimateFactor
		console.log('calcDecimate', requestedSampleTime, sampleTime, decimateFactor)
		return [decimateFactor, sampleTime]

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
			
		@source = info.output
	
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

window.server = new Dataserver('localhost:9003')	

nextListenerId = 100

class server.Listener
	constructor: (@device, @streams) ->
		@server = @device.parent
		@id = nextListenerId++
		@updated = new Event()
		@reset = new Event()
		@configure()
		
	streamIndex: (stream) -> @streams.indexOf(stream)

	configure: (startTime=null, requestedSampleTime=0.1, @count=-1) ->
		@server.listenersById[@id] = this
		[@decimateFactor, @sampleTime] = @device.calcDecimate(requestedSampleTime)
		if startTime?
			@startSample = Math.floor(startTime/@device.sampleTime)-@decimateFactor
		else
			@startSample = -@decimateFactor-2
			
	submit: ->
		@server.send 'listen'
			id: @id
			streams: ({channel:s.parent.id, stream:s.id} for s in @streams)
			decimateFactor: @decimateFactor
			start: @startSample
			count: @count

	onReset: ->
		@reset.notify()
		
	onMessage: (m) ->
		@updated.notify(m)

	cancel: ->
		@server.send 'cancelListen'
			id: @id
		if @server.listenersById[@id]
			delete @server.listenersById[@id]
			
class server.DataListener extends server.Listener
	constructor: (device, streams) ->
		super(device, streams)
		@timedata = []
		@xdata = []
		@data = ([] for i in streams)
		console.log('streams', streams)
		@requestedPoints = 0	
	
	configure: (@xmin, @xmax, @requestedPoints) ->
		time = @xmax - @xmin
		requestedSampleTime = time/@requestedPoints
		
		super(@xmin, requestedSampleTime)
		
		@len = Math.ceil(time/@sampleTime)
		
		# At end of "recent" stream means get new data
		@count = if @xmin < 0 and @xmax==0 then -1 else @len

	onMessage: (m) ->
		if m.idx == 0
			@xdata = new Float32Array(@len)
			for i in [0...@len]
				@xdata[i] = @xmin + i*@sampleTime
			
			@data = (new Float32Array(@len) for i in @streams)
			@reset.notify()
		
		for i in [0...@streams.length]
			src = m.data[i]
			dest = @data[i]
			idx = m.idx
			
			if src.length and @xmin < 0
				dest.set(dest.subarray(src.length)) #shift array element left
				idx = dest.length-src.length

			for j in src
				dest[idx++] = j
		
		super()
		
	series: (x, y) -> new DataSeries(this, x, y)

class DataSeries
	constructor: (@listener, @xseries, @yseries) ->
		@updated = @listener.updated
		@listener.reset.listen @reset
		@reset()
	
	reset: =>
		@xdata = (if @xseries == 'time'
			@listener.xdata
		else
			@listener.data[@listener.streamIndex(@xseries)])
		@ydata = @listener.data[@listener.streamIndex(@yseries)] 

