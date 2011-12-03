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

		@devices = {}
		@watchesById = {}

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
				when "capture_state"
					@captureState = m.state
					if @captureState == 'ready'
						for wId, watch of @watchesById then watch.onDone()
					@captureStateChanged.notify(@captureState)
				when "update"
					@watchesById[m.id].onMessage(m)
	
	send: (cmd, m={})->
		m._cmd = cmd
		@ws.send(JSON.stringify m)

	selectDevice: (device) ->
		@send 'selectDevice',
			id: device.id
		if @device
			@device.onRemove()
		@device = new ActiveDevice(this)

	prepareCapture: (t) ->
		@send 'prepareCapture',
			length: t	

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
		for i in ['id', 'model', 'hwversion', 'fwversion', 'serial']
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
		for i in ['id', 'model', 'hwversion', 'fwversion', 'serial']
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
		@inputStreams = {}
		@outputStreams = {}

		@infoChanged = new Event('infoChanged')
		@inputStreamAdded = new Event('inputStreamAdded')
		@removed = new Event('removed')

		@onInfo(info)

	onInfo: (info)->
		for i in ['id', 'displayName']
			this[i] = info[i]

		@inputStreams = updateCollection(@inputStreams, info.inputs, InputStream, @inputStreamAdded, this)
		@infoChanged.notify(this)
	
	onRemoved: ->
		for sId, stream of @inputStreams
			stream.onRemoved()
		@removed.notify(this)

	inputStreamHandler: (h) ->
		for sId, stream of @inputStreams then h(stream)
		@inputStreamAdded.listen(h)

	setConstant: (mode, val) ->
		server.send 'set' #TODO: don't use global?
			source: 'constant'
			channel: @id
			mode: mode
			value: val

class InputStream
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

	getWatch: ->
		channel = @parent
		device = channel.parent
		server = device.parent

		return new Watch(server, device, channel, this)
		

nextWatchId = 100

class Watch
	constructor: (@server, @device, @channel, @stream) ->
		@active = no
		@id = 'w'+(nextWatchId++)
		@data = false
		@dataFill = 0
		@updated = new Event('updated')
		@lastData = NaN

	start: (start, end, sampleTime) ->
		len = @submit(start, end, sampleTime)
		@data = new Float32Array(len)

	submit: (start, end, sampleTime) ->
		@dataFill = 0
		@server.watchesById[@id] = this
		decimateFactor = Math.max(1, Math.floor(sampleTime/@stream.sampleTime))
		console.log 'df', decimateFactor
		@server.send 'watch'
			id: @id
			device: @device.id
			channel: @channel.id
			stream: @stream.id
			startIndex: start
			endIndex: end
			decimateFactor: decimateFactor
		@active = yes
		return Math.ceil((end-start)/decimateFactor)

	continuous: (sampleTime) ->
		@data = false
		@submit(-1, -1, sampleTime)

	onMessage: (m) ->
		@dataFill = m.idx
		if @data?
			for i in m.data
				@data[@dataFill++] = i
		@lastData = m.data[m.data.length-1]
		if m.end then @onDone()
		@updated.notify()

	onDone: ->
		@active = no
		delete @server.watchesById[@id]
		console.info "watch #{@id} done"

window.server = new Dataserver('localhost:9003')	