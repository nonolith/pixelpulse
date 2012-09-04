
pixelpulse = (window.pixelpulse ?= {})

class pixelpulse.TimeseriesGraphListener extends server.DataListener
	constructor: (@device, @streams, @graphs=[]) ->
		super(@device, @streams)

		@xaxis = new livegraph.Axis(-10, 0)
		@xaxis.unit = 's'
		@xaxis.windowChanged = @checkWindowChange

		@updatePending = no

	makeGraph: (stream, elem, color) ->
		console.assert(stream in @streams, "stream ", stream, "not in", @streams)
		g = new TimeseriesGraph(this, stream, elem, color)
		@graphs.push(g)
		return g

	queueWindowUpdate: ->
		unless @updatePending
			setTimeout(@updateWindow, 10)
			@updatePending = true

	# run after a window changing operation to fetch new data from the server
	updateWindow: (min, max) =>	
		@updatePending = false
		lg = @graphs[0]
		
		return unless lg.width
		
		min ?= @xaxis.visibleMin
		max ?= @xaxis.visibleMax
		
		span = max-min
		
		min = Math.max(min - 0.2*span, @xaxis.min)
		max = Math.min(max + 0.2*span, @xaxis.max)
		pts = lg.width / 2 * (max - min) / span
		
		@configure(min, max, pts)
		@submit()

	# As part of a x-axis changing action, check if we need to fetch new server data	
	checkWindowChange: (min, max, done, target) =>
		lg = @graphs[0]
		l = this
		
		if target
			if (target[1] - target[0]) < 0.5 * (max - min)
				# if zooming in, wait until near the end to change the view
				return
			
			[min, max] = target
		
		span = max-min

		if ((l.xmax < max or l.xmin > min) \  # Off the edge of the data
		and max <= @xaxis.max and min >= @xaxis.min) \ # But not off the edge of the available data
		or span/(l.xmax - l.xmin)*l.requestedPoints < 0.45 * lg.width # or resolution too low
			@updateWindow(min, max)

	# Set the timeseries view to the specified window
	goToWindow: (min, max, animate=true) ->
		if animate
			opts = {time: 200} 
			return new livegraph.AnimateXAction(opts, @graphs[0], min, max, @graphs)
		else
			@xaxis.window(min, max, true)
			@redrawAll(true)

	redrawAll: (full=false)->
		for lg in @graphs then lg.needsRedraw(full)

	onMessage: (m) ->
		super(m)
		@redrawAll()

	cancelAllActions: ->
		for lg in @graphs then lg.startAction(null)

	zoomCompletelyOut: (animate=true) ->
		@goToWindow(@xaxis.min, @xaxis.max, animate)
	
	# Fake autoset by assuming the CEE is sourcing the wave
	# Just find out what frequency the source is
	fakeAutoset: (animate = true) ->
		src = @trigger.stream.parent.source
		sampleTime = @device.sampleTime
		
		f = 2
		
		timescale = switch src.source
			when 'adv_square'
				(src.highSamples + src.lowSamples) * sampleTime*f
			when 'sine', 'triangle', 'square', 'arb'
				src.period * sampleTime*f
			else
				0.125
				
		@goToWindow(Math.max(@xaxis.min, -timescale), Math.min(@xaxis.max, timescale), animate)

	autozoom: ->
		if @trigger
			@fakeAutoset()
		else
			@zoomCompletelyOut()
		
	canChangeView: ->
		@trigger or not server.device.captureState

	updateDotsAll: ->
		i.updateDots() for i in @graphs

	isTriggerEnabled: -> return if @trigger then true else false

	enableTrigger: ->
		@xaxis.min = -1
		@xaxis.max = 1
		
		for lg in @graphs
			lg.showXgridZero = yes
			
		default_trigger_level = 2.5
		tp = if flags.outputTrigger then 'out' else 'in'
		
		@configureTrigger(@streams[0], default_trigger_level, 0.1, 0, 0.5, tp)
		@triggerOverlay = new livegraph.TriggerOverlay(@graphs[0])
		@triggerOverlay.position(default_trigger_level)
		@setTrigger(@streams[0], default_trigger_level, false)
		@fakeAutoset(false)

	dragTrigger: (stream, level) ->
		if stream.isSource() and @device.hasOutTrigger
			@trigger.level = level = stream.sourceLevel()

		@triggerOverlay.position(level) if level?

	updateTriggerForOutput:  ->
		stream = @trigger.stream

		if stream.isSource() != (@trigger.type == 'out') and @device.hasOutTrigger
			@setTrigger(stream, @trigger.level)

		@dragTrigger(stream)

	setTrigger: (stream, level=0, submit=true) ->
		@trigger.stream = stream
		@trigger.level = level

		@trigger.type = if stream.isSource() and @device.hasOutTrigger
			@trigger.force = if stream.parent.source.source is 'constant' then 0.5 else 10
			'out'
		else
			@trigger.force = 0.5
			'in'

		@dragTrigger(stream, level)

		@submit() if submit

		@triggerOverlay.showBorder(@trigger.type == 'in')
		@updateDotsAll()

	disableTrigger: ->
		@xaxis.min = -10
		@xaxis.max = 0
		@xaxis.window(-10, 0, true)
		for lg in @graphs
			lg.showXgridZero = no
		@triggerOverlay.remove()
		@triggerOverlay = null
		super()
		@updateDotsAll()
		@redrawAll(true)

class DataSeries extends livegraph.Series
	constructor: (@listener, @xseries, @yseries) ->
		@updated = @listener.updated
		@listener.reset.listen @reset
		@reset()
	
	reset: =>
		@xdata = (if @xseries == 'time'
			@listener.xdata
		else
			@listener.data[@listener.streamIndex(@xseries)])
		@ydata = @listener.data[@listener.streamIndex(@yseries)]

class TimeseriesGraph extends livegraph.canvas
	constructor: (@timeseries, @stream, elem, color) ->
		@yaxis = new livegraph.Axis(@stream.min, @stream.max)
		@dseries = new DataSeries(@timeseries, 'time', @stream)
		@dseries.color = color

		@dots = {}
		@dotConfig = ''

		super(elem, @timeseries.xaxis, @yaxis, [@dseries])
			
	onClick: (pos, e) =>
		[x,y] = pos

		if @dotConfig is 'wave' and @dots.offset.isNear(x, y, 10)
			new DragDotAction this, pos, (lg, x, y) ->
				lg.stream.parent.setAdjust {offset:y}

		else if @dotConfig is 'wave' and @dots.period.isNear(x, y, 10)
			new DragDotAction this, pos, (lg, x, y) ->
				amplitude = y - lg.stream.parent.source.offset
				period = Math.max(5, x * 4 / server.device.sampleTime)
				lg.stream.parent.setAdjust {amplitude, period}

		else if @dotConfig is 'square' and @dots.v1.isNear(x, y, 10)
			new DragDotAction this, pos, (lg, x, y) ->
				{highSamples, lowSamples} = lg.stream.parent.source
				period = highSamples + lowSamples
				x = Math.max(0, Math.min(period-1, x/server.device.sampleTime)) + 1
				lg.stream.parent.setAdjust
					high: y
					highSamples: Math.round(x)
					lowSamples: period - Math.round(x)
					dutyCycleHint: x / period

		else if @dotConfig is 'square' and @dots.v2.isNear(x, y, 10)
			new DragDotAction this, pos, (lg, x, y) ->
				{highSamples, lowSamples, dutyCycleHint} = lg.stream.parent.source
				oldPeriod = highSamples + lowSamples
				newPeriod = Math.round(Math.max(2, x/server.device.sampleTime + 1))
				lg.stream.parent.setAdjust
					highSamples: Math.round(dutyCycleHint * newPeriod) 
					lowSamples: Math.round((1-dutyCycleHint) * newPeriod)
					low: y
					dutyCycleHint: dutyCycleHint

		else if x > @width - 45
			new DragDotAction this, pos, (lg, x, y) ->
				lg.stream.parent.setConstant(lg.stream.outputMode, y)

		else if x < 45 and @timeseries.trigger
			if @timeseries.trigger.stream != @stream
				@timeseries.triggerOverlay.remove() if @timeseries.triggerOverlay
				@timeseries.triggerOverlay = new livegraph.TriggerOverlay(this)
				@timeseries.setTrigger(@stream, null, false)
			new DragTriggerAction(this, pos)
		else if @timeseries.canChangeView()
			new livegraph.DragScrollAction(this, pos, @timeseries.graphs)
		
	onDblClick: (e, pos, btn) =>
		if not @timeseries.canChangeView() then return
		zf = if e.shiftKey or btn==2 then 2 else 0.5

		if zf < 1 and @timeseries.xaxis.span() < 40 * @timeseries.device.sampleTime
			# Prevent zooming in uselessly far
			return

		opts = {time: 200, zoomFactor:zf } 
		return new livegraph.ZoomXAction(opts, this, pos,
			@timeseries.graphs)

	resetDots: (t) ->
		unless @dotConfig is t
			for i, v of @dots
				v.remove()
			@dots = {}
			@dotConfig = t
			return true

	updateDots: ->
		isTriggerStream = @timeseries.trigger?.stream == @stream
		isSource = @stream.isSource()
		s = @stream.parent.source

		sampleTime = server.device.sampleTime

		if isSource and s.source == 'constant'
			if @resetDots('constant')
				@dots.d = new livegraph.Dot(this, @dseries.cssColor(), 5, 'r')
			@dots.d.position(null, s.value)
		else if isSource and server.device.hasOutTrigger and isTriggerStream
			if s.source in ['sine', 'triangle', 'square']
				if @resetDots('wave')
					@dots.offset = new livegraph.Dot(this, @dseries.cssColor(), 5, '')
					@dots.period = new livegraph.Dot(this, @dseries.cssColor(), 5, '')
				@dots.offset.position(0, s.offset)
				@dots.period.position(s.period*sampleTime/4, s.offset+s.amplitude)
			else if s.source is 'adv_square'
				if @resetDots('square')
					@dots.v1 = new livegraph.Dot(this, @dseries.cssColor(), 5, '')
					@dots.v2 = new livegraph.Dot(this, @dseries.cssColor(), 5, '')
				@dots.v1.position((s.highSamples-1)*sampleTime, s.high)
				@dots.v2.position((s.highSamples+s.lowSamples-1)*sampleTime, s.low)
			else
				@resetDots('')
		else
			@resetDots('')


	sourceChanged: (isSource, m) ->
		@updateDots()

		if @timeseries.trigger.stream is @stream
			@timeseries.updateTriggerForOutput()

	gainChanged: (g) ->
		@yaxis.window(@yaxis.min/g, @yaxis.max/g, true)
		@needsRedraw(true)
	
	onResized: ->
		@timeseries.queueWindowUpdate()

class DragDotAction extends livegraph.Action
	constructor: (@lg, pos, fn) ->
		super(@lg, pos)
		(@withPos = fn) if fn
		@lg.startDrag(pos)
		@transform = livegraph.makeTransform(@lg.geom, @lg.xaxis, @lg.yaxis)
		@onDrag(pos)
	
	onDrag: ([x, y]) ->
		[x, y] = livegraph.invTransform(x,y,@transform)
		y = Math.min(Math.max(y, @lg.stream.min), @lg.stream.max)
		@withPos(@lg, x, y)
			
class DragTriggerAction extends DragDotAction
	withPos: (lg, x, @y) ->
		pixelpulse.timeseries.dragTrigger(@lg.stream, @y)
	
	onRelease: ->
		pixelpulse.timeseries.setTrigger(@lg.stream, @y)


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
		
		@series = new DataSeries(pixelpulse.timeseries, @xstream, @ystream)
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