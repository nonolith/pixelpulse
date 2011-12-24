# Websocket interface to dataserver
# (C) 2011 Nonolith Labs
# Author: Kevin Mehall <km@kevinmehall.net>
# Distributed under the terms of the GNU LGPLv3

class Event
	constructor: (@name) ->
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

updateCollection = (collection, infos, type, addedEvent, parent) ->
	newCollection = {}
		
	for id, info of infos
		oldItem = collection[id]
		if oldItem
			console.log 'updated'
			oldItem.onInfo(info)
			newCollection[id] = oldItem
		else
			newCollection[id] = item = new type(info)
			item.parent = parent
			console.log 'added', item
			addedEvent.notify(item)
	
	for id, item of collection
		if not newCollection[id]
			item.onRemoved()

	return newCollection

class Dataserver
	constructor: (@host) ->
		@connected = new Event('connected')
		@disconnected = new Event('disconnected')
		@deviceAdded = new Event('deviceAdded')
		@captureStateChanged = new Event('captureStateChanged')
		@samplesReset = new Event('samplesReset')

		@captureState = 'inactive'
		@captureLength = 0
		@captureContinuous = false

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
					@devices = updateCollection(@devices, m.devices, Device, @deviceAdded, this)
					
				when "deviceInfo"
					@device.onInfo(m.device)
					
				when "captureState"
					@captureState = m.state
					@captureStateChanged.notify(@captureState)
					
				when "captureConfig"
					@captureLength = m.length
					@captureContinuous = m.continuous
					
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
					
	
	send: (cmd, m={})->
		m._cmd = cmd
		@ws.send(JSON.stringify m)

	selectDevice: (device) ->
		@send 'selectDevice',
			id: device.id
		if @device
			@device.onRemove()
		@device = new ActiveDevice(this)

	prepareCapture: (t, continuous=false) ->
		@send 'prepareCapture',
			length: t
			continuous: continuous

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
		@infoChanged = new Event('infoChanged')
		@removed = new Event('removed')
		@onInfo(info)

	onInfo: (info) ->
		for i in ['id', 'model', 'hwVersion', 'fwVersion', 'serial']
			this[i] = info[i]
		
		@infoChanged.notify(this)
	
	onRemoved: ->
		@removed.notify(this)

class ActiveDevice
	constructor: (@parent) ->
		@infoChanged = new Event('infoChanged')
		@removed = new Event('removed')
		@channelAdded = new Event('channelAdded')
		@channels = {}

	onInfo: (info) ->
		for i in ['id', 'model', 'hwVersion', 'fwVersion', 'serial', 'sampleTime']
			this[i] = info[i]

		@channels = updateCollection(@channels, info.channels, Channel, @channelAdded, this)
		@infoChanged.notify(this)

	onRemoved: ->
		for cId, channel of @channels
			channel.onRemoved()
		@removed.notify(this)

	channelHandler: (h) ->
		for cId, channel of @channels then h(channel)
		@channelAdded.listen(h)
		
	controlTransfer: (bmRequestType, bRequest, wValue, wIndex, data=[], wLength=64, callback) ->
		id = server.createCallback callback
		server.send 'controlTransfer', {bmRequestType, bRequest, wValue, wIndex, data, wLength, id}

class Channel
	constructor: (info) ->
		@streams = {}

		@infoChanged = new Event('infoChanged')
		@streamAdded = new Event('streamAdded')
		@removed = new Event('removed')
		
		@outputChanged = new Event('outputChanged')

		@onInfo(info)

	onInfo: (info)->
		for i in ['id', 'displayName']
			this[i] = info[i]

		@streams = updateCollection(@streams, info.streams, Stream, @streamAdded, this)
		@infoChanged.notify(this)
	
	onRemoved: ->
		for sId, stream of @streams
			stream.onRemoved()
		@removed.notify(this)

	streamHandler: (h) ->
		for sId, stream of @streams then h(stream)
		@streamAdded.listen(h)

	setConstant: (mode, val) ->
		server.send 'set' #TODO: don't use global?
			source: 'constant'
			channel: @id
			mode: mode
			value: val
			
	onOutputChanged: (m) ->
		@outputChanged.notify(m)

class Stream
	constructor: (info) ->
		@infoChanged = new Event('infoChanged')
		@onRemoved = new Event('removed')
		@onInfo(info)

	onInfo: (info) ->
		for i in ['id', 'displayName', 'units', 'min', 'max', 'outputMode']
			this[i] = info[i]

		@infoChanged.notify(this)

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
		@updated = new Event('updated')
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
		@updated = new Event('updated')
		@xdata = []
		@ydata = []
		@requestedPoints = 0
	
	submit: ->
		time = @xmax - @xmin
		requestedSampleTime = time/@requestedPoints
		[decimateFactor, sampleTime] = @series.calcDecimate(requestedSampleTime)
		len = time/sampleTime
		console.log 'buf', time, sampleTime, len, @requestedPoints

		@ydata = new Float32Array(len)
		@xdata = new Float32Array(len)
		for i in [0...len]
			@xdata[i] = @xmin + i*sampleTime
		
		@listener.requestedSampleTime = requestedSampleTime
		@listener.submit(@xmin)
		return
	
	onData: (d, idx) =>
		if idx == 0
			@ydata = new Float32Array(@xdata.length)

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
