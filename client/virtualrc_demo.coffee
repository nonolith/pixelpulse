window.virtualrc_start = (app) ->
	$('#loading').hide()
	setup = true
	
	app.onConfig [
			{
				'id': 'time',
				'name': 'Time',
				'unit': 's',
				'min': -30,
				'max': 'auto',
				'stateOptions': []
			},
			{
				'id': 'voltage',
				'name': 'Voltage',
				'unit': 'V',
				'min': -5,
				'max': 5,
				'state': 'source',
				'showGraph': true,
				'settable': true,
				'stateOptions': ['source', 'measure'],
				'color': 'blue',
			},
			{
				'id': 'current',
				'name': 'Current',
				'unit': 'mA',
				'min': -200,
				'max': 200,
				'state': 'measure',
				'showGraph': true,
				'settable': true,
				'stateOptions': ['source', 'measure'],
				'color': 'red',
			},
			{
				'id': 'resistance',
				'name': 'Resistance',
				'unit': '\u03A9',
				'min': 0,
				'max': 10000,
				'state': 'computed',
				'stateOptions': ['computed'],
				'color': 'orange',
			},
			{
				'id': 'digital',
				'name': 'Digital',
				'type': 'digital',
				'state': 'input',
				'stateOptions': ['input', 'output'],
				'color': 'green',
			},
		]
		
	r = 100.0
	c = 100e-4
	q = 0.0
	
	source = 'voltage'
	
	voltage = current = 0
	lastTime = 0
	tstart = new Date()
	
	step = ->
		t = (new Date() - tstart) / 1000
		dt = lastTime-t
		switch source
			when 'current'
				voltage = q/c
			
				if (voltage>=5 and current<0) or (voltage<=-5 and current>0)
					current = 0
			
				q += current*dt
			when 'voltage'
				current = -(voltage-q/c)/r
				q += current*dt
			
		lastTime = t
		imp = Math.min(Math.abs(voltage/(current)), 9999)
		if isNaN(imp) then imp = 9999
		app.onData {
			'time': t,
			'voltage': voltage,
			'current': current*1000.0,
			'resistance':imp,
			'digital': Math.sin(2*t) > 0
		}
		
		setTimeout(step, 30)
		
		
	app.setChannel = (chan, val, state) ->
		switch chan
			when 'voltage'
				if state == 'source' and val?
					voltage = val
			when 'current'
				if state == 'source' and val?
					current = val/1000
			else
				return
				
		if (state == 'source' and source != chan) or (state == 'measure' and source == chan)
			if state == 'source'
				source = chan
			else if state == 'measure' and source == 'voltage'
				source = 'current'
			else
				source = 'voltage'
				
			switch source
				when 'voltage'
					app.onState('voltage', 'source')
					app.onState('current', 'measure')
				when 'current'
					app.onState('current', 'source')
					app.onState('voltage', 'measure')
					
	step()
