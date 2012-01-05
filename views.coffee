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

		@lg.onResized = =>
			if @series.requestedPoints != @lg.width/2
				@updateSeries()
				
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
		if @stream.outputMode
			@dot = @lg.addDot('white', 'blue')
			@stream.parent.outputChanged.listen (m) =>
				@isSource = (m.mode == @stream.outputMode)
				@dot.fill = if @isSource then 'blue' else 'white'
				@dot.render()
				
				@section.toggleClass('sourcing', @isSource)
				
				if @isSource
					@dot.position(m.valueTarget)
				else
					@dot.position(@series.listener.lastData)
			
		@series.updated.listen =>
			@lg.needsRedraw()
			if @dot and not @isSource then @dot.position(@series.listener.lastData)
			
		@lg.needsRedraw()
		
	updateSeries: ->
		min = Math.max(@xaxis.visibleMin - 0.5*@xaxis.span(), @xaxis.min)
		max = Math.min(@xaxis.visibleMax + 0.5*@xaxis.span(), @xaxis.max)
		@series.configure(min, max, @lg.width)

	destroy: ->
		@series.destroy()


class DragToSetAction extends livegraph.Action
	constructor: (@view, pos) ->
		@transform = livegraph.makeTransform(@view.lg.geom, @view.lg.xaxis, @view.lg.yaxis)
		@onDrag(pos)
	
	onDrag: ([x, y]) ->
		[x, y] = livegraph.invTransform(x,y,@transform)
		@view.stream.parent.setConstant(@view.stream.outputMode, y)
	

