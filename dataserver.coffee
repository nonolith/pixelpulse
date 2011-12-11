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

		@devices = {}
		@listenersById = {}

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
					if @captureState == 'ready'
						@samplesReset.notify()
						for id, i of @listenersById
							i.onReset()
				when "update"
					for d in m.listeners
						@listenersById[d.id].onMessage(d)
	
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
		for i in ['id', 'model', 'hwVersion', 'fwVersion', 'serial']
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

class Channel
	constructor: (info) ->
		@streams = {}

		@infoChanged = new Event('infoChanged')
		@streamAdded = new Event('streamAdded')
		@removed = new Event('removed')

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

class Stream
	constructor: (info) ->
		@infoChanged = new Event('infoChanged')
		@onRemoved = new Event('removed')
		@onInfo(info)

	onInfo: (info) ->
		for i in ['id', 'displayName', 'units', 'min', 'max', 'sampleTime']
			this[i] = info[i]

		@infoChanged.notify(this)

	onRemoved: ->
		@removed.notify()

	calcDecimate: (requestedSampleTime) ->
		decimateFactor = Math.max(1, Math.floor(requestedSampleTime/@sampleTime))
		sampleTime = @sampleTime * decimateFactor
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

	submit: (startTime=false) ->
		@server.listenersById[@id] = this
		[@decimateFactor, @sampleTime] = @stream.calcDecimate(@requestedSampleTime)
		if startTime?
			startSample = startTime/@stream.sampleTime
			console.log 'startSample', startSample
		else
			startSample = -1
		@server.send 'listen'
			id: @id
			device: @device.id
			channel: @channel.id
			stream: @stream.id
			decimateFactor: @decimateFactor
			start: startSample

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
		if @server.watchesById[@id]
			delete @server.listenersById[@id]

class TimeDataSeries
	constructor: (@series) ->
		@listener = @series.listen()
		@listener.updated.listen(@onData)
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
		for i in d
			@ydata[idx++] = i
		@updated.notify()

	
	configure: (@xmin, @xmax, @requestedPoints) -> @submit()

	destroy: ->
		@listener.cancel()

window.server = new Dataserver('localhost:9003')	
