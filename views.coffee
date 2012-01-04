# Pixelpulse UI elements
# (C) 2011 Nonolith Labs
# Author: Kevin Mehall <km@kevinmehall.net>
# Distributed under the terms of the GNU GPLv3

pixelpulse = (window.pixelpulse ?= {})

pixelpulse.initViewGlobals = ->
	@timeseries_x = new livegraph.Axis(-10, 0)
	@timeseries_graph_group = []
	
pixelpulse.finishViewInit = ->
	# show the x-axis ticks on the last stream
	lastChannel = @channelviews[@channelviews.length-1]
	lastStream = lastChannel.streamViews[lastChannel.streamViews.length-1]
	lastStream.lg.showXbottom = yes
	
	#push the bottom out into the space reserved by #timeaxis
	$(lastStream.lg.div).css('margin-bottom', -livegraph.AXIS_SPACING)
	$(lastStream.lg.div).siblings('aside').css('margin-bottom', -livegraph.AXIS_SPACING)
	lastStream.lg.resized()
	
	

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
		
		# Make all timeseries graphs update together (for drag-to-scroll)
		pixelpulse.timeseries_graph_group.push(@lg)
		@lg.updateGroup = pixelpulse.timeseries_graph_group
		
		$(window).resize => @lg.resized()

		@lg.onResized = =>
			if @series.requestedPoints != @lg.width
				@series.configure(@xaxis.visibleMin, @xaxis.visibleMax, @lg.width/2)
				
		@lg.onClick = (pos) =>
			[x,y] = pos
			if x < @lg.width - 45
				return new livegraph.DragScrollAction(@lg, pos)
			else
				return new DragToSetAction(this, pos)
		
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

	destroy: ->
		@series.destroy()


class DragToSetAction
	constructor: (@view, pos) ->
		@transform = livegraph.makeTransform(@view.lg.geom, @view.lg.xaxis, @view.lg.yaxis)
		@onDrag(pos)
	
	onDrag: ([x, y]) ->
		[x, y] = livegraph.invTransform(x,y,@transform)
		@view.stream.parent.setConstant(@view.stream.outputMode, y)

	
	onAnim: ->
	onRelease: ->
	cancel: ->
	

