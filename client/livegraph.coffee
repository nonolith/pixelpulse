
OFFSET = 35

window.arange = (lo, hi, step) ->
	lo -= step
	while lo < hi
		lo += step
		
class Axis
	grid: ->
		grid=Math.pow(10, Math.round(Math.log(@max-@min)/Math.LN10)-1)
		if (@max-@min)/grid >= 10
			grid *= 2
		return grid
		
class XAxis extends Axis
	constructor: (@property, @min, @max) ->
	
		if @max == 'auto'
			@autoScroll = min
			@max = 0
		else
			@autoscroll = false
		
	resize: (@xleft, @xright) ->
		@span = @max - @min
		@width = @xright - @xleft
	
	transform: (point) ->
		(point - @min) * @width / @span + @xleft
	
class YAxis extends Axis
	constructor: (@property, @color, @min, @max) ->
	
	resize: (@ytop, @ybottom) ->
		@span = @max - @min
		@height = @ybottom - @ytop
		
	transform: (point) ->
		@ybottom - (point - @min) * @height / @span
		
	invTransform: (y) ->
		(@ybottom - y)/@height * @span + @min

class LiveGraph
	constructor: (@div, @xaxis, @yaxes) ->
		@subplots = []
		@data = []
		
		@div.setAttribute('class', 'livegraph')
		
	setData: (@data) ->
		@redrawGraph()
		
	autoscroll: ->
		if @xaxis.autoScroll
			@xaxis.max = @data[@data.length-1][@xaxis.property]
			@xaxis.min = @xaxis.max + @xaxis.autoScroll
			
	relayout: ->
		subplot_height = (@height-(Math.max(1, @yaxes.length-1))*OFFSET)/@yaxes.length - OFFSET
		y = OFFSET
		
		for i in @yaxes
			i.resize(y, y+subplot_height)
			y += subplot_height + OFFSET
			
		@xaxis.resize(OFFSET, @width - OFFSET)
		
		@redrawAxis()
		@redrawGraph()
		
		
	addSubplot: (axis) ->
		@yaxes.push(axis)
		@relayout()

class LiveGraph_canvas extends LiveGraph
	constructor: (div, xaxis, yaxes) ->
		super(div, xaxis, yaxes)
		
		@axisCanvas = document.createElement('canvas')
		@graphCanvas = document.createElement('canvas')
		@tmpCanvas = document.createElement('canvas')
		@div.appendChild(@axisCanvas)
		@div.appendChild(@graphCanvas)
	
	resized: () ->
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
		
		@relayout()
			
	redrawAxis: () ->
		@axisCanvas.width = 1
		@axisCanvas.width = @width
		
		@ctxa = @axisCanvas.getContext('2d')
		@ctxa.lineWidth = 2
		
		# Draw X Axis
		xgrid = @xaxis.grid()
		y = @height-OFFSET
		@ctxa.beginPath()
		@ctxa.moveTo(@xaxis.xleft, y)
		@ctxa.lineTo(@xaxis.xright, y)
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
		
		for x in arange(min, max, xgrid)
			@ctxa.beginPath()
			xp = @xaxis.transform(x+offset)
			@ctxa.moveTo(xp,y-4)
			@ctxa.lineTo(xp,y+4)
			@ctxa.stroke()
			@ctxa.fillText(Math.round(x*10)/10, xp ,y+textoffset)
		
		drawYAxis = (axis, x, align, textoffset) =>
			grid = axis.grid()
			@ctxa.textAlign = align
				
			@ctxa.textBaseline = 'middle'
			
			@ctxa.beginPath()
			@ctxa.moveTo(x, axis.ytop)
			@ctxa.lineTo(x, axis.ybottom)
			@ctxa.stroke()
			
			for y in arange(axis.min, axis.max, grid)
				@ctxa.beginPath()
				yp = axis.transform(y)
				@ctxa.moveTo(x-4, yp)
				@ctxa.lineTo(x+4, yp)
				@ctxa.stroke()
				@ctxa.fillText(Math.round(y*10)/10, x+textoffset, yp)
		
		
		for axis in @yaxes
			drawYAxis(axis, OFFSET,        'right', -5)
			drawYAxis(axis, @width-OFFSET, 'left',   8)
			
			
	redrawGraph: ()->
		if !@data.length then return
		@graphCanvas.width = 1
		@graphCanvas.width = @width
		@ctxg.lineWidth = 2
		
		@autoscroll()
		
		xmin = @xaxis.min
		xmax = @xaxis.max
			
		for yaxis in @yaxes
			@ctxg.strokeStyle = yaxis.color	
			@ctxg.beginPath()
			for i in @data
				x = i[@xaxis.property]
				y = i[yaxis.property]
				if x<xmin or x>xmax
					continue
				
				if y<yaxis.min then y = yaxis.min
				if y>yaxis.max then y = yaxis.max
				
				@ctxg.lineTo(@xaxis.transform(x), yaxis.transform(y))
			@ctxg.stroke()
			
			if yaxis.grabDot
				@ctxg.beginPath()
				@ctxg.arc(@xaxis.transform(x), yaxis.transform(y), 5, 0, Math.PI*2, true);
				if yaxis.grabDot == 'fill'
					@ctxg.fillStyle = yaxis.color
				else
					@ctxg.fillStyle = 'white'
				@ctxg.fill()
				@ctxg.stroke()
		
	
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
	XAxis: XAxis
	YAxis: YAxis
	canvas: LiveGraph_canvas	
		
		
	
	

	
