# Websocket interface to dataserver
# (C) 2011 Nonolith Labs
# Author: Kevin Mehall <km@kevinmehall.net>
# Distributed under the terms of the GNU LGPLv3

class window.Event
	constructor: () ->
		@listeners = []

	subscribe: (func) ->
		@listeners.push(func)
	
	listen: @::subscribe

	unListen: (func) ->
		i = @listeners.indexOf(func)
		if i!=-1
			@listeners.splice(i, 1)

	notify: (args...) ->
		func(args...) for func in @listeners
		return

window.WebSocket ?= window.MozWebSocket

removeNull = (val) -> val.replace(/\0/g, '') if val?

class Dataserver
	constructor: (@host) ->
		@connected = new Event()
		@disconnected = new Event()
		@devicesChanged = new Event()

		@devices = {}
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
			try
				m = JSON.parse(evt.data)
			catch e
				console.log("Invalid JSON frame:", evt.data)
			
			switch m._action
				when "serverHello"
					@version = m.version.replace(/^V/, '')
					@gitVersion = m.gitVersion

					if ga_event?
						ga_event("server", "connect-version", @version)

					console.log("server", @version)
					
				when "devices"
					# note that this only refreshes the device list, not
					# the active device
					@devices =  for devId, devInfo of m.devices
						new Device(devInfo, this)
					@devicesChanged.notify(@devices)
				
				when "deviceDisconnected"
					d = @device
					@device = null
					d.removed.notify()
					
				when "return"
					@runCallback(m.id, m)
					
				else
					@device.onMessage(m)
	
	send: (cmd, m={})->
		m._cmd = cmd
		@ws.send(JSON.stringify m)

	selectDevice: (device) ->
		@send 'selectDevice',
			id: device.id
		if @device
			@device.onRemoved()
		@device = device.makeActiveObj(this)
		return @device
	
	createCallback: (fn) ->
		if fn
			id = (+new Date() + Math.round(Math.random()*100000))&0xfffffff
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
		for i in ['id', 'model', 'serial']
			this[i] = info[i]

		for i in ['hwVersion', 'fwVersion']
			this[i] = removeNull(info[i])
	
	makeActiveObj: (parent) ->
		return switch @model
			when 'com.nonolithlabs.cee'
				new CEEDevice(parent)
			when 'com.nonolithlabs.bootloader'
				new BootloaderDevice(parent)

class CEEDevice
	constructor: (@parent) ->
		@changed = new Event()
		@removed = new Event()
		@captureStateChanged = new Event()
		@samplesReset = new Event()
		@listenersById = {}
		@channels = {}
	
	onMessage: (m) ->
		switch m._action
			when "deviceConfig"
				@onInfo(m.device)
				
			when "captureState"
				@captureState = m.state
				@captureDone = m.done
				@captureStateChanged.notify(@captureState)
				
			when "captureReset"
				@samplesReset.notify()
				for id, i of @listenersById
					i.onReset()
					
			when "update"
				@listenersById[m.id].onMessage(m)
					
			when "outputChanged"
				channel = @channels[m.channel]
				channel.onOutputChanged(m)
				
			when "gainChanged"
				channel = @channels[m.channel]
				stream = channel.streams[m.stream]
				stream.onGain(m)	

			when "packetDrop"
				console.log("dropped packet")

	onInfo: (info) ->
		for i in ['id', 'model', 'serial', 'length', 'continuous',
		          'sampleTime', 'captureState', 'captureDone', 'mode', 'samples', 'raw', 'minSampleTime']
			this[i] = info[i]

		for i in ['hwVersion', 'fwVersion']
			this[i] = removeNull(info[i])

		@minSampleTime ?= 1/40e3
		
		@channels = {}
		for chanId, chanInfo of info.channels
			@channels[chanId] = new Channel(chanInfo, this)
			
		@listenersById = {}

		@hasOutTrigger = @parent.version >= '1.2' and @fwVersion >= '1.2'
		@hasAdvSquare = @parent.version >= '1.2'

		@changed.notify(this)

	onRemoved: ->
		for cId, channel of @channels
			channel.onRemoved()
		@removed.notify(this)
		
	configure: (setopts = {}) ->
		opts = {mode:0, @sampleTime, @continuous, @raw}
		console.log(opts, setopts)
		for k, v of setopts
			opts[k] = v
			
		opts.samples ?= @length / opts.sampleTime
		
		@parent.send 'configure', opts
		
	startCapture: ->
		@parent.send 'startCapture'

	pauseCapture: ->
		@parent.send 'pauseCapture'
		
	controlTransfer: (bmRequestType, bRequest, wValue, wIndex, data=[], wLength=64, callback) ->
		id = server.createCallback callback
		server.send 'controlTransfer', {bmRequestType, bRequest, wValue, wIndex, data, wLength, id}
		
	calcDecimate: (requestedSampleTime) ->
		decimateFactor = Math.max(1, Math.floor(requestedSampleTime/@sampleTime))
		sampleTime = @sampleTime * decimateFactor
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
		
	set: (mode, source, dict, cb) ->
		dict['mode'] = mode
		dict['source'] = source
		@setDirect dict, cb

	setDirect: (dict, cb) ->
		dict.channel = @id

		if dict.dutyCycleHint
			dict.hint = "dutycycle:#{dict.dutyCycleHint}"
			delete dict.dutyCycleHint

		server.send 'set', dict
		if cb
			fn = (s) =>
				if s.effective
					@outputChanged.unListen fn
					cb(s)
			@outputChanged.subscribe fn

	setAdjust: (dict, val) ->
		KEEP_ATTRS = ['mode', 'source', 'value', 'high', 'low', 'highSamples', 'lowSamples', 'offset', 'amplitude', 'period']
		d = {}
		for i in KEEP_ATTRS
			if @source[i]? then d[i] = @source[i]

		if val?
			d[dict] = val
		else
			d[i] = v for i, v of dict
			
		@setDirect d

	setConstant: (mode, val, cb) ->
		@setDirect {mode, source:'constant', value:val}, cb
		
	setPeriodic: (mode, source, freq, offset, amplitude, cb) ->
		@setDirect {mode, source, period:1/freq/@parent.sampleTime, offset, amplitude}, cb
		
	# switch to a source type, picking appropriate parameters
	guessSourceOptions:  (sourceType) ->
		m = @source.mode
		value = 2.5
		period = Math.round(0.5/@parent.sampleTime)
		amplitude = 1
		switch @source.source
			when 'constant'
				value = @source.value
			when 'sine', 'triangle', 'square'
				value = @source.offset
				period = @source.period
				amplitude = @source.amplitude
			when 'adv_square'
				value = (@source.high + @source.low)/2
				period = @source.highSamples + @source.lowSamples
				amplitude = (@source.high - @source.low)/2
			when 'arb'
				period = @source.period
		switch sourceType
			when 'constant'
				@setConstant(m, value)
			when 'sine', 'triangle', 'square'
				@set m, sourceType, {offset:value, amplitude, period}
			when 'adv_square'
				@set(m, sourceType, {high:value+amplitude, low: value-amplitude, highSamples:period/2, lowSamples:period/2})
	
	onOutputChanged: (m) ->
		@source = m

		if m.source is 'adv_square'
			m.dutyCycleHint = if (match = /dutycycle:([\d.]+)/.exec(m.hint))
				parseFloat(match[1], 10)
			else
				m.highSamples / (m.highSamples + m.lowSamples)

		@outputChanged.notify(m)

class Stream
	constructor: (info, @parent) ->
		@removed = new Event()
		@gainChanged = new Event()
		@onInfo(info)

	onInfo: (info) ->
		for i in ['id', 'displayName', 'units', 'min', 'max', 'outputMode', 'gain', 'uncertainty']
			this[i] = info[i]
			
		@digits = Math.round(-Math.log(Math.max(@uncertainty, 0.0001)) / Math.LN10)
			
	onGain: (m) ->
		@gain = m.gain
		@gainChanged.notify(@gain)
		
	setGain: (g) ->
		if g != @gain
			server.send 'setGain',
				channel: @parent.id
				stream: @id
				gain: g

	onRemoved: ->
		@removed.notify()
		
	getSample: (t = 0.01, cb) ->
		l = new server.Listener(@parent.parent, [this])
		l.configure(false, t, 1)
		l.submit()
		l.updated.subscribe (m) ->
			cb(m.data[0][0])

	isSource: -> (@parent.source.mode == @outputMode)

	sourceLevel: ->
		# get the center of the source. assumes @isSource()
		source = @parent.source
		switch source.source
			when 'constant'
				source.value
			when 'sine', 'triangle', 'square'
				source.offset
			when 'adv_square'
				(source.high + source.low)/2
			else
				(@min + @max) / 2
		

window.server = new Dataserver('localhost:9003')

nextListenerId = 100

class server.Listener
	constructor: (@device, @streams) ->
		@server = @device.parent
		@id = nextListenerId++
		@updated = new Event()
		@reset = new Event()
		@done = new Event()
		@trigger = false
		@device.listenersById[@id] = this
		
	streamIndex: (stream) -> @streams.indexOf(stream)

	configure: (startTime=null, requestedSampleTime=0.1, @count=-1) ->
		unless requestedSampleTime > 0
			return console.error("Invalid sample time", requestedSampleTime)
		
		[@decimateFactor, @sampleTime] = @device.calcDecimate(requestedSampleTime)
		console.assert(@decimateFactor)
		if startTime?
			if startTime is false
				@startSample = -1
			else
				@startSample = Math.floor(startTime/@device.sampleTime)-@decimateFactor
		else
			@startSample = -@decimateFactor-2
			
	disableTrigger: -> @trigger = false
	
	configureTrigger: (stream, level, holdoff=0, offset=0, force=0, type='in') ->
		@trigger = {stream, level, holdoff, offset, force, type}
	
	submit: ->
		@server.send 'listen',
			id: @id
			streams: ({channel:s.parent.id, stream:s.id} for s in @streams)
			decimateFactor: @decimateFactor
			start: @startSample
			count: @count
			trigger: if @trigger
				type: @trigger.type ? 'in'
				channel: @trigger.stream.parent.id
				stream: @trigger.stream.id
				level: @trigger.level
				holdoff: Math.round(@trigger.holdoff / @device.sampleTime)
				offset: Math.ceil(@trigger.offset / @device.sampleTime)
				force: Math.round(@trigger.force / @device.sampleTime)
		@needsReset = true

	onReset: ->
		@reset.notify()
	
	onMessage: (m) ->
		@updated.notify(m)
		if m.done
			@done.notify()
	
	cancel: ->
		@server.send 'cancelListen',
			id: @id
		if @device.listenersById[@id]
			delete @device.listenersById[@id]
			
class server.DataListener extends server.Listener
	constructor: (device, streams) ->
		@xdata = []
		@data = ([] for i in streams)
		@requestedPoints = 0
		@sweepDone = new Event()
		super(device, streams)
	
	configure: (@xmin, @xmax, @requestedPoints, @continuous = true) ->
		time = @xmax - @xmin
		requestedSampleTime = time/@requestedPoints
		
		if @trigger
			super(-time, requestedSampleTime)
			@trigger.offset = @xmin
			#add a few samples to give range for subsample offset
			@count = @len =  Math.ceil(time/@sampleTime) + 4
			@xmin = Math.ceil(@xmin/@sampleTime)*@sampleTime
			@xmax = @xmin + time
		else
			super(@xmin, requestedSampleTime)
			@len = Math.ceil(time/@sampleTime)
			# At end of "recent" stream means get new data
			@count = if @xmin < 0 and @xmax==0 and @continuous then -1 else @len

	onMessage: (m) ->
		if m.idx == 0
			@sweepStartSample = m.sampleIndex
			@subsample = (m.subsample + 2.0)*@device.sampleTime || 0
			
			if @needsReset
				console.assert(@len)
				@needsReset = false
				@xdata = new Float32Array(@len)
			
				for i in [0...@len]
					@xdata[i] = @xmin + i*@sampleTime - @subsample
			
				@data = (new Float32Array(@len) for i in @streams)
				@reset.notify()
		
		for i in [0...@streams.length]
			src = m.data[i]
			dest = @data[i]
			idx = m.idx
			
			if src.length and @xmin < 0 and not @trigger
				dest.set(dest.subarray(src.length)) #shift array element left
				idx = dest.length-src.length

			for j in src
				dest[idx++] = j

		end_idx = m.data[0].length + m.idx
				
		for j in [m.idx...end_idx]
			@xdata[j] = @xmin + j*@sampleTime - @subsample

		@doneSamples = @decimateFactor*end_idx

		if end_idx >= @len
			@sweepDone.notify()
		
		super(m)

class BootloaderDevice
	constructor: (@server) ->
		@changed = new Event()
		@removed = new Event()
		
	onMessage: (m) ->
		switch m._action
			when "info"
				@onInfo(m)
	
	onInfo: (info) ->
		for i in ["serial", "magic", "version", "devid","page_size", "app_section_end"]
			this[i] = info[i]

		for i in ["hw_product", "hw_version"]
			this[i] = removeNull(info[i])
		@changed.notify(this)
		
	onRemoved: ->
		@removed.notify()
		
	crcApp: (callback) ->
		server.send 'crc_app', {id:server.createCallback(callback)}
	
	crcBoot: (callback) ->
		server.send 'crc_boot', {id:server.createCallback(callback)}
	
	erase: (callback) ->
		server.send 'erase', {id:server.createCallback(callback)}
	
	write: (data, callback) ->
		server.send 'write', {id:server.createCallback(callback), data}
		
	reset: ->
		server.send 'reset'
	
