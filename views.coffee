# Pixelpulse UI elements
# (C) 2011 Nonolith Labs
# Author: Kevin Mehall <km@kevinmehall.net>
# Distributed under the terms of the GNU GPLv3

pixelpulse = (window.pixelpulse ?= {})

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
	pixelpulse.timeseries.autozoom()
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
			o = o.toLowerCase()
			o = 'adv_square' if o is 'square' and server.device.hasAdvSquare
			@stream.parent.guessSourceOptions(o)
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
				@sourceTypeSel.select(if @sourceType == 'adv_square' then 'square' else @sourceType)
				
				@sourceInputs = sourceInputs = []
				@source.empty()
			
				stream = @stream
				channel = stream.parent
			
				propInput = (filter) ->
					w = numberWidget filter
					sourceInputs.push(w)
					return w

				valFilter = (prop) ->
					changedfn: (v) =>
						console.log('set', v)
						channel.setAdjust(prop, v)
					valuefn: (m) -> m[prop]
					min: stream.min
					max: stream.max
					step: Math.pow(10, -stream.digits)
					unit: stream.units
					digits: stream.digits

				freqFilter = 
					changedfn: (v) =>
						channel.setAdjust('period', 1/(v*server.device.sampleTime))
					valuefn: (m) -> 1/(m.period*server.device.sampleTime) 
					min: 0.1
					max: 1/server.device.sampleTime/5
					step: 1
					unit: 'Hz'
					digits: 1

				freqFilterSquare = $.extend {}, freqFilter,
					changedfn: (v) =>
						period = 1/(v*server.device.sampleTime)
						{dutyCycleHint} = stream.parent.source
						t1 = period * dutyCycleHint
						channel.setAdjust
							highSamples: Math.round(t1)
							lowSamples:  Math.round(period-t1)
							dutyCycleHint: dutyCycleHint

					valuefn: (m) -> 1/((m.highSamples+m.lowSamples)*server.device.sampleTime)

				dutyCycleFilter = 
					changedfn: (v) => 
						v = Math.max(0, Math.min(100, v/100))
						{highSamples,lowSamples} = stream.parent.source
						per = highSamples + lowSamples
						channel.setAdjust
							highSamples: Math.ceil(v*per)
							lowSamples: Math.floor((1-v)*per)
							dutyCycleHint: v
						return
					valuefn: (m) -> m.highSamples/(m.highSamples+m.lowSamples) * 100
					min: 0
					max: 100
					step: 1
					unit: '%'
					digits: 1
					
				switch m.source
					when 'constant'
						@source.append propInput(valFilter('value'))
					when 'adv_square'
						@source.append propInput(valFilter('low'))
						@source.append propInput(valFilter('high'))
						@source.append propInput(freqFilterSquare)
						@source.append propInput(dutyCycleFilter)
					when 'sine', 'triangle', 'square'
						@source.append propInput(valFilter('offset'))
						@source.append propInput(valFilter('amplitude'))
						@source.append propInput(freqFilter)

			for inp in @sourceInputs
				inp.set(m)
			
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

	$(window).resize -> pixelpulse.layoutChanged.notify()
	
	# Start/pause button
	$('#startpause').click ->
		if server.device.captureState
			server.device.pauseCapture()
			track_feature("pause")
		else
			server.device.startCapture()
			track_feature("start")

	pixelpulse.captureState.subscribe (s) ->
		$('#startpause').attr('title', if s then 'Pause' else 'Start')
		$(document.body).toggleClass('capturing', s)