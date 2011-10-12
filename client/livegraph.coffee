# Real-time canvas plotting library
# Distributed under the terms of the BSD License
# (C) 2011 Kevin Mehall (Nonolith Labs) <km@kevinmehall.net>

PADDING = 10
AXIS_SPACING = 25

class LiveGraph
	constructor: (@div, @xaxis, @yaxis, @series) ->		
		@div.setAttribute('class', 'livegraph')
		
#	autoscroll: ->
#		if @xaxis.autoScroll
#			@xaxis.max = @data[@data.length-1][@series[0].xvar]
#			@xaxis.min = @xaxis.max + @xaxis.autoScroll
	
	perfStat_enable: (div)->
		@psDiv = div
		@psCount = 0
		@psSum = 0
		@psRunningSum = 0
		@psRunningCount = 0

		setInterval((=> 
			@psRunningSum += @psSum
			@psRunningCount += @psCount
			@psDiv.innerHTML = "#{@psCount}fps; #{@psSum}ms draw time; Avg: #{@psRunningSum/@psRunningCount}"
			@psCount = 0
			@psSum = 0
		), 1000)

	perfStat: (time) ->
		@psCount += 1
		@psSum += time
			
class Axis
	constructor: (@min, @max) ->	
		if @max == 'auto'
			@autoScroll = min
			@max = 0
		else
			@autoscroll = false
			
		@span = @max - @min
		
	gridstep: ->
		grid=Math.pow(10, Math.round(Math.log(@max-@min)/Math.LN10)-1)
		if (@max-@min)/grid >= 10
			grid *= 2
		return grid/2
		
	grid: ->
		[min, max] = if @autoScroll then [@autoScroll, 0] else [@min, @max]
		arange(min, max, @gridstep())
		
	xtransform: (x, geom) ->
		(x - @min) * geom.width / @span + geom.xleft
		
	ytransform: (y, geom) ->
		geom.ybottom - (y - @min) * geom.height / @span
		
	invYtransform: (ypx, geom) ->
		(geom.ybottom - ypx)/geom.height * @span + @min
		
class DigitalAxis
	min = 0
	max = 1
	
	gridstep: -> 1
	grid: -> [0, 1]
	
	xtransform: (x, geom) -> if x then geom.xleft else geom.xright
	ytransform: (y, geom) -> if y then geom.ytop else geom.ybottom
	invYtransform: (ypx, geom) -> (geom.ybottom - ypx) > geom.height/2
		
digitalAxis = new DigitalAxis()

class Series
	constructor: (@xdata, @ydata, @color, @style) ->


window.requestAnimFrame = 
		 window.requestAnimationFrame ||
         window.webkitRequestAnimationFrame ||
         window.mozRequestAnimationFrame ||
         window.oRequestAnimationFrame ||
         window.msRequestAnimationFrame ||
         (callback, element) -> window.setTimeout(callback, 1000/60)
					
class LiveGraph_canvas extends LiveGraph
	constructor: (div, xaxis, yaxis, series) ->
		super(div, xaxis, yaxis, series)
		
		@axisCanvas = document.createElement('canvas')
		@graphCanvas = document.createElement('canvas')
		@div.appendChild(@axisCanvas)
		@div.appendChild(@graphCanvas)
		
		@showXbottom = window.xbottom || true
		@showYleft = true
		@showYright = true
		@showYgrid = window.ygrid || true
		
		@height = 0
		
		@resized()
	
	resized: () ->
		if @div.offsetWidth == 0 or @div.offsetHeight == 0 then return
			
		@width = @div.offsetWidth
		@height = @div.offsetHeight
		@axisCanvas.width = @width
		@axisCanvas.height = @height
		@graphCanvas.width = @width
		@graphCanvas.height = @height
		
		@ctxg = @graphCanvas.getContext('2d')
		@ctxg.lineWidth = 2
		
		@geom = 
			ytop: PADDING
			ybottom: @height - (PADDING + @showXbottom * AXIS_SPACING)
			xleft: PADDING + @showYleft * AXIS_SPACING
			xright: @width - (PADDING + @showYright * AXIS_SPACING)
			width: @width - 2*PADDING - (@showYleft+@showYright) * AXIS_SPACING
			height: @height - 2*PADDING - @showXbottom  * AXIS_SPACING
		
		@redrawAxis()
		@redrawGraph()
			
	redrawAxis: ->
		@axisCanvas.width = 1
		@axisCanvas.width = @width
		
		@ctxa = @axisCanvas.getContext('2d')
		@ctxa.lineWidth = 2
		
		if @showXbottom then @drawXAxis(@geom.ybottom)	
		if @showYgrid   then @drawYgrid()	
		if @showYleft   then @drawYAxis(@geom.xleft,  'right', -5)
		if @showYright  then @drawYAxis(@geom.xright, 'left',   8)
		
	drawXAxis: (y) ->
		xgrid = @xaxis.grid()
		@ctxa.strokeStyle = 'black'
		@ctxa.beginPath()
		@ctxa.moveTo(@geom.xleft, y)
		@ctxa.lineTo(@geom.xright, y)
		@ctxa.stroke()
		
		textoffset = 5
		@ctxa.textAlign = 'center'
		@ctxa.textBaseline = 'top'
		
		if @xaxis.autoScroll
			[min, max] = [@xaxis.autoScroll, 0]
			offset = @xaxis.max
		else
			[min, max] = [@xaxis.min, @xaxis.max]
			offset = 0
		
		for x in xgrid
			@ctxa.beginPath()
			xp = @xaxis.xtransform(x+offset, @geom)
			@ctxa.moveTo(xp,y-4)
			@ctxa.lineTo(xp,y+4)
			@ctxa.stroke()
			@ctxa.fillText(Math.round(x*10)/10, xp ,y+textoffset)
		
	drawYAxis:  (x, align, textoffset) =>
		grid = @yaxis.grid()
		@ctxa.strokeStyle = 'black'
		@ctxa.textAlign = align
		@ctxa.textBaseline = 'middle'
		
		@ctxa.beginPath()
		@ctxa.moveTo(x, @geom.ytop)
		@ctxa.lineTo(x, @geom.ybottom)
		@ctxa.stroke()
		
		for y in grid
			yp = @yaxis.ytransform(y, @geom)
			
			#draw side axis ticks and labels
			@ctxa.beginPath()
			@ctxa.moveTo(x-4, yp)
			@ctxa.lineTo(x+4, yp)
			@ctxa.stroke()
			@ctxa.fillText(Math.round(y*10)/10, x+textoffset, yp)
			
	drawYgrid: ->
		grid = @yaxis.grid()
		@ctxa.strokeStyle = 'rgba(0,0,0,0.05)'
		for y in grid
			yp = @yaxis.ytransform(y, @geom)
			@ctxa.beginPath()
			@ctxa.moveTo(@geom.xleft, yp)
			@ctxa.lineTo(@geom.xright, yp)
			@ctxa.stroke()
		
	needsRedraw: ->
		if not @redrawRequested
			@redrawRequested = true
			requestAnimFrame(@redrawGraph, @graphCanvas)

	redrawGraph: =>
		if @height != @div.offsetHeight or @width != @div.offsetWidth
			@resized()

		startTime = new Date()

		@redrawRequested = false
		
		@ctxg.clearRect(0,0,@width, @height)
		@ctxg.lineWidth = 2
		
		#@autoscroll()
		
		xmin = @xaxis.min
		xmax = @xaxis.max
		
		for series in @series
			@ctxg.strokeStyle = series.color	
			@ctxg.beginPath()

			datalen = Math.min(series.xdata.length, series.ydata.length)
			for i in [0...datalen]
				x = series.xdata[i]
				y = series.ydata[i]
				
				if not x? or not y? or x<xmin or x>xmax
					continue
				
				if y<@yaxis.min then y = @yaxis.min
				if y>@yaxis.max then y = @yaxis.max
				
				@ctxg.lineTo(@xaxis.xtransform(x, @geom), @yaxis.ytransform(y, @geom))
			@ctxg.stroke()
			
			if series.grabDot
				@ctxg.beginPath()
				if y<=@yaxis.min
					@ctxg.moveTo(@xaxis.xtransform(x, @geom)-5,@yaxis.ytransform(y, @geom))
					@ctxg.lineTo(@xaxis.xtransform(x, @geom),@yaxis.ytransform(y, @geom)+10)
					@ctxg.lineTo(@xaxis.xtransform(x, @geom)+5,@yaxis.ytransform(y, @geom))
					@ctxg.lineTo(@xaxis.xtransform(x, @geom)-5,@yaxis.ytransform(y, @geom))
				else if y>=@yaxis.max
					@ctxg.moveTo(@xaxis.xtransform(x, @geom)-5,@yaxis.ytransform(y, @geom))
					@ctxg.lineTo(@xaxis.xtransform(x, @geom),@yaxis.ytransform(y, @geom)-10)
					@ctxg.lineTo(@xaxis.xtransform(x, @geom)+5,@yaxis.ytransform(y, @geom))
					@ctxg.lineTo(@xaxis.xtransform(x, @geom)-5,@yaxis.ytransform(y, @geom))
				else
					@ctxg.arc(@xaxis.xtransform(x, @geom), @yaxis.ytransform(y, @geom), 5, 0, Math.PI*2, true);
				if series.grabDot == 'fill'
					@ctxg.fillStyle = series.color
				else
					@ctxg.fillStyle = 'white'
				@ctxg.fill()
				@ctxg.stroke()
		
		@perfStat(new Date()-startTime)
		return null
			
arange = (lo, hi, step) ->
	ret = new Float32Array((hi-lo)/step+1)
	for i in [0...ret.length]
		ret[i] = lo + i*step
	return ret

window.livegraph =
	LiveGraph: LiveGraph
	Axis: Axis
	digitalAxis: digitalAxis
	Series: Series
	canvas: LiveGraph_canvas
	arange: arange	
		
		
window.livegraph.demo = ->
	xaxis = new Axis(-20, 20)
	yaxis = new Axis(-1, 3)

	xdata = arange(-20, 20, 0.1)
	ydata = new Float32Array(xdata.length)

	updateData = ->
		n = (Math.sin(+new Date()/600)+2)*1.5

		for i in [0...ydata.length]
			x = xdata[i]
			if x != 0
				ydata[i] = Math.sin(x*Math.PI/n)/x
			else
				ydata[i] = Math.PI/n

	updateData()

	series = new livegraph.Series(xdata, ydata, 'blue')
	lg = new livegraph.canvas(document.getElementById('demoDiv'), xaxis, yaxis, [series])
	lg.needsRedraw()

	setInterval((->
		updateData()
		lg.needsRedraw()
	), 10)

	lg.perfStat_enable(document.getElementById('statDiv'))

	window.lg = lg


