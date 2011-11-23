# Pixelpulse UI elements
# (C) 2011 Nonolith Labs
# Author: Kevin Mehall <km@kevinmehall.net>
# Distributed under the terms of the GNU GPLv3

pixelpulse = (window.pixelpulse ?= {})

class pixelpulse.TileView
	constructor: (@stream)->
		@id = "#{@stream.parent.id} - #{@stream.id}"
		@tile = $("<div class='meter'>")
		@h2 = $("<h2>").appendTo(@tile)
		@el = @tile.get(0)
		@el.view = this
		@timeseries = false

		@addReadingUI(@tile)
		
		@tile.attr("title", "Drag and drop to rearrange")
		@tile.get(0).draggable = true
		@tile.get(0).ondragstart = (e) =>
			window.draggedChannel = this
			e.dataTransfer.setData('application/x-nonolith-channel-id', @id)
			i = $("<div class='meter-drag'>").text(@id).appendTo('#hidden')
			e.dataTransfer.setDragImage(i.get(0), 0, 0)
			setTimeout((-> i.remove()), 0)
				
		@stream.tile = this
		@update()

		@watch = @stream.getWatch()
		@watch.updated.listen =>
			@onValue(@watch.lastData())
		@watch.start(0, 100000, 10)

	addReadingUI: (tile) ->
		tile.append($("<span class='reading'>")
			.append(@input = $("<input>"))
			.append($("<span class='unit'>").text(@unit)))
		
		if not @settable
			$(@input).attr('disabled', true)
		else
			@input.change (e) =>
				@setValue(parseFloat($(@input).val(), 10))
				$(@input).blur()
				
			@input.click ->
				this.select()

	update: ->
		@h2.text(@stream.displayName)
		
	onValue: (v) ->
		if !@input.is(':focus')
			@input.val(if Math.abs(v)>1 then v.toPrecision(4) else v.toFixed(3))
			if (v < 0)
				@input.addClass('negative')
			else
				@input.removeClass('negative')

	showTimeseries: ->
		if @timeseries
			return $(@timeseries.el).detach()
		
		@timeseries = new pixelpulse.TimeSeriesView(@stream, this)

		return @timeseries.el

	hideTimeseries: ->
		if @timeseries
			@timeseries.destroy()
			@timeseries = false
		
		return $(@el).detach()
		

class pixelpulse.TimeSeriesView
	constructor: (@stream, @tile) ->
		@tsRow = $("<section>")
				.addClass(@cssClass)
				.append(@graphDiv = $("<div class='livegraph'>"))
				.append(@tsAside = $("<aside>"))
		@el = @tsRow.get(0)

		$(@tile.el).detach().attr('style', '').appendTo(@tsAside)

		server.captureStateChanged.listen (state) =>
			if state == 'ready' or (state != 'inactive' and not @watch)
				@watch = @stream.getWatch()
				@watch.start(0, 100, 1)
				@series.ydata = @watch.data
				@lg.needsRedraw()

				@watch.updated.listen =>
					console.info('graph upd', @lg, @xdata, @watch.data)
					@lg.needsRedraw()

		@xaxis = new livegraph.Axis(0, 10) 
		@yaxis = new livegraph.Axis(-2, 2) #TODO: get from @stream

		@xdata = livegraph.arange(0, 9.99, 0.1)
		
		@series =  new livegraph.Series(@xdata, [], 'blue')

		@lg = new livegraph.canvas(@graphDiv.get(0), @xaxis, @yaxis, [@series])
		@lg.needsRedraw()

	destroy: ->
		@tsRow.remove()
		# TODO: clean up watch



