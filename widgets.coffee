
window.numberWidget = ({valuefn, min, max, step, unit, digits, changedfn}, title, cssClass) ->
	d = $('<input type=number>')
			.attr({min, max, step})
			.change ->
				v = parseFloat(d.val())
				changedfn(v)
				
	span = $("<span>").append(d).append(unit).attr({title, 'class':cssClass})
				
	span.set = (arg) ->	d.val(valuefn(arg).toFixed(digits))
	
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

window.btnPopup = (button, popup, opencb, closecb) ->
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
		closecb() if closecb
		return
	
	$(button).click (e)->
		if not state
			opencb()
			$(document).click() # close others
			showPopup()
			e.stopPropagation()
		return
		
	$(popup).click (e) ->
		e.stopPropagation() #block events