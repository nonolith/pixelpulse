# Pixelpulse UI elements
# (C) 2011 Nonolith Labs
# Author: Kevin Mehall <km@kevinmehall.net>
# Distributed under the terms of the GNU GPLv3

pixelpulse = (window.pixelpulse ?= {})

pixelpulse.initViewGlobals = ->
	@timeseries_x = new livegraph.Axis(-10, 0)
	@timeseries_graphs = []
	
pixelpulse.finishViewInit = ->
	# show the x-axis ticks on the last stream
	lastGraph = @timeseries_graphs[@timeseries_graphs.length-1]
	lastGraph.showXbottom = yes
	
	# push the bottom out into the space reserved by #timeaxis
	$(lastGraph.div).css('margin-bottom', -livegraph.AXIS_SPACING)
	$(lastGraph.div).siblings('aside').css('margin-bottom', -livegraph.AXIS_SPACING)
	lastGraph.resized()

# run after a window changing operation to fetch new data from the server
pixelpulse.updateTimeSeries = ->
	for c in pixelpulse.channelviews
		for s in c.streamViews
			s.updateSeries()

class pixelpulse.ChannelView
	constructor: (@channel) ->
		@section = $("<section class='channel'>")
		@el = @section.get(0)
		
		@header = $("<header>").appendTo(@section)
		
		@aside = $("<aside>").appendTo(@header)
		
		@h1 = $("<h1>").text(@channel.displayName).appendTo(@aside)
		
		@streamViews = for id, s of @channel.streams
			v = new pixelpulse.StreamView(s)
			@section.append(v.el)
			v
			
	destroy: ->
		s.destroy() for s in @streamViews
		

class pixelpulse.StreamView
	constructor: (@stream)->
		@section = $("<section class='stream'>")
		@aside = $("<aside>").appendTo(@section)
		@el = @section.get(0)
		
		@h1 = $("<h1>").text(@stream.displayName).appendTo(@aside)

		@timeseriesElem = $("<div class='livegraph'>").appendTo(@section)

		@addReadingUI(@aside)

		@listener = @stream.listen =>
			@onValue(@listener.lastData)
			
		@source = $("<div class='source'>").appendTo(@aside)
		@stream.parent.outputChanged.listen @sourceChanged
		
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
		@series =  @stream.series()
		
		@lg = new livegraph.canvas(@timeseriesElem.get(0), @xaxis, @yaxis, [@series])
		
		pixelpulse.timeseries_graphs.push(@lg)
		
		$(window).resize => @lg.resized()

		@lg.onResized = => @updateSeries()
				
		@lg.onClick = (pos) =>
			[x,y] = pos
			if x < @lg.width - 45
				return new livegraph.DragScrollAction(@lg, pos,
					pixelpulse.timeseries_graphs, pixelpulse.updateTimeSeries)
			else
				return new DragToSetAction(this, pos)
				
		@lg.onDblClick = (e, pos) =>
			opts = {time: 200, zoomFactor: if e.shiftKey then 2 else 0.5} 
			return new livegraph.ZoomXAction(opts, @lg, pos,
				pixelpulse.timeseries_graphs, pixelpulse.updateTimeSeries)
		
		@isSource = false
		@dotFollowsStream = false
		if @stream.outputMode
			@dot = @lg.addDot('white', 'blue')
			@stream.parent.outputChanged.listen (m) =>
				@isSource = (m.mode == @stream.outputMode)
				@dotFollowsStream = false
				@section.toggleClass('sourcing', @isSource)
				
				if m.source is 'constant'
					@dot.fill = if @isSource then 'blue' else 'white'
					@dot.render()
					
					if @isSource
						@dot.position(m.value)
					else
						@dot.position(@series.listener.lastData)
						@dotFollowsStream = true
				else
					@dot.position(null)
								
		@series.updated.listen =>
			@lg.needsRedraw()
			if @dotFollowsStream then @dot.position(@series.listener.lastData)
			
		@lg.needsRedraw()
		
	updateSeries: ->
		min = Math.max(@xaxis.visibleMin - 0.5*@xaxis.span(), @xaxis.min)
		max = Math.min(@xaxis.visibleMax + 0.5*@xaxis.span(), @xaxis.max)
		pts = @lg.width / 2 * (max - min) / @xaxis.span()
		
		if min != @series.xmin or max != @series.xmax or @series.requestedPoints != pts
			@series.configure(min, max, pts)
			
	sourceChanged: (m) =>
		if m.mode == @stream.outputMode
			@source.empty()
			
			stream = @stream
			channel = stream.parent
			sampleTime = channel.parent.sampleTime
			
			sel = $("<select>")
			for i in ['constant', 'square', 'sine']
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
		@series.destroy()


class DragToSetAction extends livegraph.Action
	constructor: (@view, pos) ->
		@transform = livegraph.makeTransform(@view.lg.geom, @view.lg.xaxis, @view.lg.yaxis)
		@onDrag(pos)
	
	onDrag: ([x, y]) ->
		[x, y] = livegraph.invTransform(x,y,@transform)
		@view.stream.parent.setConstant(@view.stream.outputMode, y)
	

