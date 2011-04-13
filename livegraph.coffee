
OFFSET = 20

window.arange = (lo, hi, step) ->
	while lo < hi
		lo += step


class LiveGraph
	constructor: (@div) ->
		@axisCanvas = document.createElement('canvas')
		@graphCanvas = document.createElement('canvas')
		
		@div.appendChild(@axisCanvas)
		@div.appendChild(@graphCanvas)
		
		@width = 500
		@height = 400
		
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
				
	resized: () ->
		@redrawAxis()
		@redrawGraph()
		
	transformForAxis: (ctx, xaxis, yaxis) ->
		ctx.setTransform(1,0,0,1,0,0)
		ctx.translate(OFFSET-0.5, @height-OFFSET-0.5)
		
		xscale = if xaxis then (@width-2*OFFSET)/(xaxis.max-xaxis.min) else 1
		yscale = if yaxis then (@height-2*OFFSET)/(yaxis.max-yaxis.min) else 1
		
		ctx.scale(xscale, -yscale)
		return [xscale, yscale]
		
		
		
	redrawAxis: () ->
		@axisCanvas.width = 1
		@axisCanvas.width = @width
		@axisCanvas.height = @height
		@ctxa = @axisCanvas.getContext('2d')
		
		for name, axis of @axes
			grid=Math.pow(10, Math.round(Math.log(axis.max-axis.min)/Math.LN10)-1)
			if (axis.max-axis.min)/grid >= 10
				grid *= 2
			
			if axis.direction=='y'
				[xscale, yscale] = @transformForAxis(@ctxa, false, axis)
				
				x = if axis.xpos==0 then 0 else @width-2*OFFSET
				console.log('x', x, axis.xpos)
				@ctxa.lineWidth = 3
				@ctxa.beginPath()
				@ctxa.moveTo(x, axis.min)
				@ctxa.lineTo(x, axis.max)
				@ctxa.stroke()
				
				for y in arange(axis.min, axis.max, grid)
					console.log(axis.xpos, x, y)
					@ctxa.lineWidth = 2/yscale
					@ctxa.beginPath()
					@ctxa.moveTo(x-4, y)
					@ctxa.lineTo(x+4, y)
					@ctxa.stroke()
			else
				[xscale, yscale] = @transformForAxis(@ctxa, axis, false)
				
				y = 0
				@ctxa.lineWidth = 3
				@ctxa.beginPath()
				@ctxa.moveTo(axis.min, y)
				@ctxa.lineTo(axis.max, y)
				@ctxa.stroke()
				
				for x in arange(axis.min, axis.max, grid)
					@ctxa.lineWidth = 2/xscale
					@ctxa.beginPath()
					@ctxa.moveTo(x,y-4)
					@ctxa.lineTo(x,y+4)
					@ctxa.stroke()
				
			
	redrawGraph: ()->
	
	pushData: () ->
	
	setData: () ->
	
	setAxis: (axis, label, property, min, max) ->
		axis.property = property
		axis.min = min
		axis.max = max
		axis.labelSpan.innerText = label
		@redrawAxis()
		
window.LiveGraph = LiveGraph
	
