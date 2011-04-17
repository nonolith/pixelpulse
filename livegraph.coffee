
OFFSET = 35

window.arange = (lo, hi, step) ->
	lo -= step
	while lo < hi
		lo += step


class LiveGraph
	constructor: (@div) ->
		@div.setAttribute('class', 'livegraph')
		@axisCanvas = document.createElement('canvas')
		@graphCanvas = document.createElement('canvas')
		@tmpCanvas = document.createElement('canvas')
		
		@div.appendChild(@axisCanvas)
		@div.appendChild(@graphCanvas)
		
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
		
	transformForAxis: (ctx, xaxis, yaxis) ->
		ctx.setTransform(1,0,0,1,0,0)
		ctx.translate(OFFSET-0.5, @height-OFFSET-0.5)
		
		xscale = if xaxis then (@width-2*OFFSET)/(xaxis.max-xaxis.min) else 1
		yscale = if yaxis then (@height-2*OFFSET)/(yaxis.max-yaxis.min) else 1
		
		ctx.scale(xscale, -yscale)
		return [xscale, yscale]
	
	transformPoint: (axis, point) ->
		if axis.direction == 'y'
			(@height - OFFSET - (point-(axis.currentMin ? axis.min)) * (@height - OFFSET*2)/(axis.span))|0
		else
			(OFFSET + (point-(axis.currentMin ? axis.min)) * (@width - OFFSET*2)/(axis.span)))|0
		
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
				
				if axis.max == 'auto'
					axis.currentMax = 0
					axis.currentMin = axis.min
				
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
		
		xaxis = @axes.xbottom
		xmin = xaxis.min
		xmax = xaxis.max
		
		if xmax == 'auto'
			xmax = xaxis.currentMax = @data[@data.length-1][xaxis.property]
			xmin = xaxis.currentMin = xmax + xmin
			
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
		
		if @axes.xbottom.max == 'auto' and @axes.xbottom.currentMax
			xaxis = @axes.xbottom
			
			drawWidth = @width - OFFSET*2
			drawHeight = @height - OFFSET*2
			drawLeft = OFFSET
			drawTop = OFFSET
			
			xmax = xaxis.currentMax = pt[xaxis.property]
			xmin = xaxis.currentMin = xmax + xaxis.min
			
			prevX = @transformPoint(xaxis, prevPt[xaxis.property])
			move = Math.ceil(@width - OFFSET - prevX)
			
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
		
	
	setData: (@data) ->
		@redrawGraph()
	
	setAxis: (axis, label, property, min, max, color) ->
		axis.property = property
		axis.min = min
		axis.max = max
		axis.color = color
		axis.labelSpan.style.color = color
		axis.labelSpan.innerText = label
		axis.currentMin = min
		axis.currentMax = (if max is 'auto' then 0 else max)
		axis.span = (if max is 'auto' then 0 else max) - min
		@redrawAxis()
		@redrawGraph()
		
window.LiveGraph = LiveGraph
	
