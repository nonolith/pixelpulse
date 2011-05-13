
OFFSET = 35

window.arange = (lo, hi, step) ->
	lo -= step
	while lo < hi
		lo += step


class LiveGraph
	constructor: (@div) ->
		@axes =
			yleft: {direction:'y', xpos:0}
			yright: {direction:'y', xpos:1}
			xbottom: {direction:'x'}
			
		for name, axis of @axes
			axis.labelDiv = document.createElement('div')
			axis.labelSpan = document.createElement('span')
			axis.labelDiv.setAttribute('class', "livegraph-label livegraph-label-#{name}")
			@div.appendChild(axis.labelDiv)
			axis.labelDiv.appendChild(axis.labelSpan)
		@data = []
		
		@div.setAttribute('class', 'livegraph')
		
		
	transformPoint: (axis, point) ->
		if axis.direction == 'y'
			(@height - OFFSET - (point-axis.min) * (@height - OFFSET*2)/(axis.span))
		else
			(OFFSET + (point-axis.min) * (@width - OFFSET*2)/(axis.span))
			
	setData: (@data) ->
		@redrawGraph()
	
	setAxis: (axis, label, property, min, max, color) ->
		axis.property = property
		
		if max == 'auto'
			axis.autoScroll = min
			axis.min = min
			axis.max = 0
		else
			axis.min = min
			axis.max = max
			axis.autoScroll = false
			
		axis.color = color
		axis.labelSpan.style.color = color
		axis.labelSpan.innerText = label
		axis.span = axis.max - axis.min
		@redrawAxis()
		@redrawGraph()
		
	autoscroll: ->
		if @axes.xbottom.autoScroll
			@axes.xbottom.max = @data[@data.length-1][@axes.xbottom.property]
			@axes.xbottom.min = @axes.xbottom.max + @axes.xbottom.autoScroll
			
		
window.LiveGraph = LiveGraph

class LiveGraph_canvas extends LiveGraph
	constructor: (div) ->
		super(div)
		
		@axisCanvas = document.createElement('canvas')
		@graphCanvas = document.createElement('canvas')
		@tmpCanvas = document.createElement('canvas')
		@div.appendChild(@axisCanvas)
		@div.appendChild(@graphCanvas)
		
		@resized()
	
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
		
		@redrawAxis()
		@redrawGraph()
			
	redrawAxis: () ->
		@axisCanvas.width = 1
		@axisCanvas.width = @width
		
		@ctxa = @axisCanvas.getContext('2d')
		
		@ctxa.lineWidth = 2
		
		@ctxa.textBaseline
		
		for name, axis of @axes
			grid=Math.pow(10, Math.round(Math.log(axis.max-axis.min)/Math.LN10)-1)
			if (axis.max-axis.min)/grid >= 10
				grid *= 2
			
			if axis.direction=='y'
				if axis.xpos==0
					x = OFFSET
					@ctxa.textAlign = 'right'
					textoffset = -5
				else 
					x = @width-OFFSET
					@ctxa.textAlign = 'left'
					textoffset = 5
				@ctxa.textBaseline = 'middle'
				
				@ctxa.beginPath()
				@ctxa.moveTo(x, OFFSET)
				@ctxa.lineTo(x, @height-OFFSET)
				@ctxa.stroke()
				
				for y in arange(axis.min, axis.max, grid)
					@ctxa.beginPath()
					@ctxa.moveTo(x-4, @transformPoint(axis,y))
					@ctxa.lineTo(x+4, @transformPoint(axis,y))
					@ctxa.stroke()
					@ctxa.fillText(Math.round(y*10)/10, x+textoffset, @transformPoint(axis,y))
			else
				y = @height-OFFSET
				@ctxa.beginPath()
				@ctxa.moveTo(OFFSET, y)
				@ctxa.lineTo(@width-OFFSET, y)
				@ctxa.stroke()
				
				textoffset = 5
				@ctxa.textAlign = 'center'
				@ctxa.textBaseline = 'top'
				
				
				continue if axis.autoScroll
				
				for x in arange(axis.min, axis.max, grid)
					@ctxa.beginPath()
					@ctxa.moveTo(@transformPoint(axis,x),y-4)
					@ctxa.lineTo(@transformPoint(axis,x),y+4)
					@ctxa.stroke()
					@ctxa.fillText(Math.round(x*10)/10, @transformPoint(axis,x),y+textoffset)
				
			
	redrawGraph: ()->
		if !@data.length then return
		@graphCanvas.width = 1
		@graphCanvas.width = @width
		@ctxg.lineWidth = 2
		
		@autoscroll()
		
		xaxis = @axes.xbottom
		xmin = xaxis.min
		xmax = xaxis.max
			
		for yaxis in [@axes.yleft, @axes.yright]
			@ctxg.strokeStyle = yaxis.color	
			@ctxg.beginPath()
			for i in @data
				pt = i[xaxis.property]
				if pt<xmin or pt>xmax
					continue
				@ctxg.lineTo(@transformPoint(xaxis,pt), @transformPoint(yaxis,i[yaxis.property]))
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
		
window.LiveGraph_canvas = LiveGraph_canvas	

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
		
window.LiveGraph_svg = LiveGraph_svg		
		
		
	
	

	
