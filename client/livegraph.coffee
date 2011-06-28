
OFFSET = 10
AXISOFFSET = 25

window.arange = (lo, hi, step) ->
	ret = []
	while lo <= hi
		ret.push(lo)
		lo += step
	return ret
		
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
	constructor: (@xvar, @yvar, @color, @style) ->

class LiveGraph
	constructor: (@div, @xaxis, @yaxis, @data, @series) ->		
		@div.setAttribute('class', 'livegraph')
		
	autoscroll: ->
		if @xaxis.autoScroll
			@xaxis.max = @data[@data.length-1][@series[0].xvar]
			@xaxis.min = @xaxis.max + @xaxis.autoScroll
					
class LiveGraph_canvas extends LiveGraph
	constructor: (div, xaxis, yaxis, data, series) ->
		super(div, xaxis, yaxis, data, series)
		
		@axisCanvas = document.createElement('canvas')
		@graphCanvas = document.createElement('canvas')
		@tmpCanvas = document.createElement('canvas')
		@div.appendChild(@axisCanvas)
		@div.appendChild(@graphCanvas)
		
		@showXbottom = window.xbottom
		@showYleft = true
		@showYright = true
		@showYgrid = window.ygrid
		
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
		@tmpCanvas.width = @width
		@tmpCanvas.height = @height
		
		@ctxg = @graphCanvas.getContext('2d')
		@ctxt = @tmpCanvas.getContext('2d')
		@ctxg.lineWidth = 2
		
		@geom = 
			ytop: OFFSET
			ybottom: @height - (OFFSET + @showXbottom * AXISOFFSET)
			xleft: OFFSET + @showYleft * AXISOFFSET
			xright: @width - (OFFSET + @showYright * AXISOFFSET)
			width: @width - 2*OFFSET - (@showYleft+@showYright) * AXISOFFSET
			height: @height - 2*OFFSET - @showXbottom  * AXISOFFSET
		
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
			
					
			
	redrawGraph: ->
		if @data.length<2 then return
		
		if @height != @div.offsetHeight or @width != @div.offsetWidth
			@resized()
		
		if window.canvas_clear_width
			@graphCanvas.width = 1
			@graphCanvas.width = @width
		else
			@ctxg.clearRect(0,0,@width, @height)
		@ctxg.lineWidth = 2
		
		@autoscroll()
		
		xmin = @xaxis.min
		xmax = @xaxis.max
		
		for series in @series
			@ctxg.strokeStyle = series.color	
			@ctxg.beginPath()
			for i in @data
				x = i[series.xvar]
				y = i[series.yvar]
				
				if not x? or not y? or x<xmin or x>xmax
					continue
				
				if y<@yaxis.min then y = @yaxis.min
				if y>@yaxis.max then y = @yaxis.max
				
				@ctxg.lineTo(@xaxis.xtransform(x, @geom), @yaxis.ytransform(y, @geom))
			@ctxg.stroke()
			
			if series.grabDot
				@ctxg.beginPath()
				@ctxg.arc(@xaxis.xtransform(x, @geom), @yaxis.ytransform(y, @geom), 5, 0, Math.PI*2, true);
				if series.grabDot == 'fill'
					@ctxg.fillStyle = series.color
				else
					@ctxg.fillStyle = 'white'
				@ctxg.fill()
				@ctxg.stroke()
		return null
		
	
	pushData: (pt) ->
		prevPt = @data[@data.length-1]
		@data.push(pt)
		
		if @data.length < 2
			return
		
		if window.graphmode != 'blit'
			return @redrawGraph()
		
		if @axes.xbottom.autoScroll
			xaxis = @axes.xbottom
			
			drawWidth = @width - OFFSET*2
			drawHeight = @height - OFFSET*2
			drawLeft = OFFSET
			drawTop = OFFSET
			
			@autoscroll()
			
			xmax = xaxis.max
			xmin = xaxis.min
			
			prevX = @transformPoint(xaxis, prevPt[xaxis.property])
			move = 1
			
			@tmpCanvas.width=0
			@tmpCanvas.width=@width
			
			@ctxt.drawImage(@graphCanvas,
				drawLeft+move, drawTop, drawWidth, drawHeight,
				drawLeft,      drawTop, drawWidth, drawHeight)
				
			@graphCanvas.width=0
			@graphCanvas.width=@width
				
			@ctxg.drawImage(@tmpCanvas,
				drawLeft, drawTop, drawWidth, drawHeight,
				drawLeft, drawTop, drawWidth, drawHeight)
				
			@ctxg.lineWidth = 2
			for yaxis in [@axes.yleft, @axes.yright]
				@ctxg.strokeStyle = yaxis.color	
				@ctxg.beginPath()
				
				prevY = @transformPoint(yaxis,prevPt[yaxis.property])
				newY = @transformPoint(yaxis, pt[yaxis.property])
				@ctxg.moveTo(@width-OFFSET-move, prevY)
				@ctxg.lineTo(@width-OFFSET, newY)
				@ctxg.stroke()
		else
			@redrawGraph()
		
class LiveGraph_svg extends LiveGraph
	constructor: (div) ->
		super(div)
		
		@r = Raphael(@div, @div.offsetWidth, @div.offsetHeight)
		
		@resized()
		
	resized: ->	
		@width = @div.offsetWidth
		@height = @div.offsetHeight
		
		@r.setSize(@width, @height)
		
		@redrawAxis()
		@redrawGraph()
		
	redrawAxis: () ->
		if @asvg
			@asvg.remove()
			
		@asvg = @r.set()
		
		for name, axis of @axes
			grid=Math.pow(10, Math.round(Math.log(axis.max-axis.min)/Math.LN10)-1)
			if (axis.max-axis.min)/grid >= 10
				grid *= 2
			
			if axis.direction=='y'
				if axis.xpos==0
					x = OFFSET
				else 
					x = @width-OFFSET
					
				@asvg.push(@r.path("M#{x} #{OFFSET}V#{@height-OFFSET}"))
				
				for y in arange(axis.min, axis.max, grid)
					@asvg.push(@r.path("M#{x-4} #{@transformPoint(axis,y)}h8"))
			else
				y = @height-OFFSET
				
				@asvg.push(@r.path("M#{OFFSET} #{y}H#{@width-OFFSET}"))
				
				continue if axis.autoScroll
				
				for x in arange(axis.min, axis.max, grid)
					@asvg.push(@r.path("M#{@transformPoint(axis,x)} #{y-4}v8"))
					
		@asvg.attr('stroke-width':2)
	
	redrawGraph: ()->
		if !@data.length then return
		
		if @gsvg
			@gsvg.remove()
			
		@gsvg = @r.set()
		
		@autoscroll()
		
		xaxis = @axes.xbottom
		xmin = xaxis.min
		xmax = xaxis.max
			
		for yaxis in [@axes.yleft, @axes.yright]
			pth = for i in @data
				pt = i[xaxis.property]
				if pt<xmin or pt>xmax
					continue
				"L#{@transformPoint(xaxis,pt).toFixed(1)} #{@transformPoint(yaxis,i[yaxis.property]).toFixed(1)}"
			pth = 'M'+pth.join('').slice(1)
			p = @r.path(pth)
			p.attr(stroke:yaxis.color, 'stroke-width':2)
			@gsvg.push(p)
			
						
	pushData: (pt) ->
		prevPt = @data[@data.length-1]
		@data.push(pt)
		
		if @data.length < 2
			return
		
		@redrawGraph()


window.livegraph =
	LiveGraph: LiveGraph
	Axis: Axis
	digitalAxis: digitalAxis
	Series: Series
	canvas: LiveGraph_canvas	
		
		
	
	

	
