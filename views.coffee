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

GAIN_OPTIONS = [1, 2, 4, 8, 16, 32, 64]

pixelpulse.initView = (dev) ->
	@timeseries_x = new livegraph.Axis(-10, 0)
	@timeseries_graphs = []
	@channelviews = []
	
	@streams = []
	for chId, channel of dev.channels
		for sId, stream of channel.streams
			@streams.push(stream)
		
	@meter_listener = new server.Listener(dev, @streams)
	@meter_listener.configure()
	
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
	
	#@timeseries_x.windowDoneAnimating = -> pixelpulse.updateTimeSeries()
	@timeseries_x.windowChanged = pixelpulse.checkWindowChange
	
	@meter_listener.submit()

pixelpulse.toggleTrigger = ->
	@triggering = !@triggering
	$(document.body).toggleClass('triggering', pixelpulse.triggering)
	
	@cancelAllActions()
	
	xaxis = pixelpulse.timeseries_x
	if @triggering
		xaxis.min = -5
		xaxis.max = 5
		
		for lg in @timeseries_graphs
			lg.showXgridZero = yes
			
		default_trigger_level = 2.5
		@data_listener.configureTrigger(pixelpulse.streams[0], default_trigger_level, 0.25, 0, 1)
		@triggerOverlay = new livegraph.TriggerOverlay(@timeseries_graphs[0])
		@triggerOverlay.position(default_trigger_level)
		@fakeAutoset(false)
	else
		xaxis.min = -10
		xaxis.max = 0
		xaxis.window(-10, 0, true)
		for lg in @timeseries_graphs
			lg.showXgridZero = no
		@triggerOverlay.remove()
		@triggerOverlay = null
		@data_listener.disableTrigger()
		
	pixelpulse.updateTimeSeries()
		
	for i in @timeseries_graphs then i.needsRedraw(true)
			
	pixelpulse.triggeringChanged.notify(@triggering)

tsUpdateFlag = false	
pixelpulse.timeseriesNeedsUpdate = ->
	unless tsUpdateFlag
		setTimeout(pixelpulse.updateTimeSeries, 10)
		tsUpdateFlag = true

	
# run after a window changing operation to fetch new data from the server
pixelpulse.updateTimeSeries = (min, max) ->	
	xaxis = pixelpulse.timeseries_x
	lg = pixelpulse.timeseries_graphs[0]
	listener = pixelpulse.data_listener
	
	return unless lg.width
	
	min ?= xaxis.visibleMin
	max ?= xaxis.visibleMax
	
	span = max-min
	
	min = Math.max(min - 0.4*span, xaxis.min)
	max = Math.min(max + 0.4*span, xaxis.max)
	pts = lg.width / 2 * (max - min) / span
	
	#console.log('configure', min, max, pts)
	listener.configure(min, max, pts)
	listener.submit()
	tsUpdateFlag = false

# As part of a x-axis changing action, check if we need to fetch new server data	
pixelpulse.checkWindowChange = (min, max, done, target) ->
	xaxis = pixelpulse.timeseries_x
	lg = pixelpulse.timeseries_graphs[0]
	l = pixelpulse.data_listener
	
	if target
		if (target[1] - target[0]) < 0.5 * (max - min)
			# if zooming in, wait until near the end to change the view
			return
		
		[min, max] = target
	
	span = max-min

	if ((l.xmax < max or l.xmin > min) \  # Off the edge of the data
	and max <= xaxis.max and min >= xaxis.min) \ # But not off the edge of the available data
	or span/(l.xmax - l.xmin)*l.requestedPoints < 0.45 * lg.width # or resolution too low
		pixelpulse.updateTimeSeries(min, max)
		
pixelpulse.cancelAllActions = ->
	for lg in pixelpulse.timeseries_graphs
		lg.startAction(null)

# Set the timeseries view to the specified window
pixelpulse.goToWindow = (min, max, animate=true) ->
	if animate
		opts = {time: 200} 
		return new livegraph.AnimateXAction(opts, @timeseries_graphs[0], min, max, @timeseries_graphs)
	else
		@timeseries_x.window(min, max, true)
		for lg in @timeseries_graphs
			lg.needsRedraw(true)

pixelpulse.zoomCompletelyOut = (animate=true) ->
	pixelpulse.goToWindow(pixelpulse.timeseries_x.min, pixelpulse.timeseries_x.max, animate)
	
pixelpulse.fakeAutoset = (animate = true) ->
	# Fake autoset by assuming the CEE is sourcing the wave
	# Just find out what frequency the source is
	src = @data_listener.trigger.stream.parent.source
	sampleTime = server.device.sampleTime
	
	f = 3
	
	timescale = switch src.source
		when 'adv_square'
			(src.highSamples + src.lowSamples) * sampleTime*f
		when 'sine', 'triangle', 'square'
			src.period * sampleTime*f
		else
			0.125
			
	pixelpulse.goToWindow(-timescale, timescale, animate)

pixelpulse.autozoom = ->
	if @triggering
		@fakeAutoset()
	else
		@zoomCompletelyOut()
		
pixelpulse.canChangeView = -> pixelpulse.triggering or not server.device.captureState

pixelpulse.captureState.subscribe (s) ->
	if not pixelpulse.canChangeView()
		pixelpulse.zoomCompletelyOut(false)
		
pixelpulse.destroyView = ->
	$('#streams section.channel').remove()
	$('#sidegraphs > section').empty()
	if @meter_listener
		@meter_listener.cancel()
	if @data_listener
		@data_listener.cancel()
	for i in @channelviews then i.destroy()
	pixelpulse.setLayout(0)
	
numberWidget = (value, conv, changed) ->
	sampleTime = server.device.sampleTime
	
	switch conv
		when 's'
			min = sampleTime
			max = 10
			step = 0.1
			unit = 's'
			digits = 4
		when 'hz'
			min = 0.1
			max = 1/sampleTime/5
			step = 1
			unit = 'Hz'
			digits = 1
		else
			min = conv.min
			max = conv.max
			unit = conv.units
			step = 0.1
			digits = conv.digits

	d = $('<input type=number>')
			.attr({min, max, step})
			.change ->
				v = parseFloat(d.val())
				
				if conv is 's'
					v /= sampleTime
				else if conv is 'hz'
					v = (1/v)/sampleTime
					
				changed(v)
				
	span = $("<span>").append(d).append(unit)
				
	span.set = (v) ->
		switch conv
			when 's'
				v *= sampleTime
			when 'hz'
				v = 1/(v * sampleTime)
		d.val(v.toFixed(digits))
		
	span.set(value)
	
	return span
	
selectDropdown = (options, selectedOption, showText, changed) ->
	dropdown = false
	el = $("<div class='select-dropdown'>").click (e) ->
		if not dropdown and e.target == el.get(0)
			showDropdown()
			return false
			
	if showText
		el.addClass('text-dropdown')
	else
		el.addClass('icon-dropdown')
		
	iconFor = (option) -> 'icon-'+option.toLowerCase()
		
	select = (option) ->
		if showText
			el.text(option)
		if selectedOption
			el.removeClass(iconFor selectedOption)
		el.addClass(iconFor option)
		selectedOption = option
	el.select = select
		
	hideDropdown = ->
		if dropdown
			dropdown.remove()
			dropdown = false
	el.hideDropdown = hideDropdown
			
	showDropdown = ->
		$(document.body).one 'click', hideDropdown
		
		clickfunc = ->
			o = $(this).data('option')
			select(o)
			changed(o)
	
		dropdown = $("<ul>").appendTo(el)
		for i in options
			$("<li>").text(i).addClass(iconFor i).data('option', i).click(clickfunc).appendTo(dropdown)
	
	select(selectedOption) if selectedOption
	return el

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
			
		pixelpulse.meter_listener.updated.listen @onValues
			
	destroy: -> for i in @streamViews then i.destroy()
	
	onValues: (m) =>
		# Use a heuristic to determine whether the output is limited by a rail
		
		source = @channel.source
		
		unless source.source is 'constant' then return
		
		for id, s of @channel.streams
			if s.outputMode is source.mode
				sourceStream = s
			else
				measureStream = s
				
		if not sourceStream and measureStream then return
		
		arr = m.data[pixelpulse.meter_listener.streamIndex(sourceStream)]
		sourceValue = arr[arr.length - 1]
		
		arr = m.data[pixelpulse.meter_listener.streamIndex(measureStream)]
		measureValue = arr[arr.length - 1]
		
		sourceChannelIsOff = Math.abs(sourceValue - source.value) > sourceStream.uncertainty * 5
		measureChannelIsHiRail = Math.abs(measureValue - measureStream.max) < measureStream.uncertainty*5
		measureChannelIsLoRail = Math.abs(measureValue - measureStream.min) < measureStream.uncertainty*5
		
		isLimited = sourceChannelIsOff and (measureChannelIsHiRail or measureChannelIsLoRail)
		
		@section.toggleClass('limited', isLimited)

class pixelpulse.StreamView
	constructor: (@channelView, @stream, @index)->
		@section = $("<section class='stream'>")
		@aside = $("<aside>").appendTo(@section)
		@el = @section.get(0)
		
		@h1 = $("<h1>").text(@stream.displayName).appendTo(@aside)

		@timeseriesElem = $("<div class='livegraph'>").appendTo(@section)

		@addReadingUI(@aside)
		
		@initTimeseries()
		
		pixelpulse.layoutChanged.subscribe @relayout

		@isLimited = false
		
		pixelpulse.meter_listener.updated.listen (m) =>
			index = pixelpulse.meter_listener.streamIndex(@stream)
			arr = m.data[index]
			@onValue arr[arr.length - 1]
		
		@sourceHead = $("<h2>").appendTo(@aside)
		
		modeOpts = ['Source', 'Measure']
		if @stream.id == 'i' then modeOpts.push("Disable") #TODO: not cee-specific
		
		@sourceModeSel = selectDropdown modeOpts, null, true, (o)=>
			m = switch o
				when "Disable" then 0
				when "Source" then @stream.outputMode
				when "Measure"
					if @stream.id is 'v' then 2
					else if @stream.id is 'i' then 1  #TODO: not CEE-specific
					else 0
			console.log("setting mode", m, o, @stream.outputMode)
			@stream.parent.setConstant(m, 0)
					
		@sourceModeSel.appendTo(@sourceHead)
		
		@sourceTypeSel = selectDropdown ['Constant', 'Square', 'Sine', 'Triangle'], null, false, (o) ->
			@stream.parent.guessSourceOptions(o.toLowerCase())
		@sourceTypeSel.appendTo(@sourceHead)			
	
		@source = $("<div class='source'>").appendTo(@aside)
		@stream.parent.outputChanged.listen @sourceChanged
		
		if @stream.parent.source
			@sourceChanged(@stream.parent.source)
		
		if @stream.id == 'v' # TODO: flag from server to make not CEE-specific
			@gainOpts = $("<select class='gainopts'>").appendTo(@aside).change =>
				@stream.setGain(parseInt(@gainOpts.val()))
			
			for i in GAIN_OPTIONS
				@gainOpts.append($("<option>").html(i+'&times;').attr('value', i))

		@stream.gainChanged.listen @gainChanged	
		@gainChanged(@stream.gain)
		
	addReadingUI: (tile) ->
		tile.append($("<span class='reading'>")
			.append(@value = $("<span class='value'>"))
			.append($("<span class='unit'>").text(@stream.units)))
		
	onValue: (v) ->
		@value.text(v.toFixed(@stream.digits))
		if (v < 0)
			@value.addClass('negative')
		else
			@value.removeClass('negative')
		

	initTimeseries: ->
		@xaxis = pixelpulse.timeseries_x
		@yaxis = new livegraph.Axis(@stream.min, @stream.max)
		@series =  pixelpulse.data_listener.series('time', @stream)
		@series.color = COLORS[@channelView.index][@index]
		
		@lg = new livegraph.canvas(@timeseriesElem.get(0), @xaxis, @yaxis, [@series])
		
		pixelpulse.timeseries_graphs.push(@lg)
				
		@lg.onClick = (pos, e) =>
			[x,y] = pos
			if x > @lg.width - 45
				new DragToSetAction(this, pos)
			else if x < 45 and pixelpulse.triggering
				if pixelpulse.data_listener.trigger.stream != @stream
					pixelpulse.triggerOverlay.remove()
					pixelpulse.triggerOverlay = new livegraph.TriggerOverlay(@lg)
				new DragTriggerAction(this, pos)
			else if pixelpulse.canChangeView()
				new livegraph.DragScrollAction(@lg, pos,
					pixelpulse.timeseries_graphs)
				
				
		@lg.onDblClick = (e, pos, btn) =>
			if not pixelpulse.canChangeView() then return
			zf = if e.shiftKey or btn==2 then 2 else 0.5
			opts = {time: 200, zoomFactor:zf } 
			return new livegraph.ZoomXAction(opts, @lg, pos,
				pixelpulse.timeseries_graphs)
				
		@lg.onResized = ->
			pixelpulse.timeseriesNeedsUpdate()
		
		@series.updated.listen =>
			@lg.needsRedraw()
	
	relayout: =>
		@lg.resized()
		
	sourceChanged: (m) =>
		@isSource = isSource = (m.mode == @stream.outputMode)
		
		if m.mode != @lastSourceMode
			@lastSourceMode = m.mode
			@sourceHead.toggleClass('isDriving', isSource)
			
			opt = if isSource then "Source" else "Measure"
			opt = if @stream.id is'i' and m.mode == 0 then "Disable" else opt
								
			@sourceModeSel.select(opt)
			
			@sourceTypeSel.toggle(isSource) #hide sourceType if not source
			
		if isSource and m.source == 'constant'
			unless @dot
				@dot = new livegraph.Dot(@lg, @lg.cssColor(), @lg.cssColor())
			@dot.position(m.value)
		else
			@dot.remove() if @dot
			@dot = null
		
		if isSource
			if m.source != @sourceType
				@sourceType = m.source
				@sourceTypeSel.select(@sourceType)
				
				@sourceInputs = sourceInputs = {}
				@source.empty()
			
				stream = @stream
				channel = stream.parent
			
				ATTRS = ['value', 'high', 'low', 'highSamples', 'lowSamples', 'offset', 'amplitude', 'period']
			
				propInput = (prop, conv) ->
					if conv == 'val' then conv = stream
					
					sourceInputs[prop] = numberWidget m[prop], conv, (v) =>
						d = {}
						for i in ATTRS
							if channel.source[i]? then d[i] = channel.source[i]
						d[prop] = v
					
						channel.set(channel.source.mode, channel.source.source, d)
					
			
				switch m.source
					when 'constant'
						@source.append propInput('value', 'val')
					when 'adv_square'
						@source.append propInput('low', 'val')
						@source.append ' for '
						@source.append propInput('lowSamples', 's')
						@source.append propInput('high', 'val')
						@source.append ' for '
						@source.append propInput('highSamples', 's')
					when 'sine', 'triangle', 'square'
						@source.append propInput('offset', 'val')
						@source.append propInput('amplitude', 'val')
						@source.append propInput('period', 'hz')
			else
				for prop, inp of @sourceInputs
					inp.set(m[prop])
			
		else
			@source.empty()
			@sourceType = null
			
	gainChanged: (g) =>
			if @gainOpts then @gainOpts.val(g)
			@yaxis.window(@yaxis.min/g, @yaxis.max/g, true)
			@lg.needsRedraw(true)
			
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
		
		@xstream.gainChanged.listen @xGainChanged	
		@xGainChanged(@xstream.gain)
		@ystream.gainChanged.listen @yGainChanged	
		@yGainChanged(@ystream.gain)
		
		@series.updated.listen @updated
		pixelpulse.layoutChanged.subscribe @relayout
		
		@lg.needsRedraw(true)
		
	hidden: ->
		if @series
			@series.updated.unListen @updated
		pixelpulse.layoutChanged.unListen @relayout
		
		if @xaxis then @xstream.gainChanged.unListen @xGainChanged
		if @yaxis then @ystream.gainChanged.unListen @yGainChanged
	
	updated: => @lg.needsRedraw()
	
	xGainChanged: (g) =>
		@xaxis.window(@xaxis.min/g, @xaxis.max/g, true)
		@lg.needsRedraw(true)
	
	yGainChanged: (g) =>
		@yaxis.window(@yaxis.min/g, @yaxis.max/g, true)
		@lg.needsRedraw(true)
	
	relayout: =>
		@lg.resized()
		


class DragYAction extends livegraph.Action
	constructor: (@view, pos) ->
		super(@view.lg, pos)
		@view.lg.startDrag(pos)
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

btnPopup = (button, popup) ->
	button = $(button)
	popup = $(popup)
	state = false
	
	showPopup = ->
		popup.fadeIn().css(left: button.position().left, bottom: '42px')
		$(document).one 'click', ->
			hidePopup()
		button.addClass('active')
		state = true
		pixelpulse.hidePopup = -> $(document).click()
		
	hidePopup = ->
		popup.fadeOut()
		button.removeClass('active')
		state = false
	
	$(button).click (e)->
		if not state
			showPopup()
			return false
		
	$(popup).click (e) -> false #block events
		
$(document).ready ->
	btnPopup('#device-config', '#config-popup')
	
	$('#device-config').click ->
		$('#config-sample-rate').val(server.device.sampleTime)
		
		
	$('#device-config-apply').click ->
		pixelpulse.hidePopup()	
		server.device.configure({sampleTime:parseFloat($('#config-sample-rate').val())})
		 
