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
			track_feature("pause")
		else
			server.device.startCapture()
			track_feature("start")

	pixelpulse.captureState.subscribe (s) ->
		$('#startpause').attr('title', if s then 'Pause' else 'Start')



COLORS = [
	[[0x32, 0x00, 0xC7], [00, 0x32, 0xC7]]
	[[00, 0x7C, 0x16], [0x6f, 0xC7, 0x00]]
]

GAIN_OPTIONS = [1, 2, 4, 8, 16, 32, 64]

pixelpulse.initView = (dev) ->
	@timeseries_graphs = []
	@channelviews = []
	
	@streams = []
	for chId, channel of dev.channels
		for sId, stream of channel.streams
			@streams.push(stream)
		
	@meter_listener = new server.Listener(dev, @streams)
	@meter_listener.configure()
	
	@timeseries = new pixelpulse.TimeseriesGraphListener(dev, @streams)
	@timeseries.queueWindowUpdate()

	i = 0
	for chId, channel of dev.channels
		s = new pixelpulse.ChannelView(channel, i++)
		pixelpulse.channelviews.push(s)
		$('#streams').append(s.el)
	
	@sidegraph1 = new pixelpulse.XYGraphView(document.getElementById('sidegraph1'))
	@sidegraph2 = new pixelpulse.XYGraphView(document.getElementById('sidegraph2'))
	
	# show the x-axis ticks on the last stream
	lastGraph = @timeseries.graphs[@timeseries.graphs.length-1]
	lastGraph.showXbottom = yes
	
	# push the bottom out into the space reserved by #timeaxis
	$(lastGraph.div).css('margin-bottom', -livegraph.AXIS_SPACING+5)
	$(lastGraph.div).siblings('aside').css('margin-bottom', -livegraph.AXIS_SPACING+5)
	lastGraph.resized()
	
	@meter_listener.submit()

pixelpulse.toggleTrigger = ->
	triggering = not @timeseries.isTriggerEnabled()
	$(document.body).toggleClass('triggering', triggering)
	
	@timeseries.cancelAllActions()
	
	xaxis = pixelpulse.timeseries_x
	if triggering
		@timeseries.enableTrigger()
	else
		@timeseries.disableTrigger()
		
	@timeseries.updateWindow()
			
	pixelpulse.triggeringChanged.notify(@triggering)

	track_feature("trigger")

pixelpulse.autozoom = =>
	@timeseries.autozoom()
	track_feature("autoset")

pixelpulse.captureState.subscribe (s) ->
	if not pixelpulse.timeseries.canChangeView()
		pixelpulse.timeseries.zoomCompletelyOut(false)
		
pixelpulse.destroyView = ->
	$('#streams section.channel').remove()
	$('#sidegraphs > section').empty()
	if @meter_listener
		@meter_listener.cancel()
	if @timeseries
		@timeseries.cancel()
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
		
		graphElem = @timeseriesElem.get(0)
		color = COLORS[@channelView.index][@index]
		@lg = pixelpulse.timeseries.makeGraph(@stream, graphElem, color)

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
		
		@sourceTypeSel = selectDropdown ['Constant', 'Square', 'Sine', 'Triangle'], null, false, (o) =>
			@stream.parent.guessSourceOptions(o.toLowerCase())
		@sourceTypeSel.appendTo(@sourceHead)			
	
		@source = $("<div class='source'>").appendTo(@aside)
		@stream.parent.outputChanged.listen @sourceChanged
		
		if @stream.parent.source
			@sourceChanged(@stream.parent.source)
		
		if @stream.id == 'v' or flags.enableigain # TODO: flag from server to make not CEE-specific
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
		
	sourceChanged: (m) =>
		isSource = (m.mode == @stream.outputMode)
		
		if m.mode != @lastSourceMode
			@lastSourceMode = m.mode
			@sourceHead.toggleClass('isDriving', isSource)
			
			opt = if isSource then "Source" else "Measure"
			opt = if @stream.id is'i' and m.mode == 0 then "Disable" else opt
								
			@sourceModeSel.select(opt)
			
			@sourceTypeSel.toggle(isSource) #hide sourceType if not source
			
		@lg.sourceChanged(isSource, m)
		
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
		@lg.gainChanged(g)

	destroy: ->

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

	if l != 0 then track_feature("set-layout")

pixelpulse.layoutChanged.subscribe ->
	pixelpulse.timeseries.redrawAll() if pixelpulse.timeseries
	
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
		
		@series = pixelpulse.timeseries.series(@xstream, @ystream)
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
		$('#config-sample-rate option')
			.hide()
			.filter(-> parseFloat($(this).attr('value')) >= server.device.minSampleTime)
				.show()

		$('#config-sample-rate').val(server.device.sampleTime)
		
		
	$('#device-config-apply').click ->
		pixelpulse.hidePopup()	
		server.device.configure({sampleTime:parseFloat($('#config-sample-rate').val())})
		track_feature("config-apply")

		 
