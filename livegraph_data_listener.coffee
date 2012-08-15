
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
		
		min = Math.max(min - 0.4*span, @xaxis.min)
		max = Math.min(max + 0.4*span, @xaxis.max)
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
			@redrawAll()

	redrawAll: ->
		for lg in @graphs then lg.needsRedraw(true)

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
		
		f = 3
		
		timescale = switch src.source
			when 'adv_square'
				(src.highSamples + src.lowSamples) * sampleTime*f
			when 'sine', 'triangle', 'square', 'arb'
				src.period * sampleTime*f
			else
				0.125
				
		@goToWindow(-timescale, timescale, animate)

	autozoom: ->
		if @triggering
			@fakeAutoset()
		else
			@zoomCompletelyOut()
		
	canChangeView: ->
		@trigger or not server.device.captureState

	isTriggerEnabled: -> return if @trigger then true else false

	enableTrigger: ->
		@xaxis.min = -5
		@xaxis.max = 5
		
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
		if stream.isSource()
			@trigger.level = level = stream.sourceLevel()

		@triggerOverlay.position(level) if level?

	updateTriggerForOutput:  ->
		stream = @trigger.stream

		if stream.isSource() != (@trigger.type == 'out')
			console.log('updateTriggerForOutput changed trigger type', stream.isSource(), @trigger.type == 'in', @trigger.type)
			@setTrigger(stream, @trigger.level)

		@dragTrigger(stream)

	setTrigger: (stream, level=0, submit=true) ->
		@trigger.stream = stream
		@trigger.level = level

		@trigger.type = if stream.isSource() then 'out' else 'in'

		@dragTrigger(stream, level)

		@submit() if submit

		@triggerOverlay.showBorder(@trigger.type == 'in')

	disableTrigger: ->
		@xaxis.min = -10
		@xaxis.max = 0
		@xaxis.window(-10, 0, true)
		for lg in @graphs
			lg.showXgridZero = no
		@triggerOverlay.remove()
		@triggerOverlay = null
		super()

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

		super(elem, @timeseries.xaxis, @yaxis, [@dseries])
			
	onClick: (pos, e) =>
		[x,y] = pos
		if x > @width - 45
			new DragToSetAction(this, pos)
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
		opts = {time: 200, zoomFactor:zf } 
		return new livegraph.ZoomXAction(opts, this, pos,
			@timeseries.graphs)

	sourceChanged: (isSource, m) ->
		if isSource and m.source == 'constant'
			unless @dot
				@dot = new livegraph.Dot(this, @dseries.cssColor(), @dseries.cssColor())
			@dot.position(m.value)
		else
			@dot.remove() if @dot
			@dot = null

		if @timeseries.trigger.stream is @stream
			@timeseries.updateTriggerForOutput()

	gainChanged: (g) ->
		@yaxis.window(@yaxis.min/g, @yaxis.max/g, true)
		@needsRedraw(true)
	
	onResized: ->
		@timeseries.queueWindowUpdate()

class DragYAction extends livegraph.Action
	constructor: (@lg, pos) ->
		super(@lg, pos)
		@lg.startDrag(pos)
		@transform = livegraph.makeTransform(@lg.geom, @lg.xaxis, @lg.yaxis)
		@onDrag(pos)
	
	onDrag: ([x, y]) ->
		[x, y] = livegraph.invTransform(x,y,@transform)
		y = Math.min(Math.max(y, @lg.stream.min), @lg.stream.max)
		@withPos(y)
		
	withPos: (y) ->

class DragToSetAction extends DragYAction
	withPos: (y) ->
		@lg.stream.parent.setConstant(@lg.stream.outputMode, y)
			
class DragTriggerAction extends DragYAction
	withPos: (@y) ->
		pixelpulse.timeseries.dragTrigger(@lg.stream, @y)
	
	onRelease: ->
		pixelpulse.timeseries.setTrigger(@lg.stream, @y)
