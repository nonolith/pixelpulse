
window.numberWidget = (value, conv, changed) ->
	sampleTime = server.device.sampleTime
	
	switch conv
		when 's'
			min = sampleTime
			max = 10
			step = 0.1
			unit = 's'
			digits = 4
		when 'hz'
			min = 0.1
			max = 1/sampleTime/5
			step = 1
			unit = 'Hz'
			digits = 1
		else
			min = conv.min
			max = conv.max
			unit = conv.units
			step = 0.1
			digits = conv.digits

	d = $('<input type=number>')
			.attr({min, max, step})
			.change ->
				v = parseFloat(d.val())
				
				if conv is 's'
					v /= sampleTime
				else if conv is 'hz'
					v = (1/v)/sampleTime
					
				changed(v)
				
	span = $("<span>").append(d).append(unit)
				
	span.set = (v) ->
		switch conv
			when 's'
				v *= sampleTime
			when 'hz'
				v = 1/(v * sampleTime)
		d.val(v.toFixed(digits))
		
	span.set(value)
	
	return span
	
window.selectDropdown = (options, selectedOption, showText, changed) ->
	dropdown = false
	el = $("<div class='select-dropdown'>").click (e) ->
		if not dropdown and e.target == el.get(0)
			showDropdown()
			return false
			
	if showText
		el.addClass('text-dropdown')
	else
		el.addClass('icon-dropdown')
		
	iconFor = (option) -> 'icon-'+option.toLowerCase()
		
	select = (option) ->
		if showText
			el.text(option)
		if selectedOption
			el.removeClass(iconFor selectedOption)
		el.addClass(iconFor option)
		selectedOption = option
	el.select = select
		
	hideDropdown = ->
		if dropdown
			dropdown.remove()
			dropdown = false
	el.hideDropdown = hideDropdown
			
	showDropdown = ->
		$(document.body).one 'click', hideDropdown
		
		clickfunc = ->
			o = $(this).data('option')
			select(o)
			changed(o)
	
		dropdown = $("<ul>").appendTo(el)
		for i in options
			$("<li>").text(i).addClass(iconFor i).data('option', i).click(clickfunc).appendTo(dropdown)
	
	select(selectedOption) if selectedOption
	return el

window.btnPopup = (button, popup) ->
	button = $(button)
	popup = $(popup)
	state = false
	
	showPopup = ->
		popup.fadeIn().css(left: button.position().left, bottom: '42px')
		$(document).one 'click', ->
			hidePopup()
		button.addClass('active')
		state = true
		pixelpulse.hidePopup = -> $(document).click()
		
	hidePopup = ->
		popup.fadeOut()
		button.removeClass('active')
		state = false
	
	$(button).click (e)->
		if not state
			showPopup()
			return false
		
	$(popup).click (e) -> false #block events