# Websocket interface to dataserver
# (C) 2011 Nonolith Labs
# Author: Kevin Mehall <km@kevinmehall.net>
# Distributed under the terms of the GNU LGPLv3

class Event
	constructor: (@name) ->
		@listeners = []

	listen: (func) ->
		@listeners.push(func)

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
		@streamingStarted = new Event('stoppedStreaming')
		@streamingStopped = new Event('stoppedStreaming')

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
			m = JSON.parse(evt.data)
			console.log 'message', m
			switch m._action
				when "devices"
					@devices = updateCollection(@devices, m.devices, Device, @deviceAdded, this)
				when "streamstate"
					@isStreaming = m.streaming
					if m.streaming
						@streamingStart.notify()
					else
						@streamingStopped.notify()
				when "update"
					@watchesById[m.id].onMessage(m)
	
	send: (cmd, m={})->
		m._cmd = cmd
		@ws.send(JSON.stringify m)

	startStreaming: ->
		@send 'startStreaming'		

	stopStreaming: ->
		@send 'stopStreaming'
		

class Device
	constructor: (info) ->
		@infoChanged = new Event('infoChanged')
		@removed = new Event('removed')
		@channelAdded = new Event('channelAdded')
		@channels = {}
		@onInfo(info)

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

class InputStream
	constructor: (info) ->
		@infoChanged = new Event('infoChanged')
		@onRemoved = new Event('removed')
		@onInfo(info)

	onInfo: (info) ->
		for i in ['id', 'displayName', 'units']
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
		@data = []
		@dataFill = 0
		@updated = new Event('updated')

	start: (start, end, decimateFactor) ->
		@server.watchesById[@id] = this
		len = Math.ceil((end-start)/decimateFactor)
		dataFill = 0
		@data = new Float32Array(len)
		@server.send 'watch'
			id: @id
			device: @device.id
			channel: @channel.id
			stream: @stream.id
			startIndex: start
			endIndex: end
			decimateFactor: decimateFactor
		@active = yes

	onMessage: (m) ->
		@dataFill = m.idx
		for i in m.data
			@data[@dataFill++] = i
		if m.end then @onDone()
		@updated.notify()
	
	lastData: -> @data[@dataFill-1]

	onDone: ->
		@active = no
		delete @server.watchesById[@id]

window.server = new Dataserver('localhost:9003')	