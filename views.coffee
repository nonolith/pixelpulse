# Pixelpulse UI elements
# (C) 2011 Nonolith Labs
# Author: Kevin Mehall <km@kevinmehall.net>
# Distributed under the terms of the GNU GPLv3

pixelpulse = (window.pixelpulse ?= {})

pixelpulse.captureState.subscribe (s) ->
	$(document.body).toggleClass('capturing', s)

## Bottom toolbar
$ ->
# Start/pause button
	$(window).resize -> pixelpulse.layoutChanged.notify()
	
	$('#startpause').click ->
		if server.device.captureState
			server.device.pauseCapture()
		else
			server.device.startCapture()

	pixelpulse.captureState.subscribe (s) ->
		$('#startpause').attr('title', if s then 'Pause' else 'Start')



COLORS = [
	[[0x32, 0x00, 0xC7], [00, 0x32, 0xC7]]
	[[00, 0x7C, 0x16], [0x6f, 0xC7, 0x00]]
]

pixelpulse.initView = (dev) ->
	@timeseries_x = new livegraph.Axis(-10, 0)
	@timeseries_graphs = []
	@channelviews = []
	
	@streams = []
	for chId, channel of dev.channels
		for sId, stream of channel.streams
			@streams.push(stream)
		
	@meter_listener = new server.Listener(dev, @streams)
	@data_listener = new server.DataListener(dev, @streams)
	
	i = 0
	for chId, channel of dev.channels
		s = new pixelpulse.ChannelView(channel, i++)
		pixelpulse.channelviews.push(s)
		$('#streams').append(s.el)
	
	@sidegraph1 = new pixelpulse.XYGraphView(document.getElementById('sidegraph1'))
	@sidegraph2 = new pixelpulse.XYGraphView(document.getElementById('sidegraph2'))
	
	# show the x-axis ticks on the last stream
	lastGraph = @timeseries_graphs[@timeseries_graphs.length-1]
	lastGraph.showXbottom = yes
	
	# push the bottom out into the space reserved by #timeaxis
	$(lastGraph.div).css('margin-bottom', -livegraph.AXIS_SPACING)
	$(lastGraph.div).siblings('aside').css('margin-bottom', -livegraph.AXIS_SPACING)
	lastGraph.resized()
	
	@meter_listener.submit()
	setTimeout((->pixelpulse.updateTimeSeries()), 10)

pixelpulse.toggleTrigger = ->
	@triggering = !@triggering
	$(document.body).toggleClass('triggering', pixelpulse.triggering)
	
	xaxis = pixelpulse.timeseries_x
	if @triggering
		xaxis.min = -5
		xaxis.max = 5
		xaxis.visibleMin = -0.125
		xaxis.visibleMax = 0.125
		for lg in @timeseries_graphs
			lg.showXgridZero = yes
			
		default_trigger_level = 2.5
		@data_listener.configureTrigger(pixelpulse.streams[0], default_trigger_level, 0.25, 0, 0.5)
		@triggerOverlay = new livegraph.TriggerOverlay(@timeseries_graphs[0])
		@triggerOverlay.position(default_trigger_level)
	else
		xaxis.min = -10
		xaxis.max = 0
		xaxis.visibleMin = -10
		xaxis.visibleMax = 0
		for lg in @timeseries_graphs
			lg.showXgridZero = no
		@triggerOverlay.remove()
		@triggerOverlay = null
		@data_listener.disableTrigger()
		
	for i in @timeseries_graphs then i.needsRedraw(true)
	pixelpulse.updateTimeSeries()
			
	pixelpulse.triggeringChanged.notify(@triggering)
	
# run after a window changing operation to fetch new data from the server
pixelpulse.updateTimeSeries = ->
	xaxis = pixelpulse.timeseries_x
	lg = pixelpulse.timeseries_graphs[0]
	listener = pixelpulse.data_listener
	
	changed = no
	
	if pixelpulse.triggering
		min = -xaxis.span()
		max = 0
		pts = lg.width/2
		if listener.trigger.offset != xaxis.visibleMin
			listener.trigger.offset = xaxis.visibleMin
			changed = yes
		#xaxis.min = -xaxis.span()*2
		#xaxis.max = xaxis.span()*2
	else
		min = Math.max(xaxis.visibleMin - 0.5*xaxis.span(), xaxis.min)
		max = Math.min(xaxis.visibleMax + 0.5*xaxis.span(), xaxis.max)
		pts = lg.width / 2 * (max - min) / xaxis.span()
	
	if min != listener.xmin or max != listener.xmax or listener.requestedPoints or changed != pts
		console.log('configure', min, max, pts)
		listener.configure(min, max, pts)
		listener.submit()
		
pixelpulse.destroyView = ->
	$('#streams section.channel').remove()
	$('#sidegraphs > section').empty()
	if @meter_listener
		@meter_listener.cancel()
	if @data_listener
		@data_listener.cancel()
	for i in @channelviews then i.destroy()
	pixelpulse.setLayout(0)
	

class pixelpulse.ChannelView
	constructor: (@channel, @index) ->
		@section = $("<section class='channel'>")
		@el = @section.get(0)
		
		@header = $("<header>").appendTo(@section)
		
		@aside = $("<aside>").appendTo(@header)
		
		@h1 = $("<h1>").text(@channel.displayName).appendTo(@aside)
		
		i = 0
		@streamViews = for id, s of @channel.streams
			v = new pixelpulse.StreamView(this, s,  i++)
			@section.append(v.el)
			v
			
	destroy: -> for i in @streamViews then i.destroy()

class pixelpulse.StreamView
	constructor: (@channelView, @stream, @index)->
		@section = $("<section class='stream'>")
		@aside = $("<aside>").appendTo(@section)
		@el = @section.get(0)
		
		@h1 = $("<h1>").text(@stream.displayName).appendTo(@aside)

		@timeseriesElem = $("<div class='livegraph'>").appendTo(@section)

		@addReadingUI(@aside)
		
		pixelpulse.layoutChanged.subscribe @relayout

		pixelpulse.meter_listener.updated.listen (m) =>
			index = pixelpulse.meter_listener.streamIndex(@stream)
			arr = m.data[index]
			@onValue arr[arr.length - 1]
					
		@source = $("<div class='source'>").appendTo(@aside)
		@stream.parent.outputChanged.listen @sourceChanged
		
		if @stream.parent.source
			@sourceChanged(@stream.parent.source)
		
		@initTimeseries()

	addReadingUI: (tile) ->
		tile.append($("<span class='reading'>")
			.append(@value = $("<span class='value'>"))
			.append($("<span class='unit'>").text(@stream.units)))
		
	onValue: (v) ->
		@value.text(if Math.abs(v)>1 then v.toPrecision(4) else v.toFixed(3))
		if (v < 0)
			@value.addClass('negative')
		else
			@value.removeClass('negative')

	initTimeseries: ->
		@xaxis = pixelpulse.timeseries_x
		@yaxis = new livegraph.Axis(@stream.min, @stream.max)
		@series =  pixelpulse.data_listener.series('time', @stream)
		@series.color = COLORS[@channelView.index][@index]
		
		console.log(@series)
		
		@lg = new livegraph.canvas(@timeseriesElem.get(0), @xaxis, @yaxis, [@series])
		
		pixelpulse.timeseries_graphs.push(@lg)
				
		@lg.onClick = (pos) =>
			[x,y] = pos
			if x > @lg.width - 45
				return new DragToSetAction(this, pos)
			if x < 45 and pixelpulse.triggering
				if pixelpulse.data_listener.trigger.stream != @stream
					console.log('changing trigger stream')
					pixelpulse.triggerOverlay.remove()
					pixelpulse.triggerOverlay = new livegraph.TriggerOverlay(@lg)
				return new DragTriggerAction(this, pos)
			else
				return new livegraph.DragScrollAction(@lg, pos,
					pixelpulse.timeseries_graphs, pixelpulse.updateTimeSeries)
				
				
		@lg.onDblClick = (e, pos, btn) =>
			zf = if e.shiftKey or btn==2 then 2 else 0.5
			opts = {time: 200, zoomFactor:zf } 
			return new livegraph.ZoomXAction(opts, @lg, pos,
				pixelpulse.timeseries_graphs, pixelpulse.updateTimeSeries)
		
		@isSource = false
		@dotFollowsStream = false
		if @stream.outputMode
			@dot = new livegraph.Dot(@lg, 'white', @lg.cssColor())
			@stream.parent.outputChanged.listen (m) => @updateDot(m)
			@updateDot(@stream.parent.source)
		
		@series.updated.listen =>
			@lg.needsRedraw()
			if @dotFollowsStream then @dot.position(@series.listener.lastData)
			
		@lg.needsRedraw()
	
	relayout: =>
		@lg.resized()
		
	updateDot: (m) ->	
		@isSource = (m.mode == @stream.outputMode)
		@dotFollowsStream = false
		@section.toggleClass('sourcing', @isSource)
		
		if m.source is 'constant'
			@dot.fill = if @isSource then @lg.cssColor() else 'white'
			@dot.render()
			
			if @isSource
				@dot.position(m.value)
			else
				@dot.position(@series.listener.lastData)
				@dotFollowsStream = true
		else
			@dot.position(null)
		
	sourceChanged: (m) =>
		if m.mode == @stream.outputMode
			@source.empty()
			
			stream = @stream
			channel = stream.parent
			sampleTime = channel.parent.sampleTime
			
			sel = $("<select>")
			for i in ['constant', 'square', 'sine', 'triangle']
				sel.append($("<option>").text(i))
			sel.val(m.source)
				
			sel.change -> channel.guessSourceOptions(sel.val())
			
			$("<h2>Source </h2>").append(sel).appendTo(@source)
			
			ATTRS = ['value', 'high', 'low', 'highSamples', 'lowSamples', 'offset', 'amplitude', 'period']
			
			propInput = (prop, conv) ->
				value = m[prop]
				
				switch conv
					when 'val'
						min = stream.min
						max = stream.max
						unit = stream.units
						step = 0.1
					when 's'
						value *= sampleTime
						min = sampleTime
						max = 10
						step = 0.1
						unit = 's'
					when 'hz'
						value = 1/(value * sampleTime)
						min = 0.1
						max = 1/sampleTime/5
						step = 1
						unit = 'Hz'
					
				inp = $('<input type=number>')
					.attr({min, max, step})
					.val(value)
					.change =>
						d = {}
						for i in ATTRS
							if m[i]? then d[i] = m[i]
						d[prop] = parseFloat(inp.val())
						
						if conv is 's'
							d[prop] /= channel.parent.sampleTime
						else if conv is 'hz'
							d[prop] = (1/d[prop])/channel.parent.sampleTime
						
						channel.set(m.mode, m.source, d)
				
				$("<span>").append(inp).append(unit)
			
			switch m.source
				when 'constant'
					@source.append propInput('value', 'val')
				when 'square'
					@source.append propInput('low', 'val')
					@source.append ' for '
					@source.append propInput('lowSamples', 's')
					@source.append propInput('high', 'val')
					@source.append ' for '
					@source.append propInput('highSamples', 's')
				when 'sine', 'triangle'
					@source.append propInput('offset', 'val')
					@source.append propInput('amplitude', 'val')
					@source.append propInput('period', 'hz')
			
		else
			@source.html("<h2>measure</h2>")
			
	destroy: ->
		pixelpulse.layoutChanged.unListen @relayout

pixelpulse.setLayout = (l) ->
	$(document.body).removeClass('layout-0side').removeClass('layout-1side').removeClass('layout-2side')
		.addClass("layout-#{l}side")
	
	if @sidegraph1 and @sidegraph2
		if l >= 1
			@sidegraph1.configure(@streams[0], @streams[1])
		else
			@sidegraph1.hidden()
		
		if l >= 2
			@sidegraph2.configure(@streams[2], @streams[3])
		else
			@sidegraph2.hidden()
		
	pixelpulse.layoutChanged.notify()
	
pixelpulse.makeStreamSelect = ->
	s = $("<select>")
	for i in [0...@streams.length]
		stream = @streams[i]
		$("<option>").attr(value:i)
		             .text("#{stream.displayName} (#{stream.units})")
		             .appendTo(s)
	s.selectStream = (stream) ->
		s.val(pixelpulse.streams.indexOf(stream))
		return s
		
	s.stream = -> pixelpulse.streams[parseInt(s.val())]
		
	return s
	
class pixelpulse.XYGraphView
	constructor: (@el) ->
		@graphdiv = $("<div class='livegraph'>").appendTo(@el)
		
		@xlabel = pixelpulse.makeStreamSelect()
		@xlabel.addClass('xaxislabel').appendTo(@el).change(@axisSelectChanged)
		@ylabel = pixelpulse.makeStreamSelect()
		@ylabel.addClass('yaxislabel').appendTo(@el).change(@axisSelectChanged)
		
		@color = [255, 0, 0]
		
		@lg = new livegraph.canvas(@graphdiv.get(0), false, false, [false], 
			{xbottom:true, yright:false, xgrid:true})
		
	axisSelectChanged: =>
		xaxis = @xlabel.stream()
		yaxis = @ylabel.stream()
		
		if xaxis != @xaxis or yaxis != @yaxis
			@configure(xaxis, yaxis)
	
	configure: (@xstream, @ystream) ->	
		@xaxis = new livegraph.Axis(@xstream.min, @xstream.max)
		@yaxis = new livegraph.Axis(@ystream.min, @ystream.max)
		
		@lg.xaxis = @xaxis
		@lg.yaxis = @yaxis
		
		@xlabel.selectStream(@xstream)
		@ylabel.selectStream(@ystream)
		
		@hidden()
		
		@series = pixelpulse.data_listener.series(@xstream, @ystream)
		@series.color = @color
		@lg.series = [@series]
		
		@series.updated.listen @updated
		pixelpulse.layoutChanged.subscribe @relayout
		
		@lg.needsRedraw(true)
		
	hidden: ->
		if @series
			@series.updated.unListen @updated
		pixelpulse.layoutChanged.unListen @relayout
	
	updated: => @lg.needsRedraw()
	
	relayout: =>
		@lg.resized()
		


class DragYAction extends livegraph.Action
	constructor: (@view, pos) ->
		@transform = livegraph.makeTransform(@view.lg.geom, @view.lg.xaxis, @view.lg.yaxis)
		@onDrag(pos)
	
	onDrag: ([x, y]) ->
		[x, y] = livegraph.invTransform(x,y,@transform)
		y = Math.min(Math.max(y, @view.stream.min), @view.stream.max)
		@withPos(y)
		
	withPos: (y) ->

class DragToSetAction extends DragYAction
	withPos: (y) ->
		@view.stream.parent.setConstant(@view.stream.outputMode, y)
			
class DragTriggerAction extends DragYAction
	withPos: (@y) ->
		pixelpulse.triggerOverlay.position(@y)
	
	onRelease: ->
		pixelpulse.data_listener.trigger.stream = @view.stream
		pixelpulse.data_listener.trigger.level = @y
		pixelpulse.data_listener.submit()

